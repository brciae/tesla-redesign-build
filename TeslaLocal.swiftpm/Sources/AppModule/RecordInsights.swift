import SwiftUI
import Charts

/// Deep-dive screens behind the TeslaMate overview cards. Each one answers "why" for the
/// chart it came from instead of repeating the raw rows (those stay one tap away).
enum ChargeKind: String, CaseIterable, Identifiable {
    case home = "집", ac = "외부 완속", dc = "급속", supercharger = "슈퍼차저"
    var id: String { rawValue }
    var color: Color {
        switch self { case .home: return .blue; case .ac: return .green; case .dc: return .orange; case .supercharger: return .red }
    }
    @MainActor static func of(_ c: Object) -> ChargeKind {
        switch c.string("chargeType") {
        case "supercharger": return .supercharger
        case "dc": return .dc
        default: return HistoryData.isHome(c) ? .home : .ac
        }
    }
}

struct ChargeInsightsView: View {
    let charges: [Object]
    private struct KindStat: Identifiable { let id: ChargeKind; var kwh = 0.0; var cost = 0.0; var pricedKWh = 0.0; var count = 0
        var unit: Double? { pricedKWh > 0 ? cost / pricedKWh : nil } }
    private struct MonthBar: Identifiable { let id = UUID(); let month: Date; let kind: ChargeKind; let kwh: Double }
    private struct HourBar: Identifiable { let id: Int; var count = 0 }
    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date() }
    private func at(_ c: Object) -> Date? { HistoryData.date(c, "at") }
    private var thisMonth: [Object] { charges.filter { (at($0) ?? .distantPast) >= monthStart } }
    private func stats(_ list: [Object]) -> [KindStat] {
        var m: [ChargeKind: KindStat] = [:]
        for c in list {
            let k = ChargeKind.of(c), e = HistoryData.energy(c) ?? 0
            var s = m[k] ?? KindStat(id: k)
            s.kwh += e; s.count += 1
            // v1.26: the rate shown is the rate actually applied (user-set tariff or paid unit price),
            // not cost ÷ battery kWh — that ratio inflates by charging loss (210 → 221원).
            if e > 0, let rate = Self.rate(c), rate > 0 { s.cost += rate * e; s.pricedKWh += e }
            m[k] = s
        }
        return ChargeKind.allCases.compactMap { m[$0] }
    }
    static func rate(_ c: Object) -> Double? {
        if let r = c.number("unitPrice") ?? c.number("estimatedUnitPrice"), r.isFinite { return r }
        guard let cost = HistoryData.cost(c), cost > 0 else { return nil }
        let supply = c.number("supplyKWh") ?? c.number("nasSupplyKWh") ?? HistoryData.energy(c)
        guard let supply, supply > 0 else { return nil }
        return cost / supply
    }
    private var months: [MonthBar] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .month, value: -5, to: monthStart) else { return [] }
        var sums: [Date: [ChargeKind: Double]] = [:]
        for c in charges {
            guard let d = at(c), d >= start, let m = cal.dateInterval(of: .month, for: d)?.start else { continue }
            sums[m, default: [:]][ChargeKind.of(c), default: 0] += HistoryData.energy(c) ?? 0
        }
        return sums.keys.sorted().flatMap { m in ChargeKind.allCases.compactMap { k in sums[m]?[k].map { MonthBar(month: m, kind: k, kwh: $0) } } }
    }
    private var monthTotals: [(Date, Double)] {
        var t: [Date: Double] = [:]
        for b in months { t[b.month, default: 0] += b.kwh }
        return t.keys.sorted().map { ($0, t[$0] ?? 0) }
    }
    private var sixMonthDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: -5, to: monthStart) ?? monthStart
        let end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return start...end
    }
    private var hours: [HourBar] {
        var h = (0..<24).map { HourBar(id: $0) }
        for c in charges.prefix(200) { if let d = at(c) { h[Calendar.current.component(.hour, from: d)].count += 1 } }
        return h
    }
    var body: some View {
        let month = stats(thisMonth), all = stats(charges)
        let total = month.reduce(0) { $0 + $1.kwh }
        let homeUnit = all.first { $0.id == .home }?.unit
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                card("이번 달 충전 구성", "\(String(format: "%.0f", total)) kWh · \(thisMonth.count)회") {
                    if month.isEmpty { empty } else {
                        HStack(spacing: 16) {
                            Chart(month) { s in
                                SectorMark(angle: .value("kWh", s.kwh), innerRadius: .ratio(0.62), angularInset: 1.5)
                                    .foregroundStyle(s.id.color).cornerRadius(3)
                            }.frame(width: 120, height: 120)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(month) { s in
                                    HStack(spacing: 6) {
                                        Circle().fill(s.id.color).frame(width: 8, height: 8)
                                        Text(s.id.rawValue).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(total > 0 ? s.kwh / total * 100 : 0))%").font(.subheadline.monospacedDigit())
                                    }
                                    Text("\(String(format: "%.1f", s.kwh)) kWh · \(s.count)회").font(.caption).foregroundStyle(.secondary).padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
                card("kWh당 단가 비교", "비용이 기록된 충전만 계산") {
                    let priced = all.filter { $0.unit != nil }
                    if priced.isEmpty { empty } else {
                        Chart(priced) { s in
                            BarMark(x: .value("원/kWh", s.unit ?? 0), y: .value("방식", s.id.rawValue))
                                .foregroundStyle(s.id.color).cornerRadius(4)
                                .annotation(position: .trailing) { Text("\(Int(s.unit ?? 0))원").font(.caption2.monospacedDigit()) }
                        }.chartXScale(domain: 0...((priced.compactMap(\.unit).max() ?? 1) * 1.25)).frame(height: CGFloat(priced.count) * 38 + 20)
                        if let homeUnit, let away = all.filter({ $0.id != .home && $0.unit != nil }).max(by: { $0.kwh < $1.kwh }), let awayUnit = away.unit, awayUnit > homeUnit {
                            let saving = (awayUnit - homeUnit) * away.kwh
                            insight("\(away.id.rawValue) 충전을 집에서 했다면 약 \(Int(saving).formatted())원 절약 (kWh당 \(Int(awayUnit - homeUnit))원 차이)")
                        }
                    }
                }
                card("최근 6개월 추이", "방식별 충전량 kWh") {
                    if months.isEmpty { empty } else {
                        // v1.33: always six month slots (a single month no longer fills the chart),
                        // thinner stacked bars and the month total printed on top.
                        Chart {
                            ForEach(months) { b in
                                BarMark(x: .value("월", b.month, unit: .month), y: .value("kWh", b.kwh), width: .ratio(0.5))
                                    .foregroundStyle(by: .value("방식", b.kind.rawValue))
                            }
                            ForEach(monthTotals.indices, id: \.self) { i in
                                PointMark(x: .value("월", monthTotals[i].0, unit: .month), y: .value("kWh", monthTotals[i].1))
                                    .opacity(0)
                                    .annotation(position: .top, spacing: 2) { Text("\(Int(monthTotals[i].1))").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary) }
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))") } } } }
                        .chartLegend(position: .top, alignment: .leading)
                        .chartForegroundStyleScale(domain: ChargeKind.allCases.map(\.rawValue), range: ChargeKind.allCases.map(\.color))
                        .chartXScale(domain: sixMonthDomain)
                        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits), centered: true) } }
                        .chartYScale(domain: 0...max(10, (monthTotals.map(\.1).max() ?? 0) * 1.18))
                        .frame(height: 180).chartReveal()
                    }
                }
                card("충전 시작 시간대", "최근 200회 · 막대 높이 = 충전 시작 횟수") {
                    let peak = hours.max { $0.count < $1.count }
                    // v1.33: bars were invisible (ratio width on a numeric axis = 0 pt). Hours are now
                    // categories, so every hour gets a real bar; night hours sit on a shaded band.
                    Chart(hours) { h in
                        BarMark(x: .value("시", String(h.id)), y: .value("횟수", h.count))
                            .foregroundStyle(by: .value("구분", h.id >= 23 || h.id < 9 ? "심야 23~9시" : "주간 9~23시"))
                            .cornerRadius(3)
                            .annotation(position: .top, spacing: 2) { if h.count > 0 { Text("\(h.count)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary) } }
                    }
                    .chartForegroundStyleScale(["심야 23~9시": Color.indigo, "주간 9~23시": Color.teal])
                    .chartLegend(position: .top, alignment: .leading)
                    .chartXAxis { AxisMarks(values: ["0", "3", "6", "9", "12", "15", "18", "21"]) { v in AxisValueLabel { if let s = v.as(String.self) { Text("\(s)시").font(.caption2) } } } }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])); AxisValueLabel() } }
                    .chartYScale(domain: 0...Double(max(2, (hours.map(\.count).max() ?? 0) + 1)))
                    .frame(height: 180)
                    if let peak, peak.count > 0 {
                        let night = hours.filter { $0.id >= 23 || $0.id < 9 }.reduce(0) { $0 + $1.count }
                        let sum = max(1, hours.reduce(0) { $0 + $1.count })
                        insight("가장 많이 충전을 시작한 시간: \(peak.id)시 · 심야(23~9시) 비율 \(night * 100 / sum)%")
                    }
                }
                NavigationLink { ChargeListView(charges: charges) } label: {
                    Label("충전 기록 전체 보기 (\(charges.count)건)", systemImage: "list.bullet").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)
            }.padding(16)
        }
    }
    private var empty: some View { Text("기록 없음").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60) }
    private func insight(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.secondary).symbolRenderingMode(.multicolor)
    }
    private func card<C: View>(_ title: String, _ caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(caption).font(.caption).foregroundStyle(.secondary)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TripInsightsView: View {
    let trips: [Object]
    private struct TripPoint: Identifiable { let id: Int; let at: Date; let km: Double; let speed: Double; let eff: Double; let hour: Int }
    private var points: [TripPoint] {
        trips.enumerated().compactMap { i, t in
            guard let s = HistoryData.date(t, "start"), let e = HistoryData.date(t, "end"), let km = t.number("distanceKm"), km >= 2,
                  let eff = t.number("estimatedKmPerKWh"), (1.5...15).contains(eff) else { return nil }
            let h = e.timeIntervalSince(s) / 3600
            guard h > 0.02 else { return nil }
            return TripPoint(id: i, at: s, km: km, speed: km / h, eff: eff, hour: Calendar.current.component(.hour, from: s))
        }
    }
    private func month(_ offset: Int) -> [TripPoint] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .month, value: offset, to: cal.dateInterval(of: .month, for: Date())?.start ?? Date()),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return points.filter { $0.at >= start && $0.at < end }
    }
    private func avgEff(_ p: [TripPoint]) -> Double? {
        let km = p.reduce(0) { $0 + $1.km }, kwh = p.reduce(0) { $0 + $1.km / $1.eff }
        return kwh > 0 ? km / kwh : nil
    }
    var body: some View {
        let now = month(0), prev = month(-1)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                card("이번 달 vs 지난달", "효율은 주행거리 가중 평균") {
                    HStack {
                        stat("주행", "\(Int(now.reduce(0) { $0 + $1.km })) km", delta(now.reduce(0) { $0 + $1.km }, prev.reduce(0) { $0 + $1.km }, "km"))
                        stat("효율", avgEff(now).map { String(format: "%.1f km/kWh", $0) } ?? "—", {
                            guard let a = avgEff(now), let b = avgEff(prev) else { return nil }; return delta(a, b, "") }())
                        stat("횟수", "\(now.count)회", nil)
                    }
                }
                card("속도와 효율", "점 하나가 주행 1회 · 빠를수록 효율이 떨어지는지 확인") {
                    if points.isEmpty { empty } else {
                        Chart(points.prefix(150)) { p in
                            PointMark(x: .value("평균 속도 km/h", p.speed), y: .value("km/kWh", p.eff))
                                .foregroundStyle(p.eff >= (avgEff(points) ?? 0) ? Color.green : Color.orange).symbolSize(28)
                        }.frame(height: 200).chartXAxisLabel("평균 속도 km/h").chartYAxisLabel("km/kWh")
                        if let slow = avgEff(points.filter { $0.speed < 50 }), let fast = avgEff(points.filter { $0.speed >= 80 }) {
                            insight(String(format: "시속 50 미만 %.1f km/kWh · 80 이상 %.1f km/kWh — 고속에서 %d%% %@", slow, fast, Int(abs(fast - slow) / slow * 100), fast < slow ? "감소" : "증가"))
                        }
                    }
                }
                card("시간대별 효율", "출발 시각 기준") {
                    let byHour = Dictionary(grouping: points, by: { $0.hour / 3 * 3 }).compactMap { h, p in avgEff(p).map { (h, $0) } }.sorted { $0.0 < $1.0 }
                    if byHour.isEmpty { empty } else {
                        Chart(byHour, id: \.0) { item in
                            BarMark(x: .value("시간", "\(item.0)-\(item.0 + 3)시"), y: .value("km/kWh", item.1)).foregroundStyle(Color.teal.gradient).cornerRadius(4)
                        }.frame(height: 150)
                    }
                }
                card("가장 좋았던 / 나빴던 주행", "5 km 이상") {
                    let long = points.filter { $0.km >= 5 }
                    if let best = long.max(by: { $0.eff < $1.eff }), let worst = long.min(by: { $0.eff < $1.eff }) {
                        tripRow("최고", best, .green); tripRow("최저", worst, .orange)
                        if worst.speed > best.speed + 15 { insight("최저 효율 주행은 평균 속도가 \(Int(worst.speed - best.speed)) km/h 더 빨랐음") }
                    } else { empty }
                }
                NavigationLink { TripsView() } label: {
                    Label("주행 기록 전체 보기 (\(trips.count)건)", systemImage: "list.bullet").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)
            }.padding(16)
        }
    }
    private func delta(_ a: Double, _ b: Double, _ unit: String) -> String? {
        guard b > 0 else { return nil }
        let pct = (a - b) / b * 100
        return String(format: "%@%.0f%%", pct >= 0 ? "▲" : "▼", abs(pct))
    }
    private func stat(_ title: String, _ value: String, _ change: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            if let change { Text(change).font(.caption2.bold()).foregroundStyle(change.hasPrefix("▲") ? .green : .orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func tripRow(_ label: String, _ p: TripPoint, _ color: Color) -> some View {
        HStack {
            Text(label).font(.caption.bold()).foregroundStyle(color).frame(width: 34, alignment: .leading)
            Text(p.at.formatted(.dateTime.month().day().hour())).font(.caption)
            Spacer()
            Text(String(format: "%.1f km · %.0f km/h · %.1f km/kWh", p.km, p.speed, p.eff)).font(.caption.monospacedDigit())
        }
    }
    private var empty: some View { Text("기록 없음").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60) }
    private func insight(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.secondary).symbolRenderingMode(.multicolor)
    }
    private func card<C: View>(_ title: String, _ caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(caption).font(.caption).foregroundStyle(.secondary)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
