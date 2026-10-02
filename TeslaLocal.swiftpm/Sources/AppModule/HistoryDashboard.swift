import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

/// TeslaMate-style history built from records the app already keeps (trips, charges, parking periods)
/// plus the NAS Telemetry samples for curves. No extra Tesla API calls.
@MainActor enum HistoryData {
    static func date(_ row: Object, _ key: String) -> Date? { row.number(key).map { Date(timeIntervalSince1970: $0 / 1000) } }
    static func readings(_ fields: [String], from: Date, to: Date) -> [FleetTelemetryReading] {
        let vin = TeslaFleetClient.shared.selectedVin
        let set = Set(fields)
        return FleetTelemetryStore.shared.records
            .filter { $0.vin == vin && set.contains($0.field) && !$0.invalid && $0.at >= from && $0.at <= to && $0.number != nil }
            .sorted { $0.at < $1.at }
    }
    static func location(near at: Date, within seconds: TimeInterval = 900) -> CLLocationCoordinate2D? {
        let vin = TeslaFleetClient.shared.selectedVin
        let best = FleetTelemetryStore.shared.records
            .filter { $0.vin == vin && $0.field == "Location" && !$0.invalid && abs($0.at.timeIntervalSince(at)) <= seconds }
            .min { abs($0.at.timeIntervalSince(at)) < abs($1.at.timeIntervalSince(at)) }
        guard let best, let p = FleetTelemetryData.coordinate(best) else { return nil }
        return CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
    }
    static func points(_ trip: Object) -> [CLLocationCoordinate2D] {
        (trip["points"] as? [Object] ?? []).compactMap { p in
            guard let lat = p.number("lat"), let lng = p.number("lng") else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
    static func cost(_ c: Object) -> Double? { c.number("totalCost") ?? c.number("cost") ?? c.number("estimatedCost") }
    static func energy(_ c: Object) -> Double? { c.number("chargedKWh") ?? c.number("vehicleReportedKWh") ?? c.number("estimatedStoredKWh") ?? c.number("supplyKWh") ?? c.number("nasSupplyKWh") }
    /// Home charging as the cost engine decided it (saved home point within 35 m, or a place named 집).
    static func isHome(_ c: Object) -> Bool {
        c.string("chargeTypeLabel") == "집 완속" || ["집", "집완속", "자택", "home"].contains(c.string("place").lowercased())
    }
    static func typeName(_ c: Object) -> String {
        switch c.string("chargeType") {
        case "supercharger": return "슈퍼차저"
        case "dc": return "급속"
        case "ac": return isHome(c) ? "집 완속" : "외부 완속"
        default: return "충전"
        }
    }
    /// One definition of parking drain (%/day) for every screen: parkings of 6 h+, rates above 8 %/day
    /// (an unseen drive or charge in between) dropped, median of the rest.
    static func drainRates(_ periods: [Object]) -> [(start: Date, hours: Double, loss: Double, perDay: Double)] {
        periods.compactMap { p in
            guard p.string("classification") == "parking", let s = date(p, "start"), let e = date(p, "end"),
                  let d = p.number("deltaSOC"), d >= 0 else { return nil }
            let h = e.timeIntervalSince(s) / 3600, r = d / h * 24
            return h >= 6 && r <= 8 ? (s, h, d, r) : nil
        }
    }
    static func drainPerDay(_ periods: [Object]) -> Double? {
        let r = drainRates(periods).map(\.perDay).sorted()
        return r.isEmpty ? nil : r[r.count / 2]
    }
    /// One efficiency definition (km/kWh, same as 운행 기록): distance ÷ estimated energy.
    static func kmPerKWh(_ trips: [Object]) -> Double? {
        let rows = trips.filter { ($0.number("estimatedKWh") ?? 0) > 0 }
        let km = rows.compactMap { $0.number("distanceKm") }.reduce(0, +), kwh = rows.compactMap { $0.number("estimatedKWh") }.reduce(0, +)
        return km > 5 && kwh > 0 ? km / kwh : nil
    }
    static func won(_ v: Double?) -> String { v.map { "\(Int($0.rounded()).formatted())원" } ?? "—" }
    static func duration(_ from: Date?, _ to: Date?) -> String {
        guard let from, let to, to > from else { return "—" }
        let m = Int(to.timeIntervalSince(from) / 60)
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }
}

struct ChargeDetailView: View {
    let charge: Object
    private var start: Date? { HistoryData.date(charge, "at") }
    private var end: Date? { HistoryData.date(charge, "end") }
    var body: some View {
        let from = start ?? Date(), to = end ?? from.addingTimeInterval(3600)
        let power = HistoryData.readings(["DCChargingPower", "ACChargingPower", "ChargePower"], from: from, to: to)
        let soc = HistoryData.readings(["Soc", "BatteryLevel"], from: from, to: to)
        let spot = HistoryData.location(near: from)
        List {
            Section {
                row("시작", dateText(charge.number("at")))
                row("소요", HistoryData.duration(start, end))
                row("종류", HistoryData.typeName(charge))
                if let a = charge.number("startSOC"), let b = charge.number("endSOC") { row("배터리", "\(Int(a))% → \(Int(b))% (+\(Int(b - a))%)") }
                if let e = HistoryData.energy(charge) { row("충전량", String(format: "%.2f kWh", e)) }
                row(charge.number("cost") != nil ? "결제 금액" : "예상 금액", HistoryData.won(HistoryData.cost(charge)))
                if let e = HistoryData.energy(charge), let c = HistoryData.cost(charge), e > 0 { row("kWh당", HistoryData.won(c / e)) }
                if let max = power.compactMap(\.number).max() { row("최대 출력", String(format: "%.0f kW", max)) }
                if !charge.string("place").isEmpty { row("장소", charge.string("place")) }
            }
            if power.count > 2 {
                Section("충전 출력 (kW)") {
                    Chart(power, id: \.id) { LineMark(x: .value("시각", $0.at), y: .value("kW", $0.number ?? 0)).foregroundStyle(.orange) }.chartReveal().frame(height: 180)
                }
            }
            if soc.count > 2 {
                Section("배터리 (%)") {
                    Chart(soc, id: \.id) { LineMark(x: .value("시각", $0.at), y: .value("%", $0.number ?? 0)).foregroundStyle(.green) }.chartReveal().chartYScale(domain: 0...104).frame(height: 160)
                }
            }
            if let spot {
                Section("위치") {
                    Map(initialPosition: .region(MKCoordinateRegion(center: spot, latitudinalMeters: 600, longitudinalMeters: 600))) { Marker("충전", systemImage: "bolt.fill", coordinate: spot).tint(.green) }
                        .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            if power.count <= 2 && soc.count <= 2 { Text("이 충전 시간대의 NAS 세부 기록이 없어 요약만 표시합니다.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("충전 상세")
    }
    private func row(_ label: String, _ value: String?) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value ?? "—").multilineTextAlignment(.trailing) }.font(.subheadline)
    }
}

struct TripDetailView: View {
    let trip: Object
    let capacity: Double
    var body: some View {
        let start = HistoryData.date(trip, "start") ?? Date(), end = HistoryData.date(trip, "end") ?? start
        let route = HistoryData.points(trip)
        let speed = HistoryData.readings(["VehicleSpeed"], from: start, to: end)
        let km = trip.number("distanceKm") ?? 0
        // Same estimate as the 운행 기록 cards (engine energyPeriods), so numbers match everywhere.
        let usedKWh: Double? = trip.number("estimatedKWh") ?? { guard let a = trip.number("startSOC"), let b = trip.number("endSOC"), a >= b else { return nil }; return (a - b) / 100 * capacity }()
        List {
            if route.count > 1 {
                Section {
                    Map { MapPolyline(coordinates: route).stroke(.blue, lineWidth: 4)
                        if let f = route.first { Marker("출발", coordinate: f).tint(.green) }
                        if let l = route.last { Marker("도착", coordinate: l).tint(.red) } }
                        .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Section {
                row("출발", dateText(trip.number("start")))
                row("소요", HistoryData.duration(start, end))
                row("거리", String(format: "%.1f km", km))
                if end > start, km > 0 { row("평균 속도", String(format: "%.0f km/h", km / end.timeIntervalSince(start) * 3600)) }
                if let top = speed.compactMap(\.number).max() { row("최고 속도", String(format: "%.0f km/h", top * 1.609344)) }
                if let a = trip.number("startSOC"), let b = trip.number("endSOC") { row("배터리", "\(Int(a))% → \(Int(b))%") }
                if let used = usedKWh { row("소모", String(format: "%.1f kWh (추정)", used)) }
                if let used = usedKWh, used > 0, km > 1 { row("전비", String(format: "%.2f km/kWh", km / used)) }
            }
            if speed.count > 2 {
                Section("속도 (km/h)") {
                    Chart(speed, id: \.id) { AreaMark(x: .value("시각", $0.at), y: .value("km/h", ($0.number ?? 0) * 1.609344)).foregroundStyle(.blue.opacity(0.4)) }.chartReveal().frame(height: 160)
                }
            }
        }.navigationTitle("주행 상세")
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.subheadline)
    }
}

struct ParkingDrainView: View {
    let periods: [Object]
    private struct Drain: Identifiable { let id: Int; let start: Date; let hours: Double; let loss: Double; var perDay: Double { loss / hours * 24 } }
    private var rows: [Drain] {
        HistoryData.drainRates(periods).enumerated().map { Drain(id: $0.offset, start: $0.element.start, hours: $0.element.hours, loss: $0.element.loss) }
            .sorted { $0.start > $1.start }
    }
    var body: some View {
        let list = rows
        let sorted = list.map(\.perDay).sorted(), avg: Double? = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        List {
            Section {
                Text(avg.map { String(format: "하루 %.1f%% 감소 (중앙값)", $0) } ?? "6시간 이상 주차 기록이 아직 없습니다").font(.headline)
                Text("6시간 이상 주차만 사용합니다. 중간에 운행·충전이 끼어 하루 8%를 넘는 기록은 제외합니다.").font(.caption).foregroundStyle(.secondary)
            }
            if list.count > 1 {
                Section("하루 환산 감소 (%)") {
                    Chart(list.prefix(60)) { BarMark(x: .value("날짜", $0.start, unit: .day), y: .value("%/일", $0.perDay)).foregroundStyle($0.perDay < 1 ? Color.green : ($0.perDay < 2 ? .yellow : .red)) }.chartReveal().frame(height: 180)
                }
            }
            Section("주차별") {
                ForEach(list.prefix(100)) { d in
                    HStack {
                        Text(dateText(d.start.timeIntervalSince1970 * 1000)).font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f시간 · -%.0f%% · 하루 %.1f%%", d.hours, d.loss, d.perDay)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("주차 중 방전")
    }
}

struct MonthlyStatsView: View {
    let trips: [Object]
    let charges: [Object]
    private struct Bucket: Identifiable { let id: Date; var km = 0.0; var cost = 0.0; var ac = 0.0; var dc = 0.0 }
    /// Fewer than 3 months of data → weekly bars, so one month is not a single wall-sized block.
    private var weekly: Bool {
        let firsts = (trips.compactMap { HistoryData.date($0, "start") } + charges.compactMap { HistoryData.date($0, "at") })
        guard let first = firsts.min() else { return true }
        return Date().timeIntervalSince(first) < 90 * 86_400
    }
    private var buckets: [Bucket] {
        let cal = Calendar.current, unit: Calendar.Component = weekly ? .weekOfYear : .month
        var map: [Date: Bucket] = [:]
        func key(_ d: Date) -> Date { cal.dateInterval(of: unit, for: d)?.start ?? d }
        for t in trips { if let d = HistoryData.date(t, "start") { let k = key(d); map[k, default: Bucket(id: k)].km += t.number("distanceKm") ?? 0 } }
        for c in charges {
            guard let d = HistoryData.date(c, "at") else { continue }
            let k = key(d), e = HistoryData.energy(c) ?? 0
            map[k, default: Bucket(id: k)].cost += HistoryData.cost(c) ?? 0
            if ["dc", "supercharger"].contains(c.string("chargeType")) { map[k, default: Bucket(id: k)].dc += e } else { map[k, default: Bucket(id: k)].ac += e }
        }
        return Array(map.values.sorted { $0.id < $1.id }.suffix(12))
    }
    var body: some View {
        let list = buckets, unit: Calendar.Component = weekly ? .weekOfYear : .month
        let label = weekly ? "주" : "월"
        ScrollView {
            VStack(spacing: 14) {
                chartCard("\(label)별 주행거리", "km", String(format: "합계 %.0f km", list.map(\.km).reduce(0, +))) {
                    Chart(list) { b in
                        BarMark(x: .value(label, b.id, unit: unit), y: .value("km", b.km), width: .ratio(0.6)).foregroundStyle(Color.blue.gradient).cornerRadius(4)
                    }.chartReveal().chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: weekly ? .dateTime.month(.defaultDigits).day() : .dateTime.month(.abbreviated)) } }
                }
                chartCard("\(label)별 충전량", "kWh", String(format: "완속 %.0f · 급속 %.0f kWh", list.map(\.ac).reduce(0, +), list.map(\.dc).reduce(0, +))) {
                    Chart(list) { b in
                        BarMark(x: .value(label, b.id, unit: unit), y: .value("kWh", b.ac), width: .ratio(0.6)).foregroundStyle(by: .value("종류", "완속"))
                        BarMark(x: .value(label, b.id, unit: unit), y: .value("kWh", b.dc), width: .ratio(0.6)).foregroundStyle(by: .value("종류", "급속"))
                    }.chartReveal().chartForegroundStyleScale(["완속": Color.green, "급속": Color.orange])
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: weekly ? .dateTime.month(.defaultDigits).day() : .dateTime.month(.abbreviated)) } }
                }
                chartCard("\(label)별 충전 비용", "원", "합계 " + HistoryData.won(list.map(\.cost).reduce(0, +))) {
                    Chart(list) { b in
                        BarMark(x: .value(label, b.id, unit: unit), y: .value("원", b.cost), width: .ratio(0.6)).foregroundStyle(Color.pink.gradient).cornerRadius(4)
                    }.chartReveal().chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: weekly ? .dateTime.month(.defaultDigits).day() : .dateTime.month(.abbreviated)) } }
                }
            }.padding(16)
        }.navigationTitle(weekly ? "주별 통계" : "월별 통계")
    }
    private func chartCard<C: View>(_ title: String, _ unit: String, _ caption: String, @ViewBuilder _ chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) { Text(title).font(.subheadline.bold()); Text(unit).font(.caption).foregroundStyle(.secondary); Spacer(); Text(caption).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            chart().frame(height: 150)
        }.padding(12).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct VisitedPlacesView: View {
    let trips: [Object]
    let charges: [Object]
    private struct Place: Identifiable { let id: String; let coordinate: CLLocationCoordinate2D; var visits: Int; var charges: Int }
    private var places: [Place] {
        var map: [String: Place] = [:]
        func add(_ p: CLLocationCoordinate2D, charge: Bool) {
            let key = String(format: "%.3f,%.3f", p.latitude, p.longitude)
            if map[key] == nil { map[key] = Place(id: key, coordinate: p, visits: 0, charges: 0) }
            if charge { map[key]!.charges += 1 } else { map[key]!.visits += 1 }
        }
        // A visit = the car actually stopped there: a complete trip ends at a point, the next trip starts
        // within 300 m of it, and at least 10 minutes pass in between. Pass-through GPS points never count.
        let ordered = trips.filter { !$0.flag("missing") }.sorted { ($0.number("start") ?? 0) < ($1.number("start") ?? 0) }
        for (i, t) in ordered.enumerated() {
            guard let last = HistoryData.points(t).last, let end = t.number("end") else { continue }
            if i + 1 < ordered.count {
                let next = ordered[i + 1]
                guard let first = HistoryData.points(next).first, let start = next.number("start"), start - end >= 600_000,
                      CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude)) < 300 else { continue }
            }
            add(last, charge: false)
        }
        // A charge place needs a car position recorded within 5 minutes of the session start.
        for c in charges { if let d = HistoryData.date(c, "at"), let p = HistoryData.location(near: d, within: 300) { add(p, charge: true) } }
        return map.values.sorted { $0.visits + $0.charges > $1.visits + $1.charges }.prefix(15).map { $0 }
    }
    @State private var names: [String: String] = [:]
    var body: some View {
        let list = places
        List {
            if !list.isEmpty {
                Section {
                    Map { ForEach(list) { p in Marker("\(p.visits + p.charges)", systemImage: p.charges > 0 ? "bolt.fill" : "mappin", coordinate: p.coordinate).tint(p.charges > 0 ? .green : .blue) } }
                        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Section("방문 순위") {
                ForEach(list) { p in
                    HStack {
                        Text(names[p.id] ?? p.id).font(.subheadline).lineLimit(1).minimumScaleFactor(0.5)
                        Spacer()
                        Text("도착 \(p.visits) · 충전 \(p.charges)").font(.caption).foregroundStyle(.secondary)
                    }.task {
                        guard names[p.id] == nil,
                              let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude), preferredLocale: Locale(identifier: "ko_KR")).first else { return }
                        names[p.id] = mark.name ?? mark.thoroughfare ?? p.id
                    }
                }
            }
        }.navigationTitle("자주 가는 장소").overlay { if list.isEmpty { ContentUnavailableView("위치 기록 없음", systemImage: "mappin.slash") } }
    }
}

/// Imports Tesla's account data export (Supercharging history CSV/JSON) as charge records. Duplicates are skipped by the engine.
struct TeslaExportImportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var picking = false
    @State private var result = ""
    var body: some View {
        List {
            Section {
                Text("1. Tesla 계정 → 설정 → 개인정보 → 데이터 요청에서 충전 데이터(Charging Data)를 요청합니다. 슈퍼차저와 집·완속 충전이 모두 들어 있습니다.")
                Text("2. 받은 파일을 선택하면 충전 기록에 합칩니다. 앱이 이미 기록한 같은 충전은 건너뛰고, 예전에 가져온 자료는 새로 바꿉니다.")
            }.font(.subheadline)
            Button { picking = true } label: { Label("파일 선택", systemImage: "doc.badge.plus") }
            if !result.isEmpty { Text(result).font(.subheadline).foregroundStyle(.secondary) }
        }
        .navigationTitle("Tesla 자료 가져오기")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { outcome in
            guard case .success(let url) = outcome else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { result = "파일을 읽지 못했습니다."; return }
            let rows = TeslaExportParser.rows(text)
            var added = 0, skipped = 0
            // Re-import replaces what an earlier import added, so fixes to the importer apply to old rows too.
            for old in model.state.rows("charges") where old.string("note") == "Tesla 요청 자료" { model.mutate("deleteCharge", ["id": old.selfID]) }
            for row in rows {
                let at = row.number("at") ?? 0, end = row.number("end") ?? at + 600_000
                // Same session already recorded by BLE/NAS/Fleet: its start or its (late) collection time falls in this session.
                if model.state.rows("charges").contains(where: { c in
                    guard c.string("note") != "Tesla 요청 자료" else { return false }
                    let s = c.number("at") ?? 0, e = c.number("end") ?? s
                    return (s < end + 7_200_000 && e > at - 600_000)
                }) { skipped += 1; continue }
                let before = model.state.rows("charges").count
                model.mutate("addCharge", row)
                if model.state.rows("charges").count > before { added += 1 } else { skipped += 1 }
            }
            model.errorMessage = nil
            result = rows.isEmpty ? "충전 이력 형식을 찾지 못했습니다. 슈퍼차저 이력 파일인지 확인해 주세요." : "충전 \(added)건 추가 · 중복·오류 \(skipped)건 제외"
        }
    }
}

enum TeslaExportParser {
    static func rows(_ text: String) -> [Object] {
        let body = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))
        if body.hasPrefix("[") || body.hasPrefix("{"), let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            return flatten(json).compactMap(record)
        }
        let lines = body.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let header = lines.first.map(split) else { return [] }
        return lines.dropFirst().compactMap { line in
            let values = split(line)
            var row: [String: Any] = [:]
            for (i, key) in header.enumerated() where i < values.count { row[key] = values[i] }
            return record(row)
        }
    }
    private static func flatten(_ value: Any) -> [[String: Any]] {
        if let list = value as? [Any] { return list.flatMap(flatten) }
        guard let object = value as? [String: Any] else { return [] }
        let nested = object.values.flatMap { ($0 is [Any] || $0 is [String: Any]) ? flatten($0) : [] }
        return [object] + nested
    }
    private static func split(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() } else if ch == ",", !quoted { out.append(cur); cur = "" } else { cur.append(ch) }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private static func find(_ row: [String: Any], _ words: [String]) -> Any? {
        for (k, v) in row { let key = k.lowercased(); if words.contains(where: { key.contains($0) }) { return v } }
        return nil
    }
    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        guard let s = v as? String else { return nil }
        return Double(s.filter { "0123456789.-".contains($0) })
    }
    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        // Tesla's export labels its times "(UTC)"; without a zone they must not be read as local time.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "MM/dd/yyyy HH:mm", "yyyy.MM.dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt; if let d = f.date(from: s) { return d }
        }
        return nil
    }
    private static func record(_ row: [String: Any]) -> Object? {
        guard let at = date(find(row, ["charge start time", "start time", "chargestartdatetime", "start_time", "starttime", "start date", "date", "시작"])),
              let kwh = number(find(row, ["energy", "kwh", "usage", "충전량"])), kwh > 0.1, kwh < 300 else { return nil }
        var out: Object = ["at": at.timeIntervalSince1970 * 1000, "storedKWh": (kwh * 100).rounded() / 100, "storageVerified": true,
                           "note": "Tesla 요청 자료"]
        // "Europe Supercharger" / "General - AC power" (Tesla Charging Data export).
        let kind = (find(row, ["charger type", "charger_type", "chargertype", "type"]) as? String ?? "Supercharger").lowercased()
        out["chargeType"] = kind.contains("supercharger") ? "supercharger" : (kind.contains("dc") || kind.contains("fast") ? "dc" : "ac")
        if let end = date(find(row, ["charge end time", "end time", "chargestopdatetime", "end_time", "endtime", "stop", "종료"])), end > at { out["end"] = end.timeIntervalSince1970 * 1000 }
        if let cost = number(find(row, ["totalcost", "total_cost", "amount", "cost", "금액"])), cost >= 0 { out["cost"] = cost }
        if let place = find(row, ["sitelocationname", "site_name", "location", "site", "장소"]) as? String, !place.isEmpty {
            out["place"] = place == "Home" ? "집" : place == "Away" ? "외부" : String(place.prefix(120))
        }
        return out
    }
}

/// One home for every record/analysis screen, TeslaMate-style: pick a sub-tab, drill into details.
struct TeslaMateView: View {
    /// Five sections. Stats, places, parking drain, calendar and data import live inside them.
    enum Section: String, CaseIterable, Identifiable {
        case overview = "개요", charges = "충전", trips = "주행", battery = "배터리", usage = "비용·달력"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .charges: return "bolt.car"
            case .trips: return "car.side"
            case .battery: return "battery.75percent"
            case .usage: return "calendar"
            }
        }
    }
    @EnvironmentObject private var model: AppModel
    @AppStorage("teslamate.section") private var raw = Section.overview.rawValue
    @AppStorage("teslamate.usage.calendar") private var showCalendar = false
    @Namespace private var tabGlass
    private var section: Section { Section(rawValue: raw) ?? .overview }
    private var charges: [Object] {
        let priced = model.output.object("charging").rows("rows")
        return (priced.isEmpty ? model.state.rows("charges") : priced).sorted { ($0.number("at") ?? 0) > ($1.number("at") ?? 0) }
    }
    /// Trips with the engine's energy estimates (the same rows 운행 기록 shows).
    private var trips: [Object] { model.output.object("energyPeriods").object("36500").rows("trips").sorted { ($0.number("start") ?? 0) > ($1.number("start") ?? 0) } }
    private var capacity: Double { model.output.object("energy").number("capacityKWh") ?? 75 }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Section.allCases) { s in
                    Button { withAnimation(.snappy(duration: 0.32)) { raw = s.rawValue } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: s.icon).font(.system(size: 15, weight: .semibold)).symbolEffect(.bounce, value: raw == s.rawValue)
                            Text(s.rawValue).font(.caption2.weight(s == section ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .foregroundStyle(s == section ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background {
                            if s == section { RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.22)).matchedGeometryEffect(id: "tab", in: tabGlass) }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(4).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 13)).padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            content.frame(maxHeight: .infinity)
                .id(raw).transition(.blurReplace.animation(.smooth(duration: 0.3)))
        }
        .sensoryFeedback(.selection, trigger: raw)
        .navigationTitle("TeslaMate").navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
    @ViewBuilder private var content: some View {
        switch section {
        case .overview: overview
        case .charges: ChargeInsightsView(charges: charges).safeAreaInset(edge: .top) {
            links([("Tesla 충전 데이터 가져오기", "square.and.arrow.down", AnyView(TeslaExportImportView())),
                   ("슈퍼차저 이력", "bolt.fill", AnyView(FleetSupplementView(fleet: model.fleet, kind: .chargingHistory)))])
        }
        case .trips: TripInsightsView(trips: trips).safeAreaInset(edge: .top) {
            links([("자주 가는 장소", "mappin.and.ellipse", AnyView(VisitedPlacesView(trips: trips, charges: charges))),
                   ("주별·월별 통계", "chart.bar", AnyView(MonthlyStatsView(trips: trips, charges: charges)))])
        }
        case .battery: BatteryView().safeAreaInset(edge: .top) {
            // Parking location/notes live in 운행 › 위치·주차; only the battery-related drain view is here.
            links([("주차 중 방전", "moon.zzz", AnyView(ParkingDrainView(periods: model.state.rows("parkingPeriods")))),
                   ("충전 단가", "wonsign.circle", AnyView(ChargeRateSettingsView()))])
        }
        case .usage:
            VStack(spacing: 0) {
                Picker("보기", selection: $showCalendar) { Text("소비·비용").tag(false); Text("에너지 달력").tag(true) }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 6)
                if showCalendar { EnergyCalendarView() } else { DrivingInsightsView() }
            }
        }
    }
    private func links(_ items: [(String, String, AnyView)]) -> some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                NavigationLink { items[i].2 } label: {
                    Label(items[i].0, systemImage: items[i].1).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 16).padding(.vertical, 6).background(.bar)
    }
    private var overview: some View {
        TeslaMateOverview(trips: trips, charges: charges, parking: model.state.rows("parkingPeriods"), capacity: capacity) { raw = $0.rawValue }
    }
}

/// Visual dashboard: animated KPIs, 30-day activity, charge mix, efficiency trend, parking drain gauge.
struct TeslaMateOverview: View {
    let trips: [Object]
    let charges: [Object]
    let parking: [Object]
    let capacity: Double
    let open: (TeslaMateView.Section) -> Void
    @State private var shown = false
    @Namespace private var zoom
    private struct Day: Identifiable { let id: Date; var km = 0.0; var kwh = 0.0 }
    private struct Slice: Identifiable { let id: String; let kwh: Double; let color: Color }
    private struct Point: Identifiable { let id: Int; let at: Date; let whPerKm: Double }
    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date() }
    private var monthTrips: [Object] { trips.filter { (HistoryData.date($0, "start") ?? .distantPast) >= monthStart } }
    private var monthCharges: [Object] { charges.filter { (HistoryData.date($0, "at") ?? .distantPast) >= monthStart } }
    private var days: [Day] {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        var map: [Date: Day] = [:]
        for i in 0..<30 { if let d = cal.date(byAdding: .day, value: -i, to: today) { map[d] = Day(id: d) } }
        for t in trips { if let d = HistoryData.date(t, "start"), map[cal.startOfDay(for: d)] != nil { map[cal.startOfDay(for: d)]!.km += t.number("distanceKm") ?? 0 } }
        for c in charges { if let d = HistoryData.date(c, "at"), map[cal.startOfDay(for: d)] != nil { map[cal.startOfDay(for: d)]!.kwh += HistoryData.energy(c) ?? 0 } }
        return map.values.sorted { $0.id < $1.id }
    }
    private var mix: [Slice] {
        var home = 0.0, ac = 0.0, dc = 0.0, sc = 0.0
        for c in monthCharges {
            let e = HistoryData.energy(c) ?? 0
            switch c.string("chargeType") {
            case "supercharger": sc += e
            case "dc": dc += e
            default: if HistoryData.isHome(c) { home += e } else { ac += e }
            }
        }
        return [Slice(id: "집", kwh: home, color: .blue), Slice(id: "외부 완속", kwh: ac, color: .green), Slice(id: "급속", kwh: dc, color: .orange), Slice(id: "슈퍼차저", kwh: sc, color: .red)].filter { $0.kwh > 0 }
    }
    private var efficiency: [Point] {
        trips.prefix(40).enumerated().compactMap { i, t in
            guard let e = t.number("estimatedKmPerKWh"), (1.5...15).contains(e), (t.number("distanceKm") ?? 0) >= 2, let d = HistoryData.date(t, "start") else { return nil }
            return Point(id: i, at: d, whPerKm: e)
        }
    }
    private var drainPerDay: Double? { HistoryData.drainPerDay(parking) }
    var body: some View {
        let t = monthTrips, c = monthCharges
        let km = t.compactMap { $0.number("distanceKm") }.reduce(0, +)
        let kwh = c.compactMap(HistoryData.energy).reduce(0, +)
        let cost = c.compactMap(HistoryData.cost).reduce(0, +)
        let wh = HistoryData.kmPerKWh(t)
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    kpi("주행", shown ? km : 0, "%.0f", "km", .blue, .trips)
                    kpi("충전", shown ? kwh : 0, "%.0f", "kWh", .green, .charges)
                    kpi("비용", shown ? cost / 10000 : 0, "%.1f", "만원", .pink, .usage)
                }
                card("최근 30일", .trips) {
                    // Separate axes: km and kWh never share one scale.
                    HStack { legend(.blue, "주행 km"); Spacer(); Text(String(format: "%.0f km", days.map(\.km).reduce(0, +))).font(.caption).monospacedDigit().foregroundStyle(.secondary) }.font(.caption2)
                    Chart(days) { d in
                        BarMark(x: .value("날짜", d.id, unit: .day), y: .value("km", shown ? d.km : 0), width: .ratio(0.7)).foregroundStyle(Color.blue.gradient).cornerRadius(2)
                    }.chartReveal().frame(height: 90).chartXAxis(.hidden).chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                    HStack { legend(.green, "충전 kWh"); Spacer(); Text(String(format: "%.0f kWh", days.map(\.kwh).reduce(0, +))).font(.caption).monospacedDigit().foregroundStyle(.secondary) }.font(.caption2)
                    Chart(days) { d in
                        BarMark(x: .value("날짜", d.id, unit: .day), y: .value("kWh", shown ? d.kwh : 0), width: .ratio(0.7)).foregroundStyle(Color.green.gradient).cornerRadius(2)
                    }.chartReveal().frame(height: 60).chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
                }
                HStack(spacing: 10) {
                    card("이번 달 충전 구성", .charges) {
                        if mix.isEmpty { Text("충전 없음").font(.caption).foregroundStyle(.secondary).frame(height: 120) }
                        else {
                            Chart(mix) { s in
                                SectorMark(angle: .value("kWh", shown ? s.kwh : 0.001), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(s.color).cornerRadius(3)
                            }.chartReveal().frame(height: 120).overlay { VStack(spacing: 0) { Text(String(format: "%.0f", kwh)).font(.headline).monospacedDigit(); Text("kWh").font(.caption2).foregroundStyle(.secondary) } }
                            HStack(spacing: 8) { ForEach(mix) { legend($0.color, $0.id) } }.font(.caption2)
                        }
                    }
                    card("주차 중 방전", .battery) {
                        let v = drainPerDay ?? 0, color: Color = v < 1 ? .green : (v < 2 ? .yellow : .red)
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                            Circle().trim(from: 0, to: shown ? min(v / 3, 1) : 0).stroke(color.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text(drainPerDay.map { String(format: "%.1f", $0) } ?? "—").font(.title2.bold()).monospacedDigit()
                                Text("%/일").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.frame(width: 110, height: 110).frame(maxWidth: .infinity)
                        Text(drainPerDay == nil ? "6시간 이상 주차 기록 필요" : "주차 중 하루 감소 (중앙값)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                card("전비 추이 (km/kWh)", .trips) {
                    if efficiency.count < 2 { Text("주행 기록이 더 쌓이면 표시됩니다").font(.caption).foregroundStyle(.secondary).frame(height: 120) }
                    else {
                        let avg = efficiency.map(\.whPerKm).reduce(0, +) / Double(efficiency.count)
                        Chart {
                            ForEach(efficiency) { p in
                                LineMark(x: .value("시각", p.at), y: .value("km/kWh", shown ? p.whPerKm : avg)).interpolationMethod(.catmullRom).foregroundStyle(.teal)
                                PointMark(x: .value("시각", p.at), y: .value("km/kWh", shown ? p.whPerKm : avg)).foregroundStyle(.teal).symbolSize(18)
                            }
                            RuleMark(y: .value("평균", avg)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) { Text(String(format: "평균 %.2f", avg)).font(.caption2).foregroundStyle(.secondary) }
                        }.chartReveal().frame(height: 140)
                        if let wh { Text(String(format: "이번 달 %.2f km/kWh · 운행 %d회 · 충전 %d회", wh, t.count, c.count)).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 10) {
                    shortcut("주별 통계", "chart.bar") { MonthlyStatsView(trips: trips, charges: charges) }
                    shortcut("자주 가는 곳", "mappin.and.ellipse") { VisitedPlacesView(trips: trips, charges: charges) }
                    shortcut("Tesla 자료", "square.and.arrow.down") { TeslaExportImportView() }
                }
            }.padding(16)
        }
        .onAppear { withAnimation(.spring(duration: 0.9)) { shown = true } }
        .onDisappear { shown = false }
    }
    private func kpi(_ title: String, _ value: Double, _ format: String, _ unit: String, _ color: Color, _ target: TeslaMateView.Section) -> some View {
        Button { open(target) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: format, value)).font(.title2.bold()).monospacedDigit().contentTransition(.numericText(value: value))
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                Capsule().fill(color.gradient).frame(height: 4)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    private func card<C: View>(_ title: String, _ target: TeslaMateView.Section, @ViewBuilder _ content: () -> C) -> some View {
        Button { open(target) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(title).font(.subheadline.bold()); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                content()
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).cardScrollEffect()
    }
    private func shortcut<D: View>(_ title: String, _ icon: String, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink { destination().zoomDestination(title, in: zoom) } label: {
            VStack(spacing: 6) { Image(systemName: icon).font(.title3); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity, minHeight: 64).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .zoomSource(title, in: zoom)
        }.buttonStyle(.plain)
    }
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(text).foregroundStyle(.secondary) }
    }
}
