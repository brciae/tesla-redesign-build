import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

/// TeslaMate-style history built from records the app already keeps (trips, charges, parking periods)
/// plus the NAS Telemetry samples for curves. No extra Tesla API calls.
enum HistoryData {
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
    static func cost(_ c: Object) -> Double? { c.number("cost") ?? c.number("estimatedCost") }
    static func energy(_ c: Object) -> Double? { c.number("chargedKWh") ?? c.number("supplyKWh") ?? c.number("storedKWh") }
    static func typeName(_ c: Object) -> String {
        switch c.string("chargeType") {
        case "supercharger": return "슈퍼차저"
        case "dc": return "급속"
        case "ac": return "완속"
        default: return c.string("source") == "NAS" ? "충전" : c.string("source", "충전")
        }
    }
    static func won(_ v: Double?) -> String { v.map { "\(Int($0.rounded()).formatted())원" } ?? "—" }
    static func duration(_ from: Date?, _ to: Date?) -> String {
        guard let from, let to, to > from else { return "—" }
        let m = Int(to.timeIntervalSince(from) / 60)
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }
}

struct HistoryDashboardView: View {
    @EnvironmentObject private var model: AppModel
    private var charges: [Object] {
        let priced = model.output.object("charging").rows("rows")
        return (priced.isEmpty ? model.state.rows("charges") : priced).sorted { ($0.number("at") ?? 0) > ($1.number("at") ?? 0) }
    }
    private var trips: [Object] { model.state.rows("trips").sorted { ($0.number("start") ?? 0) > ($1.number("start") ?? 0) } }
    private var capacity: Double { model.output.object("energy").number("capacityKWh") ?? 75 }
    var body: some View {
        List {
            Section("이번 달") { monthSummary }
            Section("기록") {
                NavigationLink { ChargeHistoryList(charges: charges) } label: { Label("충전 기록 · \(charges.count)건", systemImage: "bolt.car") }
                NavigationLink { TripHistoryList(trips: trips, capacity: capacity) } label: { Label("주행 기록 · \(trips.count)건", systemImage: "car.side") }
                NavigationLink { ParkingDrainView(periods: model.state.rows("parkingPeriods")) } label: { Label("주차 중 방전", systemImage: "moon.zzz") }
                NavigationLink { MonthlyStatsView(trips: trips, charges: charges) } label: { Label("월별 통계", systemImage: "chart.bar") }
                NavigationLink { VisitedPlacesView(trips: trips, charges: charges) } label: { Label("자주 가는 장소", systemImage: "mappin.and.ellipse") }
            }
            Section { NavigationLink { TeslaExportImportView() } label: { Label("Tesla 요청 자료 가져오기", systemImage: "square.and.arrow.down") } }
                footer: { Text("Tesla 계정 개인정보 메뉴에서 받은 충전 데이터(Charging Data.csv)를 기존 기록과 합칩니다. 비용은 설정한 충전 단가로 추정합니다.") }
        }.navigationTitle("차량 기록")
    }
    private var monthSummary: some View {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let t = trips.filter { (HistoryData.date($0, "start") ?? .distantPast) >= start }
        let c = charges.filter { (HistoryData.date($0, "at") ?? .distantPast) >= start }
        let km = t.compactMap { $0.number("distanceKm") }.reduce(0, +)
        let kwh = c.compactMap(HistoryData.energy).reduce(0, +)
        let cost = c.compactMap(HistoryData.cost).reduce(0, +)
        let used = t.compactMap { r -> Double? in guard let a = r.number("startSOC"), let b = r.number("endSOC"), a > b else { return nil }; return (a - b) / 100 * capacity }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 6) {
            HStack { stat("주행", String(format: "%.0f km", km)); stat("충전", String(format: "%.1f kWh", kwh)); stat("비용", HistoryData.won(cost)) }
            if km > 5, used > 0 { Text(String(format: "평균 효율 %.0f Wh/km · 운행 %d회 · 충전 %d회", used * 1000 / km, t.count, c.count)).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChargeHistoryList: View {
    let charges: [Object]
    var body: some View {
        List(Array(charges.enumerated()), id: \.offset) { _, c in
            NavigationLink { ChargeDetailView(charge: c) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(HistoryData.date(c, "at")?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.subheadline.bold())
                        Spacer(); Text(HistoryData.typeName(c)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if let a = c.number("startSOC"), let b = c.number("endSOC") { Text("\(Int(a))→\(Int(b))%") }
                        if let e = HistoryData.energy(c) { Text(String(format: "%.1f kWh", e)) }
                        Spacer(); Text(HistoryData.won(HistoryData.cost(c)))
                    }.font(.caption).monospacedDigit()
                    if !c.string("place").isEmpty { Text(c.string("place")).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("충전 기록").overlay { if charges.isEmpty { ContentUnavailableView("충전 기록 없음", systemImage: "bolt.slash") } }
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
                row("시작", start?.formatted(date: .abbreviated, time: .shortened))
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
                    Chart(power, id: \.id) { LineMark(x: .value("시각", $0.at), y: .value("kW", $0.number ?? 0)).foregroundStyle(.orange) }.frame(height: 180)
                }
            }
            if soc.count > 2 {
                Section("배터리 (%)") {
                    Chart(soc, id: \.id) { LineMark(x: .value("시각", $0.at), y: .value("%", $0.number ?? 0)).foregroundStyle(.green) }.chartYScale(domain: 0...100).frame(height: 160)
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

struct TripHistoryList: View {
    let trips: [Object]
    let capacity: Double
    var body: some View {
        List(Array(trips.enumerated()), id: \.offset) { _, t in
            NavigationLink { TripDetailView(trip: t, capacity: capacity) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(HistoryData.date(t, "start")?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.subheadline.bold())
                    HStack {
                        Text(String(format: "%.1f km", t.number("distanceKm") ?? 0))
                        Text(HistoryData.duration(HistoryData.date(t, "start"), HistoryData.date(t, "end")))
                        if let a = t.number("startSOC"), let b = t.number("endSOC") { Text("\(Int(a))→\(Int(b))%") }
                    }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }.navigationTitle("주행 기록").overlay { if trips.isEmpty { ContentUnavailableView("주행 기록 없음", systemImage: "car") } }
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
        let usedKWh: Double? = { guard let a = trip.number("startSOC"), let b = trip.number("endSOC"), a >= b else { return nil }; return (a - b) / 100 * capacity }()
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
                row("출발", start.formatted(date: .abbreviated, time: .shortened))
                row("소요", HistoryData.duration(start, end))
                row("거리", String(format: "%.1f km", km))
                if end > start, km > 0 { row("평균 속도", String(format: "%.0f km/h", km / end.timeIntervalSince(start) * 3600)) }
                if let top = speed.compactMap(\.number).max() { row("최고 속도", String(format: "%.0f km/h", top * 1.609344)) }
                if let a = trip.number("startSOC"), let b = trip.number("endSOC") { row("배터리", "\(Int(a))% → \(Int(b))%") }
                if let used = usedKWh { row("소모", String(format: "%.1f kWh (추정)", used)) }
                if let used = usedKWh, km > 1 { row("효율", String(format: "%.0f Wh/km", used * 1000 / km)) }
            }
            if speed.count > 2 {
                Section("속도 (km/h)") {
                    Chart(speed, id: \.id) { AreaMark(x: .value("시각", $0.at), y: .value("km/h", ($0.number ?? 0) * 1.609344)).foregroundStyle(.blue.opacity(0.4)) }.frame(height: 160)
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
        periods.enumerated().compactMap { i, p in
            guard p.string("classification") == "parking", let s = HistoryData.date(p, "start"), let e = HistoryData.date(p, "end"),
                  let d = p.number("deltaSOC"), d >= 0 else { return nil }
            let h = e.timeIntervalSince(s) / 3600
            return h >= 3 ? Drain(id: i, start: s, hours: h, loss: d) : nil
        }.sorted { $0.start > $1.start }
    }
    var body: some View {
        let list = rows
        let avg = list.isEmpty ? nil : list.map(\.loss).reduce(0, +) / list.map(\.hours).reduce(0, +) * 24
        List {
            Section {
                Text(avg.map { String(format: "평균 하루 %.1f%% 감소", $0) } ?? "3시간 이상 주차 기록이 아직 없습니다").font(.headline)
                Text("감시 모드·공조·저온 대기에 따라 달라집니다. 주차 시작과 끝의 배터리 차이로 계산합니다.").font(.caption).foregroundStyle(.secondary)
            }
            if list.count > 1 {
                Section("하루 환산 감소 (%)") {
                    Chart(list.prefix(60)) { BarMark(x: .value("날짜", $0.start, unit: .day), y: .value("%/일", $0.perDay)).foregroundStyle(.purple) }.frame(height: 180)
                }
            }
            Section("주차별") {
                ForEach(list.prefix(100)) { d in
                    HStack {
                        Text(d.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
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
    private struct Month: Identifiable { let id: Date; var km = 0.0; var kwh = 0.0; var cost = 0.0; var ac = 0.0; var dc = 0.0 }
    private var months: [Month] {
        var map: [Date: Month] = [:]
        let cal = Calendar.current
        func key(_ d: Date) -> Date { cal.dateInterval(of: .month, for: d)?.start ?? d }
        for t in trips { if let d = HistoryData.date(t, "start") { let k = key(d); map[k, default: Month(id: k)].km += t.number("distanceKm") ?? 0 } }
        for c in charges {
            guard let d = HistoryData.date(c, "at") else { continue }
            let k = key(d), e = HistoryData.energy(c) ?? 0
            map[k, default: Month(id: k)].kwh += e
            map[k, default: Month(id: k)].cost += HistoryData.cost(c) ?? 0
            if ["dc", "supercharger"].contains(c.string("chargeType")) { map[k, default: Month(id: k)].dc += e } else { map[k, default: Month(id: k)].ac += e }
        }
        return Array(map.values.sorted { $0.id < $1.id }.suffix(12))
    }
    var body: some View {
        let list = months
        List {
            Section("주행거리 (km)") { Chart(list) { BarMark(x: .value("월", $0.id, unit: .month), y: .value("km", $0.km)).foregroundStyle(.blue) }.frame(height: 170) }
            Section("충전량 (kWh) · 완속/급속") {
                Chart(list) { m in
                    BarMark(x: .value("월", m.id, unit: .month), y: .value("kWh", m.ac)).foregroundStyle(by: .value("종류", "완속"))
                    BarMark(x: .value("월", m.id, unit: .month), y: .value("kWh", m.dc)).foregroundStyle(by: .value("종류", "급속"))
                }.chartForegroundStyleScale(["완속": Color.green, "급속": Color.orange]).frame(height: 170)
            }
            Section("충전 비용") { Chart(list) { BarMark(x: .value("월", $0.id, unit: .month), y: .value("원", $0.cost)).foregroundStyle(.pink) }.frame(height: 170) }
            Section("월별 요약") {
                ForEach(Array(list.reversed())) { m in
                    HStack {
                        Text(m.id.formatted(.dateTime.year().month())).font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f km · %.0f kWh · ", m.km, m.kwh) + HistoryData.won(m.cost)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("월별 통계")
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
        for t in trips { if let last = HistoryData.points(t).last { add(last, charge: false) } }
        for c in charges { if let d = HistoryData.date(c, "at"), let p = HistoryData.location(near: d) { add(p, charge: true) } }
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
                        Text(names[p.id] ?? p.id).font(.subheadline).lineLimit(1)
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
                Text("2. 받은 파일(CSV 또는 JSON)을 이 화면에서 선택하면 충전 기록에 합칩니다. 같은 시각·금액 기록은 건너뜁니다.")
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
            for row in rows {
                let at = row.number("at") ?? 0
                if model.state.rows("charges").contains(where: { abs(($0.number("at") ?? 0) - at) < 600_000 }) { skipped += 1; continue }
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
        var out: Object = ["at": at.timeIntervalSince1970 * 1000, "supplyKWh": (kwh * 100).rounded() / 100,
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
