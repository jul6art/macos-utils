// HoloRenderer — the face as a hologram (spec, § 8.2): a head of light points, deformed by the animation's
// ARKit weights, drawn by Metal with the hologram's layers. Until the MakeHuman faces (lot 5), the head is
// the charter's point face made 3D (docs/charte.md).

import FaceAnimation
import Foundation
import simd

/// One point of the head: where it sits at rest, how it lights, and which parts of the face move it.
struct HeadPoint {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    /// Features (eyes, lips, brows) are larger and brighter, as in the logo.
    var size: Float
    var brightness: Float
    /// How much the jaw carries it: 0 above the upper lip, 1 from the lower lip down.
    var jaw: Float = 0
    var upperLip: Float = 0
    var lowerLip: Float = 0
    var brow: Float = 0
    /// -1 left eye, 1 right eye, 0 none; pupils move with the gaze.
    var eye: Float = 0
    var pupil = false
    /// Specks: the dust around the face, drifting.
    var speck = false
}

/// The head, at rest, in head units: x to the face's right, y up, z towards the viewer; the face is about
/// two units tall.
enum PointHead {
    static let points: [HeadPoint] = build()

    private static let mouthY: Float = -0.5

    /// Half the head's width at height y: the skull's dome, the cheeks, the jaw narrowing to the chin.
    static func halfWidth(_ y: Float) -> Float {
        if y > 0.3 { return 0.78 * max(0, 1 - pow((y - 0.3) / 0.75, 2)).squareRoot() }
        if y > -0.25 { return 0.78 }
        return 0.3 + 0.48 * max(0, 1 - pow((y + 0.25) / 0.9, 2)).squareRoot()
    }

    /// The face's relief: the oval bulge, then the nose, the eye sockets, the brows, the lips, the chin.
    static func depth(_ x: Float, _ y: Float) -> Float {
        let width = max(halfWidth(y), 0.05)
        let across = min(abs(x) / width, 1)
        var z = 0.6 * (1 - across * across).squareRoot()
        func bump(_ cx: Float, _ cy: Float, _ sx: Float, _ sy: Float) -> Float {
            exp(-(pow((x - cx) / sx, 2) + pow((y - cy) / sy, 2)))
        }
        z += 0.2 * bump(0, -0.1, 0.08, 0.22) + 0.08 * bump(0, -0.3, 0.1, 0.07)
        z -= 0.08 * (bump(-0.3, 0.18, 0.13, 0.08) + bump(0.3, 0.18, 0.13, 0.08))
        z += 0.04 * (bump(-0.28, 0.33, 0.2, 0.05) + bump(0.28, 0.33, 0.2, 0.05))
        z += 0.07 * bump(0, mouthY, 0.22, 0.08)
        z += 0.06 * bump(0, -0.95, 0.2, 0.12)
        return z
    }

    private static func normal(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let step: Float = 0.01
        let dx = (depth(x + step, y) - depth(x - step, y)) / (2 * step)
        let dy = (depth(x, y + step) - depth(x, y - step)) / (2 * step)
        return simd_normalize(SIMD3(-dx, -dy, 1))
    }

    private static func build() -> [HeadPoint] {
        var points: [HeadPoint] = []
        let spacing: Float = 0.06

        // The face: a grid on the relief, leaving room for the lips and the eyes drawn below.
        var y: Float = 1.02
        while y > -1.14 {
            let width = halfWidth(y)
            var x = -width
            while x <= width {
                let inMouth = abs(x) < 0.24 && abs(y - mouthY) < 0.07
                let inEye = [-0.3, 0.3].contains { abs(x - Float($0)) < 0.1 && abs(y - 0.18) < 0.06 }
                if !inMouth && !inEye {
                    var point = HeadPoint(
                        position: SIMD3(x, y, depth(x, y)), normal: normal(x, y), size: 1, brightness: 0.9)
                    point.jaw = smoothstep(mouthY + 0.02, mouthY - 0.12, y) * smoothstep(0.62, 0.3, abs(x))
                    point.brow = exp(-pow((y - 0.33) / 0.05, 2)) * (abs(x) < 0.55 ? 1 : 0)
                    points.append(point)
                }
                x += spacing
            }
            y -= spacing
        }
        // The neck.
        y = -1.18
        while y > -1.7 {
            var x: Float = -0.3
            while x <= 0.3 {
                let z = 0.35 * max(0, 1 - pow(x / 0.33, 2)).squareRoot() - 0.15
                points.append(
                    HeadPoint(
                        position: SIMD3(x, y, z), normal: simd_normalize(SIMD3(x, 0, 0.6)), size: 0.8,
                        brightness: 0.55))
                x += spacing
            }
            y -= spacing
        }
        // The lips: two lines each, larger points.
        for index in 0...14 {
            let t = Float(index) / 14 * 2 - 1
            let x = t * 0.22
            let curve = 0.025 * (1 - t * t)
            for (dy, upper) in [(0.035 + curve, true), (0.012, true), (-0.012, false), (-0.04 - curve, false)] {
                let y = mouthY + Float(dy)
                var point = HeadPoint(
                    position: SIMD3(x, y, depth(x, y) + 0.015), normal: normal(x, y), size: 1.5, brightness: 1)
                if upper { point.upperLip = 1 } else { point.lowerLip = 1 }
                point.jaw = upper ? 0 : 1
                points.append(point)
            }
        }
        // The eyes: a ring each, and a pupil that follows the gaze.
        for side: Float in [-1, 1] {
            let centre = SIMD2<Float>(0.3 * side, 0.18)
            for index in 0..<12 {
                let angle = Float(index) / 12 * 2 * .pi
                let x = centre.x + 0.075 * cos(angle)
                let y = centre.y + 0.045 * sin(angle)
                var point = HeadPoint(
                    position: SIMD3(x, y, depth(x, y) + 0.01), normal: normal(x, y), size: 1.4, brightness: 1)
                point.eye = side
                points.append(point)
            }
            var pupil = HeadPoint(
                position: SIMD3(centre.x, centre.y, depth(centre.x, centre.y) + 0.02), normal: SIMD3(0, 0, 1),
                size: 2.6, brightness: 1)
            pupil.eye = side
            pupil.pupil = true
            points.append(pupil)
        }
        // The dust drifting off the face's right side, as in the logo.
        var random = SystemRandom(seed: 7)
        for _ in 0..<60 {
            let y = Float(random.next()) * 1.8 - 0.8
            let x = halfWidth(y) + 0.05 + Float(random.next()) * 0.55
            var point = HeadPoint(
                position: SIMD3(x, y, Float(random.next()) * 0.3), normal: SIMD3(0, 0, 1),
                size: 0.8 + Float(random.next()) * 0.9, brightness: 0.45 + Float(random.next()) * 0.5)
            point.speck = true
            points.append(point)
        }
        return points
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The head shaped by a pose, in head space, before the head's own rotation.
    static func deform(_ pose: FacePose, time: Double) -> [SIMD4<Float>] {
        let jawAngle = pose[.jawOpen] * 0.32
        let close = max(pose[.mouthClose], (pose[.mouthPressLeft] + pose[.mouthPressRight]) / 2)
        // Sealed lips keep together while the jaw opens a little under them.
        let lipJaw = jawAngle * (1 - close)
        let stretch = (pose[.mouthStretchLeft] + pose[.mouthStretchRight]) / 2
        let smile = (pose[.mouthSmileLeft] + pose[.mouthSmileRight]) / 2
        let pucker = pose[.mouthPucker]
        let funnel = pose[.mouthFunnel]
        let roll = pose[.mouthRollLower]
        let upperUp = (pose[.mouthUpperUpLeft] + pose[.mouthUpperUpRight]) / 2
        let browInner = pose[.browInnerUp]
        let browOuter = (pose[.browOuterUpLeft] + pose[.browOuterUpRight]) / 2
        let pivot = SIMD3<Float>(0, -0.05, -0.3)

        return points.map { point in
            var p = point.position
            var size = point.size
            if point.speck {
                // The dust drifts up and right, slowly, and comes back.
                let phase = Float(time * 0.15) + p.y * 3
                p.x += 0.04 * sin(phase)
                p.y += 0.03 * sin(phase * 0.7 + p.x * 5)
                return SIMD4(p.x, p.y, p.z, size)
            }
            // Lips first, in the mouth's own frame.
            let lip = max(point.upperLip, point.lowerLip)
            if lip > 0 {
                let side = min(abs(p.x) / 0.22, 1)
                p.x *= 1 + 0.25 * stretch * side - 0.3 * pucker
                p.y += 0.04 * smile * side * side
                p.z += 0.06 * funnel + 0.03 * pucker
                if point.upperLip > 0 { p.y += 0.04 * upperUp + 0.015 * funnel }
                if point.lowerLip > 0 { p.y += -0.015 * funnel + 0.03 * roll }
                if point.lowerLip > 0 { p.z -= 0.03 * roll }
            }
            // The jaw: a rotation about a pivot behind the cheeks.
            let angle = point.lowerLip > 0 ? lipJaw : jawAngle * point.jaw
            if angle != 0 {
                let local = p - pivot
                let cosine = cos(angle)
                let sine = sin(angle)
                p = pivot + SIMD3(local.x, local.y * cosine - local.z * sine, local.y * sine + local.z * cosine)
            }
            // The brows.
            if point.brow > 0 {
                let inner = 1 - min(abs(p.x) / 0.45, 1)
                p.y += 0.06 * point.brow * (browInner * inner + browOuter * (1 - inner))
            }
            // The eyes: lids close by squashing the ring; the pupil follows the gaze and hides in a blink.
            if point.eye != 0 {
                let blink = point.eye < 0 ? pose[.eyeBlinkLeft] : pose[.eyeBlinkRight]
                let centre = SIMD2<Float>(0.3 * point.eye, 0.18)
                if point.pupil {
                    p.x += 0.035 * pose.gaze.x
                    p.y += 0.025 * pose.gaze.y
                    size *= 1 - blink
                } else {
                    p.y = centre.y + (p.y - centre.y) * (1 - 0.9 * blink)
                }
            }
            return SIMD4(p.x, p.y, p.z, size)
        }
    }
}

/// A small seeded generator for the dust, so the head is the same at every launch.
private struct SystemRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
