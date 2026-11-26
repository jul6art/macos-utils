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

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private lazy var faceWindow = FaceWindowController(model: self)
    @ObservationIgnored private lazy var connectWindow = ConnectWindowController(model: self)
    @ObservationIgnored lazy var faceDriver = FaceDriver(model: self)

    private enum Key {
        static let app = "app"
        static let windowMode = "windowMode"
        static let delay = "delayMilliseconds"
        static let anticipation = "anticipationMilliseconds"
        static let extraLatency = "extraLatencyMilliseconds"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Key.delay: 150, Key.anticipation: 60, Key.extraLatency: 0])
        windowMode = WindowMode(rawValue: defaults.string(forKey: Key.windowMode) ?? "") ?? .transparent
        delayMilliseconds = defaults.integer(forKey: Key.delay)
        anticipationMilliseconds = defaults.integer(forKey: Key.anticipation)
        extraLatencyMilliseconds = defaults.integer(forKey: Key.extraLatency)
        connection = Connection(delayMilliseconds: defaults.integer(forKey: Key.delay))
    }

    /// Reconnects to the last app, or asks which one.
    func launch() {
        faceWindow.apply(windowMode)
        if let app = savedApp {
            connect(to: app)
        } else {
            showConnectWindow()
        }
    }

    func connect(to app: AIApp) {
        defaults.set(
            app.id == AIApp.claude.id || app.id == AIApp.chatGPT.id ? app.id : app.bundleIDs.first, forKey: Key.app)
        connection.connect(to: app)
        faceWindow.show()
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
enum WindowMode: String, CaseIterable, Identifiable {
    /// No frame, no background: the face floats on the desktop.
    case transparent
    /// Transparent, above every window, on every desktop.
    case floating
    /// A plain window with a title bar and a dark background: screen sharing, recording.
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transparent: String(localized: "Transparent")
        case .floating: String(localized: "Floating")
        case .classic: String(localized: "Classic")
        }
    }
}
