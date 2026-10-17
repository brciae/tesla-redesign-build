import SwiftUI

/// Shared by history and the simulator: report the observed event, not an invented start/end.
struct ChargeRecordTiming: View {
    let row: [String: Any]
    private func flag(_ key: String) -> Bool { row[key] as? Bool == true }
    private func date(_ key: String) -> String? {
        guard let value = (row[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value / 1000).formatted(date: .abbreviated, time: .shortened)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            let first = flag("collectedAfterEnd") ? "종료 후 수집" : row["startTimeObserved"] as? Bool == false ? "충전 최초 관측" : "충전 시작"
            Text("\(first): \(date("at") ?? "기록 없음")")
            if flag("active") {
                Text("마지막 수신: \(date("lastAt") ?? date("at") ?? "기록 없음")")
                Text("마지막 수신 당시 충전 중 · 종료 신호 대조 중")
            } else if let end = date("end"), !flag("collectedAfterEnd") {
                Text("\(row["endTimeObserved"] as? Bool == false ? "충전 마지막 관측" : "충전 종료"): \(end)")
            }
            if row["startTimeObserved"] as? Bool == false, !flag("collectedAfterEnd") {
                Text("실제 시작은 최초 관측 이전일 수 있음")
            }
        }.font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("charge.record.timing")
    }
}
