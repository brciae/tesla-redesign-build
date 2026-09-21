import SwiftUI
import Charts
import PhotosUI
import UniformTypeIdentifiers

@main
struct YLCompanionApp: App {
    @UIApplicationDelegateAdaptor(YLApplicationDelegate.self) private var appDelegate
    @StateObject private var owner = AppOwner()
    var body: some Scene {
        WindowGroup {
            if let model = owner.model { MainView(model: model, link: model.link, navigation: model.navigation).environmentObject(model).preferredColorScheme(.dark) }
            else { ContentUnavailableView("앱 준비 실패", systemImage: "exclamationmark.triangle", description: Text(owner.failure)).preferredColorScheme(.dark) }
        }
    }
}
final class AppOwner: ObservableObject {
    let model: AppModel?
    let failure: String
    init() { do { model = try AppModel(); failure = "" } catch { model = nil; failure = error.localizedDescription } }
}
enum Theme {
    static let bg = Color(red: 23/255, green: 24/255, blue: 26/255)
    static let surface = Color(red: 34/255, green: 35/255, blue: 38/255)
    static let muted = Color(red: 174/255, green: 178/255, blue: 183/255)
    static let green = Color(red: 93/255, green: 205/255, blue: 144/255)
}
enum Page: String, Hashable {
    case controls = "컨트롤", climate = "실내 온도", location = "위치", charging = "충전"
    case schedule = "일정 예약 설정", security = "보안 및 운전자"
    case drive = "주행·내비", battery = "충전·배터리", trips = "운행 기록", care = "차량 관리"
    case automation = "자동화", connection = "연결 상태", briefing = "오늘의 브리핑", vehicle3D = "차량 3D"
    case navigation = "카카오 내장 내비", preferences = "표시·음성 설정"
    case appearance = "차꾸미기"
}
func valueText(_ value: Double?, digits: Int = 0, suffix: String = "") -> String { guard let value, value.isFinite else { return "—" }; return String(format: "%.*f", digits, value) + suffix }
func dateText(_ ms: Double?, time: Bool = true) -> String { guard let ms else { return "미수신" }; let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = time ? "M월 d일 HH:mm" : "yyyy.MM.dd"; return f.string(from: Date(timeIntervalSince1970: ms/1000)) }
func jsonNumber(_ s: String) throws -> Any {
    if s.trimmingCharacters(in: .whitespaces).isEmpty { return NSNull() }
    guard let value = Double(s.replacingOccurrences(of: ",", with: "")), value.isFinite else { throw LocalError.message("숫자 입력 확인 필요") }; return value
}

struct MotionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduced ? 0.94 : 1)
            .animation(reduced ? nil : .spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
struct SheetShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var navigation: EmbeddedNavigation
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    @AppStorage("unitDistance") private var distance = "km"
    @AppStorage("unitTemperature") private var temperature = "C"
    @AppStorage("unitPressure") private var pressure = "bar"
    @State private var selectedTab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var controlsPath = NavigationPath()
    @State private var energyPath = NavigationPath()
    @State private var drivePath = NavigationPath()
    @State private var menuPath = NavigationPath()

    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    // Re-tapping current tab pops to root
                    switch newTab {
                    case .home: homePath = NavigationPath()
                    case .controls: controlsPath = NavigationPath()
                    case .energy: energyPath = NavigationPath()
                    case .drive: drivePath = NavigationPath()
                    case .menu: menuPath = NavigationPath()
                    default: break
                    }
                } else {
                    // Switching away or returning to menu immediately resets menu to root
                    if newTab == .menu || selectedTab == .menu {
                        menuPath = NavigationPath()
                    }
                    selectedTab = newTab
                }
            }
        )
    }

    var body: some View {
        mainContent
            .environment(\.vehicleUnits, VehicleUnits(distance: distance, temperature: temperature, pressure: pressure))
            .animation(reduced ? nil : .easeInOut(duration: 0.25), value: navigation.presented)
            .tint(.white)
            .modifier(AutomationAIHost(ai: model.aiRules, store: model.automations))
            .onOpenURL { url in model.aiRules.receive(url, vehicle: model.settings.string("vin")) }
            .task { if phase == .active { model.resume() } }
            .onChange(of: phase) { _, p in handlePhase(p) }
            .alert("확인", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("확인", role: .cancel) { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
            .sheet(isPresented: Binding(get: { model.sharedFile != nil }, set: { if !$0 { model.sharedFile = nil } })) { if let url = model.sharedFile { SheetShare(url: url) } }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .menu { menuPath = NavigationPath() }
                handleTabVoice(newTab)
            }
            .onChange(of: model.chargingPresented) { _, presented in
                if presented { model.voice.say("충전 상세 화면을 열었습니다.", category: "voiceControl", manual: true) }
            }
            .onChange(of: navigation.presented) { _, presented in handleNavVoice(presented) }
    }

    private var mainContent: some View {
        ZStack {
            Commercial5TabScaffold(selection: tabBinding) {
                NavigationStack(path: $homePath) { HomeView(link: link).modifier(AppDestinations(link: link, navigation: navigation)) }
            } controls: {
                NavigationStack(path: $controlsPath) { ControlsTabRootView(link: link).modifier(AppDestinations(link: link, navigation: navigation)) }
            } energy: {
                NavigationStack(path: $energyPath) { EnergyTabRootView(link: link).modifier(AppDestinations(link: link, navigation: navigation)) }
            } drive: {
                NavigationStack(path: $drivePath) { DriveTabRootView(link: link, navigation: navigation).modifier(AppDestinations(link: link, navigation: navigation)) }
            } menu: {
                NavigationStack(path: $menuPath) { MenuTabRootView(link: link, navigation: navigation).modifier(AppDestinations(link: link, navigation: navigation)) }
            }
            .opacity(navigation.presented ? 0 : 1).allowsHitTesting(!navigation.presented).accessibilityHidden(navigation.presented)

            if navigation.presented { DrivingWorkspace(navigation: navigation, link: link).transition(.opacity).zIndex(1) }
            if model.chargingPresented { ChargingWorkspace(link: link, isPresented: $model.chargingPresented).transition(.opacity).zIndex(2) }
        }
    }

    private func handlePhase(_ p: ScenePhase) {
        if p == .active { model.resume() }
        else if p == .background { model.pause() }
        else { model.resignActive() }
    }

    private func handleTabVoice(_ tab: AppTab) {
        let prompt: String
        switch tab {
        case .home: prompt = "홈 화면으로 이동했습니다."
        case .controls: prompt = "차량 컨트롤 화면으로 이동했습니다."
        case .energy: prompt = "에너지 화면으로 이동했습니다."
        case .drive: prompt = "운행 내비 화면으로 이동했습니다."
        case .menu: prompt = "전체 메뉴로 이동했습니다."
        default: prompt = ""
        }
        if !prompt.isEmpty { model.voice.say(prompt, category: "voiceControl", manual: true) }
    }

    private func handleNavVoice(_ presented: Bool) {
        if presented {
            model.voice.say("주행 대시보드를 표시합니다.", category: "voiceControl", manual: true)
        } else {
            model.voice.say("주행 대시보드를 닫았습니다.", category: "voiceControl", manual: true)
        }
    }
}
private struct AppDestinations: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var navigation: EmbeddedNavigation

    func body(content: Content) -> some View {
        content.navigationDestination(for: Page.self) { page in
            destinationView(for: page)
                .onAppear {
                    model.voice.say("\(page.rawValue) 화면입니다.", category: "voiceControl", manual: true)
                }
        }
    }

    @ViewBuilder
    private func destinationView(for page: Page) -> some View {
        switch page {
        case .controls: ControlsView(link: link)
        case .climate: ClimateStatusView(link: link)
        case .location: LocationStatusView(link: link)
        case .charging: ChargeStatusView(link: link)
        case .schedule: AutomationUtilitiesView(title: "일정 예약 설정")
        case .security: SecurityStatusView(link: link)
        case .drive: DriveView()
        case .navigation: NavigationSetupView(navigation: navigation)
        case .preferences: PreferencesView()
        case .appearance: VehicleAppearanceView()
        case .battery: BatteryView()
        case .trips: TripsView()
        case .care: CareView()
        case .automation: AutomationView()
        case .connection: ConnectionView(link: link)
        case .briefing: BriefingView()
        case .vehicle3D: PageBody(title: "차량 3D") { Vehicle3DPanel(link: link) }
        }
    }
}
struct PageBody<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
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
struct Metric: View {
    let title: String
    let value: Double?
    var digits = 0
    var suffix = ""
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.vehicleUnits) private var units
    var body: some View {
        let parts = units.displayParts(value, suffix: suffix, digits: digits)
        VStack(alignment: .leading, spacing: 7) {
            (Text(parts.0).font(.system(size: 32, weight: .medium, design: .rounded)) + Text(parts.1).font(.system(size: 14, weight: .medium)))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.60)
                .contentTransition(.numericText()).animation(reduced || !animated ? nil : .easeOut(duration: 0.28), value: value)
            Caption(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct DriveView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @AppStorage("keepDriveDisplayOn") private var keepDisplay = true
    @State private var confirmEnd = false
    var body: some View {
        let d = model.groups.object("drive"), c = model.groups.object("charge")
        PageBody(title: "주행 정보") {
            VStack(spacing: 8) {
                Text(model.output.object("fresh").flag("drive") ? valueText(d.number("speedKmh").map { units.distanceValue($0) }) : "—").font(.system(size: 88, weight: .light, design: .rounded)).monospacedDigit()
                Caption(units.speedLabel); Text(model.output.object("fresh").flag("drive") ? d.string("gear", "—") : "—").font(.system(size: 28, weight: .medium))
                Caption("마지막 수신 \(dateText(d.number("at")))")
                if !model.output.object("fresh").flag("drive") { Caption("최신 주행 정보 미확인 · 저장값 표시") }
            }.frame(maxWidth: .infinity).padding(.vertical, 20)
            HStack { Metric(title: "배터리", value: c.number("soc"), suffix: "%", animated: false); Metric(title: "표시 주행 가능 거리", value: c.number("rangeKm"), suffix: " km", animated: false) }
            InfoCard {
                CardTitle(title: "테슬라 목적지", systemImage: "location.north.fill",
                          info: "차량이 보고한 목적지임. 새 목적지를 수신하면 카카오 길안내로 연결함. 예상 도착과 도착 잔량은 Tesla 경로 기준 값이라 실제 주행·공조 사용에 따라 달라짐.")
                Text(d.string("destination", "목적지 미수신")).font(.title3)
                HStack { Metric(title: "예상 도착", value: d.number("arrivalMinutes"), suffix: "분", animated: false); Metric(title: "Tesla 경로 도착 잔량", value: d.number("arrivalSOC"), suffix: "%", animated: false) }
                NavigationLink("길안내 설정 · 네이버 지도로 넘기기", value: Page.navigation)
                HStack(spacing: 10) {
                    Button("운전 대시보드") { model.navigation.presented = true }.buttonStyle(.bordered)
                    Button("네이버 지도로 안내") { model.openInNaverMap() }.buttonStyle(.bordered).disabled(model.demo)
                }
                Toggle("이 화면에서 자동 잠금 방지", isOn: $keepDisplay)
            }
            if !model.state.object("activeTrip").isEmpty {
                InfoCard {
                    CardTitle(title: "운행 기록 중", systemImage: "record.circle",
                              info: "P 상태가 45초 유지되면 회차를 잠정 종료함. 실제 하차를 감지하는 것은 아니므로 필요하면 수동으로 종료할 수 있음.")
                    Button("회차 수동 종료") { confirmEnd = true }
                }
            }
        }.confirmationDialog("저장된 마지막 값으로 회차를 종료함", isPresented: $confirmEnd) { Button("수동 종료") { model.mutate("finish") } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepDisplay }
        .onChange(of: keepDisplay) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        .onDisappear { if !model.navigation.presented { UIApplication.shared.isIdleTimerDisabled = false } }
    }
}
struct BriefingView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        PageBody(title: "오늘의 브리핑") {
            InfoCard { Label("출발 전", systemImage: "sun.horizon").font(.headline); Text(model.output.string("briefing")).font(.system(size: 23)).lineSpacing(7); HStack { Button("읽어주기") { model.speak() }; Spacer(); Button("음성 중지") { model.stopSpeech() } } }
            InfoCard {
                CardTitle(title: "마지막 회차 요약", systemImage: "flag.checkered",
                          info: "저장된 마지막 회차를 기준으로 계산한 요약임. 실시간 주행 값이 아니며, 연결 중 수신한 값만 반영됨.")
                Text(model.state.string("lastBrief"))
            }
        }
    }
}
struct TripsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @State private var period = 30
    @State private var assumedCapacity = 75.0

    private static let shortMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M.d"
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        PageBody(title: "운행 기록") {
            let estimates = model.output.object("energyPeriods").object(String(period))
            let trips = Array(estimates.rows("trips").reversed())
            Picker("기간", selection: $period) { Text("7일").tag(7); Text("30일").tag(30); Text("90일").tag(90); Text("전체").tag(36500) }.pickerStyle(.segmented)

            // Daily briefing
            if !model.output.string("briefing").isEmpty {
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("오늘의 브리핑").font(.headline)
                                Spacer()
                                Button { model.speak() } label: {
                                    Label("읽어주기", systemImage: "speaker.wave.2.fill")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                            Caption(model.output.string("briefing"))
                        }
                    }
                }
            }

            // v34: summary first — the numbers that matter, then a chart, then only the recent runs.
            InfoCard {
                CardTitle(title: "요약", systemImage: "chart.bar.fill")
                HStack {
                    Metric(title: "운행", value: model.output.object("totals").number("trips"))
                    Metric(title: "거리", value: model.output.object("totals").number("distanceKm"), digits: 1, suffix: " km")
                }
                HStack {
                    Metric(title: "주행 전비", value: estimates.number("drivingKmPerKWh"), digits: 2, suffix: " km/kWh")
                    Metric(title: "종합 전비", value: estimates.number("overallKmPerKWh"), digits: 2, suffix: " km/kWh")
                }
                let recentTrips = Array(model.state.rows("trips").suffix(7))
                if !recentTrips.isEmpty {
                    let maxDist = recentTrips.compactMap { $0.number("distanceKm") }.map { units.distanceValue($0) }.max() ?? 10.0
                    let yDomainMax = max(maxDist * 1.45, 25.0)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("최근 운행 거리")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("[단위: \(units.distance)]")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Chart {
                            ForEach(recentTrips, id: \.selfID) { t in
                                let dist = units.distanceValue(t.number("distanceKm") ?? 0)
                                BarMark(
                                    x: .value("운행", t.selfID),
                                    y: .value("거리", dist)
                                )
                                .cornerRadius(6)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.green, Color.teal],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .annotation(position: .top) {
                                    if dist > 0 {
                                        Text(String(format: "%.1f", dist))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color.white.opacity(0.85))
                                            .padding(.bottom, 2)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: recentTrips.map(\.selfID)) { value in
                                if let id = value.as(String.self),
                                   let t = recentTrips.first(where: { $0.selfID == id }) {
                                    let date = Date(timeIntervalSince1970: (t.number("start") ?? 0) / 1000)
                                    AxisValueLabel {
                                        VStack(spacing: 2) {
                                            Text(Self.shortMonthDayFormatter.string(from: date))
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(Color.white.opacity(0.9))
                                            Text(Self.shortTimeFormatter.string(from: date))
                                                .font(.system(size: 8, weight: .regular))
                                                .foregroundStyle(Color.white.opacity(0.55))
                                        }
                                        .fixedSize()
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                    .foregroundStyle(Color.white.opacity(0.12))
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...yDomainMax)
                        .frame(height: 160)
                    }
                    .padding(.top, 6)
                }
            }
            if trips.isEmpty {
                ContentUnavailableView("운행 기록 없음", systemImage: "road.lanes", description: Text("차량에 연결해 실제 이동을 확인하면 기록을 시작함."))
            } else {
                InfoCard {
                    CardTitle(title: "최근 운행", systemImage: "clock.arrow.circlepath")
                    ForEach(trips.prefix(3), id: \.selfID) { trip in
                        HStack(spacing: 4) {
                            TripRow(trip: trip)
                            RecordActions(delete: { model.mutate("deleteTrip", ["id": trip.selfID]) }, title: "운행 기록")
                        }
                    }
                    if trips.count > 3 {
                        NavigationLink { TripListView(trips: trips) } label: {
                            HStack { Text("전체 \(trips.count)건 보기"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            InfoCard {
                CardTitle(title: "전비 계산 설정", systemImage: "slider.horizontal.3")
                Stepper("가정 용량 \(Int(assumedCapacity)) kWh", value: $assumedCapacity, in: 20...200, step: 1)
                HStack {
                    Button("적용") { model.mutate("settings", ["assumedCapacityKWh": assumedCapacity]) }.buttonStyle(.bordered)
                    Spacer()
                    Button("CSV 내보내기") { model.exportCSV() }.buttonStyle(.bordered)
                }
            }
        }.onAppear { assumedCapacity = model.settings.number("assumedCapacityKWh") ?? 75 }
    }
}

/// One line per run: date, distance, efficiency. Details live in the full list.
struct TripRow: View {
    @Environment(\.vehicleUnits) private var units
    let trip: Object
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText(trip.number("start"))).font(.subheadline.weight(.semibold))
                if trip.flag("missing") { Text("일부 구간 미확인").font(.caption2).foregroundStyle(.orange) }
            }
            Spacer(minLength: 4)
            Text(units.format(trip.number("distanceKm"), suffix: " km", digits: 1)).font(.subheadline).monospacedDigit()
            Text(valueText(trip.number("estimatedKmPerKWh"), digits: 2) + " km/kWh")
                .font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
        }
        .frame(minHeight: 40)
    }
}

struct TripListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    let trips: [Object]
    var body: some View {
        PageBody(title: "운행 전체 기록") {
            ForEach(trips, id: \.selfID) { trip in
                InfoCard {
                    HStack {
                        Text(dateText(trip.number("start"))).font(.headline)
                        Spacer()
                        if trip.flag("missing") { Text("일부 구간 미확인").font(.caption).foregroundStyle(.orange) }
                        else if (trip.number("gapSeconds") ?? 0) > 0 { Text("연결 공백 보정").font(.caption).foregroundStyle(Theme.muted) }
                        RecordActions(delete: { model.mutate("deleteTrip", ["id": trip.selfID]) }, title: "운행 기록")
                    }
                    HStack {
                        Metric(title: "거리", value: trip.number("distanceKm"), digits: 1, suffix: " km")
                        Metric(title: "소요시간", value: ((trip.number("end") ?? 0)-(trip.number("start") ?? 0))/60000, suffix: "분")
                    }
                    HStack {
                        Metric(title: "전비 · 추정", value: trip.number("estimatedKmPerKWh"), digits: 2, suffix: " km/kWh")
                        Metric(title: "소비 · 추정", value: trip.number("estimatedKWh"), digits: 2, suffix: " kWh")
                    }
                    HStack(spacing: 6) {
                        Caption("SOC \(valueText(trip.number("startSOC")))% → \(valueText(trip.number("endSOC")))%")
                        Spacer(minLength: 4)
                        InfoNote("이 회차의 관측 근거", tripDetail(trip))
                    }
                }
            }
        }
    }
    private func tripDetail(_ trip: Object) -> String {
        var lines = [trip.string("estimateMethod"),
                     "추정 소비 \(valueText(trip.number("estimateLowKWh"), digits: 2))–\(valueText(trip.number("estimateHighKWh"), digits: 2)) kWh"]
        if let energy = trip.number("observedMotorNetKWh"), let efficiency = trip.number("observedMotorWhPerKm"), let coveredKm = trip.number("observedMotorDistanceKm") {
            lines.append("관측 에너지 \(valueText(energy, digits: 2)) kWh · 관측 전비 \(valueText(efficiency)) Wh/km · 동시 관측 \(valueText(coveredKm, digits: 1)) km")
        } else if let used = trip.number("powerUsedKWh"), let recovered = trip.number("powerRecoveredKWh"), (trip.number("powerSeconds") ?? 0) > 0 {
            lines.append("구동계 순에너지 \(valueText(used - recovered, digits: 2)) kWh")
        } else {
            lines.append("직접 전력 관측 없음 · 추정값 사용")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension Dictionary where Key == String, Value == Any { var selfID: String { string("id") } }

struct BatteryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var add = false
    @State private var editing: Object?
    @State private var days = 30
    /// Receipt-based price per kWh; nil (shown as "—") until a charge with both a cost and a supply figure exists.
    private var averagePrice: Double? {
        let totals = model.output.object("totals")
        guard let cost = totals.number("cost"), let supply = totals.number("supplyKWh"), supply > 0.1, cost > 0 else { return nil }
        return cost / supply
    }
    var body: some View {
        let health = model.output.object("health"), target = model.output.object("target")
        let charges = model.output.object("charging").rows("rows")
        PageBody(title: "배터리·충전") {
            BatteryOverview(index: model.output.object("healthIndex"), usage: model.output.object("battery").object(String(days)), days: $days)
            InfoCard {
                CardTitle(title: "충전 요약", systemImage: "bolt.fill",
                          info: "차량 보고 충전량은 차량이 알려준 저장 에너지이고, 영수증 공급량은 직접 입력한 결제 기준 공급량임. 충전기 손실 때문에 두 값은 다를 수 있음.")
                HStack {
                    Metric(title: "충전 횟수", value: Double(charges.count))
                    Metric(title: "차량 보고", value: model.output.object("totals").number("vehicleReportedKWh"), digits: 1, suffix: " kWh")
                }
                HStack {
                    Metric(title: "영수증 공급", value: model.output.object("totals").number("supplyKWh"), digits: 1, suffix: " kWh")
                    Metric(title: "평균 단가", value: averagePrice, digits: 0, suffix: " 원/kWh")
                }
                Button { add = true } label: { Label("충전 기록 추가", systemImage: "plus.circle").frame(maxWidth: .infinity).frame(minHeight: 44) }
                    .buttonStyle(.bordered)
            }
            InfoCard {
                CardTitle(title: "맞춤 충전 목표", systemImage: "target", info: target.string("note") + "\n\n관측 용량 기준: " + health.string("note"))
                HStack {
                    Metric(title: "권장 충전 목표", value: target.number("targetSOC"), suffix: "%")
                    if let capacity = health.number("capacity") {
                        Metric(title: "관측 유효용량", value: capacity, digits: 1, suffix: " kWh")
                    } else {
                        Metric(title: "선별된 충전 회차", value: health.number("count"))
                    }
                }
                NavigationLink("예정 거리·여유 잔량 설정", value: Page.connection).frame(minHeight: 44)
            }
            if charges.isEmpty {
                ContentUnavailableView("충전 기록 없음", systemImage: "bolt.slash", description: Text("충전을 관측하거나 기록을 추가하면 여기에 쌓임."))
            } else {
                InfoCard {
                    CardTitle(title: "최근 충전", systemImage: "clock.arrow.circlepath",
                              info: "잘못 입력한 기록은 왼쪽으로 밀어 삭제할 수 있음. 삭제하면 용량·단가 계산에서도 제외됨.")
                    ForEach(charges.prefix(3), id: \.selfID) { charge in
                        HStack(spacing: 4) {
                            ChargeRow(charge: charge)
                            RecordActions(edit: { editing = charge }, delete: { model.mutate("deleteCharge", ["id": charge.selfID]) }, title: "충전 기록")
                        }
                    }
                    if charges.count > 3 {
                        NavigationLink { ChargeListView(charges: charges) } label: {
                            HStack { Text("전체 \(charges.count)건 보기"); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
        }.sheet(isPresented: $add) { ChargeForm() }
            .sheet(item: Binding(get: { editing.map(EditableCharge.init) }, set: { editing = $0?.row })) { item in
                ChargeForm(existing: item.row)
            }
    }
}

/// Identifiable wrapper so a charge row can drive a sheet.
struct EditableCharge: Identifiable {
    let row: Object
    var id: String { row.selfID }
}

/// v37: an explicit control on every record row. Swipe actions only exist inside a List, and these rows
/// live in cards, so the row carries its own menu: edit where editing makes sense, delete everywhere.
struct RecordActions: View {
    var edit: (() -> Void)?
    let delete: () -> Void
    let title: String
    @State private var confirming = false
    var body: some View {
        Menu {
            if let edit { Button { edit() } label: { Label("수정", systemImage: "pencil") } }
            Button(role: .destructive) { confirming = true } label: { Label("삭제", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .accessibilityLabel(title + " 편집·삭제")
        .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
            Button("삭제", role: .destructive, action: delete)
        } message: { Text("이 기록을 지우면 관련 통계에서도 제외됨. 되돌릴 수 없음.") }
    }
}

struct ChargeRow: View {
    let charge: Object
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText(charge.number("at"))).font(.subheadline.weight(.semibold))
                Text("\(valueText(charge.number("startSOC")))% → \(valueText(charge.number("endSOC")))%")
                    .font(.caption2).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(valueText(charge.number("supplyKWh") ?? charge.number("vehicleReportedKWh"), digits: 1) + " kWh")
                .font(.subheadline).monospacedDigit()
            if let cost = charge.number("cost") {
                Text(valueText(cost) + "원").font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
        .frame(minHeight: 40)
    }
}

struct ChargeListView: View {
    @EnvironmentObject private var model: AppModel
    let charges: [Object]
    @State private var editing: Object?
    var body: some View {
        PageBody(title: "충전 전체 기록") {
            ForEach(charges, id: \.selfID) { c in
                InfoCard {
                    HStack {
                        Label(dateText(c.number("at")), systemImage: "bolt.fill").font(.headline)
                        Spacer()
                        Caption(c.string("source"))
                        RecordActions(edit: { editing = c }, delete: { model.mutate("deleteCharge", ["id": c.selfID]) }, title: "충전 기록")
                    }
                    HStack {
                        Metric(title: c.number("supplyKWh") != nil ? "영수증 공급" : "차량 보고", value: c.number("supplyKWh") ?? c.number("vehicleReportedKWh"), digits: 1, suffix: " kWh")
                        if let cost = c.number("cost") { Metric(title: "결제액", value: cost, suffix: "원") }
                    }
                    Caption("\(valueText(c.number("startSOC")))% → \(valueText(c.number("endSOC")))% · \(c.flag("active") ? "충전 중" : c.flag("complete") ? "완료" : "부분 관측")")
                }
            }
        }
        .sheet(item: Binding(get: { editing.map(EditableCharge.init) }, set: { editing = $0?.row })) { item in
            ChargeForm(existing: item.row)
        }
    }
}

struct ChargeForm: View {
    /// nil = a new record; otherwise the record being corrected.
    var existing: Object? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var supply = ""
    @State private var cost = ""
    @State private var start = ""
    @State private var end = ""
    @State private var stored = ""
    @State private var place = ""
    @State private var note = ""
    @State private var verified = false
    @State private var complete = false
    @State private var comparable = false
    @State private var picker: PhotosPickerItem?
    var body: some View {
        NavigationStack {
            Form {
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.orange) } }
                Section {
                    PhotosPicker(selection: $picker, matching: .images) {
                        Label(model.receiptText.isEmpty ? "사진에서 자동 입력" : "다른 사진으로 다시 읽기", systemImage: "text.viewfinder").frame(minHeight: 44)
                    }
                    if model.ocrBusy { ProgressView("기기 내 이미지 분석 중") }
                    if !model.receiptText.isEmpty {
                        Label(fillSummary, systemImage: filledFields.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill")
                            .foregroundStyle(filledFields.isEmpty ? .orange : Theme.green).font(.subheadline)
                        if model.receiptDraft.flag("ambiguous") {
                            Text("숫자가 여러 개 보여 가장 큰 값을 넣었음 · 값 확인 필요").font(.caption).foregroundStyle(.orange)
                        }
                        DisclosureGroup("인식 원문 확인") { Text(model.receiptText).font(.caption).textSelection(.enabled) }
                    }
                } header: {
                    HStack { Text("영수증·충전 완료 화면"); Spacer(); InfoNote("사진 자동 입력", "사진 속 글자를 기기 안에서만 읽어 장소·시각·공급량·결제액·시작·종료 SOC·소요시간까지 채움. 항목 라벨이 있는 줄을 우선 사용하므로 영수증에 숫자가 여러 개 있어도 구분함. 누적 사용량 같은 줄은 제외함. 읽히지 않은 칸만 직접 입력하면 됨.") }
                }
                Section("충전 기록") {
                    DatePicker("충전 시각", selection: $date)
                    TextField("장소", text: $place)
                    numberField("공급량 kWh · 영수증", $supply)
                    numberField("결제 금액 원 · 무료는 0", $cost)
                    numberField("시작 SOC %", $start); numberField("종료 SOC %", $end)
                    Toggle("동일 회차의 시작·종료 확인", isOn: $complete)
                    TextField("메모", text: $note, axis: .vertical)
                }
                Section("용량 추정용 · 확인된 자료만") {
                    Toggle("배터리 저장 에너지 자료 확인", isOn: $verified)
                    if verified { numberField("실제 저장량 kWh · 공급량과 다름", $stored); Toggle("다른 회차와 조건 비교 가능", isOn: $comparable) }
                    Text("영수증의 kWh는 일반적으로 공급량임. 저장량으로 확인되지 않은 값은 이 칸에 입력하지 않아야 함.").font(.caption)
                }
            }.scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle(existing == nil ? "충전 기록 추가" : "충전 기록 수정").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") { save() }.disabled(model.ocrBusy) } }
        }.task(id: picker) {
            guard let selected = picker else { return }
            if let data = try? await selected.loadTransferable(type: Data.self), !Task.isCancelled { model.recognize(data) }
        }.onAppear { model.resetReceipt(); loadExisting() }.onDisappear { model.resetReceipt() }
            .onChange(of: model.receiptText) { _, _ in applyReceipt() }
    }

    private var filledFields: [String] { (model.receiptDraft["filled"] as? [Any])?.compactMap { $0 as? String } ?? [] }

    private var fillSummary: String {
        let names = ["place": "장소", "date": "날짜", "time": "시각", "supplyKWh": "공급량", "cost": "결제액",
                     "startSOC": "시작 SOC", "endSOC": "종료 SOC", "unitPrice": "단가", "minutes": "소요시간"]
        let listed = filledFields.compactMap { names[$0] }
        return listed.isEmpty ? "읽을 수 있는 항목을 찾지 못함 · 직접 입력 필요" : "자동 입력 \(listed.count)개: " + listed.joined(separator: ", ")
    }

    /// v35: every field the parser recognised is written into the form, so a photo is enough on its own.
    private func applyReceipt() {
        let draft = model.receiptDraft
        if let value = draft.number("supplyKWh") { supply = trimmed(value) }
        if let value = draft.number("cost") { cost = trimmed(value) }
        if let value = draft.number("startSOC") { start = trimmed(value) }
        if let value = draft.number("endSOC") { end = trimmed(value) }
        if !draft.string("place").isEmpty { place = draft.string("place") }
        if start.isEmpty == false, end.isEmpty == false { complete = true }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let day = draft.string("dateText"), clock = draft.string("timeText")
        if !day.isEmpty {
            formatter.dateFormat = clock.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
            if let parsed = formatter.date(from: clock.isEmpty ? day : day + " " + clock) { date = parsed }
        }
        var notes: [String] = []
        if let minutes = draft.number("minutes") { notes.append("충전 \(Int(minutes))분") }
        if let unit = draft.number("unitPrice") { notes.append("단가 \(Int(unit))원/kWh") }
        if !notes.isEmpty, note.isEmpty { note = notes.joined(separator: " · ") }
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
    private func numberField(_ title: String, _ binding: Binding<String>) -> some View { TextField(title, text: binding).keyboardType(.decimalPad) }

    /// Fills the form from the record being corrected.
    private func loadExisting() {
        guard let row = existing else { return }
        date = Date(timeIntervalSince1970: (row.number("at") ?? 0) / 1000)
        supply = row.number("supplyKWh").map(trimmed) ?? ""
        cost = row.number("cost").map(trimmed) ?? ""
        start = row.number("startSOC").map(trimmed) ?? ""
        end = row.number("endSOC").map(trimmed) ?? ""
        stored = row.number("storedKWh").map(trimmed) ?? ""
        place = row.string("place"); note = row.string("note")
        complete = row.flag("complete"); verified = row.flag("storageVerified"); comparable = row.flag("comparable")
    }
    private func save() {
        do {
            var input: Object = ["at": date.timeIntervalSince1970*1000, "startSOC": try jsonNumber(start), "endSOC": try jsonNumber(end), "supplyKWh": try jsonNumber(supply), "storedKWh": verified ? try jsonNumber(stored) : NSNull(), "cost": try jsonNumber(cost), "place": place, "note": note, "receiptText": model.receiptText, "complete": complete, "storageVerified": verified, "comparable": comparable, "source": model.receiptText.isEmpty ? "manual" : "OCR"]
            model.errorMessage = nil
            if let row = existing { input["id"] = row.selfID; model.mutate("updateCharge", input) } else { model.mutate("addCharge", input) }
            if model.errorMessage == nil { model.receiptText = ""; model.receiptDraft = [:]; dismiss() }
        } catch { model.errorMessage = error.localizedDescription }
    }
}
