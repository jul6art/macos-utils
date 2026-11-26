import AudioSource
import Foundation
import VoiceAnalysis

/// The live analysis: every 5 ms, on its own thread, the newly captured sound goes through the analyzer;
/// the frames land in a small store the renderer reads at each displayed frame (spec, § 10.2: the analysis
/// on a dedicated thread). Hop `n` covers the capture's frames `n × hop …`: both count from the capture's
/// start.
final class LiveVoice: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.devinthehood.visage.analysis", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    // On the analysis thread.
    private var capture: AudioCapture?
    private var analyzer: VoiceAnalyzer?
    private var nextFrame = 0
    private var scratch = [Float](repeating: 0, count: 4096)

    // Shared with the renderer, under the lock.
    private let lock = NSLock()
    private var store = [VoiceFrame?](repeating: nil, count: 1024)
    private var sharedHopFrames = 480

    /// Frames the analysis may still rewrite after first publishing them (closures, lips): republished.
    private static let settling = 24

    func attach(_ capture: AudioCapture?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.capture = capture
            self.analyzer = capture.map { VoiceAnalyzer(sampleRate: $0.sampleRate, keptSeconds: 2) }
            self.nextFrame = 0
            self.lock.withLock {
                self.store = [VoiceFrame?](repeating: nil, count: self.store.count)
                self.sharedHopFrames = self.analyzer?.hopFrames ?? 480
            }
            if capture == nil {
                self.timer?.cancel()
                self.timer = nil
            } else if self.timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
                timer.setEventHandler { [weak self] in self?.poll() }
                timer.resume()
                self.timer = timer
            }
        }
    }

    /// The frame of hop `hop`, if analysed and still kept.
    func frame(atHop hop: Int) -> VoiceFrame? {
        lock.withLock {
            guard hop >= 0 else { return nil }
            let frame = store[hop % store.count]
            return frame?.hop == hop ? frame : nil
        }
    }

    var hopFrames: Int { lock.withLock { sharedHopFrames } }

    private func poll() {
        guard let capture, let analyzer else { return }
        let written = capture.writtenFrames.load(ordering: .acquiring)
        guard written > nextFrame else { return }
        let before = analyzer.latestHop
        while nextFrame < written {
            let count = min(scratch.count, written - nextFrame)
            let copied = scratch.withUnsafeMutableBufferPointer {
                capture.copyCaptured(from: nextFrame, count: count, into: $0.baseAddress!)
            }
            // Fell behind the ring (the Mac was asleep): silence keeps the hops aligned.
            if !copied { for index in 0..<count { scratch[index] = 0 } }
            scratch.withUnsafeBufferPointer { analyzer.append(UnsafeBufferPointer(rebasing: $0[0..<count])) }
            nextFrame += count
        }
        let latest = analyzer.latestHop
        guard latest > before else { return }
        let from = max(analyzer.firstHop, min(before + 1, latest - Self.settling))
        var fresh: [VoiceFrame] = []
        for hop in from...latest {
            if let frame = analyzer.frame(atHop: hop) { fresh.append(frame) }
        }
        lock.withLock {
            for frame in fresh { store[frame.hop % store.count] = frame }
        }
    }
}
