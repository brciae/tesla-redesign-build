import SwiftUI
import MapKit

struct FleetSupplementView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var fleet: TeslaFleetClient
    let kind: FleetSupplement
    @State private var result: FleetSupplementResult?
    @State private var error = ""
    @State private var busy = false
    @State private var search = ""
    @State private var selectedSite: String?
    @State private var destination: SavedNavigationPlace?
    @State private var requestID = UUID()
    @State private var category = "전체"
    private var visibleSites: [NearbyChargingSite] { sites.filter { category == "전체" || $0.category == category } }
    private var sites: [NearbyChargingSite] {
        guard let result, result.vin == fleet.selectedVin else { return [] }
        return NearbyChargingSite.parse(result.payload)
    }
    private var cards: [FleetSupplementCard] {
        guard result?.vin == fleet.selectedVin else { return [] }
        return (result?.cards ?? []).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.rows.contains { $0.value.localizedCaseInsensitiveContains(search) } }
    }
    var body: some View {
        Group {
        if kind == .nearbyCharging { chargingMap }
        else {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DisclosureGroup("상세 안내") { Caption(kind.note) }
                Button(busy ? "조회 중…" : "자료 조회") { Task { await refresh() } }.disabled(busy)
                if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.orange) }
                if let result, result.vin == fleet.selectedVin {
                    Text("조회 " + result.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.muted)
                    TextField("항목 또는 내용 검색", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(cards) { card in
                        InfoCard {
                            Label(card.title, systemImage: kind == .nearbyCharging || kind == .chargingHistory ? "bolt.fill" : "car.fill").font(.headline)
                            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top) {
                                    Text(row.label).foregroundStyle(Theme.muted)
                                    Spacer(minLength: 16)
                                    Text(row.value).multilineTextAlignment(.trailing)
                                }.font(.subheadline)
                            }
                        }
                    }
                    if cards.isEmpty { ContentUnavailableView("표시할 기록 없음", systemImage: "tray", description: Text("조회한 범위에 표시할 기록이 없습니다.")) }
                } else { Caption("필요할 때 직접 조회합니다. 계정 권한이나 차량 지원에 따라 제공 범위가 다를 수 있습니다.") }
            }.padding(16)
        }
        }
        }.background(Theme.bg).navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .task(id: fleet.selectedVin) { await refresh() }
        .onChange(of: fleet.selectedVin) { _, _ in selectedSite = nil; destination = nil }
        .sheet(item: $destination) { place in DestinationSearchView(navigation: model.navigation, initialPlace: place).environmentObject(model) }
    }
    private var chargingMap: some View {
        Map(selection: $selectedSite) {
            ForEach(visibleSites) { site in
                Annotation(site.name, coordinate: CLLocationCoordinate2D(latitude: site.latitude, longitude: site.longitude)) {
                    Button { selectedSite = site.id } label: {
                        HStack(spacing: 4) {
                            Image(systemName: site.category == "슈퍼차저" ? "bolt.circle.fill" : site.category == "급속" ? "bolt.fill" : "powerplug.fill")
                            if let count = site.availability { Text(count).font(.caption.bold()).monospacedDigit() }
                        }.padding(9).foregroundStyle(.white)
                            .background(site.category == "슈퍼차저" ? Color.red : site.category == "급속" ? Color.orange : Color.green, in: Capsule())
                            .overlay(Capsule().stroke(.white, lineWidth: site.id == selectedSite ? 3 : 0))
                    }.buttonStyle(.plain).accessibilityLabel(site.name + " · " + site.category + (site.availability.map { " · " + $0 + "대 가능" } ?? ""))
                }.tag(site.id)
            }
        }.accessibilityIdentifier("charging.map")
        .safeAreaInset(edge: .top) {
            Picker("충전소 종류", selection: $category) {
                ForEach(["전체", "슈퍼차저", "급속", "완속"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(10).background(.regularMaterial)
        }
        .onChange(of: category) { _, _ in selectedSite = visibleSites.first?.id }
        .overlay(alignment: .topTrailing) {
            Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise").padding(14).background(.regularMaterial, in: Circle()) }
                .disabled(busy).accessibilityLabel("충전소 새로고침").padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if busy { ProgressView("충전소 조회 중…") }
                if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.orange) }
                if let site = visibleSites.first(where: { $0.id == selectedSite }) {
                    Text(site.name).font(.headline)
                    HStack {
                        Text(site.category)
                        if let power = site.powerKW { Text("\(Int(power)) kW") }
                        Spacer()
                        if let available = site.available, let total = site.total { Text("\(available)/\(total)대 가능") }
                        else if let available = site.available { Text("\(available)대 가능") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    Button("목적지로 선택") { destination = SavedNavigationPlace(name: site.name, address: "", latitude: site.latitude, longitude: site.longitude) }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).accessibilityIdentifier("charging.destination")
                } else if !busy && error.isEmpty {
                    Text(visibleSites.isEmpty ? "이 종류의 충전소가 조회되지 않았습니다" : "지도에서 충전소를 선택하세요").font(.subheadline)
                }
                Text("Tesla 제공 · 빈자리 수는 조회 시점 기준").font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        }
    }
    @MainActor private func refresh() async {
        let request = UUID(); requestID = request
        busy = true; error = ""; result = nil
        defer { if requestID == request { busy = false } }
        do {
            let requestedVIN = fleet.selectedVin
            let received = try await fleet.readSupplement(kind)
            guard !Task.isCancelled, requestID == request, requestedVIN == fleet.selectedVin, received.vin == requestedVIN else { return }
            result = received
            if !sites.contains(where: { $0.id == selectedSite }) { selectedSite = sites.first?.id }
        }
        catch is CancellationError { }
        catch { if requestID == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
