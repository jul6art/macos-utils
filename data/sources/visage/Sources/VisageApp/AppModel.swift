import AppKit
import AudioSource
import Observation
import SwiftUI

/// The app's state: which AI app, the connection, the settings, and the two windows.
@MainActor
@Observable
final class AppModel {
    let connection: Connection

    var windowMode: WindowMode {
        didSet {
            defaults.set(windowMode.rawValue, forKey: Key.windowMode)
            faceWindow.apply(windowMode)
        }
    }
    var delayMilliseconds: Int {
        didSet {
            defaults.set(delayMilliseconds, forKey: Key.delay)
            connection.delayMilliseconds = delayMilliseconds
        }
    }
    var anticipationMilliseconds: Int {
        didSet { defaults.set(anticipationMilliseconds, forKey: Key.anticipation) }
    }
    var extraLatencyMilliseconds: Int {
        didSet { defaults.set(extraLatencyMilliseconds, forKey: Key.extraLatency) }
    }
    /// The face shown: one of FaceLibrary's, or its point head. A new one is read off the main thread,
    /// then fades in over the old one, even while it speaks.
    var faceID: String {
        didSet {
            defaults.set(faceID, forKey: Key.face)
            let id = faceID
            Task {
                let model = await Task.detached { FaceLibrary.model(id: id) }.value
                guard id == faceID else { return }
                faceDriver.renderer?.fade(to: model)
                previewDriver.renderer?.fade(to: model)
            }
        }
    }

    /// From the hologram of points (0) to the face as real as its model allows (1), spec § 8.3.
    var realism: Double {
        didSet { defaults.set(realism, forKey: Key.realism) }
    }

    /// The face's size, from 0.5 to 2 times the default window.
    var faceScale: Double {
        didSet {
            defaults.set(faceScale, forKey: Key.faceScale)
            faceWindow.resize(scale: faceScale)
        }
    }

    /// The hologram's colour and layers (spec, § 8.2, § 9.2).
    var holoColour: HoloColour {
        didSet { defaults.set(holoColour.rawValue, forKey: Key.holoColour) }
    }
    var halo: Double {
        didSet { defaults.set(halo, forKey: Key.halo) }
    }
    var scanlines: Double {
        didSet { defaults.set(scanlines, forKey: Key.scanlines) }
    }
    var projector: Bool {
        didSet { defaults.set(projector, forKey: Key.projector) }
    }
    var glitches: Bool {
        didSet { defaults.set(glitches, forKey: Key.glitches) }
    }

    /// The camera option: the gaze follows the person, the head gains depth (spec, § 7.1, § 8.2).
    var camera: Bool {
        didSet {
            defaults.set(camera, forKey: Key.camera)
            Task { await applyCamera() }
        }
    }
    /// Whether macOS let Visage use the camera, as last asked.
    var cameraAccess: CameraTracker.Access?

    @ObservationIgnored let cameraTracker = CameraTracker()

    /// The microphone option: the face nods at the person's pauses and thinks once their sentence ends
    /// (spec, § 5, § 7.2). Opened only while the AI's app has its own microphone open.
    var microphone: Bool {
        didSet {
            defaults.set(microphone, forKey: Key.microphone)
            Task { await applyMicrophone() }
        }
    }
    /// Whether macOS let Visage use the microphone, as last asked.
    var microphoneAccess: MicrophoneLevel.Access?

    @ObservationIgnored let microphoneLevel = MicrophoneLevel()
    @ObservationIgnored private var microphoneClosing: Task<Void, Never>?

    /// Whether the face is on screen: the next launch puts it back as it was left.
    var faceShown: Bool {
        didSet { defaults.set(faceShown, forKey: Key.faceShown) }
    }

    /// The settings' thumbnails, per face, made the first time they are shown.
    var thumbnails: [String: CGImage] = [:]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private lazy var faceWindow = FaceWindowController(model: self) { [weak self] in
        self?.faceShown = false
    }
    @ObservationIgnored private lazy var connectWindow = ConnectWindowController(model: self)
    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)
    @ObservationIgnored private lazy var welcomeWindow = WelcomeWindowController(model: self)
    @ObservationIgnored lazy var faceDriver = FaceDriver(model: self)
    /// The settings' and the welcome's preview: the same face, at rest.
    @ObservationIgnored lazy var previewDriver = FaceDriver(model: self, preview: true)

    private enum Key {
        static let app = "app"
        static let windowMode = "windowMode"
        static let delay = "delayMilliseconds"
        static let anticipation = "anticipationMilliseconds"
        static let extraLatency = "extraLatencyMilliseconds"
        static let face = "face"
        static let realism = "realism"
        static let faceShown = "faceShown"
        static let faceScale = "faceScale"
        static let welcomed = "welcomed"
        static let holoColour = "holoColour"
        static let halo = "halo"
        static let scanlines = "scanlines"
        static let projector = "projector"
        static let glitches = "glitches"
        static let camera = "camera"
        static let microphone = "microphone"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.delay: 150, Key.anticipation: 60, Key.extraLatency: 0, Key.faceShown: true, Key.faceScale: 1.0,
            Key.halo: 1.0,
            Key.scanlines: 1.0, Key.projector: true, Key.glitches: true,
        ])
        windowMode = WindowMode(rawValue: defaults.string(forKey: Key.windowMode) ?? "") ?? .floating
        delayMilliseconds = defaults.integer(forKey: Key.delay)
        anticipationMilliseconds = defaults.integer(forKey: Key.anticipation)
        extraLatencyMilliseconds = defaults.integer(forKey: Key.extraLatency)
        faceID = defaults.string(forKey: Key.face) ?? FaceLibrary.faces.first?.id ?? FaceLibrary.points
        realism = defaults.double(forKey: Key.realism)
        faceShown = defaults.bool(forKey: Key.faceShown)
        holoColour = HoloColour(rawValue: defaults.string(forKey: Key.holoColour) ?? "") ?? .braise
        halo = defaults.double(forKey: Key.halo)
        scanlines = defaults.double(forKey: Key.scanlines)
        projector = defaults.bool(forKey: Key.projector)
        glitches = defaults.bool(forKey: Key.glitches)
        camera = defaults.bool(forKey: Key.camera)
        microphone = defaults.bool(forKey: Key.microphone)
        faceScale = min(max(defaults.double(forKey: Key.faceScale), 0.5), 2)
        connection = Connection(delayMilliseconds: defaults.integer(forKey: Key.delay))
        connection.onListeningChange = { [weak self] listening in self?.followListening(listening) }
    }

    /// The first launch welcomes, in front: the AI, the face, where it shows, where to find Visage. The
    /// next ones say nothing: Visage reconnects to the last app and puts the face back as it was left.
    func launch() {
        faceWindow.apply(windowMode)
        if camera { Task { await applyCamera() } }
        if microphone { Task { await applyMicrophone() } }
        faceWindow.resize(scale: faceScale)
        if !defaults.bool(forKey: Key.welcomed) {
            welcomeWindow.show()
        } else if let app = savedApp {
            connect(to: app, showingFace: faceShown)
        } else {
            showConnectWindow()
        }
    }

    /// The welcome is done: the face comes out, and the welcome will not be shown again.
    func finishWelcome() {
        defaults.set(true, forKey: Key.welcomed)
        welcomeWindow.close()
        showFace()
    }

    func connect(to app: AIApp, showingFace: Bool = true) {
        defaults.set(
            app.id == AIApp.claude.id || app.id == AIApp.chatGPT.id ? app.id : app.bundleIDs.first, forKey: Key.app)
        connection.connect(to: app)
        if showingFace { showFace() }
    }

    func disconnect() {
        connection.disconnect()
        defaults.removeObject(forKey: Key.app)
    }

    func showConnectWindow() {
        connectWindow.show()
    }

    func showFace() {
        faceWindow.show()
        faceShown = true
    }

    func hideFace() {
        faceWindow.hide()
        faceShown = false
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func applyCamera() async {
        if camera {
            cameraAccess = await cameraTracker.start()
        } else {
            cameraTracker.stop()
            cameraAccess = nil
        }
    }

    private func applyMicrophone() async {
        if microphone {
            microphoneAccess = await MicrophoneLevel.requestAccess()
            followListening(connection.appListening)
        } else {
            microphoneAccess = nil
            followListening(false)
        }
    }

    /// The microphone opens only while the AI's app has its own open, and closes a little after it: a voice
    /// mode may close and reopen its own between turns.
    private func followListening(_ listening: Bool) {
        microphoneClosing?.cancel()
        microphoneClosing = nil
        guard microphone, microphoneAccess == .allowed else {
            microphoneLevel.stop()
            return
        }
        if listening {
            microphoneLevel.start()
        } else {
            microphoneClosing = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                microphoneLevel.stop()
            }
        }
    }

    func loadThumbnails() async {
        guard thumbnails.isEmpty else { return }
        thumbnails = await FaceLibrary.thumbnails()
    }

    /// Apps playing sound right now, other than the known ones: candidates for « Another app ».
    func otherApps() -> [AIApp] {
        let known = Set(AIApp.known.flatMap(\.bundleIDs))
        let playing = AudioProcesses.all().filter { $0.isRunningOutput && !$0.bundleID.isEmpty }
        var seen = Set<String>()
        return playing.compactMap { process in
            let bundleID = process.bundleID
            guard !known.contains(where: { bundleID.hasPrefix($0) }), seen.insert(bundleID).inserted,
                bundleID != Bundle.main.bundleIdentifier
            else { return nil }
            let name =
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) } ?? process.executableName
            return AIApp.other(bundleID, name: name)
        }
    }

    private var savedApp: AIApp? {
        guard let saved = defaults.string(forKey: Key.app) else { return nil }
        if let known = AIApp.known.first(where: { $0.id == saved }) { return known }
        return AIApp.other(saved, name: saved)
    }
}

/// How the face's window sits on the desktop (spec, § 9.1).
/// Two modes since the first test with Claude (2026-11-26): a third, transparent among the other windows,
/// let the face vanish behind Claude as soon as Claude was clicked. A setting saved with it reads as
/// `floating`.
enum WindowMode: String, CaseIterable, Identifiable {
    /// No frame, no background, above every window, on every desktop: always in sight.
    case floating
    /// A plain window with a title bar and a dark background: screen sharing, recording.
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floating: String(localized: "Floating")
        case .classic: String(localized: "Classic")
        }
    }

    var detail: String {
        switch self {
        case .floating: String(localized: "Transparent, above every window, on every desktop: always in sight.")
        case .classic:
            String(
                localized: "A plain window, with a title bar and a dark background: to share your screen or record it.")
        }
    }
}
