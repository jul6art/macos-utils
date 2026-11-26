// FaceAnimation — what the face does at each displayed frame (spec, § 7): the 52 ARKit weights, the head's
// pose and the gaze, from the voice when it speaks, and from a life of its own when it does not.

/// The 52 ARKit blend shapes, by their standard names: the faces' glTF files carry the same names
/// (spec, § 8.1), so one animation drives them all.
public enum FaceShape: Int, CaseIterable, Sendable {
    case browDownLeft, browDownRight, browInnerUp, browOuterUpLeft, browOuterUpRight
    case cheekPuff, cheekSquintLeft, cheekSquintRight
    case eyeBlinkLeft, eyeBlinkRight, eyeLookDownLeft, eyeLookDownRight, eyeLookInLeft, eyeLookInRight
    case eyeLookOutLeft, eyeLookOutRight, eyeLookUpLeft, eyeLookUpRight, eyeSquintLeft, eyeSquintRight
    case eyeWideLeft, eyeWideRight
    case jawForward, jawLeft, jawOpen, jawRight
    case mouthClose, mouthDimpleLeft, mouthDimpleRight, mouthFrownLeft, mouthFrownRight, mouthFunnel
    case mouthLeft, mouthLowerDownLeft, mouthLowerDownRight, mouthPressLeft, mouthPressRight, mouthPucker
    case mouthRight, mouthRollLower, mouthRollUpper, mouthShrugLower, mouthShrugUpper, mouthSmileLeft
    case mouthSmileRight, mouthStretchLeft, mouthStretchRight, mouthUpperUpLeft, mouthUpperUpRight
    case noseSneerLeft, noseSneerRight
    case tongueOut

    /// The name as ARKit, and the glTF files, spell it.
    public var name: String { String(describing: self) }
}

/// The face at one displayed frame.
public struct FacePose: Sendable, Equatable {
    /// Indexed by `FaceShape.rawValue`, each in 0…1.
    public var weights: [Float]
    /// Pitch (nodding, down is positive), yaw (turning left), roll (tilting), in radians.
    public var head: SIMD3<Float>
    /// Where the eyes look, -1…1 on each axis: x to the face's right, y up.
    public var gaze: SIMD2<Float>
    /// How bright the hologram glows, 0…1: the voice lights it (spec, § 8.2).
    public var glow: Float

    public init() {
        weights = [Float](repeating: 0, count: FaceShape.allCases.count)
        head = .zero
        gaze = .zero
        glow = 0.7
    }

    public subscript(_ shape: FaceShape) -> Float {
        get { weights[shape.rawValue] }
        set { weights[shape.rawValue] = min(max(newValue, 0), 1) }
    }
}

/// What the conversation is doing (spec, § 7.2).
public enum ConversationMoment: Sendable, Equatable {
    /// Nobody speaks.
    case waiting
    /// The user speaks (their microphone is live).
    case listening
    /// Between the end of the user's sentence and the AI's answer.
    case thinking
    /// The AI speaks.
    case speaking
}
