import AppKit
import SwiftUI

/// The face's window. AppKit rather than a SwiftUI scene: the three modes change the window's style, level
/// and background on the fly, which a scene cannot.
@MainActor
final class FaceWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    /// Told when the window closes by its own button (the classic mode's).
    private let closed: () -> Void

    init(model: AppModel, closed: @escaping () -> Void) {
        window = FaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        self.closed = closed
        super.init()
        window.contentView = NSHostingView(rootView: FaceView(model: model))
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 200, height: 240)
        window.title = "Visage"
        window.setFrameAutosaveName("VisageFace")
        if !window.setFrameUsingName("VisageFace") { window.center() }
        window.delegate = self
    }

    var isVisible: Bool { window.isVisible }

    /// The face's size, from half to twice the default window, about the window's centre.
    func resize(scale: Double) {
        let size = NSSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        let frame = window.frame
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        window.setFrame(
            NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height),
            display: true, animate: window.isVisible)
    }

    static let baseSize = NSSize(width: 420, height: 520)

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { closed() }
    }

    func apply(_ mode: WindowMode) {
        let frame = window.frame
        switch mode {
        case .floating:
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
        BrandWindow.style(window)
        window.center()
    }

    func show() {
        Foreground.show(window)
    }

    func close() {
        window.close()
    }
}

/// The settings (spec, § 9.2), in a window of Visage's own rather than SwiftUI's settings scene: shown in
/// front, as the others are.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Settings")
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        BrandWindow.style(window)
        window.center()
    }

    func show() {
        Foreground.show(window)
    }
}

/// The first launch's welcome: the AI, the face, where it shows, and where to find Visage again.
@MainActor
final class WelcomeWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 820),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Visage")
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.isReleasedWhenClosed = false
        BrandWindow.style(window)
        window.center()
    }

    func show() {
        Foreground.show(window)
    }

    func close() {
        window.close()
    }
}

/// Visage lives in the menu bar, without a Dock icon: macOS never brings such an app forward, and its
/// windows opened behind the others' (the settings, the connection). While one of its own windows is
/// open, it becomes an ordinary app, in front, with a Dock icon; it returns to the menu bar when the last
/// one closes. The face's window is not one of them: it floats on its own.
@MainActor
enum Foreground {
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func show(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if observers[id] == nil {
            observers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { closed(id) }
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func closed(_ id: ObjectIdentifier) {
        if let observer = observers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        if observers.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The charter's colours (docs/charter.md, § 3).
enum Palette {
    static let charbon = NSColor(srgbRed: 0x0E / 255, green: 0x0C / 255, blue: 0x0A / 255, alpha: 1)
    static let braise = Color(red: 0xFF / 255, green: 0xC9 / 255, blue: 0x78 / 255)
    static let orPale = Color(red: 0xFF / 255, green: 0xE9 / 255, blue: 0xC4 / 255)
    static let cendre = Color(red: 0x6E / 255, green: 0x65 / 255, blue: 0x5B / 255)
    /// The secondary text on charbon: cendre itself is too faint there to read small type.
    static let cendreClaire = Color(red: 0xA9 / 255, green: 0x9D / 255, blue: 0x8E / 255)
    static let brou = Color(red: 0x3A / 255, green: 0x26 / 255, blue: 0x12 / 255)
    /// Charbon, lifted: the branded screens' cards.
    static let surface = Color(red: 0x17 / 255, green: 0x13 / 255, blue: 0x0F / 255)
}
