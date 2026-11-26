import Foundation
import Testing

@testable import VoiceAnalysis

@Suite("Reading the voice")
struct VoiceAnalyzerTests {
    /// The steady middle of a sound: its edges blur with what surrounds it.
    private func middle(_ frames: [VoiceFrame]) -> ArraySlice<VoiceFrame> {
        frames[(frames.count / 4)..<(frames.count * 3 / 4)]
    }

    @Test("The pitch of a voice", arguments: [110.0, 165.0, 220.0])
    func pitch(_ expected: Double) {
        let frames = middle(Synth.analyse(Synth.vowel(Synth.a, pitch: expected, seconds: 0.6)))
        let pitches = frames.compactMap(\.pitch)
        #expect(pitches.count > frames.count * 8 / 10)
        #expect(abs(Double(Synth.median(pitches)) - expected) / expected < 0.03)
    }

    @Test(
        "The formants of a, i and u",
        arguments: [
            ("a", Synth.a, 0.15, 0.15), ("i", Synth.i, 0.2, 0.12), ("u", Synth.u, 0.2, 0.2),
        ])
    func formants(_ name: String, _ vowel: [(Double, Double)], _ tolerance1: Double, _ tolerance2: Double) {
        let frames = middle(Synth.analyse(Synth.vowel(vowel, seconds: 0.6)))
        let f1 = Double(Synth.median(frames.compactMap(\.formant1)))
        let f2 = Double(Synth.median(frames.compactMap(\.formant2)))
        #expect(abs(f1 - vowel[0].0) / vowel[0].0 < tolerance1, "\(name): F1 \(f1)")
        #expect(abs(f2 - vowel[1].0) / vowel[1].0 < tolerance2, "\(name): F2 \(f2)")
        #expect(frames.allSatisfy { $0.sound == .vowel })
    }

    @Test("a opens the mouth, i spreads the lips, u rounds them")
    func mouthShapes() {
        let all =
            Synth.vowel(Synth.a, seconds: 0.5) + Synth.vowel(Synth.i, seconds: 0.5)
            + Synth.vowel(Synth.u, seconds: 0.5)
        let frames = Synth.analyse(all)
        func average(_ range: Range<Int>, _ value: KeyPath<VoiceFrame, Float>) -> Float {
            let slice = frames[range]
            return slice.map { $0[keyPath: value] }.reduce(0, +) / Float(slice.count)
        }
        let a = 15..<35
        let i = 65..<85
        let u = 115..<135
        #expect(average(a, \.openness) > average(i, \.openness) + 0.3)
        #expect(average(a, \.openness) > average(u, \.openness) + 0.3)
        #expect(average(i, \.frontness) > average(a, \.frontness) + 0.3)
        #expect(average(u, \.rounding) > average(a, \.rounding) + 0.3)
        #expect(average(u, \.rounding) > average(i, \.rounding) + 0.3)
    }

    @Test("s and ch, told apart by where their noise sits")
    func fricatives() {
        let s = middle(Synth.analyse(Synth.noise(centre: 6500, bandwidth: 3000, seconds: 0.4)))
        let sh = middle(Synth.analyse(Synth.noise(centre: 3200, bandwidth: 1200, seconds: 0.4, seed: 2)))
        #expect(s.filter { $0.sound == .fricativeS }.count > s.count * 8 / 10)
        #expect(sh.filter { $0.sound == .fricativeSh }.count > sh.count * 8 / 10)
        #expect(s.allSatisfy { !$0.isVoiced })
    }

    @Test("Silence is silence")
    func silence() {
        let frames = Synth.analyse(Synth.silence(seconds: 0.3))
        #expect(frames.allSatisfy { $0.sound == .silence && $0.loudness == 0 })
    }

    @Test("A stop between two vowels is a closure")
    func closure() {
        let samples =
            Synth.vowel(Synth.a, seconds: 0.25) + Synth.silence(seconds: 0.07)
            + Synth.vowel(Synth.a, seconds: 0.25)
        let frames = Synth.analyse(samples)
        let closures = frames.filter { $0.sound == .closure }
        #expect(closures.count >= 3)
        #expect(closures.allSatisfy { (24...33).contains($0.hop) })
    }

    @Test("p closes the lips: the second formant falls into it and rises out of it")
    func labialStop() {
        let samples =
            Synth.vowel(Synth.a, seconds: 0.3, endF2: 800) + Synth.silence(seconds: 0.07)
            + Synth.vowel(Synth.a, seconds: 0.3, startF2: 800)
        let closures = Synth.analyse(samples).filter { $0.sound == .closure }
        #expect(!closures.isEmpty)
        #expect(closures.allSatisfy { $0.bilabial > 0.6 })
    }

    @Test("t closes the tongue: the second formant rises towards it")
    func alveolarStop() {
        let samples =
            Synth.vowel(Synth.a, seconds: 0.3, endF2: 1700) + Synth.silence(seconds: 0.07)
            + Synth.vowel(Synth.a, seconds: 0.3, startF2: 1700)
        let closures = Synth.analyse(samples).filter { $0.sound == .closure }
        #expect(!closures.isEmpty)
        #expect(closures.allSatisfy { $0.bilabial < 0.4 })
    }

    @Test("A vowel dying out is not a murmur")
    func decay() {
        var samples = Synth.vowel(Synth.a, seconds: 0.4)
        let fade = Int(0.12 * Synth.rate)
        for index in 0..<fade {
            samples[samples.count - fade + index] *= Float(pow(0.001, Double(index) / Double(fade)))
        }
        samples += Synth.silence(seconds: 0.2)
        #expect(Synth.analyse(samples).allSatisfy { $0.sound != .nasal })
    }

    @Test("The same frames, whatever the size of the chunks")
    func chunking() {
        let samples =
            Synth.vowel(Synth.a, seconds: 0.3) + Synth.noise(centre: 6500, bandwidth: 3000, seconds: 0.2)
            + Synth.silence(seconds: 0.1) + Synth.vowel(Synth.u, seconds: 0.3)
        #expect(Synth.analyse(samples, chunk: 37) == Synth.analyse(samples, chunk: 4096))
    }

    @Test("One frame per 10 ms")
    func hops() {
        let frames = Synth.analyse(Synth.vowel(Synth.a, seconds: 1))
        #expect(frames.count >= 100)
        #expect(frames.enumerated().allSatisfy { $0.offset == $0.element.hop })
    }
}

@Suite("The low-rate filter")
struct DecimatorTests {
    private func rms(_ values: [Float]) -> Float {
        (values.map { $0 * $0 }.reduce(0, +) / Float(values.count)).squareRoot()
    }

    private func decimate(frequency: Double) -> [Float] {
        let input = (0..<44_100).map { Float(sin(2 * Double.pi * frequency * Double($0) / 44_100)) }
        var decimator = Decimator(factor: 4)
        var output: [Float] = []
        input.withUnsafeBufferPointer { decimator.process($0, into: &output) }
        return Array(output[100..<(output.count - 100)])
    }

    @Test("The voice's band goes through")
    func passband() {
        #expect(abs(rms(decimate(frequency: 500)) - 0.7071) < 0.02)
    }

    @Test("What would fold back is cut")
    func stopband() {
        #expect(rms(decimate(frequency: 8000)) < 0.03)
    }
}
