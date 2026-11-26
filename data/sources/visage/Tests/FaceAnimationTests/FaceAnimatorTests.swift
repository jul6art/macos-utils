import Testing

@testable import FaceAnimation
@testable import VoiceAnalysis

@Suite("The face, from the voice")
struct FaceAnimatorTests {
    private let frameTime = 1.0 / 60

    private func voice(
        _ sound: SoundClass, openness: Float = 0, frontness: Float = 0.5, rounding: Float = 0, loudness: Float = 0.8,
        bilabial: Float = 0
    ) -> VoiceFrame {
        VoiceFrame(
            hop: 0, sound: sound, energyDecibels: -20, loudness: loudness, isVoiced: sound == .vowel, pitch: 120,
            pitchLevel: 0.5, formant1: nil, formant2: nil, formant3: nil, openness: openness, frontness: frontness,
            rounding: rounding, centroid: 1000, highBand: 0, bilabial: bilabial)
    }

    /// Holds a sound for `seconds`, returns the last pose.
    private func hold(
        _ frame: VoiceFrame?, seconds: Double, moment: ConversationMoment = .speaking, on animator: FaceAnimator
    ) -> FacePose {
        var pose = FacePose()
        for _ in 0..<Int(seconds / frameTime) { pose = animator.update(dt: frameTime, voice: frame, moment: moment) }
        return pose
    }

    @Test("a opens the jaw, i spreads the lips, u rounds them")
    func vowels() {
        let a = hold(
            voice(.vowel, openness: 0.9, frontness: 0.2, rounding: 0.1), seconds: 0.5, on: FaceAnimator(seed: 1))
        let i = hold(voice(.vowel, openness: 0.1, frontness: 0.95), seconds: 0.5, on: FaceAnimator(seed: 1))
        let u = hold(
            voice(.vowel, openness: 0.1, frontness: 0.1, rounding: 0.9), seconds: 0.5, on: FaceAnimator(seed: 1))
        #expect(a[.jawOpen] > 0.45)
        #expect(a[.jawOpen] > i[.jawOpen] + 0.25)
        #expect(i[.mouthStretchLeft] > 0.2 && i[.mouthStretchLeft] > a[.mouthStretchLeft])
        #expect(u[.mouthFunnel] > 0.4 && u[.mouthPucker] > 0.3)
    }

    @Test("p shuts the lips within 60 ms")
    func labialClosure() {
        let animator = FaceAnimator(seed: 2)
        _ = hold(voice(.vowel, openness: 0.8), seconds: 0.3, on: animator)
        let shut = hold(voice(.closure, bilabial: 1), seconds: 0.06, on: animator)
        #expect(shut[.mouthClose] > 0.7)
        #expect(shut[.mouthPressLeft] > 0.4)
    }

    @Test("t closes the jaw, not the lips")
    func tongueClosure() {
        let animator = FaceAnimator(seed: 3)
        let open = hold(voice(.vowel, openness: 0.8), seconds: 0.3, on: animator)
        let shut = hold(voice(.closure, bilabial: 0), seconds: 0.08, on: animator)
        #expect(shut[.mouthClose] < 0.1)
        // The tongue closes a t: the jaw only comes halfway up in 80 ms, as a real jaw does.
        #expect(shut[.jawOpen] < open[.jawOpen] * 0.5)
    }

    @Test("f rolls the lower lip, ch pushes the lips forward")
    func fricatives() {
        #expect(hold(voice(.fricativeF), seconds: 0.2, on: FaceAnimator(seed: 4))[.mouthRollLower] > 0.5)
        #expect(hold(voice(.fricativeSh), seconds: 0.2, on: FaceAnimator(seed: 4))[.mouthFunnel] > 0.4)
    }

    @Test("Silence closes the mouth again")
    func silence() {
        let animator = FaceAnimator(seed: 5)
        _ = hold(voice(.vowel, openness: 0.9), seconds: 0.3, on: animator)
        #expect(hold(voice(.silence), seconds: 0.5, on: animator)[.jawOpen] < 0.1)
    }

    @Test("Every weight stays between 0 and 1")
    func bounded() {
        let animator = FaceAnimator(seed: 6)
        let sounds: [SoundClass] = [.vowel, .closure, .fricativeS, .nasal, .silence, .fricativeF, .fricativeSh]
        for step in 0..<3000 {
            let frame = voice(
                sounds[step / 13 % sounds.count], openness: 1, frontness: 1, rounding: 1, loudness: 1, bilabial: 1)
            let pose = animator.update(dt: frameTime, voice: frame, moment: .speaking)
            #expect(pose.weights.allSatisfy { (0...1).contains($0) })
        }
    }

    @Test("The same seed, the same face")
    func deterministic() {
        let first = FaceAnimator(seed: 7)
        let second = FaceAnimator(seed: 7)
        for _ in 0..<600 {
            #expect(
                first.update(dt: frameTime, voice: nil, moment: .waiting)
                    == second.update(dt: frameTime, voice: nil, moment: .waiting))
        }
    }

    @Test("Thinking, the eyes go up and aside")
    func thinking() {
        let pose = hold(nil, seconds: 1.5, moment: .thinking, on: FaceAnimator(seed: 8))
        #expect(pose.gaze.y > 0.2)
        #expect(pose.head.z > 0.02)
    }
}

@Suite("The face, at rest")
struct RestTests {
    @Test("Blinks every 2 to 6 s, never like clockwork; never still for a second (criterion 3)")
    func alive() {
        let animator = FaceAnimator(seed: 42)
        let frameTime = 1.0 / 60
        var blinkStarts: [Double] = []
        var previous = FacePose()
        var stillSince = 0.0
        var longestStill = 0.0
        var wasClosed = false
        for step in 0..<(120 * 60) {
            let time = Double(step) * frameTime
            let pose = animator.update(dt: frameTime, voice: nil, moment: .waiting)
            let closed = pose[.eyeBlinkLeft] > 0.5
            if closed && !wasClosed { blinkStarts.append(time) }
            wasClosed = closed
            var change = zip(pose.weights, previous.weights).map { abs($0 - $1) }.max() ?? 0
            change = max(change, abs(pose.head.x - previous.head.x) * 50, abs(pose.gaze.x - previous.gaze.x))
            if change > 0.0005 { stillSince = time }
            longestStill = max(longestStill, time - stillSince)
            previous = pose
        }
        #expect((15...70).contains(blinkStarts.count))
        let gaps = zip(blinkStarts.dropFirst(), blinkStarts).map { $0 - $1 }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let spread = (gaps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(gaps.count)).squareRoot()
        #expect(spread > 0.5)
        #expect(longestStill < 1)
    }
}

@Suite("The face at rest")
struct RestingFaceTests {
    @Test("waiting, a hint of a smile and relaxed lids; thinking, the lips press instead")
    func restingLook() {
        let animator = FaceAnimator(seed: 3)
        var pose = FacePose()
        for _ in 0..<120 { pose = animator.update(dt: 1.0 / 60, voice: nil, moment: .waiting) }
        #expect(pose[.mouthSmileLeft] > 0.3 && pose[.mouthSmileRight] > 0.3)
        #expect(pose[.eyeBlinkLeft] >= FaceAnimator.restingLid && pose[.eyeBlinkRight] >= FaceAnimator.restingLid)
        for _ in 0..<180 { pose = animator.update(dt: 1.0 / 60, voice: nil, moment: .thinking) }
        #expect(pose[.mouthSmileLeft] < 0.1)
    }
}
