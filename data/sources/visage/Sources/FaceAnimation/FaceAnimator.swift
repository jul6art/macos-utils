import Foundation
import Shared
import VoiceAnalysis
import simd

/// Turns the voice into a face, one displayed frame at a time (spec, § 7).
///
/// Speaking, the mouth takes the shape of the sound read *ahead* of what is heard (the caller samples the
/// voice at heard time + anticipation), the brows and the head follow the intonation. Always, the face
/// lives: it breathes, blinks, glances away, drifts, now and then half smiles (§ 7.2). Every random draw is
/// seeded: the same seed gives the same face, which the tests rely on; the app seeds it from the clock.
public final class FaceAnimator: @unchecked Sendable {
    private var random: Mulberry32
    private var time: Double = 0
    private var pose = FacePose()

    /// The mouth and brow shapes that follow targets, each with its own speed.
    private var followers: [Int: Follower] = [:]
    private static let mouthSpeeds: [(FaceShape, Float, Float)] = [
        (.jawOpen, 0.035, 0.08), (.mouthClose, 0.025, 0.06), (.mouthPressLeft, 0.025, 0.07),
        (.mouthPressRight, 0.025, 0.07), (.mouthFunnel, 0.05, 0.09), (.mouthPucker, 0.05, 0.09),
        (.mouthStretchLeft, 0.05, 0.09), (.mouthStretchRight, 0.05, 0.09), (.mouthRollLower, 0.04, 0.08),
        (.mouthUpperUpLeft, 0.05, 0.09), (.mouthUpperUpRight, 0.05, 0.09), (.mouthLowerDownLeft, 0.04, 0.08),
        (.mouthLowerDownRight, 0.04, 0.08), (.mouthSmileLeft, 0.3, 0.5), (.mouthSmileRight, 0.3, 0.5),
        (.browInnerUp, 0.12, 0.3), (.browOuterUpLeft, 0.12, 0.3), (.browOuterUpRight, 0.12, 0.3),
        (.browDownLeft, 0.15, 0.3), (.browDownRight, 0.15, 0.3),
    ]

    private var headPitch = HeadSpring(frequency: 1.6, dampingRatio: 0.8)
    private var headYaw = HeadSpring(frequency: 1.2, dampingRatio: 0.85)
    private var headRoll = HeadSpring(frequency: 1.2, dampingRatio: 0.85)
    private var gazeX = Follower(rise: 0.03, fall: 0.03)
    private var gazeY = Follower(rise: 0.03, fall: 0.03)
    private var glow = Follower(rise: 0.06, fall: 0.25, value: 0.6)

    // The life of its own.
    private let driftPhases: [Double]
    private let driftFrequencies: [Double]
    private var breathPhase: Double = 0
    private var nextBlink: Double
    private var blinkStart: Double = -10
    private var pendingDoubleBlink = false
    private var nextSaccade: Double
    private var saccade = SIMD2<Float>.zero
    private var nextGlance: Double
    private var glanceUntil: Double = -1
    private var glance = SIMD2<Float>.zero
    private var nextExpression: Double
    private var expression: (shape: [FaceShape], start: Double, duration: Double, strength: Float)?
    private var nextListeningNod: Double = 0
    /// The person's voice, with the microphone: how long they have spoken since the last pause, how long
    /// they have been silent.
    private var personSpoke: Double = 0
    private var personSilent: Double = 0

    // The voice's recent past.
    private var lastLoudness: Float = 0
    private var averageLoudness: Float = 0
    private var pitchHistory: [Float] = []
    private(set) var nodUntil: Double = -1
    private var lastVoiced: Double = -10
    private var phraseEnded = true

    public init(seed: UInt32) {
        random = Mulberry32(seed: seed)
        var draws = random
        driftPhases = (0..<9).map { _ in draws.next() * 2 * Double.pi }
        driftFrequencies = (0..<9).map { _ in 0.04 + draws.next() * 0.16 }
        random = draws
        nextBlink = 1 + draws.next() * 3
        nextSaccade = 0.5 + draws.next()
        nextGlance = 5 + draws.next() * 10
        nextExpression = 20 + draws.next() * 40
        random = draws
        for (shape, rise, fall) in Self.mouthSpeeds {
            followers[shape.rawValue] = Follower(rise: rise, fall: fall)
        }
    }

    /// Advances by `dt` seconds. `voice` is the frame read ahead (nil when nothing is captured).
    /// Where the person stands, seen from the screen (x right, y up, each −1 to 1), when the camera finds
    /// them (spec, § 7.1, point 7): the gaze rests there, and the head turns a little towards them. Nil:
    /// the gaze rests on the camera.
    public var lookAt: SIMD2<Float>?

    /// `heard`: whether the person's voice is heard, with the microphone option (nil without): listening,
    /// the head nods at their pauses rather than now and then.
    public func update(dt: Double, voice: VoiceFrame?, moment: ConversationMoment, heard: Bool? = nil) -> FacePose {
        time += dt
        if let heard {
            if heard {
                personSpoke += dt
                personSilent = 0
            } else {
                personSilent += dt
            }
        }
        let dtf = Float(dt)
        let speaking = moment == .speaking && voice.map { $0.sound != .silence } == true

        // 1. The mouth, from the sound (§ 7.1).
        var targets = mouthTargets(speaking ? voice : nil)
        // 2. The brows and the head, from the intonation; the end of a phrase.
        prosody(voice: speaking ? voice : nil, targets: &targets)
        // 3. The moment: listening, thinking.
        momentTargets(moment, heard: heard, targets: &targets)
        // 4. A rare micro-expression, never while speaking.
        microExpression(moment: moment, targets: &targets)

        for (index, var follower) in followers {
            follower.update(towards: targets[index] ?? 0, dt: dtf)
            followers[index] = follower
            pose.weights[index] = min(max(follower.value, 0), 1)
        }

        blink(moment: moment)
        gaze(moment: moment, dt: dtf)
        head(moment: moment, dt: dtf)

        let loudness = speaking ? (voice?.loudness ?? 0) : 0
        glow.update(towards: speaking ? 0.65 + 0.35 * loudness : 0.6, dt: dtf)
        pose.glow = glow.value
        return pose
    }

    // MARK: - The mouth

    private func mouthTargets(_ voice: VoiceFrame?) -> [Int: Float] {
        var targets: [Int: Float] = [:]
        func set(_ shape: FaceShape, _ value: Float) { targets[shape.rawValue] = value }
        func both(_ left: FaceShape, _ right: FaceShape, _ value: Float) {
            set(left, value)
            set(right, value)
        }
        guard let voice else { return targets }
        switch voice.sound {
        case .silence:
            break
        case .vowel:
            let level = voice.loudness.squareRoot()
            set(.jawOpen, 0.08 + 0.55 * voice.openness * level + 0.1 * level)
            both(
                .mouthStretchLeft, .mouthStretchRight,
                max(0, voice.frontness - 0.5) * 1.2 * (1 - voice.rounding) * level)
            set(.mouthFunnel, voice.rounding * 0.7 * level)
            set(.mouthPucker, voice.rounding * (1 - voice.openness) * 0.6 * level)
            both(.mouthLowerDownLeft, .mouthLowerDownRight, 0.3 * voice.openness * level)
            both(.mouthUpperUpLeft, .mouthUpperUpRight, 0.15 * voice.frontness * level)
        case .nasal:
            set(.jawOpen, 0.06)
            set(.mouthClose, voice.bilabial)
            both(.mouthPressLeft, .mouthPressRight, 0.4 * voice.bilabial)
        case .closure:
            // The lips shut first: their shapes rise faster than the jaw's (§ 7.1, point 4).
            set(.jawOpen, 0.04)
            set(.mouthClose, voice.bilabial)
            both(.mouthPressLeft, .mouthPressRight, 0.6 * voice.bilabial)
        case .fricativeS:
            set(.jawOpen, 0.1)
            both(.mouthStretchLeft, .mouthStretchRight, 0.45)
            both(.mouthUpperUpLeft, .mouthUpperUpRight, 0.25)
            both(.mouthLowerDownLeft, .mouthLowerDownRight, 0.2)
        case .fricativeSh:
            set(.jawOpen, 0.12)
            set(.mouthFunnel, 0.55)
            set(.mouthPucker, 0.35)
            both(.mouthUpperUpLeft, .mouthUpperUpRight, 0.2)
        case .fricativeF:
            set(.jawOpen, 0.08)
            set(.mouthRollLower, 0.65)
            both(.mouthUpperUpLeft, .mouthUpperUpRight, 0.3)
        }
        return targets
    }

    // MARK: - Intonation

    private func prosody(voice: VoiceFrame?, targets: inout [Int: Float]) {
        guard let voice else {
            // The phrase just ended: the head settles, a blink becomes likely (§ 7.1, point 5).
            if !phraseEnded, time - lastVoiced > 0.25 {
                phraseEnded = true
                if random.next() < 0.6 { nextBlink = min(nextBlink, time + 0.05 + random.next() * 0.3) }
            }
            return
        }
        if voice.isVoiced {
            lastVoiced = time
            phraseEnded = false
            pitchHistory.append(voice.pitchLevel)
            if pitchHistory.count > 20 { pitchHistory.removeFirst() }
        }
        // A rising pitch lifts the brows; a question lifts them more.
        let rise = (pitchHistory.last ?? 0.5) - (pitchHistory.first ?? 0.5)
        let lift = 0.35 * max(0, voice.pitchLevel - 0.55) / 0.45 + (rise > 0.25 ? 0.25 : 0)
        targets[FaceShape.browInnerUp.rawValue] = lift
        targets[FaceShape.browOuterUpLeft.rawValue] = lift * 0.7
        targets[FaceShape.browOuterUpRight.rawValue] = lift * 0.7
        // A stressed syllable: louder than the voice's recent average, voiced. A small nod.
        averageLoudness += (voice.loudness - averageLoudness) * 0.05
        if voice.isVoiced, voice.loudness > averageLoudness + 0.25, lastLoudness <= averageLoudness + 0.25,
            time > nodUntil + 0.3
        {
            nodUntil = time + 0.14
        }
        lastLoudness = voice.loudness
    }

    // MARK: - Moments

    private func momentTargets(_ moment: ConversationMoment, heard: Bool?, targets: inout [Int: Float]) {
        switch moment {
        case .thinking:
            targets[FaceShape.mouthPressLeft.rawValue] = max(targets[FaceShape.mouthPressLeft.rawValue] ?? 0, 0.18)
            targets[FaceShape.mouthPressRight.rawValue] = max(targets[FaceShape.mouthPressRight.rawValue] ?? 0, 0.18)
            targets[FaceShape.browInnerUp.rawValue] = max(targets[FaceShape.browInnerUp.rawValue] ?? 0, 0.15)
        case .listening:
            if heard != nil {
                // At a pause in the person's sentence, often a small nod (§ 7.2); never while they speak.
                if personSpoke >= 0.5, personSilent >= 0.2 {
                    personSpoke = 0
                    if time >= nextListeningNod, random.next() < 0.7 {
                        nodUntil = time + 0.16
                        nextListeningNod = time + 1.2
                    }
                }
            } else if time >= nextListeningNod {
                nodUntil = time + 0.16
                nextListeningNod = time + 2.5 + random.next() * 2
            }
        case .waiting, .speaking:
            break
        }
    }

    private func microExpression(moment: ConversationMoment, targets: inout [Int: Float]) {
        if let current = expression {
            let progress = (time - current.start) / current.duration
            if progress >= 1 {
                expression = nil
            } else if moment != .speaking {
                let envelope = Float(sin(Double.pi * progress))
                for shape in current.shape {
                    targets[shape.rawValue] = max(targets[shape.rawValue] ?? 0, current.strength * envelope)
                }
            }
        }
        guard expression == nil, time >= nextExpression else { return }
        nextExpression = time + 20 + random.next() * 40
        guard moment != .speaking else { return }
        let choices: [[FaceShape]] = [
            [.mouthSmileLeft, .mouthSmileRight], [.browInnerUp, .browOuterUpLeft, .browOuterUpRight],
            [.mouthPressLeft, .mouthPressRight],
        ]
        let shapes = choices[min(Int(random.next() * Double(choices.count)), choices.count - 1)]
        expression = (shapes, time, 1.2 + random.next() * 0.8, Float(0.2 + random.next() * 0.15))
    }

    // MARK: - Eyes and head

    /// 100 to 150 ms; every 2 to 6 s, more often while thinking; sometimes twice (§ 7.2).
    private func blink(moment: ConversationMoment) {
        if time >= nextBlink {
            blinkStart = time
            let duration = 0.1 + random.next() * 0.05
            if pendingDoubleBlink {
                pendingDoubleBlink = false
                nextBlink = time + (moment == .thinking ? 1.5 : 2) + random.next() * 4
            } else if random.next() < 0.15 {
                pendingDoubleBlink = true
                nextBlink = time + duration + 0.12
            } else {
                nextBlink = time + (moment == .thinking ? 1.5 : 2) + random.next() * 4
            }
        }
        let elapsed = time - blinkStart
        let closed: Double
        switch elapsed {
        case ..<0: closed = 0
        case ..<0.05: closed = elapsed / 0.05
        case ..<0.08: closed = 1
        case ..<0.15: closed = 1 - (elapsed - 0.08) / 0.07
        default: closed = 0
        }
        pose[.eyeBlinkLeft] = Float(closed)
        pose[.eyeBlinkRight] = Float(closed)
    }

    private func gaze(moment: ConversationMoment, dt: Float) {
        if time >= nextSaccade {
            nextSaccade = time + 0.5 + random.next() * 1.5
            saccade = SIMD2(Float(random.next() - 0.5) * 0.12, Float(random.next() - 0.5) * 0.08)
        }
        if moment != .listening, time >= nextGlance {
            nextGlance = time + 5 + random.next() * 10
            glanceUntil = time + 1 + random.next()
            glance = SIMD2(Float(random.next() - 0.5) * 1.0, Float(random.next() - 0.5) * 0.6)
        }
        var target = Self.gazeTarget(for: lookAt) + saccade
        if time < glanceUntil { target += glance }
        if moment == .thinking { target += SIMD2(0.35, 0.45) }
        gazeX.update(towards: target.x, dt: dt)
        gazeY.update(towards: target.y, dt: dt)
        pose.gaze = SIMD2(gazeX.value, gazeY.value)
        // The eyelids follow the gaze a little.
        pose[.eyeLookUpLeft] = max(0, gazeY.value) * 0.6
        pose[.eyeLookUpRight] = max(0, gazeY.value) * 0.6
        pose[.eyeLookDownLeft] = max(0, -gazeY.value) * 0.6
        pose[.eyeLookDownRight] = max(0, -gazeY.value) * 0.6
    }

    /// The gaze's resting point for a person at `position`: their place, within the eyes' reach.
    static func gazeTarget(for position: SIMD2<Float>?) -> SIMD2<Float> {
        guard let position else { return .zero }
        return simd_clamp(position, SIMD2(-1, -1), SIMD2(1, 1)) * SIMD2(0.8, 0.6)
    }

    private func head(moment: ConversationMoment, dt: Float) {
        // Breathing: 12 to 16 a minute, never quite regular.
        breathPhase += Double(dt) * (14 + 2 * sin(time * 0.05 + driftPhases[0])) / 60 * 2 * Double.pi
        let breath = Float(sin(breathPhase))
        // A slow drift: a few degrees, sums of incommensurate sines, never periodic.
        func drift(_ axis: Int) -> Float {
            var sum = 0.0
            for k in 0..<3 {
                let index = axis * 3 + k
                sum += sin(time * 2 * Double.pi * driftFrequencies[index] + driftPhases[index]) / Double(k + 1)
            }
            return Float(sum) * 0.018
        }
        // The head turns a little towards the person, after the eyes (their followers are slower).
        let toward = Self.gazeTarget(for: lookAt)
        var pitch = drift(0) + breath * 0.006 + toward.y * 0.05
        var yaw = drift(1) + toward.x * 0.08
        var roll = drift(2) * 0.6
        if time < nodUntil { pitch += 0.04 }
        if moment == .thinking {
            roll += 0.05
            yaw += 0.06
        }
        headPitch.update(towards: pitch, dt: dt)
        headYaw.update(towards: yaw, dt: dt)
        headRoll.update(towards: roll, dt: dt)
        pose.head = SIMD3(headPitch.value, headYaw.value, headRoll.value)
        // The jaw breathes too, barely, when the mouth is still.
        if pose[.jawOpen] < 0.05 { pose[.jawOpen] = pose[.jawOpen] + 0.008 * (breath + 1) }
    }
}
