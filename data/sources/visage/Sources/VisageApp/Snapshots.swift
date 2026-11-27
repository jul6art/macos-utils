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
        // The faces as holograms, then as real as they get (§ 8.3).
        for (name, realism) in [("faces", Float(0)), ("faces-real", 1)]
        where !FaceLibrary.faces.isEmpty
            && !writeFaceSheet(to: directory.appending(path: "\(name).png"), realism: realism)
        {
            failures += 1
        }
        // The settings, their thumbnails already made (the window makes them the first time it opens).
        let model = AppModel()
        model.thumbnails = FaceLibrary.makeThumbnails(FaceLibrary.choices.map(\.id))
        // The live preview is Metal, which an offscreen window leaves blank: a still of the same face instead.
        if let renderer = HoloRenderer() {
            model.previewStill = FaceLibrary.portrait(
                FaceLibrary.model(id: model.faceID), renderer: renderer, width: 520, height: 650, seed: 1,
                realism: Float(model.realism))
        }
        if !write(
            SettingsView(model: model), size: NSSize(width: 860, height: 720),
            to: directory.appending(path: "settings.png"), dark: true)
        {
            failures += 1
        }
        // The cards below the fold of the settings' snapshot, one each (no AI connected in a snapshot).
        let cards: [(name: String, title: String, height: CGFloat, content: AnyView)] = [
            ("settings-hologram", String(localized: "Hologram"), 360, AnyView(HologramSettings(model: model))),
            (
                "settings-conversation", String(localized: "Conversation"), 220,
                AnyView(ConversationSettings(model: model))
            ),
            ("settings-camera", String(localized: "Camera"), 190, AnyView(CameraSettings(model: model))),
            ("settings-window", String(localized: "Window"), 190, AnyView(WindowModeChoice(model: model))),
            ("settings-sync", String(localized: "Sync"), 300, AnyView(SyncSettings(model: model))),
        ]
        for card in cards {
            let view = BrandCard(title: card.title) { card.content }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: Palette.charbon)).foregroundStyle(Palette.orPale)
                .tint(Palette.braise)
            if !write(
                view, size: NSSize(width: 560, height: card.height),
                to: directory.appending(path: "\(card.name).png"), dark: true)
            {
                failures += 1
            }
        }
        // The first launch's welcome, its AI not chosen yet.
        if !write(
            WelcomeView(model: model), size: NSSize(width: 860, height: 820),
            to: directory.appending(path: "welcome.png"), dark: true)
        {
            failures += 1
        }
        return failures == 0 ? 0 : 1
    }

    /// The faces side by side, at rest on charbon, five to a row: to compare them at a glance.
    private static func writeFaceSheet(to url: URL, realism: Float) -> Bool {
        let faces = FaceLibrary.faces
        let (width, height, columns) = (320, 400, 5)
        let rows = (faces.count + columns - 1) / columns
        guard let renderer = HoloRenderer(),
            let sheet = CGContext(
                data: nil, width: width * columns, height: height * rows, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        for (index, face) in faces.enumerated() {
            guard
                let image = FaceLibrary.portrait(
                    FaceLibrary.model(id: face.id), renderer: renderer, width: width, height: height,
                    seed: UInt32(index + 1), realism: realism)
            else { return false }
            let (column, row) = (index % columns, index / columns)
            sheet.draw(
                image,
                in: CGRect(x: column * width, y: (rows - 1 - row) * height, width: width, height: height))
        }
        guard let image = sheet.makeImage() else { return false }
        VideoRender.savePNG(image, to: url)
        return true
    }

    private static func write(_ view: some View, size: NSSize, to url: URL, dark: Bool = false) -> Bool {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        if dark { hosting.appearance = NSAppearance(named: .darkAqua) }
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
