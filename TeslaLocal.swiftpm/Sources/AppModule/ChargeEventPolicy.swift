import Foundation

struct ChargeObservation: Codable {
    let vin: String
    let at: Date
    let state: String
    let soc: Double?
    let limit: Double?
}
struct ChargeEvent {
    let kind: String
    let title: String
    let body: String
}
enum ChargeEventPolicy {
    static func bleState(_ value: Int) -> String? {
        [2: "Disconnected", 3: "NoPower", 4: "Starting", 5: "Charging", 6: "Complete", 7: "Stopped", 8: "Calibrating"][value]
    }
    static func event(previous: ChargeObservation?, current: ChargeObservation, now: Date = Date()) -> ChargeEvent? {
        guard now.timeIntervalSince(current.at) >= -5, now.timeIntervalSince(current.at) <= 120,
              let previous, previous.vin == current.vin, current.at > previous.at,
              current.at.timeIntervalSince(previous.at) <= 300 else { return nil }
        let soc = current.soc.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        let level = soc.map { String(format: "현재 배터리 %.0f%%. ", $0) } ?? ""
        if previous.state != "Charging", current.state == "Charging" {
            return ChargeEvent(kind: "start", title: "충전 시작", body: level + "차량이 충전 중 상태를 보고했습니다.")
        }
        if previous.state == "Charging", current.state == "Complete" {
            return ChargeEvent(kind: "complete", title: "충전 완료", body: level + "차량의 충전이 완료되었습니다.")
        }
        if previous.state == "Charging", ["Stopped", "NoPower", "Disconnected"].contains(current.state) {
            let reason = current.state == "Disconnected" ? "충전 케이블 연결이 해제되었습니다." : current.state == "NoPower" ? "충전 전원 공급을 확인해 주세요." : "충전이 멈췄습니다. 예정된 중지인지 확인해 주세요."
            return ChargeEvent(kind: "stop", title: "충전 상태 변경", body: level + reason)
        }
        if current.state == "Charging", let soc, let before = previous.soc, let limit = current.limit,
           limit.isFinite, (1...100).contains(limit), before < limit, soc >= limit {
            return ChargeEvent(kind: "limit", title: "목표 충전량 도달", body: String(format: "설정한 %.0f%%에 도달했습니다. 현재 배터리 %.0f%%입니다.", limit, soc))
        }
        return nil
    }
}
