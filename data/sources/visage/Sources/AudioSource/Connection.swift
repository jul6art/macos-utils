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
        /// The IO never ran: macOS refused, or the user has not allowed system audio recording yet.
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
        // Without permission the IO never runs: no callback, not even silence.
        try? await Task.sleep(for: .seconds(3))
        guard attempt == generation else { return }
        state = capture.callbacks.load(ordering: .relaxed) > 0 ? .connected : .permissionMissing
    }

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
        case .connected where !usesBundleMode || !bundleID.contains("."):
            // Process mode: a new helper, or the app restarted with new processes.
            let processes = Set(AudioProcesses.matching(bundleID, in: AudioProcesses.all()).map(\.objectID))
            if !processes.isEmpty, processes != tappedProcesses { start(bundleID: bundleID) }
        case .permissionMissing:
            // The user may have allowed it in System Settings meanwhile.
            if let capture, capture.callbacks.load(ordering: .relaxed) > 0 { state = .connected }
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
