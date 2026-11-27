import Foundation

/// The line a reply of Claude Code ends with, for Visage to read aloud (spec, § 4.4). Claude Code writes its
/// replies for a terminal (lists, code, paths), which sound wrong read out: while Visage listens, the plugin
/// tells it to close each final reply with one or two sentences written to be heard, after 🔊.
public enum SpokenLine {
    public static let marker = "🔊"
    static let markerScalar: Unicode.Scalar = "\u{1F50A}"

    /// What Claude Code is told with each prompt, while Visage listens to it. Facts, not orders: Claude
    /// Code's hooks documentation warns that imperative, system-style wording can trip its defences against
    /// prompt injection.
    public static let context = """
        Visage, an app on this Mac, gives Claude Code a voice and a face: it reads aloud, with the Mac's voice, \
        the line of the final reply that starts with 🔊, and only that line. The user listens rather than \
        reads. That line closes every final reply: one or two short sentences in the language of the \
        conversation, written to be heard (no code, file path, list, link or markdown), saying what was done \
        or found, or what Claude Code needs from the user.
        """

    /// A reply this short, with no code, is read whole when it has no 🔊 line: « Bonjour ! » needs no
    /// summary, and a face that stays silent would look broken.
    public static let fallbackLimit = 280

    /// What to say for a reply: its last 🔊 line, or the whole of a short reply without code; nothing
    /// otherwise.
    public static func speech(for reply: String) -> String? {
        if let line = extract(from: reply) { return line }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= fallbackLimit, !text.contains("```") else { return nil }
        let spoken = speakable(text)
        return spoken.isEmpty ? nil : spoken
    }

    /// The last line that starts with the marker, cleaned of its markdown; markdown may wrap the marker
    /// too (a quote, a bullet, bold).
    public static func extract(from reply: String) -> String? {
        for line in reply.split(whereSeparator: \.isNewline).reversed() {
            // By scalars: the marker may come with an emoji variation selector, another character then.
            var scalars = Substring(line.drop { " \t>-*_".contains($0) }).unicodeScalars[...]
            guard scalars.first == markerScalar else { continue }
            scalars = scalars.dropFirst().drop { $0 == "\u{FE0F}" }
            let spoken = speakable(String(String.UnicodeScalarView(scalars)))
            return spoken.isEmpty ? nil : spoken
        }
        return nil
    }

    /// Text for the ear: links kept as their words, emphasis and code ticks dropped, one line.
    static func speakable(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`", "*"] {
            result = result.replacingOccurrences(of: mark, with: "")
        }
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " :–—-").union(.whitespacesAndNewlines))
    }
}

/// What a hook of Claude Code receives on its standard input: only the fields Visage's voice reads.
public struct HookInput: Decodable, Sendable {
    /// The final text of the turn (Stop).
    public var lastAssistantMessage: String?
    /// The kind of a notification (Notification): `permission_prompt` when Claude Code waits for a yes.
    public var notificationType: String?

    enum CodingKeys: String, CodingKey {
        case lastAssistantMessage = "last_assistant_message"
        case notificationType = "notification_type"
    }

    public init(lastAssistantMessage: String? = nil, notificationType: String? = nil) {
        self.lastAssistantMessage = lastAssistantMessage
        self.notificationType = notificationType
    }

    /// Reads it leniently: a field missing or of another shape is nil, never an error.
    public static func read(_ data: Data) -> HookInput {
        (try? JSONDecoder().decode(HookInput.self, from: data)) ?? HookInput()
    }
}

/// What a hook hands Claude Code's voice, the helper that lives while Visage listens (spec, § 4.4): a
/// sentence to say, or silence when the user speaks again.
public struct VoiceMessage: Codable, Equatable, Sendable {
    public var say: String?
    public var hush: Bool?

    public static func saying(_ text: String) -> VoiceMessage { VoiceMessage(say: text) }
    public static let hushing = VoiceMessage(hush: true)

    public init(say: String? = nil, hush: Bool? = nil) {
        self.say = say
        self.hush = hush
    }

    public var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func read(_ data: Data) -> VoiceMessage? {
        try? JSONDecoder().decode(VoiceMessage.self, from: data)
    }
}
