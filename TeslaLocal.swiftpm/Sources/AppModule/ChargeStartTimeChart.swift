import SwiftUI
import Charts

struct ChargeStartTimeChart: View {
    let charges: [Object]
    private var hours: [Int] {
        var values = Array(repeating: 0, count: 24)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        for c in charges.prefix(200) where !c.flag("collectedAfterEnd") && (c["startTimeObserved"] as? Bool) != false {
            if let at = c.number("at") { values[calendar.component(.hour, from: Date(timeIntervalSince1970: at / 1000))] += 1 }
        }
        return values
    }
    private func band(_ hour: Int) -> String {
        hour < 6 ? "심야 0~6시" : hour < 12 ? "오전 6~12시" : hour < 18 ? "오후 12~18시" : "저녁 18~24시"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("충전 시작 시간대").font(.headline)
            Text("한국 시각 · 최근 200회 · 시작 시각 미확인 제외 · 요금 구간 아님").font(.caption).foregroundStyle(.secondary)
            Chart(0..<24, id: \.self) { hour in
                BarMark(x: .value("시", String(hour)), y: .value("횟수", hours[hour]))
                    .foregroundStyle(by: .value("시간대", band(hour))).cornerRadius(3)
            }.chartForegroundStyleScale(["심야 0~6시": Color.indigo, "오전 6~12시": Color.orange, "오후 12~18시": Color.teal, "저녁 18~24시": Color.purple])
                .chartLegend(position: .top, alignment: .leading)
                .chartXAxis { AxisMarks(values: ["0", "6", "12", "18", "23"]) { v in AxisValueLabel { if let s = v.as(String.self) { Text(s + "시") } } } }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                .chartYScale(domain: 0...max(2, (hours.max() ?? 0) + 1)).frame(height: 180)
            Text("심야 00:00~05:59 · 오전 06:00~11:59 · 오후 12:00~17:59 · 저녁 18:00~23:59")
                .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("charging.time.bands")
        }
    }
}
