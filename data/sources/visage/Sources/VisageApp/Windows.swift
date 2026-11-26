import AppKit
import SwiftUI

/// The face's window. AppKit rather than a SwiftUI scene: the three modes change the window's style, level
/// and background on the fly, which a scene cannot.
@MainActor
final class FaceWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        window = FaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: FaceView(model: model))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 200, height: 240)
        window.title = "Visage"
        window.setFrameAutosaveName("VisageFace")
        if !window.setFrameUsingName("VisageFace") { window.center() }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func apply(_ mode: WindowMode) {
        let frame = window.frame
        switch mode {
        case .transparent, .floating:
            window.styleMask = [.borderless, .resizable]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
        case .classic:
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isOpaque = true
            window.backgroundColor = Palette.charbon
            window.hasShadow = true
            window.isMovableByWindowBackground = false
        }
        window.level = mode == .floating ? .floating : .normal
        window.collectionBehavior = mode == .floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        window.setFrame(frame, display: true)
    }
}

/// A borderless window can still take clicks and keys (to be dragged, to show its menu).
private final class FaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// « Connect my AI ».
@MainActor
final class ConnectWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Connect my AI")
        window.contentView = NSHostingView(rootView: ConnectScreen(model: model))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// The charter's colours (docs/charte.md, § 3).
enum Palette {
    static let charbon = NSColor(srgbRed: 0x0E / 255, green: 0x0C / 255, blue: 0x0A / 255, alpha: 1)
    static let braise = Color(red: 0xFF / 255, green: 0xC9 / 255, blue: 0x78 / 255)
    static let orPale = Color(red: 0xFF / 255, green: 0xE9 / 255, blue: 0xC4 / 255)
    static let cendre = Color(red: 0x6E / 255, green: 0x65 / 255, blue: 0x5B / 255)
}
