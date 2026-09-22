import Foundation

/// Explicit ownership: changing a screen title cannot redirect its spoken content.
enum BriefingScope: String, CaseIterable {
    case home = "홈", controls = "차량 제어", climate = "실내 공조"
    case charging = "충전", battery = "배터리 분석", batteryAndCharging = "배터리·충전"
    case driving = "주행 정보", dashboard = "운전 대시보드", navigation = "길안내"
    case trips = "운행 기록", allTrips = "운행 전체 기록", charges = "충전 전체 기록"
    case location = "차량 위치", security = "보안 및 잠금", vehicle3D = "차량 3D"
    case care = "차량 관리", automation = "자동화", schedule = "일정 예약 설정"
    case preferences = "표시·음성 설정", menu = "메뉴 및 설정", daily = "오늘의 브리핑"

    func text(_ details: [String], demo: Bool = false) -> String {
        var seen = Set<String>()
        let content = details.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return ((demo ? ["예시 자료입니다."] : [])
            + (content.isEmpty ? ["요약할 자료가 아직 없습니다."] : content)).joined(separator: " ")
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
