import AppKit
import AudioSource
import FaceAnimation
import HoloRenderer
import SwiftUI

/// `Visage --snapshot <directory>`: the screens, rendered offscreen to PNG files, in every state that
/// matters. An offscreen window rather than `ImageRenderer`, which draws AppKit-backed controls as
/// placeholders.
@MainActor
enum Snapshots {
    static func render(into directory: URL) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let apps = [
            AppCardInfo(app: .claude, isInstalled: true, isRunning: true),
            AppCardInfo(app: .chatGPT, isInstalled: false, isRunning: false),
        ]
        let others = [AIApp.other("com.example.voice", name: "Example Voice")]
        let states: [(String, Connection.State, AIApp?)] = [
            ("connect-idle", .idle, nil),
            ("connect-permission", .permissionMissing, .claude),
            ("connect-waiting", .waitingForApp, .claude),
            ("connect-connected", .connected, .claude),
        ]
        var failures = 0
        for (name, state, app) in states {
            let view = ConnectView(
                state: state, connectedApp: app, apps: apps, otherApps: others, connect: { _ in },
                showFace: {})
            if !write(view, size: NSSize(width: 560, height: 400), to: directory.appending(path: "\(name).png")) {
                failures += 1
            }
        }
        let face = MarkView(size: 360).padding(20).background(Color(nsColor: Palette.charbon))
        if !write(face, size: NSSize(width: 400, height: 400), to: directory.appending(path: "face.png")) {
            failures += 1
        }
        // The hologram at rest, transparent (the floating windows) and on charbon (the classic one).
        if let renderer = HoloRenderer() {
            let animator = FaceAnimator(seed: 1)
            var pose = FacePose()
            for _ in 0..<90 { pose = animator.update(dt: 1.0 / 60, voice: nil, moment: .waiting) }
            var settings = HoloSettings()
            for (name, background) in [
                ("hologram-transparent", SIMD4<Float>(0, 0, 0, 0)), ("hologram-classic", HoloSettings.charbon),
            ] {
                settings.background = background
                if let image = renderer.image(pose: pose, time: 1.5, settings: settings, width: 480, height: 600) {
                    VideoRender.savePNG(image, to: directory.appending(path: "\(name).png"))
                } else {
                    failures += 1
                }
            }
        } else {
            failures += 1
        }
        return failures == 0 ? 0 : 1
    }

    private static func write(_ view: some View, size: NSSize, to url: URL) -> Bool {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
