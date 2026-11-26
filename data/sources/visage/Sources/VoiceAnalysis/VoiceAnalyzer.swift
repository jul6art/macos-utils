import Accelerate
import Foundation

/// Turns a stream of mono samples into one `VoiceFrame` every 10 ms. Feed it in chunks of any size: the
/// frames are the same (a test holds it to that), so the live capture and the file mode agree.
///
/// Each hop needs a little of the future (half a window, a pitch period): it is computed about 40 ms after
/// its samples arrive, well inside the 150 ms the playback delay gives (spec, § 5).
///
/// Used from one thread at a time; it moves between threads with its owner.
public final class VoiceAnalyzer: @unchecked Sendable {
    public let sampleRate: Double
    /// Frames of the source per hop: 10 ms.
    public let hopFrames: Int
    public private(set) var frames: [VoiceFrame] = []
    /// The hop of `frames[0]`: older frames are dropped beyond `keptHops`.
    public private(set) var firstHop = 0
    private let keptHops: Int

    // Full rate: energy and spectrum.
    private var full: [Float]
    private var fullStart: Int
    private let energyWindow: Int
    private let spectrum: PowerSpectrum
    private var bins: [Float] = []
    private let binWidth: Float

    // Low rate (about 11–12 kHz): formants and pitch.
    private var decimator: Decimator
    private var low: [Float]
    private var lowStart: Int
    private let lowRate: Double
    private let lpcWindow: Int
    private let lpcHamming: [Float]
    private var pitchTracker: PitchTracker

    private var nextHop = 0
    private var profile = VoiceProfile()
    private var lastFrontness: Float = 0.5
    private static let lpcOrder = 12

    public init(sampleRate: Double, keptSeconds: Double = 4) {
        self.sampleRate = sampleRate
        hopFrames = Int((sampleRate / 100).rounded())
        keptHops = Int(keptSeconds * 100)

        energyWindow = Int(0.025 * sampleRate)
        let fftSize = sampleRate > 64_000 ? 2048 : 1024
        spectrum = PowerSpectrum(size: fftSize)
        binWidth = Float(sampleRate / Double(fftSize))

        let factor = max(1, Int((sampleRate / 11_025).rounded()))
        decimator = Decimator(factor: factor)
        lowRate = sampleRate / Double(factor)
        lpcWindow = Int(0.025 * lowRate)
        lpcHamming = vDSP.window(ofType: Float.self, usingSequence: .hamming, count: lpcWindow, isHalfWindow: false)
        pitchTracker = PitchTracker(sampleRate: lowRate)

        // Silence before the first sample, so the first hops have a past.
        let fullPad = fftSize
        full = [Float](repeating: 0, count: fullPad)
        fullStart = -fullPad
        let lowPad = pitchTracker.span + lpcWindow
        low = [Float](repeating: 0, count: lowPad)
        lowStart = -lowPad
    }

    private var factor: Int { decimator.factor }
    private var received: Int { fullStart + full.count }

    /// The frame of hop `hop`, if computed and still kept.
    public func frame(atHop hop: Int) -> VoiceFrame? {
        let index = hop - firstHop
        guard index >= 0, index < frames.count else { return nil }
        return frames[index]
    }

    /// The last hop computed, -1 before the first.
    public var latestHop: Int { nextHop - 1 }

    public func append(_ samples: UnsafeBufferPointer<Float>) {
        full.append(contentsOf: samples)
        decimator.process(samples, into: &low)
        while canAnalyse(hop: nextHop) {
            analyse(hop: nextHop)
            nextHop += 1
        }
        trim()
    }

    public func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    /// Runs out the last hops with silence, at the end of a file.
    public func finish() {
        append([Float](repeating: 0, count: Int(0.1 * sampleRate)))
    }

    // MARK: - One hop

    private func centre(of hop: Int) -> Int { hop * hopFrames + hopFrames / 2 }

    private func canAnalyse(hop: Int) -> Bool {
        let centre = centre(of: hop)
        let lowCentre = centre / factor
        let lowNeeded = lowCentre - pitchTracker.window / 2 + pitchTracker.span
        let lpcNeeded = lowCentre + lpcWindow / 2
        let lowReceived = lowStart + low.count
        return received >= centre + spectrum.size / 2 && lowReceived >= max(lowNeeded, lpcNeeded)
    }

    private func analyse(hop: Int) {
        let centre = centre(of: hop)

        // Level.
        var rms: Float = 0
        full.withUnsafeBufferPointer {
            vDSP_rmsqv($0.baseAddress! + (centre - energyWindow / 2 - fullStart), 1, &rms, vDSP_Length(energyWindow))
        }
        let energy = 20 * log10(max(rms, 1e-6))

        // Spectrum: where the energy sits.
        full.withUnsafeBufferPointer {
            spectrum.compute($0.baseAddress! + (centre - spectrum.size / 2 - fullStart), into: &bins)
        }
        var total: Float = 0
        var weighted: Float = 0
        var above4k: Float = 0
        var below1k: Float = 0
        for index in 1..<bins.count {
            let frequency = Float(index) * binWidth
            let power = bins[index]
            total += power
            weighted += power * frequency
            if frequency >= 4000 { above4k += power }
            if frequency < 1000 { below1k += power }
        }
        let centroid = total > 0 ? weighted / total : 0
        let highBand = total > 0 ? above4k / total : 0
        let lowBand = total > 0 ? below1k / total : 0

        // Pitch.
        let lowCentre = centre / factor
        let (frequency, aperiodicity) = low.withUnsafeBufferPointer {
            pitchTracker.estimate($0.baseAddress! + (lowCentre - pitchTracker.window / 2 - lowStart))
        }
        let speechLevel = profile.speechLevel
        let silent = energy < max(-60, speechLevel - 40)
        let voiced = !silent && aperiodicity < 0.25 && (60...500).contains(frequency)

        // Formants: pre-emphasis, Hamming, LPC.
        var formants: (Double?, Double?, Double?) = (nil, nil, nil)
        if !silent {
            let start = lowCentre - lpcWindow / 2 - lowStart
            var segment = [Float](repeating: 0, count: lpcWindow)
            for index in 0..<lpcWindow {
                let previous = start + index - 1 >= 0 ? low[start + index - 1] : 0
                segment[index] = (low[start + index] - 0.97 * previous) * lpcHamming[index]
            }
            if let coefficients = LPC.coefficients(of: segment, order: Self.lpcOrder) {
                formants = LPC.formants(from: LPC.envelopePeaks(coefficients, sampleRate: lowRate))
            }
        }

        // Learn the voice from its clear vowels.
        if !silent { profile.level.add(energy) }
        if voiced {
            profile.pitch.add(Float(frequency))
            if let f1 = formants.0 { profile.formant1.add(Float(f1)) }
            if let f2 = formants.1 { profile.formant2.add(Float(f2)) }
        }

        let f1 = formants.0.map(Float.init)
        let f2 = formants.1.map(Float.init)
        let f3 = formants.2.map(Float.init)
        let loudness = silent ? 0 : profile.level.normalise(energy)
        let openness = f1.map { profile.formant1.normalise($0) } ?? loudness * 0.4
        // Without F2 (merged with F1, or a consonant), the lips keep their last shape.
        let frontness = f2.map { profile.formant2.normalise($0) } ?? lastFrontness
        lastFrontness = frontness
        var frontRounding: Float = 0
        if let f2, let f3, frontness > 0.5 { frontRounding = min(max((700 - (f3 - f2)) / 500, 0), 1) }
        let rounding = max((1 - frontness) * (1 - openness), frontRounding)

        var frame = VoiceFrame(
            hop: hop, sound: .vowel, energyDecibels: energy, loudness: loudness, isVoiced: voiced,
            pitch: voiced ? Float(frequency) : nil,
            pitchLevel: voiced ? profile.pitch.normalise(Float(frequency)) : 0.5,
            formant1: f1, formant2: f2, formant3: f3, openness: voiced ? openness : loudness * 0.4,
            frontness: frontness, rounding: voiced ? rounding : 0, centroid: centroid, highBand: highBand,
            bilabial: 0)
        let previousEnergy = frames.last?.energyDecibels ?? energy
        frame.sound = classify(
            frame, silent: silent, speechLevel: speechLevel, lowBand: lowBand, previousEnergy: previousEnergy)
        frames.append(frame)
        settle(at: frames.count - 1, speechLevel: speechLevel)
    }

    private func classify(
        _ frame: VoiceFrame, silent: Bool, speechLevel: Float, lowBand: Float, previousEnergy: Float
    ) -> SoundClass {
        if silent { return .silence }
        let noisy = frame.highBand > 0.3 || (!frame.isVoiced && frame.centroid > 2200)
        if noisy {
            // A weak hiss is f (or v): the lower lip against the teeth.
            if !frame.isVoiced && frame.energyDecibels < speechLevel - 15 { return .fricativeF }
            if frame.centroid > 4300 { return .fricativeS }
            if frame.centroid > 2200 { return .fricativeSh }
            return .fricativeF
        }
        // A murmur: voiced, quiet, dark, and steady — a vowel dying out at the end of a phrase falls fast.
        // The voice bar of b, d, g sounds the same, and closes the mouth the same.
        if frame.isVoiced && frame.energyDecibels < speechLevel - 8 && lowBand > 0.8
            && (frame.formant1 ?? 0) < 420 && frame.energyDecibels - previousEnergy > -4
        {
            return .nasal
        }
        return .vowel
    }

    // MARK: - Settling what the next frames reveal

    /// Runs of closures and murmurs waiting for the frames after them, to decide whether the lips closed.
    private var pendingOcclusions: [(start: Int, end: Int)] = []
    /// Hops after an occlusion needed to read the second formant coming out of it.
    private static let occlusionLookahead = 6

    /// Each new frame can change what the frames just before it were: settled here, still in the future
    /// of what is heard (spec, § 5).
    private func settle(at index: Int, speechLevel: Float) {
        if let gapStart = markClosure(endingAt: index, speechLevel: speechLevel) {
            // The way in is known already: a first guess for the lips, refined once the way out is heard.
            markLips(start: frames[gapStart].hop, end: frames[index - 1].hop, speechLevel: speechLevel, wayOut: false)
        }
        dropShortFricatives(endingAt: index)
        bridgeOcclusion(at: index, speechLevel: speechLevel)
        if frames[index].sound.isOcclusion {
            if index >= 1, frames[index - 1].sound.isOcclusion {
                frames[index].bilabial = frames[index - 1].bilabial
            } else {
                markLips(start: frames[index].hop, end: frames[index].hop, speechLevel: speechLevel, wayOut: false)
            }
        }
        if index >= 1, !frames[index].sound.isOcclusion, frames[index - 1].sound.isOcclusion {
            var start = index - 1
            while start - 1 >= 0, frames[start - 1].sound.isOcclusion { start -= 1 }
            pendingOcclusions.append((frames[start].hop, frames[index - 1].hop))
        }
        let hop = frames[index].hop
        pendingOcclusions.removeAll { run in
            guard hop >= run.end + Self.occlusionLookahead else { return false }
            markLips(start: run.start, end: run.end, speechLevel: speechLevel, wayOut: true)
            return true
        }
    }

    /// A stop: a short hush between two sounds, ended by a sudden onset. Found when the onset comes;
    /// returns where the hush began.
    private func markClosure(endingAt index: Int, speechLevel: Float) -> Int? {
        let onset = frames[index]
        guard onset.sound != .silence, index >= 2 else { return nil }
        var gapStart = index
        while gapStart - 1 >= 0, index - gapStart < 12,
            frames[gapStart - 1].energyDecibels < speechLevel - 25
        {
            gapStart -= 1
        }
        let gapLength = index - gapStart
        guard (2...12).contains(gapLength), gapStart - 1 >= 0 else { return nil }
        let before = frames[gapStart - 1]
        guard before.sound != .silence, onset.energyDecibels - frames[index - 1].energyDecibels > 12 else {
            return nil
        }
        for gap in gapStart..<index { frames[gap].sound = .closure }
        return gapStart
    }

    /// The voice bar of a b flickers between murmur and vowel: one or two quiet vowel hops inside an
    /// occlusion belong to it. Mended here, so the occlusion is read whole.
    private func bridgeOcclusion(at index: Int, speechLevel: Float) {
        guard frames[index].sound.isOcclusion else { return }
        for gap in 1...2 where index - gap - 1 >= 0 {
            let inside = (index - gap)..<index
            guard frames[index - gap - 1].sound.isOcclusion,
                inside.allSatisfy({ frames[$0].sound == .vowel && frames[$0].energyDecibels < speechLevel - 8 })
            else { continue }
            for hop in inside { frames[hop].sound = .nasal }
            return
        }
    }

    /// A fricative lasts. Two hops of hiss are the burst of a stop, or a transition: the mouth follows the
    /// level there, it does not take a fricative's shape.
    private func dropShortFricatives(endingAt index: Int) {
        guard index >= 1, frames[index - 1].sound.isFricative, frames[index].sound != frames[index - 1].sound else {
            return
        }
        let sound = frames[index - 1].sound
        var start = index - 1
        while start - 1 >= 0, frames[start - 1].sound == sound { start -= 1 }
        if index - start < 3 {
            for short in start..<index { frames[short].sound = .vowel }
        }
    }

    /// Did the lips close (p, b, m), or the tongue (t, d, n, k, g)? The second formant tells: it falls into
    /// a labial closure and rises out of it, while the tongue pulls it up, or leaves it high. Its slopes
    /// count, with its level at the edges. Checked on French syllables (apa, ata, aka, aba… amma, anna).
    /// Without `wayOut`, a first guess from the way in alone.
    private func markLips(start: Int, end: Int, speechLevel: Float, wayOut: Bool) {
        func sonorant(_ frame: VoiceFrame) -> Bool {
            frame.sound == .vowel && frame.formant2 != nil && frame.energyDecibels > speechLevel - 15
        }
        let startIndex = start - firstHop
        let endIndex = end - firstHop
        guard startIndex >= 0, endIndex < frames.count else { return }
        // The frame right next to the occlusion straddles it: its window holds silence, its formants lie.
        // Values far from the others' median are merged or stray peaks: out too.
        func steady(_ candidates: [VoiceFrame]) -> [VoiceFrame] {
            let values = candidates.compactMap(\.formant2).sorted()
            guard !values.isEmpty else { return [] }
            let median = values[values.count / 2]
            // Around an i the transition itself spans 700 Hz: the tolerance follows the formant's height.
            let tolerance = max(400, 0.35 * median)
            return candidates.filter { abs(($0.formant2 ?? median) - median) <= tolerance }
        }
        let before = steady(frames[max(0, startIndex - 7)..<max(0, startIndex - 1)].filter(sonorant)).suffix(4)
        let after =
            wayOut
            ? steady(frames[min(frames.count, endIndex + 2)..<min(frames.count, endIndex + 10)].filter(sonorant))
                .prefix(4) : []

        func slope(_ run: some Collection<VoiceFrame>) -> Float {
            guard let first = run.first?.formant2, let last = run.reversed().first?.formant2, run.count >= 2 else {
                return 0
            }
            return last - first
        }
        // A drift of a few tens of hertz says nothing: only a real slope counts.
        func strength(_ change: Float) -> Float {
            let magnitude = min(max((abs(change) - 60) / 200, 0), 1)
            return change < 0 ? -magnitude : magnitude
        }
        let slopeIn = -strength(slope(before))
        let slopeOut = strength(slope(after))
        let edges = [before.last?.formant2, after.first?.formant2].compactMap { $0 }
        let level = edges.min().map { min(max((1500 - $0) / 500, 0), 1) } ?? 0.5
        // The slopes weigh most: around an i, the second formant stays high even for b and p. The first
        // guess leans on the way in alone.
        let evidence =
            wayOut
            ? 0.45 * slopeIn + 0.45 * slopeOut + 0.25 * (2 * level - 1)
            : 0.6 * slopeIn + 0.25 * (2 * level - 1)
        let bilabial = min(max(0.5 + evidence, 0), 1)
        for index in startIndex...endIndex { frames[index].bilabial = bilabial }
    }

    private func trim() {
        // Keep what the next hops read, and a little more.
        let keepFull = centre(of: nextHop) - spectrum.size - energyWindow
        if keepFull - fullStart > 8192 {
            let drop = keepFull - fullStart
            full.removeFirst(drop)
            fullStart += drop
        }
        let keepLow = centre(of: nextHop) / factor - pitchTracker.span - lpcWindow
        if keepLow - lowStart > 4096 {
            let drop = keepLow - lowStart
            low.removeFirst(drop)
            lowStart += drop
        }
        if frames.count > keptHops + 200 {
            let drop = frames.count - keptHops
            frames.removeFirst(drop)
            firstHop += drop
        }
    }
}
