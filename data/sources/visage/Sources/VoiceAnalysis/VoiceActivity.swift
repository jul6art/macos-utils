import Accelerate
import Foundation

/// Whether a voice is heard in a microphone's level (spec, § 5: the level only, nothing recorded): louder
/// than the room by a margin, and held through the short gaps between syllables. The room is the quietest
/// level of the last three seconds: speech always has gaps where the room shows through, and a fan that
/// starts becomes the room within three seconds.
public struct VoiceActivity: Sendable {
    /// How far above the room a voice stands, in decibels.
    public static let margin: Float = 12
    /// Nothing quieter than this is a voice, in dBFS (a microphone's own hiss in a silent room).
    public static let quietest: Float = -55
    /// A voice holds through gaps shorter than this, in seconds.
    public static let hold = 0.25
    /// The room's memory: six half seconds.
    static let slice = 0.5
    static let slices = 6

    public private(set) var voiced = false
    /// The room's level, in dBFS.
    public private(set) var room: Float = 0

    private var quietestBySlice: [Float] = []
    private var sliceQuietest = Float.infinity
    private var sliceTime = 0.0
    private var held = 0.0

    public init() {}

    /// Takes the level of the last `dt` seconds, in dBFS; returns whether a voice is heard.
    @discardableResult
    public mutating func update(levelDecibels level: Float, dt: Double) -> Bool {
        sliceQuietest = min(sliceQuietest, level)
        sliceTime += dt
        if sliceTime >= Self.slice {
            quietestBySlice.append(sliceQuietest)
            if quietestBySlice.count > Self.slices { quietestBySlice.removeFirst() }
            sliceQuietest = .infinity
            sliceTime = 0
        }
        room = min(quietestBySlice.min() ?? .infinity, sliceQuietest, level)
        if level > max(room + Self.margin, Self.quietest) { held = Self.hold } else { held -= dt }
        voiced = held > 0
        return voiced
    }

    /// The level of `samples` (root mean square), in dBFS; −120 for silence.
    public static func decibels(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let base = samples.baseAddress, !samples.isEmpty else { return -120 }
        var meanSquare: Float = 0
        vDSP_measqv(base, 1, &meanSquare, vDSP_Length(samples.count))
        return meanSquare > 1e-12 ? 10 * log10(meanSquare) : -120
    }
}
