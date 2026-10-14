import SwiftUI
import MapKit

struct HomeChargingSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var chosen: SavedNavigationPlace?
    @State private var radius = 600.0
    @State private var effective = Date()
    @State private var applyPast = true
    @State private var busy = false
    @State private var message = ""
    private var history: [Object] { model.settings.rows("homeRegions") }
    var body: some View {
        Form {
            Section("집 주소·단지 범위") {
                TextField("아파트 단지명 또는 주소", text: $query).accessibilityIdentifier("home.charge.address")
                Button(busy ? "검색 중" : "주소 검색") { search() }.disabled(busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        chosen = SavedNavigationPlace(name: item.name ?? query, address: item.placemark.title ?? query,
                            latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                        results = []
                    } label: { VStack(alignment: .leading) { Text(item.name ?? query); Text(item.placemark.title ?? "").font(.caption) } }
                }
                if let chosen {
                    Text(chosen.name).font(.headline)
                    Text(chosen.address).font(.caption)
                    Map(initialPosition: .region(MKCoordinateRegion(center: chosen.coordinate, latitudinalMeters: radius * 3, longitudinalMeters: radius * 3))) {
                        MapCircle(center: chosen.coordinate, radius: radius).foregroundStyle(.blue.opacity(0.2)).stroke(.blue, lineWidth: 2)
                        Marker("집 중심", coordinate: chosen.coordinate)
                    }.id(chosen.id + String(Int(radius))).frame(height: 210)
                }
                HStack { Text("집 충전 판별 반경"); Spacer(); Text("\(Int(radius)) m").monospacedDigit() }
                Slider(value: $radius, in: 50...2000, step: 50).accessibilityIdentifier("home.charge.radius")
                Text("기본 600m. 지도 원 안에 단지의 모든 충전소가 들어오도록 조절. 급속·슈퍼차저는 집 완속으로 바꾸지 않음.").font(.caption).foregroundStyle(.secondary)
            }
            Section("적용 기간·이사") {
                if history.isEmpty { Toggle("기존 충전 기록에도 적용", isOn: $applyPast) }
                if !history.isEmpty || !applyPast { DatePicker("새 주소 적용 시작", selection: $effective, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                Text("같은 주소의 반경 수정은 기존 분류에 반영. 새 주소는 적용 시작일을 기준으로 이전 집과 구분하며, 원본 충전 기록·결제액을 유지함.").font(.caption).foregroundStyle(.secondary)
                Button("집 주소·범위 저장") { save() }.disabled(chosen == nil).accessibilityIdentifier("home.charge.save")
            }
            if !history.isEmpty {
                Section("집 주소 이력") {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(h.string("name").isEmpty ? "저장한 집" : h.string("name"))
                            Text("반경 \(Int(h.number("radius") ?? 600))m · " + date(h.number("start")) + " ~ " + (h.number("end").map { date($0) } ?? "현재")).font(.caption)
                        }
                    }
                }
            }
            if !message.isEmpty { Section { Text(message).font(.caption) } }
        }.navigationTitle("집 충전 범위·주소")
            .onAppear { load() }
    }
    private func load() {
        radius = model.settings.number("homeRadiusM") ?? history.last?.number("radius") ?? 600
        if let data = UserDefaults.standard.data(forKey: "navigation.home"), let home = try? JSONDecoder().decode(SavedNavigationPlace.self, from: data) {
            chosen = home; query = home.address.isEmpty ? home.name : home.address
        } else {
            let p = model.settings.object("homePoint")
            if let lat = p.number("latitude"), let lon = p.number("longitude") {
                chosen = SavedNavigationPlace(name: "저장한 집", address: "", latitude: lat, longitude: lon)
            }
        }
    }
    private func search() {
        busy = true; message = ""; results = []
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        Task { @MainActor in
            defer { busy = false }
            do { results = try await MKLocalSearch(request: request).start().mapItems; if results.isEmpty { message = "검색 결과 없음. 도로명 주소로 다시 검색 필요." } }
            catch { message = error.localizedDescription }
        }
    }
    private func save() {
        guard let chosen else { return }
        let oldPoint = model.settings.object("homePoint")
        let same = oldPoint.number("latitude") == chosen.latitude && oldPoint.number("longitude") == chosen.longitude
        var regions = history
        if regions.isEmpty, let lat = oldPoint.number("latitude"), let lon = oldPoint.number("longitude"), !same {
            regions = [["latitude": lat, "longitude": lon, "radius": model.settings.number("homeRadiusM") ?? 600, "start": 0.0, "name": "이전 집"]]
        }
        var start = history.isEmpty && applyPast && (same || oldPoint.isEmpty) ? 0 : effective.timeIntervalSince1970 * 1000
        if same, let i = regions.lastIndex(where: { $0.number("end") == nil }) {
            regions[i]["radius"] = radius; regions[i]["name"] = chosen.name; regions[i]["address"] = chosen.address
        } else {
            if let i = regions.lastIndex(where: { $0.number("end") == nil }) {
                start = max(start, (regions[i].number("start") ?? 0) + 1); regions[i]["end"] = start
            }
            regions.append(["latitude": chosen.latitude, "longitude": chosen.longitude, "radius": radius, "start": start, "name": chosen.name, "address": chosen.address])
        }
        let defaults = UserDefaults.standard, previous = defaults.data(forKey: "navigation.home")
        defaults.set(try? JSONEncoder().encode(chosen), forKey: "navigation.home")
        model.errorMessage = nil
        model.mutate("settings", ["homePoint": ["latitude": chosen.latitude, "longitude": chosen.longitude], "homeRadiusM": radius, "homeRegions": regions])
        if let error = model.errorMessage { defaults.set(previous, forKey: "navigation.home"); message = error }
        else { message = "주소·범위 저장됨. 해당 기간의 충전 분류가 다시 계산됨." }
    }
    private func date(_ at: Double?) -> String {
        guard let at, at > 0 else { return "기존 기록부터" }
        return Date(timeIntervalSince1970: at / 1000).formatted(date: .abbreviated, time: .omitted)
    }
}

struct BatteryHealthReferenceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var method = "bmsNominal"
    @State private var capacity = ""
    @State private var replaced = false
    @State private var installed = Date()
    var body: some View {
        Form {
            Section("같은 종류의 기준 용량") {
                Picker("비교 종류", selection: $method) {
                    Text("차량 보고 완충 용량").tag("bmsNominal")
                    Text("충전 기반 참고 용량").tag("chargeUsable")
                }
                TextField("확인한 기준 용량 kWh · 미등록 가능", text: $capacity).keyboardType(.decimalPad)
                Text("팩 총용량·사용 가능 용량·충전기 공급량은 서로 다름. 현재 계산 종류와 같은 기준을 확인한 경우에만 등록. 일반 소비량 계산의 기본 75kWh는 열화율 기준으로 사용하지 않음.").font(.caption).foregroundStyle(.secondary)
            }
            Section("배터리 교체 이력") {
                Toggle("배터리 교체일 이후 자료만 사용", isOn: $replaced)
                if replaced { DatePicker("교체일", selection: $installed, in: ...Date(), displayedComponents: .date) }
                Text("교체일 이전 자료는 보존하고 용량 비교에서 제외. 배터리를 교체했다면 기준 용량도 새 배터리에 맞춰 변경 필요.").font(.caption).foregroundStyle(.secondary)
            }
            Button("비교 기준 저장") {
                let raw = capacity.trimmingCharacters(in: .whitespaces)
                guard raw.isEmpty || (Double(raw).map { $0.isFinite && (20...200).contains($0) } ?? false) else { model.errorMessage = "기준 용량은 20~200kWh 사이 값 필요"; return }
                var values: Object = ["healthReferenceMethod": method, "healthBatteryStartAt": replaced ? installed.timeIntervalSince1970 * 1000 : 0]
                if let value = Double(raw) { values["healthReferenceKWh"] = value } else { values["healthReferenceKWh"] = NSNull() }
                model.mutate("settings", values)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("용량 비교 기준")
            .onAppear {
                method = model.settings.string("healthReferenceMethod").isEmpty ? "bmsNominal" : model.settings.string("healthReferenceMethod")
                capacity = model.settings.number("healthReferenceKWh").map { String($0) } ?? ""
                if let at = model.settings.number("healthBatteryStartAt"), at > 0 { replaced = true; installed = Date(timeIntervalSince1970: at / 1000) }
            }
    }
}
