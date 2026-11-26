/// Where the conversation stands (spec, § 7.2), from what Visage can tell without reading it: whether the
/// AI speaks (its voice, captured), whether it listens (its app has the microphone open), and, with the
/// microphone option, whether the person speaks (how loud, nothing else).
///
/// - *speaking*: the AI's voice, and its pauses between phrases;
/// - *listening*: its app has the microphone open;
/// - *thinking*: the person's sentence has ended, or a dictation has, and the AI has not answered yet;
/// - *waiting*: none of these.
public struct ConversationTracker: Sendable {
    /// The AI's turn goes on through pauses shorter than this.
    public static let aiPause = 0.8
    /// Right after the AI, the microphone still hears it through the speakers: the person is not heard then.
    public static let echoTail = 0.4
    /// A silence this long after the person spoke ends their sentence: the AI thinks. Voice modes wait for
    /// about as long before they answer.
    public static let sentenceEnd = 0.7
    /// Less voice than this is a cough or a click, not a sentence.
    public static let shortestSentence = 0.3
    /// The microphone open this long, then closed: a dictation ended, what was said is on its way. Longer,
    /// it was a voice mode, closed after the conversation.
    public static let dictation = 1.0...90.0
    /// Thinking with no answer gives up after this long.
    public static let longestThought = 15.0

    private var time = 0.0
    private var lastAIVoice = -Double.infinity
    /// When the app opened its microphone, and whether the person was heard since.
    private var listening: (since: Double, heard: Bool)?
    /// The person's sentence under way: how long they have spoken, when they last did.
    private var sentence: (voiced: Double, lastVoice: Double)?
    private var thinkingSince: Double?

    public init() {}

    /// Advances by `dt` seconds. `aiVoiced`: the AI's voice sounds in this frame; `appListening`: its app
    /// has the microphone open; `personVoiced`: the person's voice is heard (nil without the microphone).
    public mutating func update(dt: Double, aiVoiced: Bool, appListening: Bool, personVoiced: Bool?)
        -> ConversationMoment
    {
        time += dt
        if aiVoiced {
            lastAIVoice = time
            thinkingSince = nil
            sentence = nil
        }
        let aiTurn = time - lastAIVoice < Self.aiPause

        // The person, while the AI listens, and not its own echo.
        if appListening, let personVoiced, time - lastAIVoice >= Self.aiPause + Self.echoTail {
            if personVoiced {
                var current = sentence ?? (0, time)
                current.voiced += dt
                current.lastVoice = time
                sentence = current
                listening?.heard = true
                thinkingSince = nil
            } else if let current = sentence, time - current.lastVoice >= Self.sentenceEnd {
                sentence = nil
                if current.voiced >= Self.shortestSentence { thinkingSince = time }
            }
        }

        // The microphone closed: a dictation ended (not if the person, heard, said nothing).
        if appListening {
            if listening == nil { listening = (time, false) }
        } else if let ended = listening {
            listening = nil
            sentence = nil
            let heardNothing = personVoiced != nil && !ended.heard
            if !aiTurn, Self.dictation.contains(time - ended.since), !heardNothing { thinkingSince = time }
        }

        if aiTurn { return .speaking }
        if let since = thinkingSince {
            if time - since < Self.longestThought { return .thinking }
            thinkingSince = nil
        }
        return appListening ? .listening : .waiting
    }
}
