import AppKit
import AudioSource
import Observation
import Shared
import SwiftUI

/// The app's state: the faces, each with its AI and its window (`FaceSlot`), the settings they share, and
/// the windows around them. The settings, the welcome and « Connect my AI » show the selected face: its
/// settings read and write through here.
@MainActor
@Observable
final class AppModel {
    /// The faces, in the order they were added; never empty.
    private(set) var slots: [FaceSlot] = []
    /// The face the settings and « Connect my AI » show.
    var selectedID = FaceSlot.mainID {
        didSet {
            guard selectedID != oldValue else { return }
            let id = selected.faceID
            Task {
                let head = await Task.detached { FaceLibrary.model(id: id) }.value
                previewDriver.renderer?.fade(to: head)
            }
        }
    }
    var selected: FaceSlot { slots.first { $0.id == selectedID } ?? slots[0] }

    // MARK: - The selected face's settings

    var connection: Connection { selected.connection }
    var faceDriver: FaceDriver { selected.driver }
    var faceID: String {
        get { selected.faceID }
        set { selected.faceID = newValue }
    }
    var realism: Double {
        get { selected.realism }
        set { selected.realism = newValue }
    }
    var faceScale: Double {
        get { selected.faceScale }
        set { selected.faceScale = newValue }
    }
    var holoColour: HoloColour {
        get { selected.holoColour }
        set { selected.holoColour = newValue }
    }
    var halo: Double {
        get { selected.halo }
        set { selected.halo = newValue }
    }
    var scanlines: Double {
        get { selected.scanlines }
        set { selected.scanlines = newValue }
    }
    var projector: Bool {
        get { selected.projector }
        set { selected.projector = newValue }
    }
    var glitches: Bool {
        get { selected.glitches }
        set { selected.glitches = newValue }
    }
    var windowMode: WindowMode {
        get { selected.windowMode }
        set { selected.windowMode = newValue }
    }
    var faceShown: Bool { selected.faceShown }
    var backdrop: Bool {
        get { selected.backdrop }
        set { selected.backdrop = newValue }
    }

    // MARK: - The shared settings

    var delayMilliseconds: Int {
        didSet {
            defaults.set(delayMilliseconds, forKey: Key.delay)
            for slot in slots { slot.connection.delayMilliseconds = delayMilliseconds }
        }
    }
    var anticipationMilliseconds: Int {
        didSet { defaults.set(anticipationMilliseconds, forKey: Key.anticipation) }
    }
    var extraLatencyMilliseconds: Int {
        didSet { defaults.set(extraLatencyMilliseconds, forKey: Key.extraLatency) }
    }

    /// The camera option: the gaze follows the person, the head turns to them (spec, § 7.1, § 8.2).
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
    /// (spec, § 5, § 7.2). Opened only while an AI's app has its own microphone open.
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

    /// Whether Siri is among the AIs of « Connect my AI » (spec, § 4.5): off at first, as Siri speaks only
    /// once its voice responses are on. Turned off while a face listens to Siri, that face disconnects.
    var siri: Bool {
        didSet {
            defaults.set(siri, forKey: Key.siri)
            if !siri { for slot in slots where slot.connection.app?.kind == .siri { disconnect(slot) } }
        }
    }

    /// The AIs « Connect my AI » offers.
    var apps: [AIApp] { AIApp.known.filter { siri || $0.kind != .siri } }

    /// The AIs another face than the selected one listens to: one AI has one face, as two would mute and
    /// play its voice twice.
    var appsElsewhere: Set<String> {
        Set(slots.filter { $0 !== selected }.compactMap { $0.connection.app?.id ?? $0.source })
    }

    /// The settings' thumbnails, per face, made the first time they are shown.
    var thumbnails: [String: CGImage] = [:]
    /// A still of the face in place of the live preview: for the snapshots, as an offscreen window does not
    /// draw Metal.
    var previewStill: CGImage?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private lazy var connectWindow = ConnectWindowController(model: self)
    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)
    @ObservationIgnored private lazy var welcomeWindow = WelcomeWindowController(model: self)
    /// The settings' and the welcome's preview: the selected face, at rest.
    @ObservationIgnored lazy var previewDriver = FaceDriver(model: self, preview: true)
    /// While the faces are read at launch, nothing is saved.
    @ObservationIgnored private var loading = true

    private enum Key {
        static let faces = ClaudeCodeVoice.facesKey
        static let delay = "delayMilliseconds"
        static let anticipation = "anticipationMilliseconds"
        static let extraLatency = "extraLatencyMilliseconds"
        static let welcomed = "welcomed"
        static let camera = "camera"
        static let microphone = "microphone"
        static let siri = "siri"
        /// A face's settings, as Visage kept them before there could be several: read once, into the first.
        static let single = [
            ClaudeCodeVoice.sourceKey, ClaudeCodeVoice.faceKey, "realism", "faceScale", "holoColour", "halo",
            "scanlines", "projector", "glitches", "windowMode", "faceShown",
        ]
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Key.delay: 150, Key.anticipation: 60, Key.extraLatency: 0])
        delayMilliseconds = defaults.integer(forKey: Key.delay)
        anticipationMilliseconds = defaults.integer(forKey: Key.anticipation)
        extraLatencyMilliseconds = defaults.integer(forKey: Key.extraLatency)
        camera = defaults.bool(forKey: Key.camera)
        microphone = defaults.bool(forKey: Key.microphone)
        siri = defaults.bool(forKey: Key.siri)

        let saved = (defaults.array(forKey: Key.faces) as? [[String: Any]] ?? []).filter { FaceSlot.id(of: $0) != nil }
        if saved.isEmpty {
            // Before there could be several faces, their settings sat each under its own name.
            var single: [String: Any] = [:]
            for key in Key.single { single[key] = defaults.object(forKey: key) }
            slots = [makeSlot(id: FaceSlot.mainID, settings: single)]
        } else {
            slots = saved.map { makeSlot(id: FaceSlot.id(of: $0)!, settings: $0) }
        }
        selectedID = slots[0].id
        loading = false
    }

    private func makeSlot(id: String, settings: [String: Any]) -> FaceSlot {
        let slot = FaceSlot(model: self, id: id, settings: settings, delayMilliseconds: delayMilliseconds)
        slot.connection.onListeningChange = { [weak self] _ in self?.followListening() }
        return slot
    }

    /// Saves the faces, after any change to one of them.
    func save() {
        guard !loading else { return }
        defaults.set(slots.map(\.settings), forKey: Key.faces)
    }

    /// The first launch welcomes, in front: the AI, the face, where it shows, where to find Visage. The
    /// next ones say nothing: each face reconnects to its AI and comes back as it was left.
    func launch() {
        if camera { Task { await applyCamera() } }
        if microphone { Task { await applyMicrophone() } }
        for slot in slots {
            slot.window.apply(slot.windowMode)
            slot.window.resize(scale: slot.faceScale)
        }
        if !defaults.bool(forKey: Key.welcomed) {
            welcomeWindow.show()
            return
        }
        for slot in slots {
            if let app = savedApp(of: slot) {
                connect(slot, to: app, showingFace: slot.faceShown)
            } else if slot.faceShown {
                slot.window.show()
            }
        }
        if savedApp(of: slots[0]) == nil { showConnectWindow() }
    }

    /// The welcome is done: the face comes out, and the welcome will not be shown again.
    func finishWelcome() {
        defaults.set(true, forKey: Key.welcomed)
        welcomeWindow.close()
        showFace()
    }

    // MARK: - Connecting, showing, adding a face

    /// Connects the selected face.
    func connect(to app: AIApp, showingFace: Bool = true) {
        connect(selected, to: app, showingFace: showingFace)
    }

    func connect(_ slot: FaceSlot, to app: AIApp, showingFace: Bool = true) {
        // One AI has one face: another face listening to it lets go of it.
        for other in slots where other !== slot && other.connection.app?.id == app.id { disconnect(other) }
        slot.source = AIApp.known.contains { $0.id == app.id } ? app.id : app.bundleIDs.first
        slot.connection.connect(to: app)
        if showingFace { slot.show() }
    }

    /// Disconnects the selected face.
    func disconnect() {
        disconnect(selected)
    }

    func disconnect(_ slot: FaceSlot) {
        slot.connection.disconnect()
        slot.source = nil
    }

    func showConnectWindow() {
        connectWindow.show()
    }

    /// Opens « Connect my AI » for a face.
    func showConnectWindow(for slot: FaceSlot) {
        selectedID = slot.id
        connectWindow.show()
    }

    func showFace() {
        selected.show()
    }

    func hideFace() {
        selected.hide()
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// A new face, another head than the others, a little aside: selected, it waits for its AI.
    func addFace() {
        let used = Set(slots.map(\.faceID))
        let head = FaceLibrary.faces.first { !used.contains($0.id) }?.id ?? selected.faceID
        var settings = selected.settings
        settings[ClaudeCodeVoice.sourceKey] = nil
        settings[ClaudeCodeVoice.faceKey] = head
        let slot = makeSlot(id: UUID().uuidString, settings: settings)
        slots.append(slot)
        save()
        slot.window.apply(slot.windowMode)
        slot.window.resize(scale: slot.faceScale)
        slot.window.placeBeside(selected.window)
        slot.show()
        showConnectWindow(for: slot)
    }

    /// Removes a face; the last one stays.
    func removeFace(_ slot: FaceSlot) {
        guard slots.count > 1 else { return }
        slot.connection.disconnect()
        slot.window.hide()
        slots.removeAll { $0 === slot }
        if selectedID == slot.id { selectedID = slots[0].id }
        save()
        followListening()
    }

    /// Quitting: every AI gets its sound back.
    func disconnectAll() {
        for slot in slots { slot.connection.disconnect() }
    }

    // MARK: - Camera and microphone

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
        } else {
            microphoneAccess = nil
        }
        followListening()
    }

    /// The microphone opens only while an AI's app has its own open, and closes a little after it: a voice
    /// mode may close and reopen its own between turns.
    private func followListening() {
        let listening = slots.contains { $0.connection.appListening }
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

    /// Whether Claude Code's plugin has run on this Mac: its hooks call Visage's helper, which notes it.
    var claudeCodePluginSeen: Bool {
        defaults.double(forKey: ClaudeCodeVoice.pluginSeenKey) > 0
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

    /// The AI a face reconnects to at launch.
    private func savedApp(of slot: FaceSlot) -> AIApp? {
        guard let saved = slot.source else { return nil }
        if let known = AIApp.known.first(where: { $0.id == saved }) { return apps.contains(known) ? known : nil }
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
