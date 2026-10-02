import Foundation

/// One selected set and one calculation for on-screen charging metrics and speech.
struct ChargePeriodSummary {
    let rows: [[String: Any]]
    init(rows: [[String: Any]], days: Int? = nil, now: Date = Date()) {
        let stamp = now.timeIntervalSince1970 * 1000
        self.rows = rows.filter { row in
            guard row["active"] as? Bool != true, row["chargeExcluded"] as? Bool != true else { return false }
            guard let days else { return true }
            guard let at = Self.number(row, "end") ?? Self.number(row, "at") else { return false }
            return at >= stamp - Double(days) * 86400000 && at <= stamp
        }
    }
    static func number(_ row: [String: Any], _ key: String) -> Double? {
        guard let value = (row[key] as? NSNumber)?.doubleValue, value.isFinite, value >= 0 else { return nil }
        return value
    }
    func total(_ key: String) -> Double? {
        let values = rows.compactMap { Self.number($0, key) }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var cost: Double? {
        let values = rows.compactMap { Self.number($0, "cost") ?? Self.number($0, "estimatedCost") }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var estimated: Bool { rows.contains { $0["chargeEnergyEstimated"] as? Bool == true || (Self.number($0, "cost") == nil && Self.number($0, "estimatedCost") != nil) } }
    var spoken: [String] {
        guard !rows.isEmpty else { return ["선택한 범위의 충전 기록이 없습니다."] }
        var facts = ["충전 \(rows.count)회"]
        if let energy = total("chargedKWh") { facts.append(String(format: "총충전량 %.1f킬로와트시", energy)) }
        if let cost { facts.append("총충전비 \(Int(cost.rounded()))원") }
        return [facts.joined(separator: ", ") + "입니다." + (estimated ? " 추정값이 포함되어 있습니다." : "")]
    }
}

/// Explicit ownership: changing a screen title cannot redirect its spoken content.
enum BriefingScope: String, CaseIterable {
    case home = "홈", controls = "차량 제어", climate = "실내 공조"
    case charging = "충전", battery = "배터리 분석", batteryAndCharging = "배터리·충전"
    case driving = "주행 정보", dashboard = "운전 대시보드", navigation = "길안내"
    case trips = "운행 기록", allTrips = "운행 전체 기록", charges = "충전 전체 기록"
    case location = "차량 위치", security = "보안 및 잠금", vehicle3D = "차량 3D"
    case care = "차량 관리", automation = "자동화", schedule = "일정 예약 설정"
    case preferences = "표시·음성 설정", menu = "메뉴 및 설정", daily = "오늘의 브리핑"

    var supportsSpeech: Bool {
        switch self {
        case .preferences, .menu, .automation, .schedule, .vehicle3D, .controls, .navigation: return false
        default: return true
        }
    }

    func text(_ details: [String], demo: Bool = false) -> String {
        guard supportsSpeech else { return "" }
        var seen = Set<String>()
        let content = details.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return ((demo ? ["예시 자료입니다."] : [])
            + (content.isEmpty ? ["요약할 자료가 아직 없습니다."] : Array(content.prefix(3)))).joined(separator: " ")
    }

    static func tripSummary(_ distances: [Double?]) -> [String] {
        guard !distances.isEmpty else { return ["선택한 범위의 운행 기록이 없습니다."] }
        let known = distances.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        var lines = ["선택한 범위의 운행은 \(distances.count)회입니다."]
        if !known.isEmpty { lines.append(String(format: "거리 확인된 %d회 합계는 %.1f킬로미터입니다.", known.count, known.reduce(0, +))) }
        if known.count != distances.count { lines.append("일부 운행의 거리는 미확인입니다.") }
        return lines
    }
}
