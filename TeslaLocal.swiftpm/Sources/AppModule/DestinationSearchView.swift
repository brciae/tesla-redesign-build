import SwiftUI
import MapKit

@MainActor
final class DestinationSuggestions: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var items: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    static let korea = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.3, longitude: 127.8), span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.korea
        completer.resultTypes = [.address, .pointOfInterest]
    }
    func update(_ query: String) {
        items = []
        completer.queryFragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self, weak completer] in self?.items = completer?.results ?? [] }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.items = [] }
    }
}

struct SavedNavigationPlace: Codable, Identifiable {
    var id: String { name + String(latitude) + String(longitude) }
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct DestinationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @ObservedObject var navigation: EmbeddedNavigation
    var canEdit: Bool = true
    var initialPlace: SavedNavigationPlace?
    @State private var query = ""
    @State private var results: [SavedNavigationPlace] = []
    @State private var recent: [SavedNavigationPlace] = []
    @State private var home: SavedNavigationPlace?
    @State private var work: SavedNavigationPlace?
    @State private var selected: SavedNavigationPlace?
    @State private var route: MKRoute?
    @State private var busy = false
    @State private var sending = false
    @State private var sendFailed = false
    @State private var message = ""
    @State private var task: Task<Void, Never>?
    @StateObject private var suggestions = DestinationSuggestions()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        TextField("장소·주소 검색", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { search() }.accessibilityIdentifier("destination.query")
                        Button("검색") { search() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    }
                    if busy { ProgressView() }
                    if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.orange) }
                    if let selected {
                        preview(selected)
                    } else {
                        HStack {
                            shortcut("집", icon: "house.fill", place: home)
                            shortcut("회사", icon: "building.2.fill", place: work)
                        }
                        if !results.isEmpty { Text("검색 결과").font(.headline); places(results) }
                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty {
                            ForEach(Array(suggestions.items.prefix(8).enumerated()), id: \.offset) { _, item in
                                Button { search(completion: item) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(item.title, systemImage: "mappin.circle.fill")
                                        Text(item.subtitle).font(.caption).foregroundStyle(Theme.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                }.buttonStyle(.plain)
                            }
                        }
                        if !recent.isEmpty { Text("최근 목적지").font(.headline); places(recent) }
                        if home == nil || work == nil { Caption("장소를 검색한 뒤 집·회사로 저장하면 한 번에 경로를 열 수 있습니다.") }
                    }
                }.padding(16).disabled(sending)
            }.background(Theme.bg).navigationTitle("목적지 검색").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(sending) } }
                .overlay { if sending { ProgressView("차량에 목적지 전송 중…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
                .interactiveDismissDisabled(sending)
        }.onAppear {
            recent = load([SavedNavigationPlace].self, "navigation.recent") ?? []
            home = load(SavedNavigationPlace.self, "navigation.home")
            work = load(SavedNavigationPlace.self, "navigation.work")
            if let initialPlace { select(initialPlace) }
        }.onDisappear { task?.cancel(); suggestions.update("") }
            .onChange(of: query) { _, value in
                task?.cancel(); busy = false; results = []; selected = nil; route = nil; message = ""
                suggestions.update(value)
            }
            .onChange(of: canEdit) { _, allowed in if !allowed { task?.cancel(); dismiss() } }
    }
    private func shortcut(_ name: String, icon: String, place: SavedNavigationPlace?) -> some View {
        Button { if let place { select(place) } else { message = "장소를 검색한 뒤 \(name)(으)로 저장해 주세요." } } label: {
            Label(name, systemImage: icon).frame(maxWidth: .infinity, minHeight: 48).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func places(_ values: [SavedNavigationPlace]) -> some View {
        ForEach(values) { place in
            Button { select(place) } label: {
                VStack(alignment: .leading, spacing: 4) { Text(place.name).font(.headline); Text(place.address).font(.caption).foregroundStyle(Theme.muted) }
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
    }
    private func preview(_ place: SavedNavigationPlace) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("검색 결과로 돌아가기") { selected = nil; route = nil; task?.cancel(); busy = false }
            Text(place.name).font(.title2.bold())
            if !place.address.isEmpty, place.address != place.name { Text(place.address).font(.subheadline).foregroundStyle(Theme.muted) }
            if let route {
                Map(initialPosition: .rect(route.polyline.boundingMapRect)) {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
                    Marker(place.name, coordinate: place.coordinate)
                }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                Text(String(format: "약 %.0f분 · %.1f km", route.expectedTravelTime / 60, route.distance / 1000)).font(.headline)
                Caption("미리보기는 Apple 지도 기준이며 실제 카카오 안내 경로와 다를 수 있습니다.")
            }
            Button { sendAndNavigate(place) } label: { Text("차량으로 전송하고 안내 시작").font(.headline).frame(maxWidth: .infinity, minHeight: 36) }
                .buttonStyle(.borderedProminent).tint(.blue).foregroundStyle(.white).accessibilityIdentifier("destination.send")
            Button(sendFailed ? "앱에서만 안내 시작" : "앱 길안내만 사용") { startGuidance(place, vehicleAccepted: false) }
                .accessibilityIdentifier("destination.appOnly")
            HStack {
                Button("집으로 저장") { home = place; save(place, "navigation.home"); message = "집 위치를 저장했습니다." }
                Spacer()
                Button("회사로 저장") { work = place; save(place, "navigation.work"); message = "회사 위치를 저장했습니다." }
            }
        }
    }
    private func startGuidance(_ place: SavedNavigationPlace, vehicleAccepted: Bool) {
        do {
            guard canEdit else { return }
            try navigation.startManualDestination(name: place.name, coordinate: place.coordinate, vin: model.fleet.selectedVin.isEmpty ? model.settings.string("vin") : model.fleet.selectedVin)
            recent = Array(([place] + recent.filter { $0.id != place.id }).prefix(20)); save(recent, "navigation.recent")
            model.voice.say(vehicleAccepted ? "차량에서 목적지 전송을 승인했습니다. 앱 길안내를 시작합니다." : "앱 길안내를 시작합니다.", category: "voiceControl", manual: true)
            dismiss()
        } catch { message = (vehicleAccepted ? "차량 전송 승인됨 · 앱 안내 시작 실패: " : "") + error.localizedDescription }
    }
    private func sendAndNavigate(_ place: SavedNavigationPlace) {
        guard canEdit, !sending, CLLocationCoordinate2DIsValid(place.coordinate) else { return }
        task?.cancel(); busy = false; sending = true; sendFailed = false; message = ""
        let vin = model.fleet.selectedVin
        task = Task { @MainActor in
            defer { sending = false }
            do {
                guard !model.demo, !vin.isEmpty else { throw FleetCommandPolicy.failure("연결된 차량을 먼저 확인하세요.") }
                let accepted = try await model.fleet.sendCommand(vin: vin, command: "navigation_gps_request",
                    parameters: ["lat": place.latitude, "lon": place.longitude, "order": 1],
                    authorized: { !model.demo && canEdit && model.fleet.selectedVin == vin && !Task.isCancelled })
                guard accepted else { throw FleetCommandPolicy.failure("차량에서 목적지 전송을 승인하지 않았습니다.") }
                guard !Task.isCancelled, canEdit, model.fleet.selectedVin == vin else { return }
                startGuidance(place, vehicleAccepted: true)
            } catch {
                guard !Task.isCancelled else { return }
                sendFailed = true
                message = "차량 전송을 확인하지 못했습니다. " + error.localizedDescription
                model.voice.say("차량 목적지 전송을 확인하지 못했습니다. 앱 길안내만 사용할 수 있습니다.", category: "voiceControl", manual: true)
            }
        }
    }
    private func search(completion: MKLocalSearchCompletion? = nil) {
        task?.cancel(); selected = nil; route = nil; results = []; message = ""; busy = true
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task { @MainActor in
            defer { if !Task.isCancelled { busy = false } }
            do {
                let request = completion.map { MKLocalSearch.Request(completion: $0) } ?? MKLocalSearch.Request()
                if completion == nil { request.naturalLanguageQuery = text }
                request.region = DestinationSuggestions.korea
                request.resultTypes = [.address, .pointOfInterest]
                var items: [MKMapItem] = []
                var searchError: Error?
                do { items = try await MKLocalSearch(request: request).start().mapItems }
                catch { searchError = error }
                guard !Task.isCancelled else { return }
                // Verified institutional address: https://www.iae.re.kr/document/contact
                // Resolve the address through the provider; never invent a destination coordinate.
                let normalized = text.replacingOccurrences(of: " ", with: "").lowercased()
                if completion == nil && ["고등기술연구원", "고등기술연구원연구조합", "iae"].contains(normalized) {
                    let addressRequest = MKLocalSearch.Request()
                    addressRequest.naturalLanguageQuery = "경기도 용인시 처인구 백암면 고안로51번길 175-28"
                    addressRequest.region = DestinationSuggestions.korea
                    addressRequest.resultTypes = .address
                    if let response = try? await MKLocalSearch(request: addressRequest).start() {
                        items += response.mapItems
                    }
                }
                if items.isEmpty && completion == nil {
                    let fallback = MKLocalSearch.Request()
                    fallback.naturalLanguageQuery = text
                    fallback.resultTypes = [.address, .pointOfInterest]
                    do { items = try await MKLocalSearch(request: fallback).start().mapItems }
                    catch { searchError = error }
                }
                guard !Task.isCancelled else { return }
                var seen = Set<String>()
                results = items.map { SavedNavigationPlace(name: $0.name ?? "목적지", address: $0.placemark.title ?? "", latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude) }.filter { seen.insert($0.id).inserted }
                if results.isEmpty {
                    if let searchError { throw searchError }
                    message = "일치하는 장소를 찾지 못했습니다. 추천 장소를 선택하거나 도로명 주소로 검색해 주세요."
                }
            } catch { if !Task.isCancelled { message = "장소 검색을 완료하지 못했습니다. " + error.localizedDescription } }
        }
    }
    private func select(_ place: SavedNavigationPlace) {
        task?.cancel(); selected = place; route = nil; message = ""; busy = true
        task = Task { @MainActor in
            defer { if !Task.isCancelled { busy = false } }
            do {
                let request = MKDirections.Request(); request.source = .forCurrentLocation(); request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); request.transportType = .automobile
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled else { return }; route = response.routes.first
            } catch { if !Task.isCancelled { message = "경로 미리보기를 불러오지 못했습니다. 목적지를 확인한 뒤 길안내를 시작할 수 있습니다." } }
        }
    }
    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) } }
    private func save<T: Encodable>(_ value: T, _ key: String) { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) } }
}


struct NavigationLandingPanel: View {
    let guiding: Bool
    let recent: [SavedNavigationPlace]
    let search: () -> Void
    let dashboard: () -> Void
    let charging: () -> Void
    let naver: () -> Void
    let tmap: () -> Void
    let select: (SavedNavigationPlace) -> Void
    var externalEnabled = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("어디로 갈까요?").font(.title2.bold())
                Button(action: search) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("장소 또는 주소 검색")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.padding(.horizontal, 16).frame(minHeight: 56)
                        .foregroundStyle(.white).background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("landing.search")
                HStack(spacing: 12) {
                    tile(guiding ? "길안내 계속" : "운전 대시보드", icon: "map.fill", action: dashboard)
                    tile("주변 충전소", icon: "bolt.car.fill", action: charging)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("최근 목적지").font(.headline)
                    if recent.isEmpty {
                        Text("검색한 장소에서 길안내를 시작하면 여기에 저장됩니다.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    } else {
                        ForEach(Array(recent.prefix(5))) { place in
                            Button { select(place) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(place.name).font(.subheadline.weight(.semibold))
                                        if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5) }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.frame(minHeight: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("차량 목적지를 외부 지도로").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        tile("네이버 지도", icon: "arrow.up.right.square", action: naver)
                        tile("티맵", icon: "arrow.up.right.square", action: tmap)
                    }.disabled(!externalEnabled)
                }
            }.padding(16)
        }.background(Theme.bg).foregroundStyle(.primary)
    }
    private func tile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
