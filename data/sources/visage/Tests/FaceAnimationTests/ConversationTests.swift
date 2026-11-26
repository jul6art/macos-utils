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
