import AppKit
import AudioSource
import Shared
import SwiftUI

/// The menu bar menu (and the face's context menu).
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(status)
        Divider()
        if model.connection.app != nil {
            Button("Disconnect") { model.disconnect() }
        }
        Button("Connect my AI…") { model.showConnectWindow() }
        if model.faceShown {
            Button("Hide the face") { model.hideFace() }
        } else {
            Button("Show the face") { model.showFace() }
        }
        Picker(
            "Window",
            selection: Binding(get: { model.windowMode }, set: { model.windowMode = $0 })
        ) {
            ForEach(WindowMode.allCases) { Text($0.title).tag($0) }
        }
        FacePicker(model: model)
        Divider()
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Quit Visage") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        let name = model.connection.app?.name ?? ""
        switch model.connection.state {
        case .connected: return String(localized: "Connected to \(name)")
        case .starting: return String(localized: "Connecting…")
        case .waitingForPermission, .permissionMissing: return String(localized: "Waiting for permission")
        case .waitingForApp: return String(localized: "Waiting for \(name)")
        case .notInstalled: return String(localized: "\(name) is not installed")
        case .failed: return String(localized: "Connection failed")
        case .idle: return String(localized: "Not connected")
        }
    }
}

/// The menu bar icon: the charter's glyph, as a template image macOS tints for the menu bar
/// (docs/charte.md, § 2).
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            for (point, radius, opacity) in MenuBarGlyph.dots {
                NSColor.black.withAlphaComponent(opacity).setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
