import AVFoundation
import Foundation

/// iOS 기본 한국어 음성(AVSpeechSynthesizer) 프리셋 5종.
/// 타입캐스트 사용 불가·만료·비활성·오프라인 상황에서 즉시 대체 음성 또는 기본 음성으로 동작한다.
struct SystemKoreanVoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let rateMultiplier: Float
    let pitchMultiplier: Float
    let preferredNames: [String]
    let preferMaleOrDeep: Bool

    var storageIdentifier: String { "system:\(id)" }

    static let defaultId = "yuna"
    static let defaultTag = "system:yuna"

    static let all: [SystemKoreanVoice] = [
        SystemKoreanVoice(
            id: "yuna",
            title: "기본 한국어 · 유나 (표준)",
            subtitle: "자연스럽고 균형 잡힌 표준 한국어 안내",
            rateMultiplier: 1.0,
            pitchMultiplier: 1.0,
            preferredNames: ["Yuna", "유나", "Sora", "소라"],
            preferMaleOrDeep: false
        ),
        SystemKoreanVoice(
            id: "clear",
            title: "기본 한국어 · 또렷함",
            subtitle: "주행 소음에서도 또렷하게 들리는 밝고 빠른 톤",
            rateMultiplier: 1.06,
            pitchMultiplier: 1.08,
            preferredNames: ["Sora", "소라", "Jian", "지안", "Yuna", "유나"],
            preferMaleOrDeep: false
        ),
        SystemKoreanVoice(
            id: "calm",
            title: "기본 한국어 · 차분함",
            subtitle: "장거리·야간 주행에 맞춘 부드럽고 안정적인 톤",
            rateMultiplier: 0.94,
            pitchMultiplier: 0.96,
            preferredNames: ["Yuna", "유나", "Sora", "소라", "Flo", "Shelley"],
            preferMaleOrDeep: false
        ),
        SystemKoreanVoice(
            id: "deep",
            title: "기본 한국어 · 중저음",
            subtitle: "낮고 묵직한 저음 위주의 차분한 안내",
            rateMultiplier: 0.96,
            pitchMultiplier: 0.84,
            preferredNames: ["Minsu", "민수", "Hyun", "현", "Eddy", "Reed", "Rocko", "Grandpa"],
            preferMaleOrDeep: true
        ),
        SystemKoreanVoice(
            id: "bright",
            title: "기본 한국어 · 경쾌함",
            subtitle: "시내 주행·짧은 알림에 어울리는 경쾌한 톤",
            rateMultiplier: 1.04,
            pitchMultiplier: 1.14,
            preferredNames: ["Sandy", "Jian", "지안", "Sora", "소라", "Yuna"],
            preferMaleOrDeep: false
        ),
    ]

    static func find(_ identifier: String) -> SystemKoreanVoice? {
        let key: String
        if identifier.hasPrefix("system:") {
            key = String(identifier.dropFirst("system:".count))
        } else {
            key = identifier
        }
        return all.first { $0.id == key }
    }

    static func fallback(from defaults: UserDefaults = .standard) -> SystemKoreanVoice {
        let stored = defaults.string(forKey: "fallbackSystemVoice") ?? defaultTag
        return find(stored) ?? all[0]
    }

    func resolveAVVoice() -> AVSpeechSynthesisVoice? {
        let koreanVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("ko")
        }
        if !koreanVoices.isEmpty {
            let ranked = koreanVoices.sorted { lhs, rhs in
                lhs.quality.rawValue > rhs.quality.rawValue
            }
            for hint in preferredNames {
                let low = hint.lowercased()
                if let match = ranked.first(where: {
                    $0.name.lowercased().contains(low) || $0.identifier.lowercased().contains(low)
                }) {
                    return match
                }
            }
            if preferMaleOrDeep {
                if #available(iOS 17.0, *) {
                    if let male = ranked.first(where: { $0.gender == .male }) {
                        return male
                    }
                }
            }
            if let enhanced = ranked.first(where: { $0.quality == .enhanced || $0.quality == .premium }) {
                return enhanced
            }
            if let first = ranked.first {
                return first
            }
        }
        return AVSpeechSynthesisVoice(language: "ko-KR")
    }

    func utterance(for text: String, baseRate: Float = 1.0, volume: Float = 1.0) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveAVVoice()
        let safeBase = max(0.65, min(1.35, baseRate))
        let targetRate = AVSpeechUtteranceDefaultSpeechRate * safeBase * rateMultiplier
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, targetRate))
        utterance.pitchMultiplier = max(0.5, min(2.0, pitchMultiplier))
        utterance.volume = max(0.1, min(1.0, volume))
        return utterance
    }
}
