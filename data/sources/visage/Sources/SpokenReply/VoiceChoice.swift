/// A voice installed on the Mac, as the speech synthesizer lists it.
public struct VoiceInfo: Sendable, Equatable {
    public enum Gender: Sendable, Equatable {
        case unspecified, male, female
    }

    public var identifier: String
    public var name: String
    /// BCP 47, as the synthesizer gives it: « fr-FR ».
    public var language: String
    /// 1 default, 2 enhanced, 3 premium.
    public var quality: Int
    public var gender: Gender
    /// A novelty voice (bells, a whisper) or a personal voice: never picked on their own.
    public var isSpecial: Bool

    public init(
        identifier: String, name: String, language: String, quality: Int, gender: Gender, isSpecial: Bool = false
    ) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
        self.isSpecial = isSpecial
    }
}

/// Which voice reads Claude Code's replies: one of the reply's language, of the face's gender when one is
/// installed, then the best quality, then the user's region (« fr-FR » rather than « fr-CA » in France).
public enum VoiceChoice {
    public static func best(
        among voices: [VoiceInfo], language: String, region: String? = nil, gender: VoiceInfo.Gender = .unspecified
    ) -> VoiceInfo? {
        let base = language.split(separator: "-").first.map { $0.lowercased() } ?? ""
        let candidates = voices.filter {
            !$0.isSpecial && $0.language.split(separator: "-").first?.lowercased() == base
        }
        func rank(_ voice: VoiceInfo) -> (Int, Int, Int) {
            let sameGender = gender != .unspecified && voice.gender == gender ? 1 : 0
            let sameRegion =
                region.map { voice.language.lowercased().hasSuffix("-" + $0.lowercased()) } == true ? 1 : 0
            return (sameGender, voice.quality, sameRegion)
        }
        return candidates.max { left, right in
            let (a, b) = (rank(left), rank(right))
            // Equal ranks: the name decides, so that the choice does not hang on the list's order.
            return a == b ? left.name > right.name : a < b
        }
    }

    /// The face's gender, from faces.json's value: 0 a woman, 1 a man.
    public static func gender(fromFaceValue value: Double?) -> VoiceInfo.Gender {
        guard let value else { return .unspecified }
        return value < 0.5 ? .female : .male
    }
}
