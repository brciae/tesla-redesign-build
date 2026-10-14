import SwiftUI
import Charts

/// Shared by the production battery page and native UI probe; no inferred BMS diagnosis.
struct BatteryOverview: View {
    let index: Object
    let usage: Object
    @Binding var days: Int
    private let accent = Color(red: 0.30, green: 0.86, blue: 0.65)
    private static let batteryChartDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private static let tripRowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("분석 기간", selection: $days) {
                Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90)
            }.pickerStyle(.segmented).accessibilityIdentifier("battery.period")
            Text("주행·배터리 요약").font(.title3.bold())
            HStack { measure("주행 전비", usage.object("energy").number("drivingKmPerKWh"), "km/kWh"); measure("주행 거리", usage.number("distanceKm"), "km") }
            HStack { measure("주행 소비 · 추정", usage.object("energy").number("drivingKWh"), "kWh"); measure("주차 감소 · 관측", usage.number("unexplainedParkingSOC"), "%p") }
            Text("주행 \(Int(usage.number("tripCount") ?? 0))회 · 충전 \(Int(usage.number("chargeCount") ?? 0))회").font(.caption).foregroundStyle(.secondary)
            healthCard
            socChart
            tripChart
            parkingCard
            let trips = usage.rows("tripRows").sorted { ($0.number("at") ?? 0) > ($1.number("at") ?? 0) }
            if !trips.isEmpty {
                Text("트립별 에너지").font(.headline)
                ForEach(Array(trips.prefix(5)), id: \.batteryRowID) { trip in tripEnergyRow(trip) }
                if trips.count > 5 {
                    DisclosureGroup("전체 \(trips.count)회 보기") { ForEach(Array(trips.dropFirst(5)), id: \.batteryRowID) { tripEnergyRow($0) } }
                }
            }
            DisclosureGroup("계산 근거·상세 수치") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(index.string("statusReason")).font(.caption)
                    Text(index.string("note")).font(.caption).foregroundStyle(.secondary)
                    HStack { measure("종합 전비 · 추정", usage.object("energy").number("overallKmPerKWh"), "km/kWh"); measure("전력 관측률", usage.number("powerCoverage"), "%") }
                    HStack { measure("관측 사용 전력", usage.number("observedUsedKWh"), "kWh"); measure("관측 회생", usage.number("observedRecoveredKWh"), "kWh") }
                    Text("전비·kWh는 관측 SOC 또는 구동계 전력으로 계산한 추정값. 공조·감시 모드별 소비를 임의로 배분하지 않음.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("배터리 용량·열화 추정").font(.headline)
                InfoNote("열화율 추정", "차량 보고 완충 용량을 우선 사용. 충전 기반 참고 용량은 저장 에너지와 관측 SOC로 계산하며, 두 종류를 섞지 않음. 신차 기준이 없으면 기록 시작 대비 변화만 표시.")
            }
            HStack {
                measure(index.string("capacityLabel").isEmpty ? "관측 용량" : index.string("capacityLabel"), index.number("capacityMedianKWh") ?? index.number("recentCapacityKWh"), "kWh")
                measure(index.string("comparisonLabel").isEmpty ? "기준 대비 감소" : index.string("comparisonLabel"), index.flag("initial") ? nil : index.number("degradationPercent"), "%")
            }
            Text(index.string("statusReason").isEmpty ? "계산 가능한 충전 \(Int(index.number("sampleCount") ?? 0))회 · 최소 3회 필요" : index.string("statusReason"))
                .font(.caption).foregroundStyle(index.flag("initial") ? Color.orange : accent)
                .accessibilityIdentifier("battery.health.reason")
            Text("계산 가능 \(Int(index.number("sampleCount") ?? 0))회 · 최근 비교 \(Int(index.number("stableSampleCount") ?? 0))회").font(.caption).foregroundStyle(.secondary)
            if let low = index.number("capacityMinKWh"), let high = index.number("capacityMaxKWh") {
                Text(String(format: "최근 관측 범위 %.1f~%.1f kWh", low, high)).font(.caption).foregroundStyle(.secondary)
            }
            if index.flag("provisional") { Text("신차 기준이 없으면 기록 시작 대비 변화만 제공. Tesla 배터리 상태검사와 동일한 진단이 아님.").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
    private var socChart: some View {
        let trend = usage.rows("trend").sorted { ($0.number("at") ?? 0) < ($1.number("at") ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("잔량 변화 · 주행과 충전").font(.headline)
            Text("파랑 = 주행 · 초록 = 충전. 기록이 없는 시간은 연결하지 않음.").font(.caption).foregroundStyle(.secondary)
            if trend.isEmpty { Text("기간 내 잔량 기록 없음").font(.caption) }
            else {
                Chart {
                    ForEach(trend.indices, id: \.self) { i in
                        let p = trend[i]
                        if let at = p.number("at"), let soc = p.number("soc") {
                            LineMark(x: .value("시각", Date(timeIntervalSince1970: at / 1000)), y: .value("잔량 %", soc), series: .value("기록", p.string("segment")))
                                .interpolationMethod(.linear).foregroundStyle(p.string("kind") == "충전" ? Color.green : Color.blue)
                            PointMark(x: .value("시각", Date(timeIntervalSince1970: at / 1000)), y: .value("잔량 %", soc))
                                .foregroundStyle(p.string("kind") == "충전" ? Color.green : Color.blue).symbolSize(22)
                        }
                    }
                }.chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100]) { _ in AxisGridLine(); AxisValueLabel() } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel { if let date = value.as(Date.self) { Text(Self.batteryChartDateFormatter.string(from: date)).font(.caption2) } }
                    } }
                    .frame(height: 180).accessibilityIdentifier("battery.soc.chart")
            }
        }
    }
    private var tripChart: some View {
        let rows = usage.rows("tripRows").filter { ($0.number("km") ?? 0) >= 2 && ($0.number("whPerKm") ?? 0) > 0 }.sorted { ($0.number("at") ?? 0) < ($1.number("at") ?? 0) }.suffix(20)
        return VStack(alignment: .leading, spacing: 10) {
            Text("트립별 소비량 · Wh/km").font(.headline)
            Text("막대 하나 = 한 번의 주행. 낮을수록 적게 소비함 · 최근 20회, 2km 이상.").font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty { Text("전비 계산 가능한 트립 없음").font(.caption) }
            else {
                Chart(Array(rows.enumerated()), id: \.offset) { i, t in
                    BarMark(x: .value("주행 순서", String(i + 1)), y: .value("Wh/km", t.number("whPerKm") ?? 0))
                        .foregroundStyle(t.flag("partial") ? Color.orange : Color.teal).cornerRadius(3)
                }.chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                    .chartXAxisLabel("과거 → 최근 주행 순서").frame(height: 165).accessibilityIdentifier("battery.trip.chart")
            }
        }
    }
    private var parkingCard: some View {
        let parking = usage.object("parking")
        return VStack(alignment: .leading, spacing: 8) {
            Text("주차 중 잔량 감소").font(.headline)
            HStack { measure("확인된 구간", parking.number("count"), "회"); measure("하루 환산 · 중앙값", parking.number("medianPerDay"), "%p/일") }
            Text("P 상태 주차 구간 · 주행거리 변화 200m 이내. 짧은 주차도 기록하며 하루 환산은 정밀도 충분한 구간만 사용.").font(.caption).foregroundStyle(.secondary)
            if let count = parking.number("excludedCount"), count > 0 { Text("확인 보류 \(Int(count))구간 · 상세에서 이유 확인").font(.caption).foregroundStyle(.orange) }
        }.accessibilityIdentifier("battery.parking")
    }
    private func tripEnergyRow(_ t: Object) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(Self.tripRowDateFormatter.string(from: Date(timeIntervalSince1970: (t.number("at") ?? 0) / 1000))); Spacer(); Text(number(t.number("km")) + " km") }
                .font(.subheadline.weight(.medium))
            HStack { Text(number(t.number("startSOC")) + "% → " + number(t.number("endSOC")) + "%"); Spacer(); Text(number(t.number("kwh")) + " kWh · " + number(t.number("whPerKm")) + " Wh/km") }.font(.caption).monospacedDigit()
            Text(t.string("method") + (t.flag("partial") ? " · 부분 기록" : "")).font(.caption2).foregroundStyle(t.flag("partial") ? Color.orange : Color.secondary)
        }.padding(.vertical, 8)
    }

    private func tripRow(_ trip: Object) -> some View {
        HStack(spacing: 8) {
            let start = trip.number("at") ?? 0
            Text(Self.tripRowDateFormatter.string(from: Date(timeIntervalSince1970: start / 1000)))
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Color.primary.opacity(0.85))
            Spacer(minLength: 4)
            Text(number(trip.number("km")) + " km · " + number(trip.number("soc")) + "%p")
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.primary.opacity(0.7))
            if trip.flag("partial") { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).accessibilityLabel("부분 기록") }
        }.font(.caption).monospacedDigit()
    }

    private func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func count(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
    private func pattern(_ icon: String, _ title: String, _ value: Double?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(accent)
            Text(count(value) + "회").font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private func measure(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            (Text(number(value)).font(.system(size: 25, weight: .medium)) + Text(" " + unit).font(.system(size: 12)))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Dictionary where Key == String, Value == Any {
    var batteryRowID: String { string("id") }
}

/// v91: the trend's marks live outside the view body; the type-checker gave up
/// on the single expression once the end-point dot joined it.
private extension BatteryOverview {
    /// v1.33: straight segments (catmull-rom invented peaks between sparse samples), and the line breaks
    /// across gaps > 6 h instead of drawing a fake curve. A dashed 20 % line marks the low level.
    struct SocPoint: Identifiable { let id: String; let seg: Int; let date: Date; let soc: Double }
    static func socSegments(_ trend: [Object]) -> [SocPoint] {
        var out: [SocPoint] = []
        var seg = 0, last: Double?
        for p in trend {
            guard let at = p.number("at"), let raw = p.number("soc") else { continue }
            if let l = last, at - l > 6 * 3600 * 1000 { seg += 1 }
            last = at
            out.append(SocPoint(id: p.batteryRowID + "#\(out.count)", seg: seg, date: Date(timeIntervalSince1970: at / 1000), soc: min(100, max(0, raw))))
        }
        return out
    }
    @ChartContentBuilder func socMarks(_ trend: [Object]) -> some ChartContent {
                        let pts = Self.socSegments(trend)
                        RuleMark(y: .value("경고", 20))
                            .foregroundStyle(Color.red.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) { Text("20%").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7)) }
                        ForEach(pts) { p in
                            AreaMark(x: .value("시각", p.date), yStart: .value("0", 0), yEnd: .value("잔량", p.soc),
                                     series: .value("구간", p.seg))
                                .interpolationMethod(.linear)
                                .foregroundStyle(LinearGradient(colors: [Color.cyan.opacity(0.22), Color.cyan.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("시각", p.date), y: .value("잔량", p.soc), series: .value("구간", p.seg))
                                .interpolationMethod(.linear)
                                .foregroundStyle(Color.cyan)
                                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        }
                        // v90: a filled dot marks where the trace ends, so the
                        // current level reads without chasing the line's tip.
                        if let last = trend.last, let at = last.number("at"), let soc = last.number("soc") {
                            PointMark(
                                x: .value("시각", Date(timeIntervalSince1970: at / 1000)),
                                y: .value("잔량", min(100.0, max(0.0, soc)))
                            )
                            .symbolSize(60)
                            .foregroundStyle(Color.cyan)
                        }
    }
}
