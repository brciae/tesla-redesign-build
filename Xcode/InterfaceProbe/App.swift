import SwiftUI
import CryptoKit

// Compiles the exact production tab container and Form buttons; no vehicle or SDK access.
@main struct InterfaceProbeApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("reset-appearance-fixture") {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("appearance.v1.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    var body: some Scene { WindowGroup {
        Group {
            if ProcessInfo.processInfo.arguments.contains("tabbar-probe") { TabBarProbe() }
            else if ProcessInfo.processInfo.arguments.contains("cache-probe") { VoiceCacheProbe() }
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

struct NavigationProbe: View {
    @State private var theme: NavigationTheme = .cluster
    @State private var blank = false
    @State private var bend = 0.0
    @State private var moving = false
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
    let runtime = try! LocalRuntime()
    var settings: Object = [:]
    var demo = true
}
enum Theme {
    static let bg = Color(red: 23/255, green: 24/255, blue: 26/255)
    static let surface = Color(red: 34/255, green: 35/255, blue: 38/255)
    static let muted = Color(red: 174/255, green: 178/255, blue: 183/255)
}
