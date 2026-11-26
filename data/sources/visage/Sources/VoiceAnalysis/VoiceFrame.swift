// VoiceAnalysis — what the voice says to the face, every 10 ms (spec, § 6.1): its level, its pitch, its
// vowels as formants, its fricatives, its closures. No model, no dependency: Accelerate and arithmetic.

/// The sound of a 10 ms hop, as the face needs to know it.
public enum SoundClass: String, Sendable, Codable {
    case silence
    /// A voiced, open sound: the vowels (and the liquids, l and r).
    case vowel
    /// A nasal murmur (m, n): voiced, quiet, dark.
    case nasal
    /// s, z: lips spread, teeth close.
    case fricativeS
    /// ch, j: lips pushed forward.
    case fricativeSh
    /// f, v: the lower lip under the teeth.
    case fricativeF
    /// The silence inside a stop (p, t, k), between two sounds.
    case closure

    /// The mouth shut, or nearly: a stop's silence, or a murmur (m, n, and the voice bar of b, d, g).
    public var isOcclusion: Bool { self == .closure || self == .nasal }

    public var isFricative: Bool { self == .fricativeS || self == .fricativeSh || self == .fricativeF }
}

/// The analysis of one hop. Hop `n` covers frames `n × hop ..< (n + 1) × hop` of the source: 10 ms.
public struct VoiceFrame: Sendable, Equatable, Codable {
    public var hop: Int
    public var sound: SoundClass
    /// dBFS of the 25 ms around the hop.
    public var energyDecibels: Float
    /// 0 (silence) to 1 (the voice's loudest), relative to this voice.
    public var loudness: Float
    public var isVoiced: Bool
    /// Hz, when voiced.
    public var pitch: Float?
    /// 0 to 1 within this voice's range; 0.5 when unvoiced.
    public var pitchLevel: Float
    /// Hz, when found.
    public var formant1: Float?
    public var formant2: Float?
    public var formant3: Float?
    /// From F1, relative to this voice: how open the mouth is.
    public var openness: Float
    /// From F2: front vowels (i, é) spread the lips, back ones (ou, o) do not.
    public var frontness: Float
    /// Back vowels, and the front rounded ones of French (u, eu), whose F3 comes down towards F2.
    public var rounding: Float
    /// Hz: where the spectrum's weight sits.
    public var centroid: Float
    /// Share of the energy above 4 kHz.
    public var highBand: Float
    /// For closures and nasals: how likely the lips are what closes (b, p, m), from the second formant
    /// around it. 0 when it does not apply.
    public var bilabial: Float
}
