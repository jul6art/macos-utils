import Foundation
import Testing

@testable import VoiceAnalysis

@Suite("A voice in the microphone's level")
struct VoiceActivityTests {
    private let step = 1024.0 / 48_000

    /// Feeds `level` for `seconds`; returns the share of steps heard as a voice.
    @discardableResult
    private func feed(_ activity: inout VoiceActivity, _ level: Float, seconds: Double) -> Double {
        let steps = Int(seconds / step)
        var voiced = 0
        for _ in 0..<steps where activity.update(levelDecibels: level, dt: step) { voiced += 1 }
        return Double(voiced) / Double(max(steps, 1))
    }

    @Test("a quiet room is no voice, nor a steady fan")
    func room() {
        var quiet = VoiceActivity()
        #expect(feed(&quiet, -62, seconds: 5) == 0)
        var fan = VoiceActivity()
        #expect(feed(&fan, -38, seconds: 5) == 0)
    }

    @Test("speech, gaps and all, is a voice; it ends a moment after the person stops")
    func speech() {
        var activity = VoiceActivity()
        feed(&activity, -62, seconds: 2)
        var heard = 0.0
        for _ in 0..<8 {
            heard += feed(&activity, -26, seconds: 0.3) / 16
            heard += feed(&activity, -60, seconds: 0.1) / 16
        }
        #expect(heard > 0.98)
        #expect(activity.room < -55)
        feed(&activity, -62, seconds: VoiceActivity.hold + 0.05)
        #expect(!activity.voiced)
    }

    @Test("a fan that starts becomes the room within three seconds; a voice over it is still heard")
    func fanStarts() {
        var activity = VoiceActivity()
        feed(&activity, -62, seconds: 2)
        feed(&activity, -38, seconds: 3.6)
        #expect(feed(&activity, -38, seconds: 2) == 0)
        #expect(feed(&activity, -20, seconds: 0.3) > 0.9)
    }

    @Test("under the quietest level, nothing is a voice, however silent the room")
    func quietest() {
        var activity = VoiceActivity()
        feed(&activity, -90, seconds: 2)
        #expect(feed(&activity, -60, seconds: 1) == 0)
    }

    @Test("the level: a full-scale sine is −3 dBFS, silence −120")
    func decibels() {
        let sine = (0..<4800).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        let zeros = [Float](repeating: 0, count: 480)
        #expect(abs(sine.withUnsafeBufferPointer(VoiceActivity.decibels) + 3.01) < 0.05)
        #expect(zeros.withUnsafeBufferPointer(VoiceActivity.decibels) == -120)
    }
}
