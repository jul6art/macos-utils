import AppKit
import CoreAudio
import Foundation
import Observation

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
        /// The app has been playing for a while and nothing of it came through: macOS keeps its sound from
        /// Visage (not allowed, or allowed for an earlier build of the app).
        case permissionMissing
        /// Process mode only: the app has no audio process yet; it gets one when it first speaks.
        case waitingForApp
        case connected
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var app: AIApp?
    public private(set) var capture: AudioCapture?
    public var delayMilliseconds: Int {
        didSet { capture?.setDelay(milliseconds: delayMilliseconds) }
    }

    /// Bundle mode (macOS 26) lets Core Audio follow the app; process mode follows its processes by hand.
    public var usesBundleMode: Bool {
        if #available(macOS 26, *) { return !Self.forceProcessMode }
        return false
    }

    /// For the pilot's comparisons, and as a way out if bundle mode misbehaves on some app.
    public static var forceProcessMode: Bool {
        UserDefaults.standard.bool(forKey: "forceProcessMode")
    }

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tappedProcesses: Set<AudioObjectID> = []
    @ObservationIgnored private var watchdog: Timer?
    /// How long the app has been playing, in watchdog ticks (seconds), while the capture listens.
    @ObservationIgnored private var playingSeconds = 0.0
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
        if installation.url.pathExtension == "app", !app.isRunning {
            NSWorkspace.shared.openApplication(at: installation.url, configuration: NSWorkspace.OpenConfiguration())
        }
        watchOutputDevice()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.watch() }
        }
        start(bundleID: installation.bundleID)
    }

    public func disconnect() {
        generation += 1
        watchdog?.invalidate()
        watchdog = nil
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
        var target = CaptureTarget()
        if usesBundleMode, bundleID.contains(".") {
            target.bundleIDs = Array(Set(processes.map(\.bundleID).filter { !$0.isEmpty } + [bundleID])).sorted()
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
        playingSeconds = 0
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

    private func stopCapture() {
        capture?.stop()
        capture = nil
        tappedProcesses = []
    }

    // MARK: - Keeping it alive

    private func watch() {
        guard let app, let bundleID = app.installation?.bundleID ?? app.bundleIDs.first else { return }
        switch state {
        case .waitingForApp:
            start(bundleID: bundleID)
        case .connected, .permissionMissing:
            let processes = AudioProcesses.matching(bundleID, in: AudioProcesses.all())
            // Process mode: a new helper, or the app restarted with new processes.
            if !usesBundleMode || !bundleID.contains(".") {
                let objects = Set(processes.map(\.objectID))
                if !objects.isEmpty, objects != tappedProcesses {
                    start(bundleID: bundleID)
                    return
                }
            }
            // Is the app's sound coming through? The user may also have allowed it meanwhile.
            guard let capture else { return }
            playingSeconds = processes.contains(where: \.isRunningOutput) ? playingSeconds + 1 : 0
            let missing = Self.permissionLooksMissing(
                heardSomething: capture.heardCallbacks.load(ordering: .relaxed) > 0, playingFor: playingSeconds)
            if missing != (state == .permissionMissing) { state = missing ? .permissionMissing : .connected }
        default:
            break
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
    private func outputDeviceChanged() {
        guard let app, capture != nil, let bundleID = app.installation?.bundleID ?? app.bundleIDs.first else { return }
        start(bundleID: bundleID)
    }
}
