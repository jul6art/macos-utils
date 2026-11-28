import AppKit
import AudioSource
import Shared
import SwiftUI

/// The menu bar menu, and a face's context menu. With one face, its items directly; with several, a menu
/// each, named after its head and its AI (spec, § 9.3).
struct MenuContent: View {
    let model: AppModel
    /// A face's own menu (a right click on it); the menu bar's shows them all.
    var slot: FaceSlot?

    var body: some View {
        if let slot {
            FaceMenu(model: model, slot: slot)
        } else if model.slots.count == 1 {
            FaceMenu(model: model, slot: model.slots[0])
        } else {
            ForEach(model.slots) { slot in
                Menu(slot.title) { FaceMenu(model: model, slot: slot) }
            }
        }
        Divider()
        Button("Add a face") { model.addFace() }
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Quit Visage") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// What a face's menu holds: its state, its AI, whether it shows, its window and its head.
private struct FaceMenu: View {
    let model: AppModel
    let slot: FaceSlot

    var body: some View {
        Text(status)
        Divider()
        if slot.connection.app != nil {
            Button("Disconnect") { model.disconnect(slot) }
        }
        Button("Connect my AI…") { model.showConnectWindow(for: slot) }
        if slot.faceShown {
            Button("Hide the face") { slot.hide() }
        } else {
            Button("Show the face") { slot.show() }
        }
        Picker("Window", selection: Binding(get: { slot.windowMode }, set: { slot.windowMode = $0 })) {
            ForEach(WindowMode.allCases) { Text($0.title).tag($0) }
        }
        FacePicker(slot: slot)
        if model.slots.count > 1 {
            Button("Remove this face") { model.removeFace(slot) }
        }
    }

    private var status: String {
        let name = slot.connection.app?.name ?? ""
        switch slot.connection.state {
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
/// (docs/charter.md, § 2).
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
