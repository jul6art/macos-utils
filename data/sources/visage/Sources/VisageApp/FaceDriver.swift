import AppKit
import AudioSource
import FaceAnimation
import HoloRenderer
import MetalKit
import Shared
import SwiftUI
import VoiceAnalysis

/// Drives the face on screen: at each displayed frame, which sound will be heard at that instant, the voice
/// read `anticipation` ahead of it, the animation, the hologram (spec, § 7.1, point 9).
@MainActor
final class FaceDriver: NSObject, MTKViewDelegate {
    let renderer: HoloRenderer?
    private let model: AppModel
    private let voice = LiveVoice()
    private let animator = FaceAnimator(seed: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)))
    private weak var attached: AudioCapture?
    private var lastDraw: CFTimeInterval = 0
    private let start = CACurrentMediaTime()

    init(model: AppModel) {
        self.model = model
        renderer = HoloRenderer(model: FaceLibrary.model(id: model.faceID))
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        guard let renderer, let drawable = view.currentDrawable, let commandBuffer = renderer.makeCommandBuffer()
        else { return }
        let now = CACurrentMediaTime()
        let dt = lastDraw == 0 ? 1.0 / 60 : min(now - lastDraw, 0.1)
        lastDraw = now

        let capture = model.connection.capture
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
        let speaking = frame.map { $0.sound != .silence } == true
        let pose = animator.update(dt: dt, voice: frame, moment: speaking ? .speaking : .waiting)
        // Full rate while it speaks, half at rest (spec, § 7.2: economy).
        view.preferredFramesPerSecond = speaking ? 60 : 30

        var settings = HoloSettings()
        if model.windowMode == .classic { settings.background = HoloSettings.charbon }
        settings.realism = Float(model.realism)
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
