import Testing

@testable import SpokenReply

@Suite("Choosing Claude Code's voice")
struct VoiceChoiceTests {
    private let voices = [
        VoiceInfo(identifier: "thomas", name: "Thomas", language: "fr-FR", quality: 1, gender: .male),
        VoiceInfo(identifier: "amelie", name: "Amélie", language: "fr-CA", quality: 2, gender: .female),
        VoiceInfo(identifier: "audrey", name: "Audrey", language: "fr-FR", quality: 3, gender: .female),
        VoiceInfo(identifier: "jacques", name: "Jacques", language: "fr-FR", quality: 2, gender: .male),
        VoiceInfo(
            identifier: "bells", name: "Bells", language: "fr-FR", quality: 3, gender: .unspecified, isSpecial: true),
        VoiceInfo(identifier: "samantha", name: "Samantha", language: "en-US", quality: 3, gender: .female),
    ]

    @Test("the face's gender first, then the quality")
    func gender() {
        #expect(VoiceChoice.best(among: voices, language: "fr", gender: .male)?.identifier == "jacques")
        #expect(VoiceChoice.best(among: voices, language: "fr", gender: .female)?.identifier == "audrey")
    }

    @Test("without a gender, the best quality; a novelty or personal voice is never picked")
    func quality() {
        #expect(VoiceChoice.best(among: voices, language: "fr-FR")?.identifier == "audrey")
    }

    @Test("at equal quality, the user's region")
    func region() {
        let two = [
            VoiceInfo(identifier: "ca", name: "A", language: "fr-CA", quality: 2, gender: .female),
            VoiceInfo(identifier: "fr", name: "B", language: "fr-FR", quality: 2, gender: .female),
        ]
        #expect(VoiceChoice.best(among: two, language: "fr", region: "FR")?.identifier == "fr")
        #expect(VoiceChoice.best(among: two, language: "fr", region: "CA")?.identifier == "ca")
    }

    @Test("only the reply's language; none installed, no voice")
    func language() {
        #expect(VoiceChoice.best(among: voices, language: "en")?.identifier == "samantha")
        #expect(VoiceChoice.best(among: voices, language: "de") == nil)
    }

    @Test("a face's gender from faces.json")
    func faceGender() {
        #expect(VoiceChoice.gender(fromFaceValue: 0) == .female)
        #expect(VoiceChoice.gender(fromFaceValue: 1) == .male)
        #expect(VoiceChoice.gender(fromFaceValue: nil) == .unspecified)
    }
}
