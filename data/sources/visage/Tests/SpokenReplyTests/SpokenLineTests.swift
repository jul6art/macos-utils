import Foundation
import Testing

@testable import SpokenReply

@Suite("What Claude Code's voice reads")
struct SpokenLineTests {
    @Test("the last 🔊 line, without the rest of the reply")
    func lastLine() {
        let reply = """
            J'ai corrigé le test :

            - `AudioCapture.swift` : le délai
            - `Connection.swift` : la reconnexion

            🔊 J'ai corrigé les deux fichiers, et les tests passent.
            """
        #expect(SpokenLine.speech(for: reply) == "J'ai corrigé les deux fichiers, et les tests passent.")
    }

    @Test("markdown around and inside the line is dropped, links keep their words")
    func markdown() {
        #expect(SpokenLine.extract(from: "> 🔊 **C'est fait.**") == "C'est fait.")
        #expect(SpokenLine.extract(from: "- 🔊: voir [la doc](https://example.com) et `make`") == "voir la doc et make")
        #expect(SpokenLine.extract(from: "**🔊** Prêt.") == "Prêt.")
    }

    @Test("the marker with an emoji variation selector still counts")
    func variationSelector() {
        #expect(SpokenLine.extract(from: "🔊\u{FE0F} Terminé.") == "Terminé.")
    }

    @Test("the last of several 🔊 lines wins, and an empty one says nothing")
    func severalLines() {
        #expect(SpokenLine.extract(from: "🔊 Première.\ntexte\n🔊 Seconde.") == "Seconde.")
        #expect(SpokenLine.extract(from: "🔊   ") == nil)
    }

    @Test("a short reply without the line is read whole; a long one, or one with code, is not")
    func fallback() {
        #expect(SpokenLine.speech(for: "Bonjour ! Que puis-je faire ?") == "Bonjour ! Que puis-je faire ?")
        #expect(SpokenLine.speech(for: String(repeating: "mot ", count: 100)) == nil)
        #expect(SpokenLine.speech(for: "Voici :\n```\nls\n```") == nil)
        #expect(SpokenLine.speech(for: "  ") == nil)
    }

    @Test("the context names the marker it asks for")
    func context() {
        #expect(SpokenLine.context.contains(SpokenLine.marker))
        #expect(!SpokenLine.context.contains("\n"))
    }

    @Test("a hook's input is read leniently")
    func hookInput() {
        let stop = HookInput.read(Data(#"{"hook_event_name":"Stop","last_assistant_message":"Fini."}"#.utf8))
        #expect(stop.lastAssistantMessage == "Fini.")
        let notification = HookInput.read(Data(#"{"notification_type":"permission_prompt"}"#.utf8))
        #expect(notification.notificationType == "permission_prompt")
        #expect(HookInput.read(Data("not json".utf8)).lastAssistantMessage == nil)
        #expect(HookInput.read(Data(#"{"last_assistant_message":42}"#.utf8)).lastAssistantMessage == nil)
    }

    @Test("a message to the voice goes there and back")
    func message() {
        #expect(VoiceMessage.read(VoiceMessage.saying("Fini.").data) == .saying("Fini."))
        #expect(VoiceMessage.read(VoiceMessage.hushing.data)?.hush == true)
        #expect(VoiceMessage.read(Data("nonsense".utf8)) == nil)
    }
}
