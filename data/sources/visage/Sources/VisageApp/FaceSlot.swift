import AppKit
import AudioSource
import Observation
import Shared

/// One face on the desktop (spec, § 9.3): its AI, its head, its hologram and its window. Several can run at
/// once, each with an AI of its own (Claude Desktop in one, Siri in another), never the same twice. The
/// sync, the camera and the microphone are shared by all of them.
@MainActor
@Observable
final class FaceSlot: Identifiable {
    /// "main" for the first face, the one Visage had before there could be several: its window keeps its
    /// place.
    let id: String
    let connection: Connection

    /// The AI to reconnect to at launch: a known app's id, or another app's bundle ID.
    var source: String? {
        didSet { changed() }
    }
    /// The face shown: one of FaceLibrary's, or its point head. A new one is read off the main thread, then
    /// fades in over the old one, even while it speaks.
    var faceID: String {
        didSet {
            changed()
            fadeToFace()
        }
    }
    /// From the hologram of points (0) to the face as real as its model allows (1), spec § 8.3.
    var realism: Double {
        didSet { changed() }
    }
    /// The face's size, from 0.5 to 2 times the default window.
    var faceScale: Double {
        didSet {
            changed()
            window.resize(scale: faceScale)
        }
    }
    /// The hologram's colour and layers (spec, § 8.2, § 9.2).
    var holoColour: HoloColour {
        didSet { changed() }
    }
    var halo: Double {
        didSet { changed() }
    }
    var scanlines: Double {
        didSet { changed() }
    }
    var projector: Bool {
        didSet { changed() }
    }
    var glitches: Bool {
        didSet { changed() }
    }
    var windowMode: WindowMode {
        didSet {
            changed()
            window.apply(windowMode)
        }
    }
    /// Whether the face is on screen: the next launch puts it back as it was left.
    var faceShown: Bool {
        didSet { changed() }
    }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored lazy var driver = FaceDriver(model: model!, slot: self)
    @ObservationIgnored lazy var window = FaceWindowController(model: model!, slot: self) { [weak self] in
        self?.faceShown = false
    }

    /// The window's saved place: the first face keeps the one it had before there could be several.
    var windowName: String { id == Self.mainID ? "VisageFace" : "VisageFace-\(id)" }

    static let mainID = "main"

    private enum Key {
        static let id = "id"
        static let source = ClaudeCodeVoice.sourceKey
        static let face = ClaudeCodeVoice.faceKey
        static let realism = "realism"
        static let faceScale = "faceScale"
        static let holoColour = "holoColour"
        static let halo = "halo"
        static let scanlines = "scanlines"
        static let projector = "projector"
        static let glitches = "glitches"
        static let windowMode = "windowMode"
        static let faceShown = "faceShown"
    }

    /// A face from its saved settings: an entry of `faces`, or the settings Visage kept before there could
    /// be several, which use the same names. What is missing takes the first launch's value.
    init(model: AppModel, id: String, settings: [String: Any], delayMilliseconds: Int) {
        self.model = model
        self.id = id
        connection = Connection(delayMilliseconds: delayMilliseconds)
        source = settings[Key.source] as? String
        faceID = settings[Key.face] as? String ?? FaceLibrary.faces.first?.id ?? FaceLibrary.points
        realism = settings[Key.realism] as? Double ?? 0
        faceScale = min(max(settings[Key.faceScale] as? Double ?? 1, 0.5), 2)
        holoColour = HoloColour(rawValue: settings[Key.holoColour] as? String ?? "") ?? .braise
        halo = settings[Key.halo] as? Double ?? 1
        scanlines = settings[Key.scanlines] as? Double ?? 1
        projector = settings[Key.projector] as? Bool ?? true
        glitches = settings[Key.glitches] as? Bool ?? true
        windowMode = WindowMode(rawValue: settings[Key.windowMode] as? String ?? "") ?? .floating
        faceShown = settings[Key.faceShown] as? Bool ?? true
    }

    /// What is saved of it, in `faces`; Claude Code's voice reads `source` and `face` there.
    var settings: [String: Any] {
        var settings: [String: Any] = [
            Key.id: id, Key.face: faceID, Key.realism: realism, Key.faceScale: faceScale,
            Key.holoColour: holoColour.rawValue, Key.halo: halo, Key.scanlines: scanlines, Key.projector: projector,
            Key.glitches: glitches, Key.windowMode: windowMode.rawValue, Key.faceShown: faceShown,
        ]
        if let source { settings[Key.source] = source }
        return settings
    }

    static func id(of settings: [String: Any]) -> String? { settings[Key.id] as? String }

    /// The face's name, and its AI's: how the menu and the settings tell the faces apart.
    var title: String {
        let face = FaceLibrary.choices.first { $0.id == faceID }?.name ?? "Visage"
        guard let app = connection.app else { return face }
        return "\(face) · \(app.name)"
    }

    func show() {
        window.show()
        faceShown = true
    }

    func hide() {
        window.hide()
        faceShown = false
    }

    private func changed() {
        model?.save()
    }

    private func fadeToFace() {
        let id = faceID
        Task {
            let head = await Task.detached { FaceLibrary.model(id: id) }.value
            guard id == faceID else { return }
            driver.renderer?.fade(to: head)
            if model?.selected === self { model?.previewDriver.renderer?.fade(to: head) }
        }
    }
}
