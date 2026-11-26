import Accelerate
import Foundation

/// A low-pass FIR filter that keeps one sample in `factor`: the formants and the pitch are read at about
/// 11–12 kHz, where a 12th-order LPC fits the voice and YIN costs a sixteenth.
struct Decimator {
    let factor: Int
    private let taps: [Float]
    private var history: [Float]
    private var phase = 0

    init(factor: Int, tapCount: Int = 63) {
        self.factor = factor
        // Windowed sinc, cut at 90 % of the new Nyquist frequency.
        let cutoff = 0.45 / Double(factor)
        let middle = Double(tapCount - 1) / 2
        var taps = (0..<tapCount).map { index -> Float in
            let x = Double(index) - middle
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let hamming = 0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(tapCount - 1))
            return Float(sinc * hamming)
        }
        let sum = taps.reduce(0, +)
        taps = taps.map { $0 / sum }
        self.taps = taps
        // Half a filter of silence ahead: output m is then centred on input m × factor, no delay.
        history = [Float](repeating: 0, count: (tapCount - 1) / 2)
    }

    /// Input samples an output needs beyond its centre.
    var lookahead: Int { (taps.count - 1) / 2 }

    /// Appends the decimated samples of `input` to `output`.
    mutating func process(_ input: UnsafeBufferPointer<Float>, into output: inout [Float]) {
        history.append(contentsOf: input)
        let tapCount = taps.count
        var start = phase
        taps.withUnsafeBufferPointer { taps in
            history.withUnsafeBufferPointer { samples in
                while start + tapCount <= samples.count {
                    var value: Float = 0
                    vDSP_dotpr(samples.baseAddress! + start, 1, taps.baseAddress!, 1, &value, vDSP_Length(tapCount))
                    output.append(value)
                    start += factor
                }
            }
        }
        // Keep what the next output still needs.
        let removed = min(start, history.count)
        history.removeFirst(removed)
        phase = start - removed
    }
}

/// Power spectrum of a real signal, by vDSP's FFT.
final class PowerSpectrum {
    let size: Int
    private let log2Size: vDSP_Length
    private let setup: FFTSetup
    private var real: [Float]
    private var imaginary: [Float]
    private let window: [Float]
    private var windowed: [Float]

    init(size: Int) {
        precondition(size > 0 && size & (size - 1) == 0, "a power of two")
        self.size = size
        log2Size = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2))!
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: size)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// `size / 2` bins, from 0 Hz up to just under Nyquist.
    func compute(_ input: UnsafePointer<Float>, into output: inout [Float]) {
        if output.count != size / 2 { output = [Float](repeating: 0, count: size / 2) }
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(size))
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
                // zrip packs the Nyquist bin into the first imaginary value: drop it.
                split.imagp[0] = 0
                output.withUnsafeMutableBufferPointer { bins in
                    vDSP_zvmags(&split, 1, bins.baseAddress!, 1, vDSP_Length(size / 2))
                }
            }
        }
    }
}

/// Linear prediction: the vocal tract as an all-pole filter, whose peaks are the formants.
enum LPC {
    /// The coefficients a[0…order] (a[0] = 1) of the prediction error filter, by Levinson-Durbin on the
    /// autocorrelation of `samples`. Nil for silence or an unstable recursion.
    static func coefficients(of samples: [Float], order: Int) -> [Double]? {
        var autocorrelation = [Double](repeating: 0, count: order + 1)
        for lag in 0...order {
            var sum = 0.0
            for index in lag..<samples.count { sum += Double(samples[index]) * Double(samples[index - lag]) }
            autocorrelation[lag] = sum
        }
        guard autocorrelation[0] > 1e-9 else { return nil }
        autocorrelation[0] *= 1 + 1e-6  // a little white noise: steadier on very clean signals

        var a = [Double](repeating: 0, count: order + 1)
        a[0] = 1
        var error = autocorrelation[0]
        for step in 1...order {
            var acc = autocorrelation[step]
            for index in 1..<step { acc += a[index] * autocorrelation[step - index] }
            let reflection = -acc / error
            guard abs(reflection) < 1 else { return nil }
            var next = a
            for index in 1..<step { next[index] = a[index] + reflection * a[step - index] }
            next[step] = reflection
            a = next
            error *= 1 - reflection * reflection
        }
        return a
    }

    /// The peaks of the spectral envelope 1 / |A(f)|², in Hz, by increasing frequency, refined by
    /// parabolic interpolation.
    static func envelopePeaks(_ a: [Double], sampleRate: Double, points: Int = 512, from low: Double = 120) -> [Double]
    {
        var envelope = [Double](repeating: 0, count: points)
        for k in 0..<points {
            let omega = Double.pi * Double(k) / Double(points)
            var re = 0.0
            var im = 0.0
            for (m, coefficient) in a.enumerated() {
                re += coefficient * cos(omega * Double(m))
                im -= coefficient * sin(omega * Double(m))
            }
            envelope[k] = -10 * log10(max(re * re + im * im, 1e-12))
        }
        let binWidth = sampleRate / 2 / Double(points)
        var peaks: [Double] = []
        for k in 1..<(points - 1) where envelope[k] > envelope[k - 1] && envelope[k] >= envelope[k + 1] {
            let frequency = Double(k) * binWidth
            guard frequency >= low else { continue }
            let (left, centre, right) = (envelope[k - 1], envelope[k], envelope[k + 1])
            let denominator = left - 2 * centre + right
            let offset = denominator == 0 ? 0 : 0.5 * (left - right) / denominator
            peaks.append((Double(k) + offset) * binWidth)
        }
        return peaks
    }

    /// F1, F2, F3 among the envelope's peaks, each in its usual band and apart from the one before.
    static func formants(from peaks: [Double]) -> (Double?, Double?, Double?) {
        let f1 = peaks.first { (200...1100).contains($0) }
        var f2 = peaks.first { (550...3000).contains($0) && $0 > (f1 ?? 0) + 150 }
        var f3 = peaks.first { (1500...4200).contains($0) && $0 > (f2 ?? 0) + 150 }
        // F1 and F2 merge into one peak when they come close (a back vowel, the transition into a labial):
        // the next peak is then F3. No vowel has both a high F1 and a high F2: such a pair is a merge.
        if let first = f1, let second = f2, second > 3100 - 1.5 * (first - 250) {
            f3 = second
            f2 = nil
        }
        return (f1, f2, f3)
    }
}

/// YIN (de Cheveigné & Kawahara, 2002): the period whose difference function dips first under a threshold.
struct PitchTracker {
    let sampleRate: Double
    let window: Int
    let minLag: Int
    let maxLag: Int
    private var difference: [Float]
    private var scratch: [Float]

    init(sampleRate: Double, lowest: Double = 60, highest: Double = 500, windowSeconds: Double = 0.03) {
        self.sampleRate = sampleRate
        window = Int(windowSeconds * sampleRate)
        minLag = max(2, Int(sampleRate / highest))
        maxLag = Int(sampleRate / lowest)
        difference = [Float](repeating: 0, count: maxLag + 2)
        scratch = [Float](repeating: 0, count: window)
    }

    /// Samples needed: `window + maxLag + 1`.
    var span: Int { window + maxLag + 1 }

    /// The frequency, and the aperiodicity (0 for a pure period, towards 1 for noise).
    mutating func estimate(_ samples: UnsafePointer<Float>) -> (frequency: Double, aperiodicity: Float) {
        let count = vDSP_Length(window)
        for lag in 1...(maxLag + 1) {
            vDSP_vsub(samples + lag, 1, samples, 1, &scratch, 1, count)
            var sum: Float = 0
            vDSP_svesq(scratch, 1, &sum, count)
            difference[lag] = sum
        }
        // Cumulative mean normalised difference.
        var running: Float = 0
        difference[0] = 1
        for lag in 1...(maxLag + 1) {
            running += difference[lag]
            difference[lag] = running > 0 ? difference[lag] * Float(lag) / running : 1
        }
        var chosen = -1
        var lag = minLag
        while lag <= maxLag {
            if difference[lag] < 0.15 {
                while lag + 1 <= maxLag && difference[lag + 1] < difference[lag] { lag += 1 }
                chosen = lag
                break
            }
            lag += 1
        }
        if chosen < 0 {
            chosen = minLag
            for candidate in minLag...maxLag where difference[candidate] < difference[chosen] { chosen = candidate }
        }
        let (left, centre, right) = (difference[chosen - 1], difference[chosen], difference[chosen + 1])
        let denominator = left - 2 * centre + right
        let offset = denominator == 0 ? 0 : 0.5 * (left - right) / denominator
        return (sampleRate / (Double(chosen) + Double(offset)), centre)
    }
}
