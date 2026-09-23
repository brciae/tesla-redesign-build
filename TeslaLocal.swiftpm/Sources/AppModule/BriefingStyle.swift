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
        text
    }
    static var selected: Self { Self(rawValue: UserDefaults.standard.string(forKey: "voiceDeliveryStyle") ?? "standard") ?? .standard }
}
