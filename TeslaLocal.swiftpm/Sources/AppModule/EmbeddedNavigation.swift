import SwiftUI
import CoreLocation
import Security
import KakaoNavigationBridge

/// No secret in source, defaults, JSON backups, route events or diagnostic messages.
private enum NavigationKey {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "YLCompanion.KakaoNavigation", kSecAttrAccount as String: "nativeAppKey"] }
    static func read() throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(q as CFDictionary, &result)
        if code == errSecItemNotFound { return "" }
        guard code == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw LocalError.message("내비 보안 키 읽기 실패") }
        return key
    }
    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let code = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if code == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LocalError.message("내비 보안 키 저장 실패") }; return
        }
        guard code == errSecSuccess else { throw LocalError.message("내비 보안 키 갱신 실패") }
    }
}

final class EmbeddedNavigation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status = "카카오 내장 내비 · 최초 설정 필요"
    @Published private(set) var hasKey = false
    @Published private(set) var busy = false
    @Published private(set) var guiding = false
    @Published private(set) var directionNotice = ""
    @Published private(set) var controller: YLKakaoController?
    @Published private(set) var telemetry: [String: Any] = [:]
    @Published private(set) var lifecycleDiagnostics: [String] = []
    /// v30: false while the user browses the map; the UI shows a "현위치" button.
    @Published private(set) var following = true
    private var speedSample: (kmh: Double, at: TimeInterval)?
    private var brakeUntil: TimeInterval = 0
    @Published var theme = NavigationTheme(rawValue: UserDefaults.standard.string(forKey: "navigationTheme") ?? "cluster") ?? .cluster {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "navigationTheme") }
    }
    @Published var presented = false
    @Published var enabled = UserDefaults.standard.bool(forKey: "embeddedNavigationEnabled")
    @Published var consent = UserDefaults.standard.bool(forKey: "embeddedNavigationConsent")
    @Published var hipass = UserDefaults.standard.bool(forKey: "navigationHipass")
    @Published var orientation = NavigationDirection(rawValue: UserDefaults.standard.string(forKey: "navigationOrientation") ?? "auto") ?? .auto
    var canPresent: () -> Bool = { UIApplication.shared.applicationState == .active }
    var willStart: (() -> Void)?
    var onVoiceActivity: ((Bool) -> Void)?
    var onSpokenGuide: ((String, Bool) -> Void)?
    var onAudioSession: ((Bool) -> Void)?
    private let runtime: LocalRuntime
    private let locator = CLLocationManager()
    private var deadline: Timer?
    private var candidate: Object?
    private var ticket: Double?
    private var vehicleIdentity = ""
    private var heldOrientation = false
    private var previousIdleTimer = false
    /// v29: transient Kakao/GPS failures retry automatically (bounded) instead of blocking the destination.
    private var startFailures = 0
    private var lastTelemetry: [String: Any] = [:]
    private weak var navigationScene: UIWindowScene?
    var ownsAudio: Bool { busy || guiding || controller != nil }
    var bundleID: String { Bundle.main.bundleIdentifier ?? "확인 불가" }
    init(runtime: LocalRuntime) {
        self.runtime = runtime
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locator.activityType = .automotiveNavigation
        locator.pausesLocationUpdatesAutomatically = false
        NavigationOrientation.failure = { [weak self] message in self?.directionNotice = message }
        do { hasKey = !(try NavigationKey.read()).isEmpty; if hasKey { status = "최신 차량 목적지 대기" } }
        catch { status = error.localizedDescription }
    }
    private func gate(_ action: String, _ values: Object = [:]) -> Any? {
        var args = values; args["action"] = action
        do { return try runtime.call("navGate", args) }
        catch { status = "내비 상태 처리 실패 · 안내 중단"; return nil }
    }
    private func current(_ value: Double) -> Bool { ticket == value && (gate("check", ["ticket": value]) as? Bool == true) }
    func saveSetup(key: String) {
        do {
            let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                guard clean.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else { throw LocalError.message("32자리 Native App Key 확인 필요 · REST API 키가 아님") }
                let old = try NavigationKey.read()
                if clean != old { stop(); try NavigationKey.save(clean) }
                hasKey = true
            }
            guard !enabled || (hasKey && consent) else { throw LocalError.message("앱 키 저장 및 카카오 위치·목적지 전달 동의 필요") }
            UserDefaults.standard.set(enabled, forKey: "embeddedNavigationEnabled")
            UserDefaults.standard.set(consent, forKey: "embeddedNavigationConsent")
            UserDefaults.standard.set(hipass, forKey: "navigationHipass")
            if !enabled || !consent { stop(); status = "자동 내장 길안내 꺼짐"; return }
            status = "설정 저장됨 · 새 차량 목적지 수신 후 자동 시작"
            if locator.authorizationStatus == .notDetermined { locator.requestWhenInUseAuthorization() }
        } catch { status = error.localizedDescription }
    }
    func applyAudioPreferences() {
        let d = UserDefaults.standard
        controller?.configureVoice(enabled: d.bool(forKey: "navVoiceEnabled"), safety: d.bool(forKey: "navSafetyVoice"), volume: Float(d.double(forKey: "navVoiceVolume")), duck: d.bool(forKey: "voiceDuck"))
        // 0 brief · 1 normal · 2 everything. Defaults to brief when the key was never written.
        controller?.configureVoiceDetail(d.object(forKey: "navVoiceDetail") == nil ? 0 : d.integer(forKey: "navVoiceDetail"))
    }
    func setDirection(_ value: NavigationDirection) {
        directionNotice = ""
        orientation = value; UserDefaults.standard.set(value.rawValue, forKey: "navigationOrientation")
        if heldOrientation { NavigationOrientation.apply(value.mask, scene: navigationScene) }
    }
    func observe(_ event: Object, vin: String) {
        if vehicleIdentity != vin { reset(); vehicleIdentity = vin }
        let auth = locator.authorizationStatus
        let ready = enabled && consent && hasKey && (auth == .authorizedAlways || auth == .authorizedWhenInUse) && canPresent()
        guard let decision = gate("observe", ["event": event, "ready": ready, "guiding": guiding || busy]) as? Object else { return }
        let stamp = Date().formatted(date: .omitted, time: .standard)
        lifecycleDiagnostics.append("\(stamp) · 수신 \(event.string("type")) → \(decision.string("type")) · 안내 \(guiding ? "중" : "꺼짐")")
        if decision.string("type") == "refresh" || decision.string("type") == "wait", lifecycleDiagnostics.last?.hasSuffix(decision.string("type") + " · 안내 \(guiding ? "중" : "꺼짐")") == true { lifecycleDiagnostics.removeLast() }
        if lifecycleDiagnostics.count > 24 { lifecycleDiagnostics.removeFirst(lifecycleDiagnostics.count - 24) }
        if decision.string("type") == "clear" || decision.string("type") == "cancel" {
            stopNative(); status = "차량 활성 목적지 없음"; return
        }
        if decision.string("type") == "refresh" {
            candidate = decision
            return
        }
        if event.string("type") == "route", !ready, !ownsAudio {
            status = !hasKey ? "카카오 Native App Key 등록 필요" : (!consent || !enabled ? "내장 내비 설정·동의 필요" : "위치 권한 또는 화면 준비 대기")
        }
        guard decision.string("type") == "start", let next = decision.number("ticket") else { return }
        stopNative(keepDisplay: presented) // A changed route stays inside the same driving workspace.
        ticket = next; candidate = decision; busy = true; status = "현재 GPS 위치 확인 중"
        willStart?()
        locator.startUpdatingLocation()
        deadline = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.failed("정확한 현재 위치를 받지 못함 · 야외에서 위치 권한·GPS 확인", ticket: next) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            stop(); status = "위치 권한 거부됨 · iOS 설정에서 허용 필요"
        }
        // New authenticated vehicle snapshots, not cached coordinates, trigger startup.
    }
    /// v29: while guidance runs, keep our own location session alive so iOS keeps the process running
    /// when the screen is locked or another app is in front (BLE polling timers + Kakao engine keep working).
    private func holdBackgroundLocation(_ on: Bool) {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard modes.contains("location") else { return }
        locator.allowsBackgroundLocationUpdates = on
        locator.showsBackgroundLocationIndicator = on
        if on { locator.startUpdatingLocation() } else { locator.stopUpdatingLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard busy, controller == nil, let candidate, let ticket, current(ticket), canPresent(), let point = locations.last else { return }
        guard let receivedAt = candidate.number("receivedAt"), Date().timeIntervalSince1970 * 1000 - receivedAt <= 30000 else {
            failed("목적지 수신 후 시간이 지남 · 최신 목적지로 다시 시도 필요", ticket: ticket); return
        }
        let age = Date().timeIntervalSince(point.timestamp)
        guard age >= 0, age <= 15, point.horizontalAccuracy >= 0, point.horizontalAccuracy <= 100,
              CLLocationCoordinate2DIsValid(point.coordinate), let lat = candidate.number("latitude"), let lng = candidate.number("longitude") else { return }
        deadline?.invalidate()
        holdBackgroundLocation(true)
        do {
            let key = try NavigationKey.read()
            guard !key.isEmpty else { throw LocalError.message("내비 키 없음") }
            let view = YLKakaoController()
            controller = view; status = "카카오 경로 탐색 중"
            applyAudioPreferences()
            view.eventHandler = { [weak self, weak view] event, message in
                let handle = {
                    guard let self, let view, self.controller === view, self.current(ticket) else { return }
                    if event == "audioAcquired" { self.onAudioSession?(true); return }
                    if event == "spokenGuide" || event == "spokenSafety" { self.onSpokenGuide?(message, event == "spokenSafety"); return }
                    if event == "voiceStart" || event == "voiceEnd" { return } // SDK never plays audio (v30)
                    if event == "follow" { self.following = message == "1"; return }
                    if event == "visible" {
                        self.navigationScene = view.view.window?.windowScene
                        NavigationOrientation.apply(self.orientation.mask, scene: self.navigationScene); return
                    }
                    if event == "error" { self.failed(message, ticket: ticket); return }
                    if event == "ended" { self.stop(); return }
                    if event == "ready" || event == "started" {
                        // v29: a start that completes under the lock screen keeps running; UI appears on return.
                        if UIApplication.shared.applicationState == .active { self.presented = true }
                    }
                    if event == "started" { self.busy = false; self.guiding = true; self.startFailures = 0; self.deadline?.invalidate(); self.holdBackgroundLocation(true) }
                    if !self.guiding || event != "ready" { self.status = message }
                }
                if Thread.isMainThread { handle() } else { DispatchQueue.main.async(execute: handle) }
            }
            view.telemetryHandler = { [weak self, weak view] snapshot in
                let handle = {
                    guard let self, let view, self.controller === view, self.current(ticket) else { return }
                    // v29: never blank the dashboard on an empty/partial tick; merge over the last good snapshot.
                    if snapshot.isEmpty { return }
                    var merged = self.lastTelemetry
                    snapshot.forEach { merged[$0.key] = $0.value }
                    // Position-dependent keys and route guidance must be cleared when not present in current snapshot
                    for key in ["turnMetres", "nextTurn", "nextSymbol", "nextMetres", "nextExitClock", "speedLimit", "speedLimitMetres", "routeBend", "motionValid", "gpsSpeedKmh", "laneCount", "laneSuggested", "laneMetres", "laneRaw", "routePath"] where snapshot[key] == nil {
                        merged.removeValue(forKey: key)
                    }
                    if snapshot["turn"] == nil {
                        merged.removeValue(forKey: "turn")
                        merged.removeValue(forKey: "symbol")
                        merged.removeValue(forKey: "highway")
                        merged.removeValue(forKey: "exitClock")
                    }
                    if !self.guiding {
                        merged.removeValue(forKey: "remainMetres")
                        merged.removeValue(forKey: "remainSeconds")
                        merged.removeValue(forKey: "routeTotalMetres")
                    }
                    if let remain = merged["remainMetres"] as? Double, remain.isFinite, remain >= 0 {
                        merged["routeTotalMetres"] = max(remain, merged["routeTotalMetres"] as? Double ?? 0)
                    }
                    // Brake-light cue from phone GPS speed: a clear deceleration (≥ 1.8 km/h per s) or standing still.
                    let now = Date().timeIntervalSince1970
                    if let kmh = merged["gpsSpeedKmh"] as? Double, kmh.isFinite {
                        if let last = self.speedSample, now - last.at >= 0.4, now - last.at <= 4 {
                            if (last.kmh - kmh) / (now - last.at) >= 1.8 { self.brakeUntil = now + 1.4 }
                        }
                        if self.speedSample == nil || now - (self.speedSample?.at ?? 0) >= 0.4 { self.speedSample = (kmh, now) }
                        merged["braking"] = now < self.brakeUntil || kmh < 1
                    } else { merged["braking"] = now < self.brakeUntil }
                    if let follow = merged["following"] as? Bool, follow != self.following { self.following = follow }
                    self.lastTelemetry = merged
                    self.telemetry = merged
                }
                if Thread.isMainThread { handle() } else { DispatchQueue.main.async(execute: handle) }
            }
            deadline = Timer.scheduledTimer(withTimeInterval: 35, repeats: false) { [weak self] _ in self?.failed("카카오 길안내 시작 응답 지연 · 자동 재시도 중단됨", ticket: ticket) }
            view.prepare(appKey: key, latitude: point.coordinate.latitude, longitude: point.coordinate.longitude,
                         destinationLatitude: lat, destinationLongitude: lng, name: candidate.string("name"), hipass: hipass, validUntil: Date().timeIntervalSince1970 + 60)
        } catch { failed("내비 보안 키 읽기 실패", ticket: ticket) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        if let ticket { failed("현재 위치 조회 실패 · 위치 권한·GPS 확인", ticket: ticket) }
    }
    private func failed(_ message: String, ticket: Double) {
        guard current(ticket) else { return }
        startFailures += 1
        let auth = message.contains("인증") || message.contains("앱 키") || message.contains("권한")
        if auth || startFailures >= 3 {
            _ = gate("finish", ["ticket": ticket]); stopNative(); status = message + (auth ? "" : " · 3회 실패로 자동 재시도 중단")
        } else {
            // Unblocked cancel: the next authenticated vehicle snapshot restarts guidance.
            _ = gate("cancel", ["block": false]); stopNative(keepDisplay: presented)
            status = message + " · 다음 차량 수신 시 자동 재시도 (\(startFailures)/3)"
        }
    }
    private func stopNative(keepDisplay: Bool = false) {
        deadline?.invalidate(); deadline = nil; locator.stopUpdatingLocation()
        controller?.eventHandler = nil; controller?.telemetryHandler = nil; controller?.stopNavigation(); controller = nil
        telemetry = [:]; lastTelemetry = [:]; following = true; speedSample = nil; brakeUntil = 0
        holdBackgroundLocation(false)
        onVoiceActivity?(false); onAudioSession?(false)
        busy = false; guiding = false; candidate = nil; ticket = nil
        if !keepDisplay { presented = false }
    }
    func stop() { _ = gate("cancel"); stopNative(); status = "길안내 종료됨 · 같은 목적지는 직접 재시도 전까지 유지" }
    func retry() { if !ownsAudio { startFailures = 0; _ = gate("retry"); status = "최신 차량 목적지 다시 수신 중" } }
    func reset() { startFailures = 0; _ = gate("reset"); stopNative(); status = "최신 차량 목적지 대기" }
    /// v29: returning to the foreground re-shows guidance that started or continued under the lock screen.
    func foregrounded() { if guiding, controller != nil { presented = true } }
    /// v30: return the map camera to the car after manual browsing.
    func recenter() { controller?.recenter(); following = true }
    func suspendPending() {
        // Established GPS navigation survives BLE loss/background; pending startup does not.
        if !guiding { _ = gate("cancel", ["block": false]); stopNative() }
    }
    func screenAppeared() {
        if !heldOrientation { previousIdleTimer = UIApplication.shared.isIdleTimerDisabled }
        heldOrientation = true
        navigationScene = controller?.view.window?.windowScene
        NavigationOrientation.apply(orientation.mask, scene: navigationScene)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func screenDisappeared() {
        guard heldOrientation else { return }
        heldOrientation = false; NavigationOrientation.apply(.all, scene: navigationScene)
        navigationScene = nil; UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
    }
}

/// Map + a Kakao-style "현위치" button while the user browses the map.
struct KakaoMapPanel: View {
    @ObservedObject var navigation: EmbeddedNavigation
    let controller: YLKakaoController
    var theme: NavigationTheme
    var anchorX: Double
    var anchorY: Double
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            KakaoMapSurface(controller: controller, theme: theme, anchorX: anchorX, anchorY: anchorY)
            if !navigation.following {
                Button { navigation.recenter() } label: {
                    Label("현위치", systemImage: "location.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityIdentifier("map.recenter")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: navigation.following)
    }
}

struct KakaoMapSurface: UIViewControllerRepresentable {
    let controller: YLKakaoController
    var theme: NavigationTheme = .cluster
    var anchorX: Double = 0.52
    var anchorY: Double = 0.72
    func makeUIViewController(context: Context) -> YLKakaoController { controller }
    func updateUIViewController(_ controller: YLKakaoController, context: Context) { controller.configureMapAnchor(x: anchorX, y: anchorY); controller.configureMapTheme(theme.rawValue) }
}
struct EmbeddedNavigationScreen: View {
    @ObservedObject var navigation: EmbeddedNavigation
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(navigation.guiding ? "카카오 길안내" : "안내 준비 중").font(.headline)
                Spacer()
                DirectionPicker(navigation: navigation).frame(maxWidth: 240)
                Button("종료", role: .destructive) { navigation.stop() }.padding(.leading, 8)
            }.padding(12).background(Theme.bg)
            if !navigation.directionNotice.isEmpty { Text(navigation.directionNotice).font(.caption).padding(6).accessibilityLabel(navigation.directionNotice) }
            if let controller = navigation.controller { KakaoMapPanel(navigation: navigation, controller: controller, theme: .cluster, anchorX: 0.52, anchorY: 0.72) }
            else { ContentUnavailableView("길안내 종료됨", systemImage: "map") }
        }
        .background(Theme.bg).interactiveDismissDisabled()
        .onAppear { navigation.screenAppeared() }
        .onDisappear { navigation.screenDisappeared() }
    }
}
struct DirectionPicker: View {
    @ObservedObject var navigation: EmbeddedNavigation
    var body: some View {
        Picker("내비 화면 방향", selection: Binding(get: { navigation.orientation }, set: { navigation.setDirection($0) })) {
            ForEach(NavigationDirection.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).accessibilityLabel("내비 화면 방향")
    }
}
struct NavigationSetupView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var navigation: EmbeddedNavigation
    @AppStorage("handOffToNaver") private var handOffToNaver = false
    @State private var nativeKey = ""
    var body: some View {
        PageBody(title: "길안내") {
            // v39: an honest route to a licensed celebrity guidance voice. This app cannot synthesise a
            // real person's voice, but Naver Map already ships those voices, so the destination can be
            // handed to it and Naver speaks the turns.
            InfoCard {
                CardTitle(title: "외부 내비게이션으로 목적지 전송", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                HStack(spacing: 10) {
                    Button { model.openInTMap() } label: {
                        Label("티맵", systemImage: "arrow.turn.up.right").frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.bordered).disabled(model.demo)
                    
                    Button { model.openInNaverMap() } label: {
                        Label("네이버 지도", systemImage: "paperplane.fill").frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.bordered).disabled(model.demo)
                }
                Toggle("새 목적지를 받으면 자동으로 네이버 지도로 넘기기", isOn: $handOffToNaver)
            }
            InfoCard {
                Label("앱 안에서 바로 길안내", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.title3)
                Text(navigation.status)
                if navigation.guiding { Button("진행 중인 내비 보기") { navigation.presented = true } }
                Button("최신 목적지로 다시 시도") { navigation.retry(); model.refreshVehicle() }.disabled(navigation.ownsAudio || model.demo)
                Button {
                    navigation.presented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "car.fill")
                        Text("운전 대시보드 열기")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(red: 0.15, green: 0.45, blue: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            InfoCard {
                Text("화면 방향").font(.headline)
                DirectionPicker(navigation: navigation)
                if !navigation.directionNotice.isEmpty { Caption(navigation.directionNotice) }
            }
            InfoCard {
                Text("카카오 SDK 설정").font(.headline)
                Text(navigation.bundleID).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                SecureField(navigation.hasKey ? "키 저장됨 · 변경할 때만 입력" : "Native App Key", text: $nativeKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("카카오에 현재 GPS·목적지 전달 동의", isOn: $navigation.consent)
                Toggle("경로 선택 시 내비모드 자동 켜기", isOn: $navigation.enabled)
                Toggle("하이패스 사용", isOn: $navigation.hipass)
                Button("설정 저장") { navigation.saveSetup(key: nativeKey); nativeKey = ""; model.refreshVehicle() }
            }
        }
        .onChange(of: navigation.consent) { _, value in if !value { navigation.stop(); UserDefaults.standard.set(false, forKey: "embeddedNavigationConsent") } }
        .onChange(of: navigation.enabled) { _, value in if !value { navigation.stop(); UserDefaults.standard.set(false, forKey: "embeddedNavigationEnabled") } }
    }
}