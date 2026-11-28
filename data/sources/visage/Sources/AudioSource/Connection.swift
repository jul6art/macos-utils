import AppKit
import CoreAudio
import Foundation
import Observation
import Shared

/// « Connect my AI »: finds the app, taps its sound, and keeps the tap alive — when the app restarts, when
/// the output changes (headphones), when its audio processes change. The capture starts off the main
/// thread, because macOS blocks it while waiting for the user's permission (pilot, § 2.3).
@MainActor
@Observable
public final class Connection {
    public enum State: Equatable, Sendable {
        case idle
        case notInstalled
        case starting
        case waitingForPermission
        /// The app has been playing for a while and nothing of it came through, or the capture would not run
        /// under it even restarted: macOS keeps its sound from Visage (not allowed, or allowed for an earlier
        /// build of the app).
        case permissionMissing
        /// Process mode only: the app has no audio process yet; it gets one when it first speaks.
        case waitingForApp
        case connected
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var app: AIApp?
    public private(set) var capture: AudioCapture?
    /// Whether the app has its microphone open: its voice mode, or its dictation, listens (spec, § 7.2).
    /// Read four times a second; Core Audio tells it with no permission, never what the microphone hears.
    public private(set) var appListening = false
    /// Called when `appListening` changes.
    @ObservationIgnored public var onListeningChange: (@MainActor (Bool) -> Void)?
    public var delayMilliseconds: Int {
        didSet { capture?.setDelay(milliseconds: delayMilliseconds) }
    }

    /// Bundle mode (macOS 26) lets Core Audio follow the app; process mode follows its processes by hand.
    public var usesBundleMode: Bool {
        if #available(macOS 26, *) { return !Self.forceProcessMode }
        return false
    }

    /// Bundle mode for this connection. Claude Code's voice is a helper that comes and goes: a tap by bundle ID
    /// missed a helper born after it, and stayed blocked once the helper was gone (seen on 2026-11-27).
    /// Visage follows its process instead, as on macOS 15, and the helper lives while Visage listens to it
    /// (spec, § 4.4).
    private var tapsByBundleID: Bool {
        usesBundleMode && app?.kind != .claudeCode
    }

    /// For the pilot's comparisons, and as a way out if bundle mode misbehaves on some app.
    public static var forceProcessMode: Bool {
        UserDefaults.standard.bool(forKey: "forceProcessMode")
    }

    /// The app's sound passes through, as Siri's always does (spec, § 4.5), while it listens: a voice mode
    /// runs macOS's voice processing, which lowers every other sound, Visage's playback with it. With Claude
    /// Desktop's voice mode, the face spoke and nothing was heard (2026-11-28).
    @ObservationIgnored private var passingThrough = false
    @ObservationIgnored private var playbackReturn: Task<Void, Never>?
    /// A voice mode may close its microphone between turns: the playback comes back only once the microphone
    /// has stayed closed this long.
    nonisolated public static let playbackReturnDelay = 10.0

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tappedProcesses: Set<AudioObjectID> = []
    /// Bundle mode: the bundle IDs given to Core Audio, which follows exactly those.
    @ObservationIgnored private var tappedBundleIDs: Set<String> = []
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var listeningWatch: Timer?
    /// The app's audio processes, as last seen.
    @ObservationIgnored private var appProcesses: [AudioObjectID] = []
    /// How long the app has been playing, in watchdog ticks (seconds), while the capture listens.
    @ObservationIgnored private var playingSeconds = 0.0
    /// The capture's callbacks at the last tick, how long they have not moved while the app plays, and how
    /// many restarts that has cost since they last moved.
    @ObservationIgnored private var lastCallbacks = 0
    @ObservationIgnored private var stalledSeconds = 0.0
    @ObservationIgnored private var stallRestarts = 0
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?

    public init(delayMilliseconds: Int) {
        self.delayMilliseconds = delayMilliseconds
        ProcessTaps.destroyLeftovers()
    }

    // MARK: - Connecting

    public func connect(to app: AIApp) {
        disconnect()
        self.app = app
        guard let installation = app.installation ?? commandLineInstallation(of: app) else {
            state = .notInstalled
            return
        }
        if app.opensOnConnect, installation.url.pathExtension == "app", !app.isRunning {
            NSWorkspace.shared.openApplication(at: installation.url, configuration: NSWorkspace.OpenConfiguration())
        }
        watchOutputDevice()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.watch() }
        }
        listeningWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { self.watchListening() }
        }
        // After sleep, the aggregate device may be gone: start again.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.restart() }
        }
        start(bundleID: installation.bundleID)
    }

    public func disconnect() {
        generation += 1
        watchdog?.invalidate()
        watchdog = nil
        listeningWatch?.invalidate()
        listeningWatch = nil
        appProcesses = []
        setListening(false)
        playbackReturn?.cancel()
        playbackReturn = nil
        passingThrough = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        unwatchOutputDevice()
        stopCapture()
        app = nil
        state = .idle
    }

    /// A command-line tool (`afplay`, for tests) has no installation to find: it only needs to be playing.
    private func commandLineInstallation(of app: AIApp) -> (bundleID: String, url: URL)? {
        guard let identifier = app.bundleIDs.first, !identifier.contains(".") else { return nil }
        return (identifier, URL(fileURLWithPath: "/usr/bin").appending(path: identifier))
    }

    private func start(bundleID: String) {
        stopCapture()
        let processes = AudioProcesses.matching(bundleID, in: AudioProcesses.all())
        appProcesses = processes.map(\.objectID)
        var target = CaptureTarget(passThrough: passesThrough)
        if tapsByBundleID, bundleID.contains(".") {
            // Siri's voice is a service born for each answer: Visage waits for the first one, then taps it by
            // its bundle ID, which Core Audio follows to the next ones.
            if app?.kind == .siri, processes.isEmpty {
                state = .waitingForApp
                return
            }
            target.bundleIDs = Array(Set(processes.map(\.bundleID).filter { !$0.isEmpty } + [bundleID])).sorted()
            tappedBundleIDs = Set(target.bundleIDs)
        } else {
            guard !processes.isEmpty else {
                state = .waitingForApp
                return
            }
            target.processObjects = processes.map(\.objectID)
        }
        tappedProcesses = Set(processes.map(\.objectID))

        generation += 1
        let attempt = generation
        let capture = AudioCapture()
        let delay = delayMilliseconds
        state = .starting

        // The permission prompt blocks the start: say so if it takes long.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if self.generation == attempt, self.state == .starting { self.state = .waitingForPermission }
        }
        Task.detached {
            let result = Result { try capture.start(target: target, delayMilliseconds: delay) }
            await self.started(capture, result: result, attempt: attempt)
        }
    }

    private func started(_ capture: AudioCapture, result: Result<Void, Error>, attempt: Int) async {
        guard attempt == generation else {
            capture.stop()
            return
        }
        if case .failure(let error) = result {
            state = .failed("\(error)")
            return
        }
        self.capture = capture
        // The app began or stopped listening while the capture started.
        if capture.passThrough != passesThrough { restart() }
        playingSeconds = 0
        lastCallbacks = 0
        stalledSeconds = 0
        // Connected, and listening: whether macOS lets the sound through shows only once the app plays.
        state = .connected
    }

    /// Whether macOS seems to keep the app's sound from Visage: the app has played for `limit` seconds and
    /// nothing but zeros came through since the capture began. No callback at all says nothing: on macOS 26,
    /// a capture by bundle ID does not run while the app is silent (a first version said « not allowed »
    /// there, until the app spoke). Once anything is heard, the permission is proven for the capture.
    nonisolated public static func permissionLooksMissing(heardSomething: Bool, playingFor seconds: Double) -> Bool {
        !heardSomething && seconds >= silentPlayLimit
    }

    nonisolated public static let silentPlayLimit = 6.0

    public enum StallVerdict: Sendable, Equatable {
        case fine
        /// The app plays and the capture stopped (sleep, a device gone, a stuck IO): start it again.
        case restart
        /// Restarts did not bring it back: macOS refuses the capture.
        case refused
    }

    /// What the watchdog does about a capture whose callbacks have not moved for `stalled` seconds while the
    /// app plays: wait `stallLimit` seconds, restart, and after `restartLimit` restarts in vain, give up. A
    /// silent app tells nothing: on macOS 26, a capture by bundle ID does not run while the app is silent.
    nonisolated public static func stallVerdict(stalled seconds: Double, restarts: Int) -> StallVerdict {
        guard seconds >= stallLimit else { return .fine }
        return restarts >= restartLimit ? .refused : .restart
    }

    nonisolated public static let stallLimit = 2.0

    /// Whether the app has a process with a bundle ID the bundle-mode tap was not given: Core Audio follows
    /// exactly the bundle IDs it is given, so a helper born after the connection would play unheard.
    nonisolated public static func missesHelpers(seen: [String], tapped: Set<String>) -> Bool {
        seen.contains { !$0.isEmpty && !tapped.contains($0) }
    }
    nonisolated public static let restartLimit = 2

    private func restart() {
        guard let app, capture != nil, let bundleID = app.installation?.bundleID ?? app.bundleIDs.first else { return }
        start(bundleID: bundleID)
    }

    private func stopCapture() {
        capture?.stop()
        capture = nil
        tappedProcesses = []
        tappedBundleIDs = []
    }

    // MARK: - Keeping it alive

    private func watch() {
        guard let app, let bundleID = app.installation?.bundleID ?? app.bundleIDs.first else { return }
        let processes = AudioProcesses.matching(bundleID, in: AudioProcesses.all())
        appProcesses = processes.map(\.objectID)
        switch state {
        case .waitingForApp:
            start(bundleID: bundleID)
        case .connected, .permissionMissing:
            if tapsByBundleID, bundleID.contains(".") {
                // Bundle mode: a helper whose bundle ID the tap was not given (Claude's audio service, when
                // it first plays or listens after the connection).
                if Self.missesHelpers(seen: processes.map(\.bundleID), tapped: tappedBundleIDs) {
                    start(bundleID: bundleID)
                    return
                }
            } else {
                // Process mode: a new helper, or the app restarted with new processes.
                let objects = Set(processes.map(\.objectID))
                if !objects.isEmpty, objects != tappedProcesses {
                    start(bundleID: bundleID)
                    return
                }
            }
            // Is the app's sound coming through? The user may also have allowed it meanwhile.
            guard let capture else { return }
            let playing = processes.contains(where: \.isRunningOutput)
            // Has the capture stopped under a playing app?
            let callbacks = capture.callbacks.load(ordering: .relaxed)
            if callbacks != lastCallbacks { stallRestarts = 0 }
            stalledSeconds = playing && callbacks == lastCallbacks ? stalledSeconds + 1 : 0
            lastCallbacks = callbacks
            switch Self.stallVerdict(stalled: stalledSeconds, restarts: stallRestarts) {
            case .restart:
                stallRestarts += 1
                start(bundleID: bundleID)
                return
            case .refused:
                if state != .permissionMissing { state = .permissionMissing }
                return
            case .fine:
                break
            }
            playingSeconds = playing ? playingSeconds + 1 : 0
            let missing = Self.permissionLooksMissing(
                heardSomething: capture.heardCallbacks.load(ordering: .relaxed) > 0, playingFor: playingSeconds)
            if missing != (state == .permissionMissing) { state = missing ? .permissionMissing : .connected }
        default:
            break
        }
    }

    private func watchListening() {
        var processes = appProcesses
        // Claude Code: the `claude` process holds its dictation's microphone, not the helper that speaks.
        if let app, app.kind == .claudeCode {
            processes += AudioProcesses.all().filter(app.listens(through:)).map(\.objectID)
        }
        setListening(processes.contains(where: AudioProcesses.isRunningInput))
    }

    private func setListening(_ listening: Bool) {
        guard listening != appListening else { return }
        appListening = listening
        onListeningChange?(listening)
        followVoiceProcessing(listening)
    }

    /// Whether the sound passes through now: Siri's always, an app's while it listens.
    private var passesThrough: Bool {
        app?.passesThrough == true || passingThrough
    }

    /// An app that opens its microphone passes through at once; it is played back again once its microphone
    /// has stayed closed `playbackReturnDelay` seconds. Each switch remakes the tap, a fraction of a second.
    private func followVoiceProcessing(_ listening: Bool) {
        guard app?.kind == .app else { return }
        playbackReturn?.cancel()
        playbackReturn = nil
        if listening {
            guard !passingThrough else { return }
            passingThrough = true
            restart()
        } else if passingThrough {
            playbackReturn = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.playbackReturnDelay))
                guard !Task.isCancelled, !self.appListening else { return }
                self.passingThrough = false
                self.restart()
            }
        }
    }

    private func watchOutputDevice() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.outputDeviceChanged() }
        }
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectAddPropertyListenerBlock(systemObject, &address, DispatchQueue.main, listener) == noErr {
            outputListener = listener
        }
    }

    private func unwatchOutputDevice() {
        guard let outputListener else { return }
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(systemObject, &address, DispatchQueue.main, outputListener)
        self.outputListener = nil
    }

    /// Headphones plugged in, AirPods connected: the aggregate device follows the old output; rebuild it.
    /// A new default output (headphones plugged in, AirPods): the aggregate is built on the old one.
    private func outputDeviceChanged() {
        restart()
    }
}
