import Foundation

@testable import VoiceAnalysis

/// Test signals whose answers are known: vowels made by formant synthesis (a pulse train through
/// resonators), noise shaped like fricatives, silence.
enum Synth {
    static let rate = 44_100.0

    /// Classic formant frequencies and bandwidths (Hz) of a few vowels.
    static let a: [(Double, Double)] = [(730, 90), (1090, 110), (2440, 170), (3400, 250)]
    static let i: [(Double, Double)] = [(270, 60), (2290, 100), (3010, 150), (3700, 250)]
    static let u: [(Double, Double)] = [(300, 60), (870, 90), (2240, 150), (3400, 250)]

    /// A vowel; its second formant can glide from `startF2` over its first `glide` seconds, or to `endF2`
    /// over its last ones — the transitions a consonant leaves on the vowels around it.
    static func vowel(
        _ formants: [(Double, Double)], pitch: Double = 120, seconds: Double, startF2: Double? = nil,
        endF2: Double? = nil, glide: Double = 0.06
    ) -> [Float] {
        let count = Int(seconds * rate)
        var signal = [Double](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            phase += pitch / rate
            if phase >= 1 {
                phase -= 1
                signal[index] = 1
            }
        }
        // A glottal-like slope (two leaky integrators), then the lips' radiation (a first difference).
        for _ in 0..<2 {
            var previous = 0.0
            for index in 0..<count {
                previous = 0.97 * previous + signal[index]
                signal[index] = previous
            }
        }
        var previousInput = 0.0
        for index in 0..<count {
            let input = signal[index]
            signal[index] = input - previousInput
            previousInput = input
        }
        let glideCount = Double(Int(glide * rate))
        for (index, (frequency, bandwidth)) in formants.enumerated() {
            if index == 1, startF2 != nil || endF2 != nil {
                signal = resonate(signal, bandwidth: bandwidth) { sample in
                    let position = Double(sample)
                    if let startF2, position < glideCount {
                        return startF2 + (frequency - startF2) * position / glideCount
                    }
                    let fromEnd = Double(count) - position
                    if let endF2, fromEnd < glideCount {
                        return endF2 + (frequency - endF2) * fromEnd / glideCount
                    }
                    return frequency
                }
            } else {
                signal = resonate(signal, frequency: frequency, bandwidth: bandwidth)
            }
        }
        return normalised(signal, peak: 0.5)
    }

    static func noise(centre: Double, bandwidth: Double, seconds: Double, seed: UInt64 = 1) -> [Float] {
        var state = seed
        var signal = (0..<Int(seconds * rate)).map { _ -> Double in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        signal = resonate(signal, frequency: centre, bandwidth: bandwidth)
        return normalised(signal, peak: 0.3)
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    static func analyse(_ samples: [Float], chunk: Int = 512) -> [VoiceFrame] {
        let analyzer = VoiceAnalyzer(sampleRate: rate, keptSeconds: 60)
        var start = 0
        while start < samples.count {
            let end = min(start + chunk, samples.count)
            samples.withUnsafeBufferPointer { analyzer.append(UnsafeBufferPointer(rebasing: $0[start..<end])) }
            start = end
        }
        analyzer.finish()
        return analyzer.frames
    }

    static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }

    private static func resonate(_ input: [Double], frequency: Double, bandwidth: Double) -> [Double] {
        resonate(input, bandwidth: bandwidth) { _ in frequency }
    }

    private static func resonate(_ input: [Double], bandwidth: Double, frequency: (Int) -> Double) -> [Double] {
        let r = exp(-Double.pi * bandwidth / rate)
        var output = [Double](repeating: 0, count: input.count)
        var y1 = 0.0
        var y2 = 0.0
        for index in 0..<input.count {
            let c = 2 * r * cos(2 * Double.pi * frequency(index) / rate)
            let y = input[index] + c * y1 - r * r * y2
            output[index] = y
            y2 = y1
            y1 = y
        }
        return output
    }

    private static func normalised(_ signal: [Double], peak: Double) -> [Float] {
        let maximum = signal.map(abs).max() ?? 1
        return signal.map { Float($0 / max(maximum, 1e-12) * peak) }
    }
}
