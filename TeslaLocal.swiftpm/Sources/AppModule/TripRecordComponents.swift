import SwiftUI
import Charts

struct TripRecordSummaryCard: View {
    let metrics: TripRecordMetrics
    var startName = "출발 위치"
    var endName = "도착 위치"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let start = metrics.start { Text(start, format: .dateTime.year().month().day().weekday()).font(.headline) }
            endpoint(startName, metrics.start, metrics.startSOC, .secondary)
            Image(systemName: "arrow.down").foregroundStyle(.red).padding(.leading, 4)
            endpoint(endName, metrics.end, metrics.endSOC, .red)
            Divider()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("거리", "ruler", metrics.distanceKm, "km", 2)
                metric("시간", "clock", metrics.minutes, "분", 0)
                metric("소비 · 추정", "bolt.fill", metrics.energyKWh, "kWh", 2)
                metric("전비 · 추정", "leaf", metrics.efficiency, "km/kWh", 1)
            }
            if metrics.partial { Label("일부 구간 미확인 · 완전한 기록과 비교 시 주의", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func endpoint(_ name: String, _ at: Date?, _ soc: Double?, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mappin.circle.fill").foregroundStyle(color)
            Text(name).font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(at?.formatted(date: .omitted, time: .shortened) ?? "시각 미확인")
                Text(soc.map { String(format: "%.0f%%", $0) } ?? "잔량 미확인")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ symbol: String, _ value: Double?, _ unit: String, _ digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.flatMap { $0.isFinite ? String(format: "%.*f", digits, $0) : nil } ?? "—").font(.title2.bold()).monospacedDigit()
                Text(unit).font(.caption)
            }.lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TripComparisonScreen: View {
    let current: TripRecordMetrics
    let candidates: [TripRecordMetrics]
    @State private var selected = ""
    private var available: [TripRecordMetrics] { Array(candidates.filter { $0.id != current.id }.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }.prefix(100)) }
    private var comparison: TripRecordMetrics? { available.first { $0.id == selected } ?? available.first { current.sameEndpoints(as: $0) == true } ?? available.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TripRecordSummaryCard(metrics: current, startName: "이번 주행 출발", endName: "이번 주행 도착")
                if let other = comparison {
                    Picker("비교할 주행", selection: $selected) {
                        ForEach(available) { item in Text((item.start?.formatted(date: .abbreviated, time: .shortened) ?? "시각 미확인") + String(format: " · %.1f km", item.distanceKm ?? 0)).tag(item.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("trip.compare.selection")
                    Text(current.sameEndpoints(as: other) == true ? "출발·도착 위치가 각각 500m 이내인 기록 · 실제 경로는 다를 수 있음" : current.sameEndpoints(as: other) == false ? "출발·도착 위치가 다른 주행 · 효율 차이를 같은 경로의 효과로 해석하지 않음" : "위치 기록 부족 · 같은 경로 여부 미확인")
                        .font(.caption).foregroundStyle(.secondary)
                    if let a = current.minutes, let b = other.minutes { Text(String(format: "소요 시간 %+.0f분", a - b)).font(.headline).accessibilityIdentifier("trip.compare.time") }
                    if let change = current.efficiencyChange(from: other) { Text(String(format: "전비 %+.1f%%", change)).font(.headline).accessibilityIdentifier("trip.compare.efficiency") }
                    bars("시간", "분", current.minutes, other.minutes)
                    bars("거리", "km", current.distanceKm, other.distanceKm)
                    bars("소비 · 추정", "kWh", current.energyKWh, other.energyKWh)
                    bars("전비 · 추정", "km/kWh", current.efficiency, other.efficiency)
                    Text("기온·교통·속도·공조·경로 차이는 이 수치만으로 원인을 확정할 수 없음. 소비와 전비는 기록된 추정값 기준임.").font(.caption).foregroundStyle(.secondary)
                } else { Text("비교할 다른 주행 기록 없음").foregroundStyle(.secondary) }
            }.padding(16)
        }.navigationTitle("주행 비교").onAppear { if selected.isEmpty { selected = comparison?.id ?? "" } }
    }
    private func bars(_ title: String, _ unit: String, _ a: Double?, _ b: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + " · " + unit).font(.subheadline.bold())
            if let a, let b, a.isFinite, b.isFinite, a >= 0, b >= 0 {
                Chart {
                    BarMark(x: .value("주행", "이번 주행"), y: .value(title, a)).foregroundStyle(Color.red).annotation(position: .top) { Text(String(format: "%.1f", a)).font(.caption2) }
                    BarMark(x: .value("주행", "비교 대상"), y: .value(title, b)).foregroundStyle(Color.blue).annotation(position: .top) { Text(String(format: "%.1f", b)).font(.caption2) }
                }.frame(height: 120)
            } else { Text("양쪽 기록의 값이 있어야 비교 가능함").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TripGuidanceTimeline: View {
    @ObservedObject private var journal = GuidanceJournal.shared
    let vin: String
    let from: Date?
    let to: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("안내 내역 · 재생 시작 기준").font(.headline)
            Text("최근 2,000건·용량 한도 내 보관").font(.caption2).foregroundStyle(.secondary)
            let rows = from.flatMap { start in to.map { journal.rows(vin: vin, from: start, to: $0) } } ?? []
            if rows.isEmpty { Text("저장된 안내 없음 · 이 기능 추가 이후 실제 재생을 시작한 안내부터 기록함").font(.caption).foregroundStyle(.secondary) }
            ForEach(rows) { row in HStack(alignment: .top, spacing: 10) { Text(row.at, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary); Text(row.text).font(.subheadline) } }
        }.padding(16).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}
