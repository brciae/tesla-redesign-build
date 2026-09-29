import SwiftUI
import MapKit

struct FleetSupplementView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var fleet: TeslaFleetClient
    let kind: FleetSupplement
    var samplePublicSites: [NearbyChargingSite] = []
    @State private var result: FleetSupplementResult?
    @State private var error = ""
    @State private var busy = false
    @State private var search = ""
    @State private var selectedSite: String?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var destination: SavedNavigationPlace?
    @State private var requestID = UUID()
    @State private var category = "전체"
    @AppStorage("charging.public.region") private var region = ""
    @State private var publicSites: [NearbyChargingSite] = []
    @State private var showSetup = false
    /// Region resolved from the car position; used when no region was chosen by hand ("" = automatic).
    @State private var autoRegion = ""
    @State private var centeredOnOrigin = false
    @State private var locator = CLLocationManager()
    private var effectiveRegion: String { region.isEmpty ? autoRegion : region }
    private var origin: CLLocation? {
        let location = homePresentation(model, model.link).object("location")
        guard location.flag("hasCoordinates"), let lat = location.number("latitude"), let lon = location.number("longitude"),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }
    private var visibleSites: [NearbyChargingSite] {
        let filtered = sites.filter { $0.matches(category) }
        guard let origin else { return Array(filtered.prefix(300)) }
        return Array(filtered.sorted { a, b in
            origin.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude)) < origin.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }.prefix(300))
    }
    private var sites: [NearbyChargingSite] {
        let tesla = result.flatMap { $0.vin == fleet.selectedVin ? NearbyChargingSite.parse($0.payload) : nil } ?? []
        let publicOnly = (publicSites + samplePublicSites).filter { site in
            !tesla.contains { existing in
                site.providerID == "TE" && existing.category == site.category && CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: CLLocation(latitude: site.latitude, longitude: site.longitude)) < 60
            }
        }
        return tesla + publicOnly
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
        .task(id: fleet.selectedVin + "|" + effectiveRegion) { await refresh() }
        .task(id: origin.map { "\(Int($0.coordinate.latitude * 100)),\(Int($0.coordinate.longitude * 100))" } ?? "") {
            guard kind == .nearbyCharging, let origin, let code = await PublicChargingRegions.code(near: origin) else { return }
            if autoRegion != code { autoRegion = code }
        }
        .task(id: effectiveRegion) {
            guard kind == .nearbyCharging else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                if PublicChargingKey.read() != nil, !effectiveRegion.isEmpty, !model.demo {
                    let requestedRegion = effectiveRegion
                    do {
                        let values = try await PublicChargingAPI.shared.sites(region: requestedRegion)
                        guard !Task.isCancelled, requestedRegion == effectiveRegion else { return }
                        publicSites = values
                        self.error = ""
                    } catch {
                        if !Task.isCancelled {
                            publicSites = publicSites.map { site in
                                var stale = site; stale.available = nil; stale.categoryAvailability = [:]; stale.chargingDetail = "상태 갱신 대기"
                                return stale
                            }
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        }
        .onChange(of: fleet.selectedVin) { _, _ in selectedSite = nil; destination = nil }
        .sheet(item: $destination) { place in DestinationSearchView(navigation: model.navigation, initialPlace: place).environmentObject(model) }
        .sheet(isPresented: $showSetup, onDismiss: { Task { await refresh() } }) { PublicChargingSetupView(region: $region) }
    }
    private var chargingMap: some View {
        Map(position: $mapPosition, selection: $selectedSite) {
            UserAnnotation()
            if let origin { Marker("내 차", systemImage: "car.fill", coordinate: origin.coordinate).tint(.red) }
            ForEach(visibleSites) { site in
                stationAnnotation(site)
            }
        }.accessibilityIdentifier("charging.map")
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
        .onAppear { if locator.authorizationStatus == .notDetermined { locator.requestWhenInUseAuthorization() } }
        .safeAreaInset(edge: .top) { mapFilters }
        .onChange(of: category) { _, _ in selectedSite = visibleSites.first?.id }
        .onChange(of: visibleSites.map(\.id)) { _, _ in fitChargingMap() }
        .safeAreaInset(edge: .bottom) { stationPanel }
    }
    private func fitChargingMap() {
        // Show the area around the car in detail instead of zooming out to every charger in the region.
        if let origin {
            guard !centeredOnOrigin else { return }
            centeredOnOrigin = true
            mapPosition = .region(MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 6000, longitudinalMeters: 6000))
            return
        }
        let values = visibleSites
        guard let first = values.first else { return }
        let latitudes = values.map(\.latitude), longitudes = values.map(\.longitude)
        let lowLat = latitudes.min() ?? first.latitude, highLat = latitudes.max() ?? first.latitude
        let lowLon = longitudes.min() ?? first.longitude, highLon = longitudes.max() ?? first.longitude
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lowLat + highLat) / 2, longitude: (lowLon + highLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.025, (highLat - lowLat) * 1.3), longitudeDelta: max(0.025, (highLon - lowLon) * 1.3))))
    }
    private func stationAnnotation(_ site: NearbyChargingSite) -> some MapContent {
        Annotation(site.name, coordinate: CLLocationCoordinate2D(latitude: site.latitude, longitude: site.longitude)) {
            ChargingStationMapPin(site: site, filter: category, selected: site.id == selectedSite) {
                selectedSite = site.id
            }
        }.annotationTitles(site.id == selectedSite ? .automatic : .hidden).tag(site.id)
    }
    private var mapFilters: some View {
            VStack(spacing: 8) {
            HStack {
                Button { showSetup = true } label: { Label(PublicChargingKey.read() == nil ? "공공 충전소 연결" : (region.isEmpty ? "자동 · " + (PublicChargingRegions.names[autoRegion] ?? "차량 위치 확인 중") : PublicChargingRegions.names[region] ?? region), systemImage: "slider.horizontal.3") }.font(.caption)
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.disabled(busy).accessibilityLabel("충전소 새로고침")
            }
            Picker("충전소 종류", selection: $category) {
                ForEach(["전체", "슈퍼차저", "급속", "완속"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            }.padding(10).background(.regularMaterial)
    }
    private var stationPanel: some View {
            VStack(alignment: .leading, spacing: 10) {
                if busy { ProgressView("충전소 조회 중…") }
                if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.orange) }
                if let site = visibleSites.first(where: { $0.id == selectedSite }) {
                    Text(site.name).font(.headline)
                    if !site.address.isEmpty, site.address != site.name { Text(site.address).font(.caption).foregroundStyle(.secondary) }
                    if let origin { Text(String(format: "차량 위치에서 %.1f km", origin.distance(from: CLLocation(latitude: site.latitude, longitude: site.longitude)) / 1000)).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Text(site.category)
                        if let power = site.powerKW { Text("\(Int(power)) kW") }
                        Spacer()
                        if let available = site.available, let total = site.total { Text("\(available)/\(total)대 가능") }
                        else if let available = site.available { Text("\(available)대 가능") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if !site.chargingDetail.isEmpty { Text(site.chargingDetail).font(.caption) }
                    if !site.restriction.isEmpty { Text(site.restriction).font(.caption).foregroundStyle(.orange) }
                    if let at = site.fetchedAt { Text("조회 " + at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                    Button { destination = SavedNavigationPlace(name: site.name, address: site.address, latitude: site.latitude, longitude: site.longitude) } label: {
                        Label("목적지로 선택", systemImage: "location.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                    }.buttonStyle(.borderedProminent).tint(.blue).foregroundStyle(.white).accessibilityIdentifier("charging.destination")
                } else if !busy && error.isEmpty {
                    Text(visibleSites.isEmpty ? "이 종류의 충전소가 조회되지 않았습니다" : "지도에서 충전소를 선택하세요").font(.subheadline)
                }
                Text(publicSites.isEmpty && samplePublicSites.isEmpty ? "Tesla 제공 · 빈자리 수는 조회 시점 기준" : "한국환경공단·Tesla · 충전 가능 대수 기준").font(.caption2).foregroundStyle(.secondary)
                if sites.filter({ $0.matches(category) }).count > 300 { Text("가까운 충전소 최대 300곳 표시").font(.caption2).foregroundStyle(.secondary) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }
    @MainActor private func refresh() async {
        let request = UUID(); requestID = request
        busy = true; error = ""; result = nil; publicSites = []
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
        if kind == .nearbyCharging, PublicChargingKey.read() != nil, !effectiveRegion.isEmpty, !model.demo {
            do {
                let values = try await PublicChargingAPI.shared.sites(region: effectiveRegion)
                guard requestID == request, !Task.isCancelled else { return }
                publicSites = values
                if selectedSite == nil { selectedSite = visibleSites.first?.id }
            } catch { if requestID == request && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct ChargingStationMapPin: View {
    let site: NearbyChargingSite
    let filter: String
    let selected: Bool
    let action: () -> Void
    private var symbol: String {
        if site.category == "슈퍼차저" { return "bolt.circle.fill" }
        return site.category.contains("급속") ? "bolt.fill" : "powerplug.fill"
    }
    private var color: Color {
        if site.category == "슈퍼차저" { return .red }
        return site.category.contains("급속") ? .orange : .green
    }
    private var accessibilityText: String {
        let base = site.name + " · " + site.category
        guard let count = site.availability(for: filter) else { return base }
        return base + " · " + count + "대 가능"
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: selected ? 12 : 9, weight: .bold))
                if let count = site.availability(for: filter) {
                    Text(count).font(.system(size: selected ? 12 : 10, weight: .bold)).monospacedDigit()
                }
            }
            .padding(.horizontal, selected ? 7 : 4).padding(.vertical, selected ? 5 : 3)
            .dynamicTypeSize(.large)
            .foregroundStyle(Color.white)
            .background(color, in: Capsule())
            .overlay(Capsule().stroke(Color.white, lineWidth: selected ? 2 : 1))
            .shadow(radius: selected ? 3 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}
