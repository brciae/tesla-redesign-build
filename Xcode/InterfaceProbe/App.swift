import SwiftUI
import CryptoKit
import AVFoundation
import MapKit

// Compiles the exact production tab container and Form buttons; no vehicle or SDK access.
@main struct InterfaceProbeApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("climate-probe") { precondition(UIImage(named: "TeslaYLInterior") != nil, "Cabin fixture must include the production image asset") }
        if ProcessInfo.processInfo.arguments.contains("reset-appearance-fixture") {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("appearance.v1.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    var body: some Scene { WindowGroup {
        Group {
            if ProcessInfo.processInfo.arguments.contains("search-probe") { DestinationSearchView(navigation: EmbeddedNavigation()).environmentObject(AppModel()) }
            else if ProcessInfo.processInfo.arguments.contains(where: { ["voice-playback-probe", "voice-events-probe", "voice-lifecycle-probe"].contains($0) }) { VoicePlaybackProbe() }
            else if ProcessInfo.processInfo.arguments.contains("charge-cost-probe") { ChargeCostProbe() }
            else if ProcessInfo.processInfo.arguments.contains("charge-audit-probe") { ChargeAuditCalendarProbe() }
            else if ProcessInfo.processInfo.arguments.contains("archive-probe") { NavigationStack { FleetTelemetryView(vin: "TEST", connectionSettings: true) }.environmentObject(AppModel()) }
            else if ProcessInfo.processInfo.arguments.contains("climate-probe") { ClimateFleetProbe() }
            else if ProcessInfo.processInfo.arguments.contains("fleet-probe") { ClimateFleetProbe(fleetScreen: true) }
            else if ProcessInfo.processInfo.arguments.contains("tabbar-probe") { TabBarProbe() }
            else if ProcessInfo.processInfo.arguments.contains("cache-probe") { VoiceCacheProbe() }
            else if ProcessInfo.processInfo.arguments.contains("landing-probe") { NavigationLandingProbe() }
            else if ProcessInfo.processInfo.arguments.contains("fullscreen-navigation-probe") { FullscreenNavigationProbe() }
            else if ProcessInfo.processInfo.arguments.contains("navigation-probe") { NavigationProbe() }
            else if ProcessInfo.processInfo.arguments.contains("battery-probe") { BatteryProbe() }
            else if ProcessInfo.processInfo.arguments.contains("battery-gauge-probe") { BatteryGaugeProbe() }
            else { ProbeRoot() }
        }.preferredColorScheme(.dark)
    } }
}

struct VoiceCacheProbe: View {
    @State private var voice = "아엘"
    @State private var files = 24
    @State private var previews = 0
    @State private var diskResult = "검사 중"
    var body: some View {
        Form {
            VStack {
                Button("음성 변경") { voice = voice == "아엘" ? "은경" : "아엘" }.buttonStyle(.plain)
                Text(diskResult).accessibilityIdentifier("cache.disk")
                Text(voice).accessibilityIdentifier("cache.voice")
                Button("미리 듣기") { previews += 1 }.buttonStyle(.borderedProminent)
                Text("\(files)").accessibilityIdentifier("cache.files")
                VoiceCacheDeleteButton { files = 0 }
            }
        }
        .task { await verifyDiskCache() }
    }
    @MainActor private func verifyDiskCache() async {
        let client = TypecastClient.shared
        let previous = client.selectedVoiceId
        let text = "cache isolation fixture"
        let voices = ["fixture-voice-a", "fixture-voice-b"]
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/TypecastAudioCache")
        let urls = voices.map { voice in
            let digest = SHA256.hash(data: Data("\(voice)_\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
            return dir.appendingPathComponent(digest + ".wav")
        }
        defer {
            client.selectedVoiceId = previous
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (index, url) in urls.enumerated() { try Data(repeating: UInt8(index + 1), count: 256).write(to: url) }
            for index in [0, 1, 0] {
                client.selectedVoiceId = voices[index]
                guard client.cachedURL(for: text, voiceId: voices[index]) == urls[index] else { diskResult = "FAIL voice isolation"; return }
                let reused = try await client.synthesize(text: text, voiceId: voices[index])
                let bytes = try Data(contentsOf: reused)
                guard reused == urls[index], bytes == Data(repeating: UInt8(index + 1), count: 256) else { diskResult = "FAIL reuse"; return }
            }
            guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }), client.cachedURL(for: text, voiceId: "fixture-voice-c") == nil else { diskResult = "FAIL preservation"; return }
            diskResult = "PASS voice isolation and disk reuse"
        } catch { diskResult = "FAIL disk fixture" }
    }
}

struct TabBarProbe: View {
    @State private var selection: AppTab = .home
    @AppStorage("tabBarOpacity") private var opacity = 1.0
    private var page: some View {
        NavigationStack {
            VStack {
                Text("불투명도 \(Int(opacity * 100))%")
                Button("불투명") { opacity = 1 }.accessibilityIdentifier("opacity.full")
                Button("반투명") { opacity = 0.5 }.accessibilityIdentifier("opacity.half")
                Spacer()
                Button("하단 콘텐츠") {}.accessibilityIdentifier("content.bottom")
            }.frame(maxWidth: .infinity).background(Color.red)
        }
    }
    var body: some View {
        Commercial5TabScaffold(selection: $selection) {
            page
        } controls: { page } energy: { page } drive: { page } menu: { page }
    }
}

struct NavigationLandingProbe: View {
    @State private var result = "대기"
    var body: some View {
        VStack {
            NavigationLandingPanel(guiding: false, recent: [SavedNavigationPlace(name: "반포대교 남단", address: "서울 서초구", latitude: 37.5, longitude: 127)], search: { result = "검색 열림" }, dashboard: { result = "대시보드 열림" }, charging: { result = "충전소 열림" }, naver: {}, tmap: {}, select: { result = $0.name })
            Text(result).accessibilityIdentifier("landing.result")
        }
    }
}

struct FullscreenNavigationProbe: View {
    @State private var theme: NavigationTheme = .cluster
    @State private var stopped = false
    var body: some View {
        NavigationWorkspaceChrome {
            NavigationDashboard(theme: theme, data: sample) { NavigationMapFixture() }
                car: { Color.clear }
        } controls: {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(NavigationTheme.allCases) { value in
                        Button(value.title) { theme = value }.frame(minHeight: 44)
                    }
                }
            }.frame(height: 44)
            if !stopped { ParkedNavigationActions { stopped = true } }
            else { Text("안내 종료됨").accessibilityIdentifier("fullscreen.stopped") }
        }.background(.black).statusBarHidden(true).persistentSystemOverlays(.hidden)
    }
    private var sample: NavigationReadout {
        var r = NavigationReadout()
        r.speed = "0"; r.gear = "P"; r.battery = "71%"; r.range = "399 km"
        r.turn = "출발지 지나고 진행"; r.turnDistance = "0 m"; r.turnSymbol = "arrow.up"
        r.next = "24 m · 좌회전"; r.remaining = "54분 남음"; r.remainingDistance = "29.9 km"; r.arrival = "18:19"
        r.mediaTitle = "Orbit Pop"; r.mediaPlaying = true
        return r
    }
}

struct NavigationProbe: View {
    @State private var theme: NavigationTheme = .cluster
    @State private var blank = false
    @State private var bend = 0.0
    @State private var moving = false
    @State private var routeStopped = false
    @StateObject private var model = AppModel()
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Picker("테마", selection: $theme) { ForEach(NavigationTheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Button(blank ? "수신됨" : "미수신") { blank.toggle() }
                        .buttonStyle(.bordered).accessibilityIdentifier("navigation.empty")
                    if theme == .minimal && ProcessInfo.processInfo.arguments.contains("motion-probe") {
                        Button("좌") { bend = -0.7 }.accessibilityIdentifier("motion.left")
                        Button("우") { bend = 0.7 }.accessibilityIdentifier("motion.right")
                        Button(moving ? "정지" : "이동") { moving.toggle() }.accessibilityIdentifier("motion.toggle")
                    }
                }.padding(.horizontal, 8)
            }.frame(height: 44)
            if ProcessInfo.processInfo.arguments.contains("parked-route-probe") {
                if routeStopped { Text("자유주행").accessibilityIdentifier("navigation.stopped") }
                else { ParkedNavigationActions { routeStopped = true } }
            }
            NavigationDashboard(theme: theme, data: sample) {
                NavigationMapFixture()
            } car: {
                if let camera = theme.carCamera {
                    RealityVehicleView(runtime: model.runtime, presentation: sample.scenePresentation(theme: theme), command: VehicleCameraCommand(serial: NavigationTheme.allCases.firstIndex(of: theme) ?? 0, action: "angle", yaw: camera.yaw, pitch: camera.pitch, zoom: theme.carZoom), reducedMotion: true,
                        backgroundColor: .clear) { _ in }
                }
            }
        }.background(.black)
    }
    private var sample: NavigationReadout {
        if blank { return NavigationReadout() }
        var r = NavigationReadout()
        r.speed = "34"; r.gear = "D"; r.battery = "68%"; r.range = "321 km"; r.inside = "22°C"
        r.batterySOC = 68
        r.speedKmh = moving ? 34 : 0; r.routeBend = bend; r.motionValid = true; r.connected = true; r.outside = "25°C"
        r.turn = "동작대교 방면 오른쪽 진출"; r.turnDistance = "1.5 km"; r.turnSymbol = "arrow.up.right"; r.highway = "진출"
        if ProcessInfo.processInfo.arguments.contains("roundabout-probe") { r.exitClock = 9; r.turn = "회전교차로"; r.highway = "" }
        r.next = "1.3 km · 좌회전"; r.nextSymbol = "arrow.turn.up.left"; r.remaining = "22분 남음"; r.remainingDistance = "8.7 km"; r.arrival = "19:02"; r.speedFraction = 34 / 140
        r.destination = "반포대교 남단"; r.speedLimit = 80; r.speedLimitDistance = "2.1 km"; r.clock = "18:40"; r.routeProgress = 0.42; r.odometer = "12,450 km"; r.powerKW = 18; r.laneCount = 4; r.laneSuggested = [1, 2]; r.laneDistance = "416 m"
        r.currentRoadLanes = 3; r.currentRoadClass = "urban"; r.arrivalSOC = 61; r.braking = !moving; r.night = theme != .touring
        // Gentle right-hand curve 0…80 m ahead ([left, forward] metres).
        r.routePath = stride(from: 0.0, through: 80.0, by: 10.0).flatMap { f in [-(bend * f * f / 160), f] }
        r.mediaTitle = "Night Drive (샘플 트랙)"; r.mediaArtist = "YL 샘플 아티스트"; r.mediaSource = "Bluetooth"
        r.mediaPlaying = true; r.mediaElapsed = 74; r.mediaDuration = 253
        return r
    }
}
// Synthetic map fixture only: checks compositing and blur, NOT Kakao rendering or live routing.
private struct NavigationMapFixture: View {
    var body: some View {
        GeometryReader { g in
            Canvas { context, size in
                let w = size.width, h = size.height
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.16, green: 0.17, blue: 0.19)))
                for r in [CGRect(x: 0.08*w, y: 0.08*h, width: 0.25*w, height: 0.44*h),
                          CGRect(x: 0.43*w, y: 0.08*h, width: 0.21*w, height: 0.42*h),
                          CGRect(x: 0.70*w, y: 0.12*h, width: 0.25*w, height: 0.37*h),
                          CGRect(x: 0.44*w, y: 0.76*h, width: 0.50*w, height: 0.23*h)] {
                    context.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color(red: 0.22, green: 0.24, blue: 0.28)))
                }
                var road = Path()
                road.move(to: CGPoint(x: 0, y: h*0.64)); road.addLine(to: CGPoint(x: w, y: h*0.64))
                road.move(to: CGPoint(x: w*0.38, y: 0)); road.addLine(to: CGPoint(x: w*0.38, y: h))
                context.stroke(road, with: .color(.gray.opacity(0.65)), style: StrokeStyle(lineWidth: 24, lineJoin: .round))
                var route = Path()
                route.move(to: CGPoint(x: w*0.38, y: h)); route.addLine(to: CGPoint(x: w*0.38, y: h*0.64)); route.addLine(to: CGPoint(x: w, y: h*0.64))
                context.stroke(route, with: .color(.white.opacity(0.78)), style: StrokeStyle(lineWidth: 11, lineJoin: .round))
            }
            Image(systemName: "location.north.fill").font(.system(size: 24)).foregroundStyle(.blue)
                .padding(10).background(.white, in: Circle()).position(x: g.size.width*0.38, y: g.size.height*0.76)
        }.accessibilityLabel("검증용 지도 · 실제 지도 아님")
    }
}
struct BatteryGaugeProbe: View {
    var body: some View {
        VStack(spacing: 26) {
            Text("배터리 잔량 표시").font(.title2)
            ForEach([0, 20, 21, 50, 51, 100], id: \.self) { value in
                HStack { BatteryGauge(level: Double(value), width: 64); Text("\(value)%").font(.title2).frame(width: 90, alignment: .trailing) }
            }
            HStack { BatteryGauge(level: nil, width: 64); Text("미수신").font(.title2).frame(width: 90, alignment: .trailing) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
    }
}
struct BatteryProbe: View {
    @State private var days = 30
    var body: some View {
        ScrollView {
            BatteryOverview(index: ["degradationPercent": 0.0, "soh": 100.0, "initial": true, "sampleCount": 0,
                "note": "신차 기준 SOH 100% · 초기 가정. 실측값 아님.", "forecastNote": "관측 자료 수집 중"],
                usage: ["tripCount": 5, "completeTrips": 4, "excludedRateTrips": 1, "driveSOC": 65.0,
                    "chargeSOC": 125.0, "socPer100Km": 22.4, "distanceKm": 290.0, "observedDischargeCycles": 0.65,
                    "energy": ["drivingKmPerKWh": 8.02, "overallKmPerKWh": 6.78, "parkingKWh": 0.0, "unclassifiedKWh": 2.25],
                    "medianDischargeDepth": 16.3, "lowEndTrips": 1, "deepDischargeTrips": 0, "highEndCharges": 1,
                    "powerCoverage": 76.0, "observedUsedKWh": 42.1, "observedRecoveredKWh": 6.5,
                    "unexplainedParkingSOC": 1.0, "mixedParkingCount": 1,
                    "trend": [["id":"a","segment":"drive","at":1789380000000.0,"soc":80.0,"kind":"주행"],
                              ["id":"b","segment":"drive","at":1789383600000.0,"soc":64.0,"kind":"주행"],
                              ["id":"c","segment":"charge","at":1789387200000.0,"soc":64.0,"kind":"충전"],
                              ["id":"d","segment":"charge","at":1789390800000.0,"soc":90.0,"kind":"충전"]]], days: $days)
        }.background(Theme.bg)
    }
}
struct ProbeRoot: View {
    @StateObject private var model = AppModel()
    @State private var selection: AppTab = .vehicle
    @State private var starts = 0
    @State private var stops = 0
    @State private var voice = ""
    @State private var style = "standard"
    var body: some View {
        AppTabScaffold(selection: $selection) {
            NavigationStack {
                List {
                    NavigationLink("자동화") { Text("독립 자동화 화면").accessibilityIdentifier("automation.detail") }.accessibilityIdentifier("home.automation")
                    NavigationLink("차꾸미기") { VehicleAppearanceView().environmentObject(model) }.accessibilityIdentifier("home.appearance")
                }
                    .navigationTitle("차량").accessibilityIdentifier("vehicle.root")
            }
        } automation: {
            NavigationStack { Text("나만의 룰 · 실행 내역").accessibilityIdentifier("automation.root").navigationTitle("자동화") }
        } settings: {
            NavigationStack {
                Form {
                    VoiceSelectionControls(identifier: $voice, style: $style)
                    VoiceAdvancedControls(identifier: $voice, style: $style)
                    VoicePreviewControls(preview: { starts += 1 }, stop: { stops += 1 })
                    Text("\(starts),\(stops)").accessibilityIdentifier("voice.counts")
                }.navigationTitle("표시·음성 설정").accessibilityIdentifier("settings.root")
            }
        }
    }
}

// Fixture only: no BLE device, enrollment, navigation SDK, or real VIN.
@MainActor final class AppModel: ObservableObject {
    @Published var spokenSummary = ""
    func speak(_ text: String) { spokenSummary = text }
    func stopSpeech() { spokenSummary = "" }
    let runtime = try! LocalRuntime()
    var settings: Object = [:]
    var errorMessage: String?
    func mutate(_ action: String, _ input: Object) {
        do { _ = try runtime.call(action, input); output = try runtime.call("view") as? Object ?? [:]; settings = state.object("settings"); objectWillChange.send() }
        catch { errorMessage = error.localizedDescription }
    }
    var output: Object = ["charging": ["rows": [
        ["id": "fixture-charge-1", "at": Date().addingTimeInterval(-86400).timeIntervalSince1970 * 1000, "supplyKWh": 30.0, "cost": 9000],
        ["id": "fixture-charge-2", "at": Date().addingTimeInterval(-172800).timeIntervalSince1970 * 1000, "supplyKWh": 50.0, "cost": 15000]], "supplyKWh": 80.0, "cost": 24000],
        "energyPeriods": ["30": ["drivingKmPerKWh": 6.2, "overallKmPerKWh": 4.7, "drivingKWh": 100.0, "parkingKWh": 30.0, "totalKWh": 130.0, "totalDistanceKm": 620.0]]]
    var state: Object { output.object("state") }
    var groups: Object { state.object("groups") }
    var vehicleReference: Object = ["sourceDate": "2026-09-24", "nominalKWh": 88.2, "chemistry": "NCM", "cellMaker": "검증용 제조사", "basicWarrantyEnd": "2030-09-10", "batteryWarrantyEnd": "2034-09-10"]
    var displayOdometerKm: Double? { 1234 }
    let fleet = TeslaFleetClient()
    let link = VehicleLink()
    let voice = ProbeVoice()
    func requestVehicleControl(_ key: String, title: String, args: Object = [:]) { spokenSummary = title }
    func screenBriefing(_ scope: BriefingScope, days: Int = 30) -> String { "검증용 브리핑입니다." }
    var demo = true
}
// The fixture's Theme must carry every member the app's Theme carries, or a
// shared source file compiles in the app and fails only here. It drifted once
// already; briefing-coverage.cjs now compares the two member lists.
enum Theme {
    static let bg = Color(red: 23/255, green: 24/255, blue: 26/255)
    static let surface = Color(red: 34/255, green: 35/255, blue: 38/255)
    static let muted = Color(red: 174/255, green: 178/255, blue: 183/255)
    static let green = Color(red: 93/255, green: 205/255, blue: 144/255)
}

struct InfoCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.75))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }
}
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
}

struct MotionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduced ? 0.94 : 1)
            .animation(reduced ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}


func valueText(_ value: Double?, digits: Int = 0, suffix: String = "") -> String { value.map { String(format: "%.*f", digits, $0) + suffix } ?? "—" }
func homePresentation(_ model: AppModel, _ link: VehicleLink) -> Object { ["charge": ["soc": 90.0, "rangeKm": 451.0, "isCharging": false], "climate": ["insideC": 25.0, "outsideC": 29.0, "targetC": 22.0, "isOn": false]] }
final class VehicleLink: ObservableObject {
    var controlBusy = false; var preparingControl = false; var confirmation: String?
    var authentic = true; var controlEnabled = false
    func controlsReady(category: String) -> Bool { false }
    func runAutomation(_ action: String, title: String, args: Object, authorized: @escaping () -> Bool, completion: @escaping (String) -> Void) -> String? { "검증 환경 · 차량 명령 차단" }
}
struct ProbeVoice { func say(_ text: String, category: String, manual: Bool) {} }
enum FleetCommandPolicy { static func failure(_ text: String) -> Error { NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) } }
final class TeslaFleetClient: ObservableObject {
    static let shared = TeslaFleetClient()
    @MainActor func sendCommand(vin: String? = nil, command: String, parameters: [String: Any]? = nil, authorized: (() -> Bool)? = nil) async throws -> Bool { throw FleetCommandPolicy.failure("검증 환경 · 차량 명령 차단") }
    var virtualKeyPairingURL: URL? { nil }
    var isSendingCommand = false; var isAuthenticated = true; var isReadingVehicle = false
    var commandStatus = "UI 검증용 · 실제 차량에 명령을 보내지 않음"
    var vehicleReadStatus = "검증용 수신값"; var vehicleReadError: String?
    var selectedVin = "UI-FIXTURE"
    var vehicleSnapshot: FleetVehicleSnapshot? = FleetVehicleSnapshot(vin: "UI-FIXTURE", receivedAt: Date(), payload: [
        "charge_state": ["battery_level": 90, "battery_range": 280, "charger_power": 7, "charger_voltage": 220, "charger_actual_current": 32, "charge_energy_added": 12.4, "timestamp": Date().timeIntervalSince1970 * 1000],
        "climate_state": ["seat_heater_left": 1, "seat_heater_right": 0, "seat_fan_front_left": 0, "seat_fan_front_right": 2, "timestamp": Date().timeIntervalSince1970 * 1000],
        "vehicle_state": ["tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.8, "tpms_pressure_rl": 2.9, "tpms_pressure_rr": 2.85, "locked": true, "sentry_mode": false, "car_version": "fixture", "timestamp": Date().timeIntervalSince1970 * 1000]])
    func refreshVehicleSnapshot(force: Bool = false) async {}
    func readSupplement(_ kind: FleetSupplement) async throws -> FleetSupplementResult {
        FleetSupplementResult(vin: selectedVin, receivedAt: Date(), payload: ["fixture": true])
    }
    func repairLocationStreaming(vin: String) async throws -> FleetSupplementResult {
        throw FleetCommandPolicy.failure("UI 검증에서는 차량 수집 설정을 변경하지 않습니다.")
    }
    func setPreconditioningMax(on: Bool) async throws -> Bool { true }
    func setSteeringWheelHeater(on: Bool) async throws -> Bool { true }
    func setSeatCooler(seatPosition: Int, level: Int) async throws -> Bool { true }
    func setSeatHeater(seatPosition: Int, level: Int) async throws -> Bool { true }
    func setClimateKeeperMode(mode: Int) async throws -> Bool { true }
}
struct VoicePlaybackProbe: View {
    @StateObject private var voice = VoiceCoordinator()
    @State private var boardingCoordinator: AutomationCoordinator?
    @State private var boardingResult = "탑승 조건 대기"
    @State private var eventResult = "전체 이벤트 검사 대기"
    private let labels = ["수동 미리듣기", "화면 브리핑", "제어 응답", "연결 알림", "운행 알림", "충전 알림", "자동화", "길안내", "안전 안내"]
    private let categories = ["", "", "voiceControl", "voiceConnection", "voiceTrip", "voiceCharge", "voiceAutomations", "", ""]
    var body: some View {
        VStack {
            Text("재생 시작 \(voice.playbackStarts) / 완료 \(voice.playbackCompletions)").accessibilityIdentifier("voice.probe.count")
            Text(voice.playbackState)
            Text(voice.automaticStatus)
            Text(voice.notice)
            if ProcessInfo.processInfo.arguments.contains("voice-output-probe") {
                VoiceOutputSettings()
                Text(voice.lastPlaybackOutput).accessibilityIdentifier("voice.output.last")
            }
            ForEach(labels.indices, id: \.self) { index in Button(labels[index]) { play(index) } }
            Button("탑승 자동화 검증") { boarding() }
            Button("Fleet 탑승 자동화 검증") { boarding(fleet: true) }
            Text(boardingResult)
            Text(eventResult)
        }.onAppear {
            let d = UserDefaults.standard
            for key in ["voiceEnabled", "voiceControl", "voiceConnection", "voiceTrip", "voiceCharge", "voiceAutomations", "navVoiceEnabled", "navSafetyVoice"] { d.set(true, forKey: key) }
            d.set("system", forKey: "voiceOutput")
            d.set(false, forKey: "voiceQuietEnabled"); d.set(0.8, forKey: "voiceVolume"); d.set(0.8, forKey: "navVoiceVolume")
            d.set("typecast:은경", forKey: "voiceIdentifier"); TypecastClient.shared.isEnabled = true
            if ProcessInfo.processInfo.arguments.contains("voice-events-probe") { Task { await eventMatrix() } }
            if ProcessInfo.processInfo.arguments.contains("voice-lifecycle-probe") { Task { await lifecycleMatrix() } }
        }
    }
    @MainActor private func lifecycleMatrix() async {
        let d = UserDefaults.standard
        let text = "전체 음성 재생 상태 검증입니다."
        let safetyText = "전방 안전 안내 우선 재생 검증입니다."
        cache(SpeechText.prepare(BriefingStyle.selected.phrase(text, category: "voiceAutomations")))
        cache(SpeechText.prepare(text))
        cache(SpeechText.prepare(safetyText))
        var passed = 0
        func request() { voice.say(text, key: UUID().uuidString, category: "voiceAutomations", ttl: 60, manual: false) }
        func blocked(_ name: String, configure: () -> Void, invoke: () -> Void, restore: () -> Void) async -> Bool {
            voice.stop(); let count = voice.playbackStarts; configure(); invoke()
            try? await Task.sleep(nanoseconds: 200_000_000)
            let result = voice.playbackStarts == count
            restore(); voice.stop()
            if result { passed += 1 } else { eventResult = "실패 · " + name }
            return result
        }
        guard await blocked("전체 음성 OFF", configure: { d.set(false, forKey: "voiceEnabled") }, invoke: request, restore: { d.set(true, forKey: "voiceEnabled") }) else { return }
        guard await blocked("자동화 음성 OFF", configure: { d.set(false, forKey: "voiceAutomations") }, invoke: request, restore: { d.set(true, forKey: "voiceAutomations") }) else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        guard await blocked("방해 금지", configure: { d.set(true, forKey: "voiceQuietEnabled"); d.set(hour, forKey: "voiceQuietStart"); d.set((hour + 1) % 24, forKey: "voiceQuietEnd") }, invoke: request, restore: { d.set(false, forKey: "voiceQuietEnabled") }) else { return }
        guard await blocked("음량 0", configure: { d.set(0, forKey: "voiceVolume") }, invoke: request, restore: { d.set(0.8, forKey: "voiceVolume") }) else { return }
        guard await blocked("타입캐스트 OFF", configure: { TypecastClient.shared.isEnabled = false }, invoke: request, restore: { TypecastClient.shared.isEnabled = true }) else { return }
        guard await blocked("길안내 OFF", configure: { d.set(false, forKey: "navVoiceEnabled") }, invoke: { voice.navigationGuide(text, safety: false) }, restore: { d.set(true, forKey: "navVoiceEnabled") }) else { return }
        guard await blocked("안전 안내 OFF", configure: { d.set(false, forKey: "navSafetyVoice") }, invoke: { voice.navigationGuide(text, safety: true) }, restore: { d.set(true, forKey: "navSafetyVoice") }) else { return }
        guard await blocked("이미 지난 안내", configure: {}, invoke: {
            let cue: Object = ["text": text, "validUntil": Date().addingTimeInterval(-1).timeIntervalSince1970]
            voice.navigationGuide(String(data: try! JSONSerialization.data(withJSONObject: cue), encoding: .utf8)!, safety: false)
        }, restore: {}) else { return }
        guard await blocked("안내 지점 통과", configure: { voice.navigationTargetIsAhead = { _ in false } }, invoke: {
            let cue: Object = ["text": text, "targetID": "passed", "validUntil": Date().addingTimeInterval(10).timeIntervalSince1970]
            voice.navigationGuide(String(data: try! JSONSerialization.data(withJSONObject: cue), encoding: .utf8)!, safety: false)
        }, restore: { voice.navigationTargetIsAhead = nil; voice.nativeSession(false) }) else { return }
        guard await blocked("통화 중", configure: {
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        }, invoke: request, restore: {
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        }) else { return }
        // After the interruption a new event must actually finish, rather than remain blocked.
        var count = voice.playbackCompletions; request()
        for _ in 0..<40 where voice.playbackCompletions == count { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard voice.playbackCompletions == count + 1 else { eventResult = "실패 · 통화 종료 후 새 안내"; return }; passed += 1
        // Safety navigation preempts an automatic clip and itself reaches completion.
        count = voice.playbackCompletions; let starts = voice.playbackStarts
        request(); voice.nativeSession(false); voice.navigationGuide(safetyText, safety: true)
        for _ in 0..<40 where voice.playbackCompletions == count { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard voice.playbackStarts == starts + 2 && voice.playbackCompletions == count + 1 else { eventResult = "실패 · 안전 안내 우선 재생"; return }; passed += 1
        // Memory and explicit automatic-stop cancellation must stop the actual player.
        for memory in [false, true] {
            voice.nativeSession(false); request(); count = voice.playbackCompletions
            if memory { NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil) }
            else { voice.stopAutomatic() }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !voice.speaking && voice.playbackCompletions == count else { eventResult = "실패 · 안내 취소"; return }; passed += 1
        }
        voice.nativeVoice(true); count = voice.playbackStarts; request()
        guard voice.playbackStarts == count else { eventResult = "실패 · 내비 오디오 대기"; return }
        let finished = voice.playbackCompletions; voice.nativeVoice(false)
        for _ in 0..<50 where voice.playbackCompletions == finished { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard voice.playbackCompletions == finished + 1 else { eventResult = "실패 · 내비 오디오 대기 해제"; return }; passed += 1
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        guard !voice.outputDescription.isEmpty else { eventResult = "실패 · 출력 경로 상태"; return }; passed += 1
        // Settings' Typecast test uses its own production AVAudioPlayer, not VoiceCoordinator.
        var previewDone = false
        TypecastClient.shared.testSpeech(text: SpeechText.prepare(text), voiceId: "은경") { previewDone = true }
        for _ in 0..<50 where !previewDone { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard previewDone && TypecastClient.shared.lastStatus == "재생 완료" else { eventResult = "실패 · 타입캐스트 설정 미리듣기"; return }; passed += 1
        eventResult = "음성 상태 \(passed)/17 검증 완료"
    }
    @MainActor private func eventMatrix() async {
        UserDefaults.standard.set(false, forKey: "voiceConnection")
        defer { UserDefaults.standard.set(true, forKey: "voiceConnection") }
        var passed = 0
        let fleetSpeechCases = AutomationTrigger.allCases.filter { ![.chargeStart, .chargeEnd, .chargingLocked].contains($0) }.map { ($0, "Fleet speech") }
        let cases = AutomationTrigger.allCases.map { ($0, "BLE") } + [(AutomationTrigger.chargeStart, "Fleet start"), (.chargeEnd, "Fleet complete"), (.chargeEnd, "Fleet stop")] + fleetSpeechCases
        for (trigger, source) in cases {
            let vin = String(format: "7SAYGDEE0PF%06d", 100 + passed)
            eventResult = "검사 중 · \(trigger.title) · \(source)"
            let text = "\(trigger.title) \(source) 이벤트 검증입니다."
            cache(SpeechText.prepare(BriefingStyle.selected.phrase(source == "Fleet start" ? text + " 80퍼센트" : text, category: "voiceAutomations")))
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var rule = AutomationRule(name: trigger.title, trigger: trigger)
            rule.message = text; rule.cooldownMinutes = 1
            if source == "Fleet start" { rule.message += " {배터리}" }
            if source == "Fleet start" || (source == "Fleet speech" && trigger == .batteryLow) { rule.cabinCondition = "above"; rule.cabinThresholdC = 26 }
            if [.rest, .delay].contains(trigger) { rule.threshold = 1 }
            if trigger == .remaining { rule.threshold = 10 }
            if trigger == .tireLow { rule.threshold = 2.4 }
            try! rule.validate()
            var doc = AutomationDocument(); doc.rules = [rule]
            try! JSONEncoder().encode(doc).write(to: folder.appendingPathComponent("automations.json"))
            let base = Date().addingTimeInterval(-90)
            var clock = base
            let coordinator = try! AutomationCoordinator(folder: folder, observationNow: { clock.addingTimeInterval(0.01) })
            let link = VehicleLink()
            let before = voice.playbackCompletions
            let startsBefore = voice.playbackStarts
            func feed(_ seconds: Double, gear: String = "P", soc: Double = 80, charging: Int = 2, route: String = "집", minutes: Double = 11, endedTrip: Bool = false, endedCharge: Bool = false, lowTire: Bool = false, inside: Double = 30) {
                clock = base.addingTimeInterval(seconds)
                let at = clock.timeIntervalSince1970 * 1000
                let groups: Object = ["drive": ["at": at, "receivedAt": at, "gear": gear, "speedKmh": gear == "P" ? 0 : 30, "destination": route, "arrivalMinutes": minutes],
                                      "closures": ["at": at, "receivedAt": at, "userPresent": true, "driverFront": false],
                                      "charge": ["at": at, "receivedAt": at, "soc": soc, "charging": charging],
                                      "tire": ["at": at, "receivedAt": at, "values": [2.9, 2.9, 2.9, 2.9], "seenAt": [at, at, at, at], "warnings": [lowTire]]]
                let output: Object = ["fresh": ["drive": true, "closures": true, "charge": true, "tire": true],
                                      "state": ["settings": ["vin": vin], "groups": groups,
                                                "trips": endedTrip ? [["id": "finished-trip", "start": at - 60000, "end": at, "distanceKm": 1]] : [],
                                                "charges": endedCharge ? [["id": "finished-charge"]] : []]]
                if source == "Fleet speech" {
                    link.authentic = false; TeslaFleetClient.shared.selectedVin = vin
                    let snapshot = FleetVehicleSnapshot(vin: vin, receivedAt: clock, payload: [
                        "drive_state": ["timestamp": at, "shift_state": gear, "speed": gear == "P" ? 0 : 20, "active_route_destination": route, "active_route_minutes_to_arrival": minutes],
                        "vehicle_state": ["timestamp": at, "is_user_present": true, "df": 0, "locked": false, "tpms_pressure_fl": 2.9, "tpms_hard_warning_fl": lowTire],
                        "charge_state": ["timestamp": at, "battery_level": soc], "climate_state": ["timestamp": at, "inside_temp": inside]])
                    coordinator.observeFleetSpeech(snapshot, history: output.object("state"), previousTrips: 0, link: link, voice: voice)
                } else { coordinator.observe(output: output, previousTrips: 0, previousCharges: 0, link: link, voice: voice, demo: false) }
            }
            if ["Fleet start", "Fleet complete", "Fleet stop"].contains(source) || trigger == .chargingLocked {
                TeslaFleetClient.shared.selectedVin = vin
                func fleet(_ state: String, seconds: Double, inside: Double = 30) {
                    let at = Date().addingTimeInterval(seconds).timeIntervalSince1970 * 1000
                    let snapshot = FleetVehicleSnapshot(vin: vin, receivedAt: Date(), payload: ["charge_state": ["timestamp": at, "charging_state": state, "battery_level": 80, "charge_limit_soc": 80], "vehicle_state": ["timestamp": at, "locked": true], "climate_state": ["timestamp": at, "inside_temp": inside]])
                    coordinator.observeFleet(snapshot, voice: voice, bleActive: false)
                }
                if trigger == .chargingLocked { fleet("Charging", seconds: 0) }
                else if trigger == .chargeStart {
                    fleet("Disconnected", seconds: -6); fleet("Charging", seconds: -5, inside: 20)
                    guard voice.playbackStarts == startsBefore else { eventResult = "실패 · Fleet 충전 온도 조건 무시"; return }
                    fleet("Disconnected", seconds: -4); fleet("Charging", seconds: -3)
                    fleet("Disconnected", seconds: -2); fleet("Charging", seconds: -1)
                    guard coordinator.logs.count == 1 else { eventResult = "실패 · Fleet 충전 재실행 간격"; return }
                }
                else { fleet("Charging", seconds: -2); fleet(source == "Fleet stop" ? "Stopped" : "Complete", seconds: 0) }
            } else {
                switch trigger {
                case .boarding: feed(0); feed(3)
                case .departure: feed(0); feed(3, gear: "D")
                case .arrival: feed(0, gear: "D"); feed(3, endedTrip: true)
                case .chargeStart: feed(0); feed(3, charging: 5)
                case .chargeEnd: feed(0, charging: 5); feed(3, charging: 6, endedCharge: true)
                case .batteryLow:
                    feed(0)
                    if source == "Fleet speech" {
                        feed(3, gear: "D", soc: 10, inside: 20)
                        guard voice.playbackStarts == startsBefore else { eventResult = "실패 · Fleet 배터리 온도 조건 무시"; return }
                    }
                    feed(6, gear: "D", soc: 10)
                case .tireLow: feed(0); feed(3, gear: "D", lowTire: true)
                case .rest: for second in stride(from: 0, through: 75, by: 15) { feed(Double(second), gear: "D") }
                case .remaining: feed(0, gear: "D"); feed(3, gear: "D", minutes: 9)
                case .delay: feed(0, gear: "D", minutes: 10); feed(3, gear: "D", minutes: 12)
                case .destination: feed(0, gear: "D"); feed(3, gear: "D", route: "회사")
                case .chargingLocked: break
                }
            }
            for _ in 0..<60 where voice.playbackCompletions == before { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard voice.playbackCompletions == before + 1 else { eventResult = "실패 · \(trigger.title) · \(source) · \(coordinator.status) · \(voice.automaticStatus) · \(voice.notice)"; return }
            passed += 1
        }
        eventResult = "자동화 \(passed)/\(cases.count) 재생 완료"
    }
    private func play(_ index: Int) {
        // Test-only PCM cache in the simulator sandbox; no API key or paid request.
        let text = labels[index] + " 음성 검증입니다."
        let prepared = SpeechText.prepare(index >= 7 ? text : BriefingStyle.selected.phrase(text, category: categories[index]))
        cache(prepared)
        if index == 0 { voice.preview(text) }
        else if index >= 7 { voice.navigationGuide(text, safety: index == 8) }
        else { voice.say(text, key: "probe-\(index)", category: categories[index], priority: 2, ttl: 60, manual: index < 3) }
    }
    private func boarding(fleet: Bool = false) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let coordinator = try! AutomationCoordinator(folder: folder)
        boardingCoordinator = coordinator
        let greeting = AutomationPolicy.greeting(hour: Calendar.current.component(.hour, from: Date())) + " 배터리 80퍼센트입니다."
        cache(SpeechText.prepare(BriefingStyle.selected.phrase(greeting, category: "voiceAutomations")))
        let link = VehicleLink()
        link.authentic = !fleet
        func observe() {
            let at = Date().timeIntervalSince1970 * 1000
            if fleet {
                TeslaFleetClient.shared.selectedVin = "7SAYGDEE0PF000002"
                let snapshot = FleetVehicleSnapshot(vin: "7SAYGDEE0PF000002", receivedAt: Date(), payload: [
                    "vehicle_state": ["timestamp": at, "is_user_present": true, "df": 0, "locked": false],
                    "charge_state": ["timestamp": at, "battery_level": 80]])
                coordinator.observeFleetSpeech(snapshot, link: link, voice: voice)
                return
            }
            let output: Object = ["fresh": ["drive": true, "closures": true, "charge": true], "state": ["settings": ["vin": "7SAYGDEE0PF000001"], "groups": [
                "drive": ["at": at, "receivedAt": at, "gear": "P", "speedKmh": 0],
                "closures": ["at": at, "receivedAt": at, "userPresent": true, "driverFront": false],
                "charge": ["at": at, "receivedAt": at, "soc": 80]]]]
            coordinator.observe(output: output, previousTrips: 0, previousCharges: 0, link: link, voice: voice, demo: false)
        }
        observe()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            observe()
            boardingResult = coordinator.logs.contains { $0.rule == "탑승 인사" } ? (fleet ? "Fleet 탑승 조건 충족 · 실제 자동화 음성 요청" : "탑승 조건 충족 · 실제 자동화 음성 요청") : coordinator.status
            // A reconnect cannot trigger a second greeting for the same boarding.
            coordinator.resetObservation(); observe()
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            observe()
            precondition(coordinator.logs.filter { $0.rule == "탑승 인사" }.count == 1)
        }
    }
    private func cache(_ prepared: String) {
        let key = SHA256.hash(data: Data(("은경_" + prepared).utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/TypecastAudioCache")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        buffer.frameLength = 16000
        for sample in 0..<16000 { buffer.int16ChannelData![0][sample] = Int16(sin(Double(sample) * 2 * .pi * 440 / 16000) * 200) }
        do { let file = try AVAudioFile(forWriting: dir.appendingPathComponent(key + ".wav"), settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true); try file.write(from: buffer) }
        catch { fatalError("Fixture WAV failed: \(error)") }
        precondition(TypecastClient.shared.cachedURL(for: prepared, voiceId: "은경") != nil)
    }
}
struct ChargeAuditCalendarProbe: View {
    @StateObject private var model: AppModel
    init() {
        let m = AppModel()
        var state = (try! m.runtime.call("export")) as! Object
        let at = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        state["charges"] = (0..<36).map { i -> Object in
            ["id": "duplicate-fixture-\(i)", "at": at + Double(i) * 60000, "end": at + Double(i) * 60000,
             "startSOC": 25, "endSOC": 80 - Double(i) * 0.11, "vehicleReportedKWh": 40.36,
             "collectedAfterEnd": true, "source": "Fleet", "complete": false]
        }
        m.output = (try! m.runtime.call("load", state)) as! Object
        _model = StateObject(wrappedValue: m)
    }
    var body: some View { NavigationStack { EnergyCalendarView().environmentObject(model) } }
}
struct ClimateFleetProbe: View {
    @StateObject private var model = AppModel()
    var fleetScreen = false
    var body: some View {
        NavigationStack {
            Group {
                if fleetScreen { FleetInsightsView(fleet: model.fleet) }
                else { TeslaInteractiveClimateView(link: model.link).navigationTitle("실내 공조") }
            }
        }.environmentObject(model)
    }
}

@MainActor final class EmbeddedNavigation: ObservableObject {
    func startManualDestination(name: String, coordinate: CLLocationCoordinate2D, vin: String) throws {}
}

private struct ProbeUnitsKey: EnvironmentKey { static let defaultValue = VehicleUnits() }
extension EnvironmentValues { var vehicleUnits: VehicleUnits { get { self[ProbeUnitsKey.self] } set { self[ProbeUnitsKey.self] = newValue } } }
struct CareView: View { var body: some View { ScrollView { TirePressureDiagram().padding() }.navigationTitle("타이어·정비") } }

enum Page: Hashable { case chargingSettings }

// This uses the real JS estimate policy and the production cost details view.
struct ChargeCostProbe: View {
    @StateObject private var model = AppModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(model.output.object("charging").rows("rows"), id: \.selfID) { row in
                        ChargeCostDetails(charge: row)
                    }
                    NavigationLink("단가 설정 열기") { ChargeRateSettingsView() }
                }.padding()
            }.navigationTitle("충전 예상 금액")
        }.environmentObject(model).onAppear {
            model.mutate("settings", ["tariff": 200, "fastTariff": 350])
            model.mutate("addCharge", ["at": Date().addingTimeInterval(-7200).timeIntervalSince1970 * 1000, "supplyKWh": 10, "place": "집", "chargeType": "ac"])
            model.mutate("addCharge", ["at": Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000, "supplyKWh": 20, "place": "수퍼차저 검증", "chargeType": "supercharger"])
        }
    }
}
extension Dictionary where Key == String, Value == Any { var selfID: String { string("id") } }
