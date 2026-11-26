import AppKit
import AudioSource
import FaceAnimation
import HoloRenderer
import MetalKit
import Shared
import SwiftUI
import VoiceAnalysis

/// Drives the face on screen: at each displayed frame, which sound will be heard at that instant, the voice
/// read `anticipation` ahead of it, the animation, the hologram (spec, § 7.1, point 9). As a `preview`
/// (the settings', the welcome's), it hears nothing: the face at rest, on charbon, as the settings make it.
@MainActor
final class FaceDriver: NSObject, MTKViewDelegate {
    let renderer: HoloRenderer?
    private let model: AppModel
    private let preview: Bool
    private let voice = LiveVoice()
    private let animator = FaceAnimator(seed: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)))
    private weak var attached: AudioCapture?
    private var lastDraw: CFTimeInterval = 0
    /// The viewer's place, eased between the camera's ten readings a second.
    private var viewer = SIMD2<Float>.zero
    /// Where the conversation stands: speaking, listening, thinking, waiting (spec, § 7.2).
    private var conversation = ConversationTracker()
    private let start = CACurrentMediaTime()

    init(model: AppModel, preview: Bool = false) {
        self.model = model
        self.preview = preview
        renderer = HoloRenderer(model: FaceLibrary.model(id: model.faceID))
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        // A preview whose window is closed draws nothing.
        if preview, view.window?.isVisible != true { return }
        guard let renderer, let drawable = view.currentDrawable, let commandBuffer = renderer.makeCommandBuffer()
        else { return }
        let now = CACurrentMediaTime()
        let dt = lastDraw == 0 ? 1.0 / 60 : min(now - lastDraw, 0.1)
        lastDraw = now

        let capture = preview ? nil : model.connection.capture
        if capture !== attached {
            attached = capture
            voice.attach(capture)
        }

        var frame: VoiceFrame?
        if let capture, model.connection.state == .connected {
            // The instant this frame will be on screen, and the sound heard then.
            let displayed =
                HostClock.now + HostClock.hostTime(seconds: 1 / Double(max(view.preferredFramesPerSecond, 1)))
            let extraLatency = Double(model.extraLatencyMilliseconds) / 1000
            if let heard = capture.heardFrame(at: displayed, extraLatency: extraLatency) {
                let ahead = heard + Double(model.anticipationMilliseconds) / 1000 * capture.sampleRate
                frame = voice.frame(atHop: Int(ahead) / voice.hopFrames)
            }
        }
        let heard = preview || !model.microphone ? nil : model.microphoneLevel.personVoiced
        let moment =
            preview
            ? ConversationMoment.waiting
            : conversation.update(
                dt: dt, aiVoiced: frame.map { $0.sound != .silence } == true,
                appListening: model.connection.appListening, personVoiced: heard)
        let seen = model.camera ? model.cameraTracker.position : nil
        animator.lookAt = seen
        viewer += ((seen ?? .zero) - viewer) * Float(min(1, dt / 0.25))
        let pose = animator.update(dt: dt, voice: frame, moment: moment, heard: heard)
        // Full rate while it speaks, half otherwise (spec, § 7.2: economy).
        view.preferredFramesPerSecond = moment == .speaking ? 60 : 30

        var settings = HoloSettings()
        if model.windowMode == .classic || preview { settings.background = HoloSettings.charbon }
        settings.realism = Float(model.realism)
        settings.colour = model.holoColour.rgb
        settings.halo = Float(model.halo)
        settings.scanlines = Float(model.scanlines)
        settings.projector = model.projector
        settings.glitches = model.glitches
        settings.viewer = viewer
        renderer.encode(
            pose: pose, time: now - start, settings: settings, into: drawable.texture, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// The hologram's view: a Metal view with a clear background, so the face floats on the desktop.
struct HoloView: NSViewRepresentable {
    let driver: FaceDriver

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: driver.renderer?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 30
        view.delegate = driver
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}
}
