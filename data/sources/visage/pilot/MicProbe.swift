import AVFoundation
import Foundation

/// Listens to the default microphone for a few seconds and writes its level, every 100 ms, to a JSON
/// file. The pilot uses it as an ear: with a voice playing through the speakers, the level tells whether
/// that voice is heard, without asking anyone.
enum MicProbe {
    static func run(seconds: Double, output: URL) -> Int32 {
        guard requestAccess() else {
            write(["error": "microphone access refused"], to: output)
            return 1
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let meter = Meter(windowFrames: Int(format.sampleRate / 10))
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            meter.add(buffer)
        }
        do {
            try engine.start()
        } catch {
            write(["error": "\(error)"], to: output)
            return 1
        }
        Thread.sleep(forTimeInterval: seconds)
        engine.stop()
        input.removeTap(onBus: 0)

        let levels = meter.levels
        let sorted = levels.sorted()
        func percentile(_ p: Double) -> Double {
            sorted.isEmpty ? -120 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        write([
            "seconds": seconds,
            "windows": levels.count,
            "medianDb": round1(percentile(0.5)),
            "p90Db": round1(percentile(0.9)),
            "maxDb": round1(sorted.last ?? -120),
            "levelsDb": levels.map(round1),
        ], to: output)
        return 0
    }

    private static func requestAccess() -> Bool {
        let answer = Answer()
        let semaphore = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            answer.granted = granted
            semaphore.signal()
        }
        semaphore.wait()
        return answer.granted
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private static func write(_ object: [String: Any], to url: URL) {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: url, options: .atomic)
    }

    private final class Answer: @unchecked Sendable {
        var granted = false
    }

    /// RMS level per window of 100 ms, in dBFS. Fed from the audio thread, read once at the end.
    private final class Meter: @unchecked Sendable {
        private let lock = NSLock()
        private let windowFrames: Int
        private var sum: Double = 0
        private var count = 0
        private var collected: [Double] = []

        init(windowFrames: Int) {
            self.windowFrames = max(windowFrames, 1)
        }

        func add(_ buffer: AVAudioPCMBuffer) {
            guard let channel = buffer.floatChannelData?[0] else { return }
            lock.lock()
            defer { lock.unlock() }
            for index in 0..<Int(buffer.frameLength) {
                let sample = Double(channel[index])
                sum += sample * sample
                count += 1
                if count == windowFrames {
                    collected.append(20 * log10(max((sum / Double(count)).squareRoot(), 1e-6)))
                    sum = 0
                    count = 0
                }
            }
        }

        var levels: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return collected
        }
    }
}
