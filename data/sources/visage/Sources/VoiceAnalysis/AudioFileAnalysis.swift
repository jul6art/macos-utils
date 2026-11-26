import AVFAudio
import Foundation

/// The file mode (spec, § 11.2): the same analysis as the live capture, fed from an audio file. It tunes
/// the analysis without an AI, and drives the offline video renders.
public enum AudioFileAnalysis {
    public struct Result: Sendable {
        public let frames: [VoiceFrame]
        public let sampleRate: Double
        public let duration: Double
        /// The file, mixed down to mono: the offline render plays it back.
        public let samples: [Float]
    }

    public static func analyse(_ url: URL) throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let analyzer = VoiceAnalyzer(sampleRate: format.sampleRate, keptSeconds: 24 * 3600)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        var mono = [Float](repeating: 0, count: 4096)
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            for index in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += data[channel][index] }
                mono[index] = sum / Float(channels)
            }
            mono.withUnsafeBufferPointer { analyzer.append(UnsafeBufferPointer(rebasing: $0[0..<frames])) }
            samples.append(contentsOf: mono[0..<frames])
        }
        analyzer.finish()
        let duration = Double(file.length) / format.sampleRate
        let hops = Int(duration * 100)
        return Result(
            frames: Array(analyzer.frames.prefix(hops)), sampleRate: format.sampleRate, duration: duration,
            samples: samples)
    }
}
