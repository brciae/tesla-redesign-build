import SwiftUI
import PhotosUI
import CoreLocation
import Charts
import UniformTypeIdentifiers
import AppIntents
import UserNotifications

struct CareView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @State private var addMaintenance = false
    @State private var addParking = false
    var body: some View {
        PageBody(title: "차량 관리", briefing: .care) {
            SmartParkingCard(link: model.link)
            ParkingSection(addParking: $addParking)
            InfoCard {
                CardTitle(title: "타이어 공기압", systemImage: "tirepressure",
                          info: "차량이 보고한 값이며 개별 센서의 실제 측정 시각은 다를 수 있음. 냉간·열간을 구분하지 않으므로 주행 직후에는 높게 보임. 누설 진단이 아니고, 차량의 공기압 경고를 우선 확인해야 함. 차량 응답 \(dateText(model.groups.object("tire").number("at")))")
                let tire = model.groups.object("tire"), pressures = tire["values"] as? [Any] ?? []
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(0..<4, id: \.self) { index in Metric(title: ["앞 왼쪽", "앞 오른쪽", "뒤 왼쪽", "뒤 오른쪽"][index], value: pressures.indices.contains(index) ? (pressures[index] as? NSNumber)?.doubleValue : nil, digits: 2, suffix: " bar") }
                }
                if !tirePoints.isEmpty {
                    Chart(tirePoints) { point in LineMark(x: .value("측정 시각", point.date), y: .value(units.pressure, units.pressureValue(point.pressure))).foregroundStyle(by: .value("타이어", point.sensor)) }.frame(height: 180)
                }
            }
            InfoCard {
                CardTitle(title: "주차 중 배터리 변화", systemImage: "parkingsign.circle",
                          info: "완료된 운행 다음 이동 시점의 잔량을 비교해 기록함. 양 끝 자료가 모두 있어야 계산되며, 대기 전력·온도·충전 여부가 섞여 있어 손실 진단으로 쓸 수 없음.")
                if model.state.rows("parkingPeriods").isEmpty { Text("기록 준비 중").foregroundStyle(Theme.muted) }
                ForEach(Array(model.state.rows("parkingPeriods").suffix(3).reversed()), id: \.selfID) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOC 차이 \(valueText(p.number("deltaSOC"), digits: 1))%p").font(.subheadline)
                        Caption("\(dateText(p.number("start"))) → \(dateText(p.number("end")))")
                    }
                }
            }
            InfoCard {
                HStack {
                    CardTitle(title: "정비·소모품", systemImage: "wrench.and.screwdriver.fill",
                              info: "직접 입력한 주기를 관리함. 부품 수명·교환 필요 여부를 진단하지 않음.")
                    Button { addMaintenance = true } label: { Image(systemName: "plus.circle").font(.title2) }
                        .buttonStyle(.plain).accessibilityLabel("정비 기록 추가")
                }
                if model.state.rows("maintenance").isEmpty { Text("기록 없음").foregroundStyle(Theme.muted) }
                ForEach(Array(model.state.rows("maintenance").reversed().prefix(6)), id: \.selfID) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.string("title")).font(.subheadline.weight(.semibold))
                        Caption("\(dateText(m.number("at"), time: false)) · \(units.format(m.number("odometerKm"), suffix: " km")) · \(valueText(m.number("cost")))원")
                        if let next = m.number("nextKm") {
                            Text("다음 확인 \(units.format(next, suffix: " km"))").font(.caption)
                                .foregroundStyle((model.groups.object("drive").number("odometerKm") ?? -1) >= next ? .orange : Theme.muted)
                        }
                    }
                }
            }
        }.sheet(isPresented: $addMaintenance) { MaintenanceForm() }.sheet(isPresented: $addParking) { ParkingForm() }
    }
    private var tirePoints: [TirePoint] {
        let resetAt = model.state.rows("maintenance").filter { $0.flag("tireReset") }.compactMap { $0.number("at") }.max() ?? 0
        return model.state.rows("tires").suffix(200).flatMap { row -> [TirePoint] in
            guard let at = row.number("at"), at >= resetAt, let values = row["values"] as? [Any] else { return [] }
            return (0..<min(4, values.count)).compactMap { i in
                guard let p = values[i] as? NSNumber else { return nil }
                return TirePoint(id: row.selfID + String(i), date: Date(timeIntervalSince1970: at/1000), pressure: p.doubleValue, sensor: ["앞 왼쪽", "앞 오른쪽", "뒤 왼쪽", "뒤 오른쪽"][i])
            }
        }
    }
}

/// v31: the newest parking spot is the whole section; older records live behind "이전 기록".
struct ParkingSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var addParking: Bool
    @StateObject private var locator = ParkingLocator()
    var body: some View {
        let notes = model.state.rows("parkingNotes")
        InfoCard {
            CardTitle(title: "주차 위치", systemImage: "parkingsign.circle.fill",
                      info: "차량이 P로 바뀌고 새 좌표를 보내면 자동으로 기록함. 같은 자리에 다시 주차하면 기존 기록을 갱신하므로 목록이 쌓이지 않음. 지하 층수·구역은 차량이 제공하지 않으므로 메모로 직접 입력해야 하고, 좌표는 차량이 마지막으로 보고한 값이라 실내 주차장에서는 오차가 있을 수 있음. 차량 카메라·센트리 영상은 차 안 USB에만 저장되고 블루투스나 테슬라 앱으로 가져올 방법이 없어 사진은 자동 연계가 불가함 — 필요할 때만 직접 촬영해 첨부하면 됨.")
            if let latest = notes.last {
                ParkingDetail(note: latest, locator: locator)
            } else {
                Text("기록 없음 · 주차 후 자동 저장되거나 아래에서 직접 추가").foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Button { model.mutate("captureParking") } label: { Label("현재 위치 저장", systemImage: "mappin.and.ellipse").frame(minHeight: 44) }
                    .buttonStyle(.bordered)
                Button { addParking = true } label: { Label("메모 추가", systemImage: "square.and.pencil").frame(minHeight: 44) }
                    .buttonStyle(.bordered)
            }
            if notes.count > 1 {
                NavigationLink { ParkingHistoryView() } label: {
                    HStack { Text("이전 기록 \(notes.count - 1)건"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        .frame(minHeight: 44)
                }
            }
        }
    }
}

struct ParkingDetail: View {
    @EnvironmentObject private var model: AppModel
    let note: Object
    @ObservedObject var locator: ParkingLocator
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.string("note", "주차 위치")).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let lat = note.number("latitude"), let lng = note.number("longitude") {
                Label(locator.address(lat, lng) ?? "주소 확인 중", systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(dateText(note.number("at"))).font(.subheadline).foregroundStyle(Theme.muted)
                if let visits = note.number("visits"), visits >= 2 {
                    Text("· 같은 자리 \(Int(visits))회").font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            if let url = model.attachmentURL(note.string("photoName")), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let lat = note.number("latitude"), let lng = note.number("longitude") {
                if let distance = locator.distance(to: lat, lng) {
                    Label(distance, systemImage: "figure.walk").font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 10) {
                    if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=\("내 차 위치".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Car")") {
                        Link(destination: url) { Label("지도", systemImage: "map").frame(minHeight: 44) }
                    }
                    if let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=w") {
                        Link(destination: url) { Label("걸어서 안내", systemImage: "figure.walk.circle").frame(minHeight: 44) }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .task { locator.start() }
    }
}

struct ParkingHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var locator = ParkingLocator()
    var body: some View {
        let notes = Array(model.state.rows("parkingNotes").reversed())
        List {
            LocalBriefingControls(title: "주차 기록") {
                guard let latest = notes.first else { return ["저장된 주차 기록이 없습니다."] }
                return ["최근 주차 메모: \(latest.string("note", "메모 없음")).", "\(dateText(latest.number("at"))) 기록입니다."]
            }
            ForEach(notes, id: \.selfID) { note in
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.string("note", "주차 위치")).font(.subheadline.weight(.semibold))
                    Caption(dateText(note.number("at")))
                    if let lat = note.number("latitude"), let lng = note.number("longitude"),
                       let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)") {
                        Link("지도에서 보기", destination: url).font(.caption).frame(minHeight: 36)
                    }
                }
                .swipeActions {
                    Button("삭제", role: .destructive) { model.mutate("deleteParking", ["id": note.selfID]) }
                }
            }
        }
        .navigationTitle("주차 기록").navigationBarTitleDisplayMode(.inline)
    }
}

struct TirePoint: Identifiable { let id: String; let date: Date; let pressure: Double; let sensor: String }
struct MaintenanceForm: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var odo = ""
    @State private var next = ""
    @State private var cost = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var reset = false
    var body: some View {
        NavigationStack {
            Form {
                LocalBriefingControls(title: "정비 기록") { [title.isEmpty ? "정비 항목 미입력." : "\(title).", odo.isEmpty ? "" : "작업 시 주행거리 \(odo)킬로미터.", next.isEmpty ? "" : "다음 확인 \(next)킬로미터.", cost.isEmpty ? "" : "비용 \(cost)원.", "저장 전 입력 내용입니다."] }
                if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
                TextField("정비·소모품 이름", text: $title); DatePicker("작업 날짜", selection: $date, displayedComponents: .date)
                TextField("작업 시 주행거리 km", text: $odo).keyboardType(.decimalPad)
                TextField("다음 확인 주행거리 km", text: $next).keyboardType(.decimalPad)
                TextField("금액 원", text: $cost).keyboardType(.decimalPad)
                TextField("메모", text: $note, axis: .vertical)
                Toggle("타이어 보충·교체·위치 교환", isOn: $reset)
                Text("타이어 작업을 표시하면 이후 압력 추세를 새로운 구간으로 표시함.").font(.caption).foregroundStyle(Theme.muted)
            }.navigationTitle("정비 기록").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") {
                    do { model.errorMessage = nil; model.mutate("maintenance", ["title": title, "at": date.timeIntervalSince1970*1000, "odometerKm": try jsonNumber(odo), "nextKm": try jsonNumber(next), "cost": try jsonNumber(cost), "note": note, "tireReset": reset]); if model.errorMessage == nil { dismiss() } }
                    catch { model.errorMessage = error.localizedDescription }
                } }
            }
        }
    }
}
struct ParkingForm: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var picker: PhotosPickerItem?
    @State private var photo: Data?
    @State private var camera = false
    var body: some View {
        NavigationStack {
            Form {
                LocalBriefingControls(title: "주차 메모") { [note.isEmpty ? "주차 메모 미입력." : note, photo == nil ? "사진 없음." : "사진 첨부됨.", "저장 전 입력 내용입니다."] }
                if model.demo {
                    Text("예시 모드에서는 저장되지 않음 · 홈 화면에서 예시 모드를 종료한 뒤 사용").foregroundStyle(.orange)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
                Section {
                    TextField("예: 지하 3층 C구역 기둥 옆", text: $note, axis: .vertical).lineLimit(1...4)
                } header: { Text("메모") }
                Section {
                    DisclosureGroup("사진 추가 (선택)") {
                        InfoRow("차량 카메라", "센트리·주행 영상은 차 안 USB에만 남고 블루투스로는 받을 수 없어 자동 첨부가 불가함.")
                        Button { camera = true } label: { Label("사진 촬영", systemImage: "camera.fill").frame(minHeight: 44) }
                        PhotosPicker(selection: $picker, matching: .images) { Label("앨범에서 선택", systemImage: "photo").frame(minHeight: 44) }
                        if let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            Button("사진 지우기", role: .destructive) { self.photo = nil; picker = nil }
                        }
                    }
                }
            }.navigationTitle("주차 메모").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.disabled(model.demo || (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil))
                }
            }
            .sheet(isPresented: $camera) { CameraPicker { photo = $0 } }
        }.task(id: picker) { guard let item = picker else { return }; if let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled { photo = data } }
    }
    private func save() {
        do {
            let name = try photo.map { try model.storePhoto($0) } ?? ""
            model.errorMessage = nil
            model.mutate("parking", ["note": note, "photoName": name])
            if model.errorMessage == nil { dismiss() }
        } catch { model.errorMessage = error.localizedDescription }
    }
}

/// Camera capture for a parking photo (the album picker alone cannot take a new photo).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: { dismiss() }) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let dismiss: () -> Void
        init(onImage: @escaping (Data) -> Void, dismiss: @escaping () -> Void) { self.onImage = onImage; self.dismiss = dismiss }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { onImage(data) }
            dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { dismiss() }
    }
}

/// One-shot phone location (walking distance) plus a reverse-geocoded address for the parked spot.
@MainActor
final class ParkingLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private var here: CLLocation?
    @Published private var addresses: [String: String] = [:]
    private let manager = CLLocationManager()
    private var asked = false
    private var lookingUp: Set<String> = []

    /// Address of a stored spot. Resolved once per coordinate and kept for the session.
    func address(_ latitude: Double, _ longitude: Double) -> String? {
        let key = String(format: "%.5f,%.5f", latitude, longitude)
        if let cached = addresses[key] { return cached.isEmpty ? nil : cached }
        guard !lookingUp.contains(key) else { return nil }
        lookingUp.insert(key)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        Task { [weak self] in
            let text = await Self.lookup(location)
            guard let self else { return }
            self.addresses[key] = text ?? ""
            self.lookingUp.remove(key)
        }
        return nil
    }

    private static func lookup(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let place = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR")).first else { return nil }
        // Korean order: 시/도 → 구/군 → 동·도로명 → 번지, skipping parts the geocoder does not return.
        let parts = [place.administrativeArea, place.locality, place.subLocality, place.thoroughfare, place.subThoroughfare]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let text = parts.filter { seen.insert($0).inserted }.joined(separator: " ")
        if !text.isEmpty { return text }
        return place.name
    }

    func start() {
        guard !asked else { return }
        asked = true
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else { return }
        manager.requestLocation()
    }

    /// Straight-line distance; walking route length is longer, so it is labelled as such in the UI.
    func distance(to latitude: Double, _ longitude: Double) -> String? {
        guard let here, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 200 else { return nil }
        let metres = here.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        guard metres.isFinite, metres < 200_000 else { return nil }
        if metres < 1000 { return "직선거리 약 \(Int((metres / 10).rounded() * 10)) m" }
        return String(format: "직선거리 약 %.1f km", metres / 1000)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.here = last }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { manager.requestLocation() }
        }
    }
}

struct AutomationUtilitiesView: View {
    var title = "자동화"
    @EnvironmentObject private var model: AppModel
    @AppStorage("backgroundBLERead") private var backgroundRead = true
    @State private var time = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    @State private var weatherConsent = false
    var body: some View {
        PageBody(title: title, briefing: .schedule, briefingText: { await scheduleSummary() }) {
            InfoCard {
                Text("연속 상태 수집").font(.headline)
                Toggle("앱 전환 후 BLE 조회 유지", isOn: $backgroundRead)
            }
            InfoCard {
                Text("매일 출발 확인 알림").font(.headline)
                DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                HStack { Button("알림 설정") { let parts = Calendar.current.dateComponents([.hour, .minute], from: time); model.scheduleReminder(hour: parts.hour ?? 8, minute: parts.minute ?? 0) }; Spacer(); Button("해제") { model.removeReminder() } }
            }
            InfoCard {
                Text("날씨").font(.headline)
                if !model.state.object("weather").isEmpty { let w = model.state.object("weather"); Text("기온 \(valueText(w.number("temperature_2m"), digits: 1))°C · 강수 \(valueText(w.number("precipitation"), digits: 1)) mm"); Caption("조회 \(dateText(w.number("receivedAt")))") }
                Button("차량 위치로 날씨 조회") { weatherConsent = true }
            }
            InfoCard {
                Text("iPhone 단축어").font(.headline)
                Text("차량 오디오 Bluetooth 연결 → YL Companion 자동 실행").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }.confirmationDialog("차량 위치를 기반으로 날씨를 조회합니다", isPresented: $weatherConsent) { Button("위치 전송 후 조회") { model.fetchWeather() } }
    }
    private func scheduleSummary() async -> String {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let settings = await center.notificationSettings()
        guard let request = requests.first(where: { $0.identifier == "YL.dailyBrief" }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let hour = trigger.dateComponents.hour, let minute = trigger.dateComponents.minute else { return "등록된 출발 확인 알림이 없습니다." }
        let blocked = settings.authorizationStatus == .denied ? " 알림 권한이 꺼져 있어 수신할 수 없습니다." : ""
        return "매일 \(hour)시 \(minute)분 출발 확인 알림이 등록되어 있습니다." + blocked
    }
}
struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var vin = ""
    @State private var name = ""
    @State private var km = ""
    @State private var reserve = ""
    @State private var daily = ""
    @State private var tariff = ""
    @State private var enroll = false
    @State private var importer = false
    @State private var restoreURL: URL?
    @State private var historyImporter = false
    var body: some View {
        Form {
            Section { LocalBriefingControls(title: "연결 상태") { [link.authentic ? "블루투스 인증 완료." : "블루투스 미연결.", "Fleet: \(model.fleet.vehicleDisplayStatus).", "저장된 운행 \(model.state.rows("trips").count)회, 충전 \(model.state.rows("charges").count)회입니다."] } }
            Section("인터넷 차량 기록") {
                NavigationLink { FleetTelemetryView(vin: model.fleet.selectedVin) } label: {
                    Label("NAS 연결·차량 수집 설정", systemImage: "externaldrive.connected.to.line.below")
                }
                Text("블루투스 연결과 별도로 Tesla 가상 키·차량 스트리밍·NAS 기록 수신을 확인합니다.").font(.caption)
            }
            Section {
                NavigationLink("표시 단위·자동 음성 안내", value: Page.preferences)
                TextField("표시 이름", text: $name)
                TextField("VIN 17자리", text: $vin).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.system(.body, design: .monospaced))
            } header: { Text("차량 프로필") }
            Section("충전 계획") {
                TextField("예정 거리 km", text: $km).keyboardType(.decimalPad)
                TextField("여유 잔량 %", text: $reserve).keyboardType(.decimalPad)
                TextField("차량이 안내하는 일상 충전 기준 %", text: $daily).keyboardType(.decimalPad)
                TextField("참고 단가 원/kWh", text: $tariff).keyboardType(.decimalPad)
                Button("프로필·계획 저장") { saveSettings() }
            }
            Section {
                HStack(spacing: 10) {
                    Image(systemName: link.authentic ? "checkmark.shield.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(link.authentic ? Theme.green : Theme.muted)
                    Text(link.status).lineLimit(2)
                    Spacer(minLength: 4)
                    if link.busy { ProgressView() }
                    InfoNote("연결·수집", connectionHelp)
                }
                if !link.deferredGroups.isEmpty { Text("조회 거절로 보류: \(link.deferredGroups.sorted().joined(separator: ", ")) · 약 2분 후 자동 재조회").font(.caption).foregroundStyle(.orange) }
                if !link.timedOutGroups.isEmpty { Text("응답 지연으로 보류: \(link.timedOutGroups.sorted().joined(separator: ", ")) · 약 1분 후 자동 재조회").font(.caption).foregroundStyle(.orange) }
                if !link.closuresSupported { Text("차량이 개폐 조회를 거절함 · 3D는 미확인 표시 유지").font(.caption).foregroundStyle(.orange) }
                Button("차량 연결") { saveSettings(); if model.errorMessage == nil { model.connect() } }.disabled(model.demo || link.busy)
                Button("지금 상태 최신화") { model.refreshVehicle() }.disabled(model.demo || link.controlBusy || link.confirmation != nil)
                DisclosureGroup("키 등록·연결 해제") {
                    Button("조회 전용 키 등록 요청") { enroll = true }.disabled(!link.connected || model.demo)
                    Button("차량 승인 후 조회") { link.authenticate() }.disabled(!link.connected || model.demo)
                    Button("연결 해제") { link.disconnect() }
                }
                DisclosureGroup("진단") {
                    ForEach(["drive", "charge", "climate", "tire", "location", "closures"], id: \.self) { key in
                        LabeledContent(key, value: "\(model.output.object("fresh").flag(key) ? "최근 수신" : "저장값/미수신") · \(dateText(model.groups.object(key).number("at")))").font(.caption)
                    }
                    Text("무관 응답 \(link.ignoredReplies)회 · 시간 초과 \(link.responseTimeouts)회 · 재인증 \(link.recoveryAttempts)/1회").font(.caption)
                    Text(link.diagnostics.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                    Text(model.navigation.lifecycleDiagnostics.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                }
            } header: { Text("연결") }
            Section {
                LabeledContent("저장된 기록", value: "운행 \(model.state.rows("trips").count)회 · 충전 \(model.state.rows("charges").count)회")
                LabeledContent("자동 누적", value: link.authentic && !model.demo ? "수신 중" : "연결 대기")
                DisclosureGroup("내보내기·복원") {
                    Button("사진 포함 JSON 백업") { model.exportBackup() }
                    Button("운행·충전 CSV 내보내기") { model.exportCSV() }
                    Button("백업 파일 선택") { importer = true }.disabled(model.demo)
                    Button("과거 운행·충전 기록 합치기") { historyImporter = true }.disabled(model.demo)
                    Link("Tesla 개인정보 사본 요청 안내", destination: URL(string: "https://www.tesla.com/support/privacy")!)
                }
            } header: {
                HStack { Text("기록"); Spacer(); InfoNote("기록 백업", backupHelp) }
            }
            Section {
                Button(model.demo ? "예시 모드 종료" : "예시 데이터로 화면 둘러보기") { if model.demo { model.exitDemo() } else { model.enterDemo() } }
            } header: {
                HStack { Text("앱 정보"); Spacer(); InfoNote("구현 범위", scopeHelp) }
            } footer: {
                Text("개인용 비공식 앱 · v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
            }
        }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("연결 상태").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .onAppear { populate() }
            .confirmationDialog("차량에 조회용 공개키 등록을 요청함. 차량에서 키카드 승인 필요.", isPresented: $enroll) { Button("조회 키 등록 요청") { link.enrollMonitorKey() } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                switch result { case .success(let url): restoreURL = url; case .failure(let error): model.errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $historyImporter, allowedContentTypes: [.json]) { result in
                switch result { case .success(let url): model.mergeHistory(url); case .failure(let error): model.errorMessage = error.localizedDescription }
            }
            .confirmationDialog("현재 기록을 선택한 백업으로 교체함. 먼저 현재 자료 백업 필요.", isPresented: Binding(get: { restoreURL != nil }, set: { if !$0 { restoreURL = nil } })) { Button("검사 후 복원", role: .destructive) { if let url = restoreURL { model.restore(url) }; restoreURL = nil; populate() } }
    }
    private var connectionHelp: String {
        (link.supportsBackgroundRead ? "백그라운드 BLE로 연결을 유지하지만 실기 지속 수집은 검증 전임. " : "이 기기에서는 백그라운드 BLE 지원이 확인되지 않음. ")
        + "차량이 조회를 거절하거나 응답이 늦으면 해당 항목만 보류하고 1~2분 뒤 자동으로 다시 조회함. 상태 값은 차량이 마지막으로 보고한 값이라 주차 중에는 갱신이 느릴 수 있음."
    }
    private var backupHelp: String {
        var text = "연결 중에만 자동 저장되고, 연결하지 않은 기간의 이력은 복원되지 않음. 백업 JSON에는 위치·개인 기록·사진이 포함되고 차량 키는 제외되므로 재설치 전 별도 보관 필요. 기록 합치기는 동일 차량의 앱 JSON 백업만 지원함."
        if let first = model.state.rows("trips").compactMap({ $0.number("start") }).min() { text += " 가장 이른 저장 운행: \(dateText(first))." }
        return text
    }
    private var scopeHelp: String {
        "개인용 비공식 앱임. BloxBloger 3D 모델 CC BY-NC 4.0 · 정식 Tesla 자산 아님. 유료 Tesla API·서버는 사용하지 않고, AI 규칙 생성은 선택한 외부 앱에서만 실행됨. 자동 휴대폰 키·원격 시동은 지원하지 않음."
    }

    private func populate() { let s = model.settings; vin = s.string("vin"); name = s.string("name"); km = s.number("plannedKm").map { String($0) } ?? ""; reserve = s.number("reserveSOC").map { String($0) } ?? "20"; daily = s.number("dailyLimit").map { String($0) } ?? ""; tariff = s.number("tariff").map { String($0) } ?? "" }
    private func saveSettings() {
        do { model.errorMessage = nil; model.mutate("settings", ["name": name, "vin": vin.uppercased().trimmingCharacters(in: .whitespacesAndNewlines), "plannedKm": try jsonNumber(km), "reserveSOC": try jsonNumber(reserve), "dailyLimit": try jsonNumber(daily), "tariff": try jsonNumber(tariff)]) }
        catch { model.errorMessage = error.localizedDescription }
    }
}
struct OpenVehicleAppIntent: AppIntent {
    static var title: LocalizedStringResource = "YL Companion 열기"
    static var description = IntentDescription("개인 차량 앱을 열면 저장된 VIN으로 근거리 연결·최신화를 시작함. 차량 제어는 실행하지 않음.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult { .result() }
}
struct VehicleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenVehicleAppIntent(), phrases: ["\(.applicationName) 열기"], shortTitle: "차량 앱 열기", systemImageName: "car.side")
    }
}
