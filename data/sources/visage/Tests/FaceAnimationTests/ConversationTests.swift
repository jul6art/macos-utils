import Testing

@testable import FaceAnimation

@Suite("The moment of the conversation")
struct ConversationTests {
    private let frameTime = 1.0 / 60

    /// Holds the same signals for `seconds`, returns the moments seen, in order, without repeats.
    @discardableResult
    private func hold(
        _ tracker: inout ConversationTracker, seconds: Double, ai: Bool = false, listening: Bool = false,
        person: Bool? = nil
    ) -> [ConversationMoment] {
        var moments: [ConversationMoment] = []
        for _ in 0..<Int((seconds / frameTime).rounded()) {
            let moment = tracker.update(dt: frameTime, aiVoiced: ai, appListening: listening, personVoiced: person)
            if moments.last != moment { moments.append(moment) }
        }
        return moments
    }

    @Test("the AI's turn goes on through its pauses, then ends")
    func aiTurn() {
        var tracker = ConversationTracker()
        #expect(hold(&tracker, seconds: 1) == [.waiting])
        #expect(hold(&tracker, seconds: 1, ai: true) == [.speaking])
        #expect(hold(&tracker, seconds: 0.5) == [.speaking])
        #expect(hold(&tracker, seconds: 1, ai: true) == [.speaking])
        #expect(hold(&tracker, seconds: 1.5) == [.speaking, .waiting])
    }

    @Test("an open microphone in the AI's app is listening")
    func listening() {
        var tracker = ConversationTracker()
        #expect(hold(&tracker, seconds: 120, listening: true) == [.listening])
        #expect(hold(&tracker, seconds: 1, ai: true, listening: true) == [.speaking])
        #expect(hold(&tracker, seconds: 2, listening: true) == [.speaking, .listening])
    }

    @Test("a dictation that ends is a question on its way: thinking, until the AI answers")
    func dictation() {
        var tracker = ConversationTracker()
        hold(&tracker, seconds: 5, listening: true)
        #expect(hold(&tracker, seconds: 4) == [.thinking])
        #expect(hold(&tracker, seconds: 1, ai: true) == [.speaking])
    }

    @Test("thinking with no answer gives up; a microphone open a long while was a conversation, not a question")
    func noAnswer() {
        var tracker = ConversationTracker()
        hold(&tracker, seconds: 5, listening: true)
        #expect(hold(&tracker, seconds: ConversationTracker.longestThought + 1) == [.thinking, .waiting])
        hold(&tracker, seconds: 120, listening: true)
        #expect(hold(&tracker, seconds: 2) == [.waiting])
    }

    @Test("with the microphone: the person's sentence, its pauses, then thinking once it ends")
    func sentence() {
        var tracker = ConversationTracker()
        #expect(hold(&tracker, seconds: 1, listening: true, person: false) == [.listening])
        #expect(hold(&tracker, seconds: 1.5, listening: true, person: true) == [.listening])
        #expect(hold(&tracker, seconds: 0.4, listening: true, person: false) == [.listening])
        #expect(hold(&tracker, seconds: 1, listening: true, person: true) == [.listening])
        #expect(hold(&tracker, seconds: 1.5, listening: true, person: false) == [.listening, .thinking])
        #expect(hold(&tracker, seconds: 1, ai: true, listening: true, person: true) == [.speaking])
    }

    @Test("a cough is no sentence; the AI's echo right after it is not the person")
    func noise() {
        var tracker = ConversationTracker()
        hold(&tracker, seconds: 1, listening: true, person: false)
        hold(&tracker, seconds: 0.1, listening: true, person: true)
        #expect(hold(&tracker, seconds: 2, listening: true, person: false) == [.listening])
        hold(&tracker, seconds: 1, ai: true, listening: true, person: true)
        // Its echo, through the speakers, while its turn ends.
        hold(&tracker, seconds: ConversationTracker.aiPause + 0.2, listening: true, person: true)
        #expect(hold(&tracker, seconds: 2, listening: true, person: false) == [.listening])
    }

    @Test("the person heard while the AI does not listen is not talking to it; nor is a silent dictation")
    func notToIt() {
        var tracker = ConversationTracker()
        hold(&tracker, seconds: 2, person: true)
        #expect(hold(&tracker, seconds: 2, person: false) == [.waiting])
        hold(&tracker, seconds: 5, listening: true, person: false)
        #expect(hold(&tracker, seconds: 2, person: false) == [.waiting])
    }
}

@Suite("Listening, with the microphone")
struct ListeningTests {
    private let frameTime = 1.0 / 60

    @Test("the head nods at the person's pauses, never while they speak, nor while they are silent")
    func nodsAtPauses() {
        let animator = FaceAnimator(seed: 11)
        var starts: [Double] = []
        var last = animator.nodUntil
        var time = 0.0
        func run(_ heard: Bool, _ seconds: Double) {
            for _ in 0..<Int((seconds / frameTime).rounded()) {
                _ = animator.update(dt: frameTime, voice: nil, moment: .listening, heard: heard)
                time += frameTime
                if animator.nodUntil != last {
                    starts.append(time)
                    last = animator.nodUntil
                }
            }
        }
        run(false, 4)
        run(true, 4)
        #expect(starts.isEmpty)
        for _ in 0..<6 {
            run(true, 1.2)
            run(false, 0.5)
        }
        #expect(starts.count >= 3)
        // Each at a pause: 0.2 s into the silence, never while the voice is heard.
        for start in starts {
            let cycle = (start - 8).truncatingRemainder(dividingBy: 1.7)
            #expect(cycle > 1.2 && cycle < 1.5)
        }
    }
}
