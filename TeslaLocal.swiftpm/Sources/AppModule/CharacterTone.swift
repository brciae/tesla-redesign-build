import Foundation

/// v37. Timbre alone never reads as a character: what makes a voice sound like a 10-, 20- or 30-something
/// is *how the line is worded and paced*, not only how it is filtered. The engine cannot be told to act,
/// so the persona rewrites the sentence endings before synthesis and carries its own tempo.
///
/// Every rule below only touches sentence-final morphology of the app's own Korean guidance strings.
/// Place names, numbers and road names are never rewritten.
enum CharacterTone: String, Codable, CaseIterable {
    case teen        // 10대: short, excited, 반말
    case twenties    // 20대: friendly 해요체
    case thirties    // 30대: composed 합니다체

    var title: String {
        switch self {
        case .teen: return "10대 · 발랄한 반말"
        case .twenties: return "20대 · 친근한 해요체"
        case .thirties: return "30대 · 차분한 합니다체"
        }
    }

    /// Endings are replaced longest-first so "하십시오" never matches the shorter "십시오" rule first.
    private var rules: [(String, String)] {
        switch self {
        case .teen:
            return [("하시기 바랍니다", "해"), ("하겠습니다", "할게"), ("드리겠습니다", "줄게"), ("하십시오", "해"),
                    ("겠습니다", "겠어"), ("했습니다", "했어"), ("있습니다", "있어"), ("없습니다", "없어"),
                    ("남았습니다", "남았어"), ("도착합니다", "도착이야"), ("드립니다", "줄게"),
                    ("합니다", "해"), ("입니다", "야"), ("됩니다", "돼"), ("갑니다", "가"), ("옵니다", "와"),
                    ("습니다", "어"), ("하세요", "해"), ("세요", "해"), ("어요", "어"), ("에요", "야"), ("예요", "야")]
        case .twenties:
            return [("하시기 바랍니다", "하세요"), ("하겠습니다", "할게요"), ("드리겠습니다", "드릴게요"), ("하십시오", "하세요"),
                    ("겠습니다", "겠어요"), ("했습니다", "했어요"), ("있습니다", "있어요"), ("없습니다", "없어요"),
                    ("남았습니다", "남았어요"), ("드립니다", "드릴게요"),
                    ("합니다", "해요"), ("입니다", "예요"), ("됩니다", "돼요"), ("갑니다", "가요"), ("습니다", "어요")]
        case .thirties:
            return [("할게요", "하겠습니다"), ("드릴게요", "드리겠습니다"), ("남았어요", "남았습니다"), ("남았어", "남았습니다"),
                    ("있어요", "있습니다"), ("없어요", "없습니다"), ("돼요", "됩니다"), ("해줘", "하세요"),
                    ("해요", "합니다"), ("이야", "입니다"), ("에요", "입니다"), ("예요", "입니다")]
        }
    }

    /// Korean copula agreement: "좌회전" + "이야", but "퍼센트" + "야". A syllable carries a final
    /// consonant when (code − 0xAC00) % 28 != 0, and only the copula endings need the extra 이.
    static func agreeing(_ ending: String, after stem: String) -> String {
        guard ending == "야" || ending == "예요" else { return ending }
        guard let last = stem.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return ending }
        let hasFinalConsonant = (last.value - 0xAC00) % 28 != 0
        guard hasFinalConsonant else { return ending }
        return ending == "야" ? "이야" : "이에요"
    }

    /// Exclamation for the teen voice; the others keep the punctuation the source used.
    private var excited: Bool { self == .teen }

    func rewrite(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let parts = text.split(whereSeparator: { ".!?…\n".contains($0) }).map(String.init)
        guard !parts.isEmpty else { return text }
        var out: [String] = []
        for raw in parts {
            var sentence = raw.trimmingCharacters(in: .whitespaces)
            if sentence.isEmpty { continue }
            for (from, to) in rules where sentence.hasSuffix(from) {
                let stem = String(sentence.dropLast(from.count))
                sentence = stem + Self.agreeing(to, after: stem)
                break
            }
            out.append(sentence + (excited ? "!" : "."))
        }
        return out.joined(separator: " ")
    }
}

extension VoiceProfile {
    /// Persona attached to a preset (nil = speak the text exactly as written).
    var tone: CharacterTone? { toneID.flatMap(CharacterTone.init(rawValue:)) }
}
