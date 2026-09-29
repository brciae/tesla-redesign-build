import Foundation

enum BriefingStyle: String, CaseIterable, Identifiable {
    case standard, calm, brisk, friendly
    var id: String { rawValue }
    var title: String { switch self { case .standard: "기본"; case .calm: "차분하게"; case .brisk: "경쾌하게"; case .friendly: "친근하게" } }
    var rateMultiplier: Float { switch self { case .standard: 1; case .calm: 0.88; case .brisk: 1.10; case .friendly: 0.96 } }
    var description: String { switch self {
        case .standard: "원래 목소리와 기본 템포"
        case .calm: "낮은 속도와 여유 있는 음성 구간 간격"
        case .brisk: "조금 빠른 속도와 짧은 음성 구간 간격"
        case .friendly: "부드러운 템포"
    } }
    var pause: TimeInterval { switch self { case .standard: 0.10; case .calm: 0.30; case .brisk: 0.04; case .friendly: 0.18 } }
    func phrase(_ text: String, category: String) -> String {
        SpeechEnding.natural(text)
    }
    static var selected: Self { Self(rawValue: UserDefaults.standard.string(forKey: "voiceDeliveryStyle") ?? "standard") ?? .standard }
}

/// Screen-style fragments ("충전 중 · 80%", "문 열림", "확인 필요") read aloud as full polite sentences.
/// Navigation cues do not pass through here; they keep Kakao's own wording.
enum SpeechEnding {
    static func natural(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: "·", with: ", ")
        // Split on sentence ends only, never on decimal points ("80.5%").
        let parts = normalized.replacingOccurrences(of: "\n", with: ". ").components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return text }
        return parts.map(sentence).joined(separator: " ")
    }
    private static let done: Set<String> = ["다", "요", "까", "죠", "님", "!", "?", "…"]
    private static let rules: [(String, String)] = [
        ("않음", "않습니다"), ("없음", "없습니다"), ("있음", "있습니다"), ("했음", "했습니다"), ("였음", "였습니다"),
        ("됐음", "됐습니다"), ("되었음", "되었습니다"), ("필요함", "필요합니다"), ("필요", "필요합니다"),
        ("완료됨", "완료되었습니다"), ("완료", "완료되었습니다"), ("종료됨", "종료되었습니다"), ("종료", "종료되었습니다"),
        ("시작됨", "시작되었습니다"), ("시작", "시작했습니다"), ("연결됨", "연결되었습니다"), ("해제됨", "해제되었습니다"),
        ("잠김", "잠겨 있습니다"), ("열림", "열려 있습니다"), ("닫힘", "닫혀 있습니다"), ("꺼짐", "꺼져 있습니다"), ("켜짐", "켜져 있습니다"),
        ("미수신", "아직 받지 못했습니다"), ("확인 중", "확인하고 있습니다"), ("중", "중입니다"),
        ("됨", "됩니다"), ("함", "합니다"), ("임", "입니다"), ("음", "습니다")
    ]
    static func sentence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        guard let last = s.last else { return raw }
        if done.contains(String(last)) || s.hasSuffix("니다") || s.hasSuffix("세요") { return s.hasSuffix("!") || s.hasSuffix("?") ? s : s + "." }
        for (tail, replacement) in rules where s.hasSuffix(tail) {
            // "음" only after a verb stem (있음/없음 handled above); never rewrite nouns like "소음".
            if tail == "음" { break }
            s = String(s.dropLast(tail.count)) + replacement
            return s + "."
        }
        return s + "입니다."
    }
}
