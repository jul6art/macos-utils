import AVFoundation
import VoiceAnalysis

/// The microphone option (spec, § 5; § 7.2, *listening*): whether the person's voice is heard, from its
/// level, nothing else. Opened only while the AI's app has its own microphone open; each buffer is measured,
/// then dropped: nothing is recorded or sent.
final class MicrophoneLevel: @unchecked Sendable {
    enum Access: Sendable {
        case allowed
        case denied
        case noMicrophone
    }

    /// Whether the person's voice is heard now; nil while the microphone is closed.
    var personVoiced: Bool? { lock.withLock { running ? activity.voiced : nil } }

    private let lock = NSLock()
    private var activity = VoiceActivity()
    private var running = false
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.devinthehood.visage.microphone")
    private var configurationObserver: NSObjectProtocol?

    static func requestAccess() async -> Access {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return .denied }
        return AVCaptureDevice.default(for: .audio) == nil ? .noMicrophone : .allowed
    }

    func start() {
        queue.async { self.open() }
    }

    func stop() {
        queue.async { self.close() }
    }

    private func open() {
        guard !lock.withLock({ running }) else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.measure(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        lock.withLock {
            activity = VoiceActivity()
            running = true
        }
        // Another microphone (headphones, AirPods): the engine stops; open it again on the new one.
        if configurationObserver == nil {
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.queue.async {
                    guard let self, self.lock.withLock({ self.running }) else { return }
                    self.close()
                    self.open()
                }
            }
        }
    }

    private func close() {
        guard lock.withLock({ running }) else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.withLock { running = false }
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        let level = VoiceActivity.decibels(UnsafeBufferPointer(start: channel, count: count))
        let dt = Double(count) / buffer.format.sampleRate
        lock.withLock { _ = activity.update(levelDecibels: level, dt: dt) }
    }
}
