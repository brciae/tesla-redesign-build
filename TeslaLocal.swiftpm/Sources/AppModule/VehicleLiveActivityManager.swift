import ActivityKit
import UIKit
import Combine

@MainActor
final class VehicleLiveActivityManager: ObservableObject {
    static let shared = VehicleLiveActivityManager()
    private var activity: Activity<VehicleActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastState: VehicleActivityAttributes.ContentState?
    private var failedUntil = Date.distantPast
    private var updateTask: Task<Void, Never>?
    private var restarting = false
    private var latestInput: VehicleActivityAttributes.ContentState?
    private var latestEnabled = false
    private var foregroundObserver: AnyCancellable?
    private var stateTask: Task<Void, Never>?
    private var trackedID: String?
    private var endingIDs: Set<String> = []
    @Published private(set) var status = "실시간 현황 대기"
    @Published private(set) var lifecycle = "활동 없음"
    @Published private(set) var lastPublishedAt: Date?
    private lazy var extensionBundle: Bundle? = {
        guard let root = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        return urls.filter { $0.pathExtension == "appex" }.compactMap { Bundle(url: $0) }.first {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
                && $0.bundleIdentifier?.hasSuffix(".liveactivity") == true
        }
    }()
    private var installationIssue: String? {
        guard let bundle = extensionBundle else { return "설치된 실시간 현황 확장 프로그램 없음 · 확장을 포함해 재설치 필요" }
        guard bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "앱과 실시간 현황 확장 버전이 다름 · 함께 재설치 필요"
        }
        guard let appID = Bundle.main.bundleIdentifier, bundle.bundleIdentifier?.hasPrefix(appID + ".") == true else {
            return "앱과 실시간 현황 확장 식별자가 다름 · 함께 재서명 필요"
        }
        return nil
    }
    private func track(_ current: Activity<VehicleActivityAttributes>) {
        guard trackedID != current.id else { return }
        stateTask?.cancel(); trackedID = current.id
        recordState(current.activityState)
        stateTask = Task { [weak self] in
            for await state in current.activityStateUpdates {
                guard !Task.isCancelled, let self, self.trackedID == current.id else { return }
                self.recordState(state)
            }
        }
    }
    private func recordState(_ state: ActivityState) {
        switch state {
        case .active: lifecycle = "활동 활성 · 실제 화면 렌더링은 별도 확인"
        case .stale: lifecycle = "갱신 지연"
        case .ended: lifecycle = "활동 종료"
        case .dismissed: lifecycle = "시스템에서 제거됨"
        @unknown default: lifecycle = "활동 상태 확인 필요"
        }
    }
    private init() {
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let state = self.latestInput else { return }
                    self.failedUntil = .distantPast
                    self.update(state, enabled: self.latestEnabled)
                }
            }
    }
    var installationSummary: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let extensionBuild = extensionBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "없음"
        return "앱 \(build) · 위젯 \(extensionBuild) · iOS \(UIDevice.current.systemVersion) · 서명 유효성은 기기 로그로 확인"
    }

    func update(_ state: VehicleActivityAttributes.ContentState, enabled: Bool) {
        latestInput = state; latestEnabled = enabled
        guard !restarting else { return }
        if activity == nil {
            activity = Activity<VehicleActivityAttributes>.activities.first {
                !endingIDs.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale)
            }
        }
        guard enabled else { end(); status = "실시간 현황 꺼짐"; return }
        if let issue = installationIssue { end(); status = issue; return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end(); status = "iPhone 설정에서 실시간 현황 허용 필요"; return
        }
        if let current = activity, current.activityState == .dismissed || current.activityState == .ended {
            activity = nil; lastState = nil
            // Respect the user's dismissal until the next foreground visit.
            guard UIApplication.shared.applicationState == .active else { return }
        }
        let hasSession = state.connected || state.guiding || (state.charging && !state.chargingStale)
        let previouslyGuiding = lastState?.guiding ?? activity?.content.state.guiding ?? false
        let previouslyCharging = lastState?.charging ?? activity?.content.state.charging ?? false
        if VehicleActivitySessionPolicy.shouldEnd(connected: state.connected, guiding: state.guiding,
            previouslyGuiding: previouslyGuiding, observationAge: Date().timeIntervalSince(state.observedAt),
            charging: state.charging, previouslyCharging: previouslyCharging) {
            end(); status = "차량 연결·길안내·충전 시작 후 표시 가능"; return
        }
        guard hasSession || activity != nil else { status = "차량 연결·길안내·충전 시작 후 표시 가능"; return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        // A first request must not wait for an asynchronous restart of an empty activity list.
        if activity != nil, UIApplication.shared.applicationState == .active,
           UserDefaults.standard.string(forKey: "liveActivity.rendererBuild") != build {
            UserDefaults.standard.set(build, forKey: "liveActivity.rendererBuild")
            restart(); return
        }
        let staleAt = !state.guiding && state.charging ? (state.chargeObservedAt ?? .distantPast).addingTimeInterval(120) : state.observedAt.addingTimeInterval(30)
        let content = ActivityContent(state: state, staleDate: staleAt,
                                      relevanceScore: state.guiding ? 100 : state.charging ? 80 : state.connected ? 50 : 0)
        if activity == nil {
            guard UIApplication.shared.applicationState == .active else {
                status = "앱을 열면 실시간 현황 시작"; return
            }
            guard hasSession, Date() >= failedUntil else { return }
            do {
                activity = try Activity.request(attributes: VehicleActivityAttributes(), content: content, pushType: nil)
                if let activity { track(activity) }
                lastUpdate = Date(); lastState = state
                lastPublishedAt = lastUpdate
                UserDefaults.standard.set(build, forKey: "liveActivity.rendererBuild")
                status = "실시간 현황 요청됨 · 화면 표시 별도 확인"
            } catch {
                failedUntil = Date().addingTimeInterval(60)
                status = "실시간 현황 시작 실패: \(error.localizedDescription)"
            }
            return
        }
        let changed = lastState?.connected != state.connected || lastState?.guiding != state.guiding ||
            lastState?.instruction != state.instruction || lastState?.remainingMinutes != state.remainingMinutes ||
            lastState?.destination != state.destination || lastState?.batteryPercent != state.batteryPercent ||
            lastState?.turnSymbol != state.turnSymbol || lastState?.turnMetres != state.turnMetres ||
            lastState?.exitClock != state.exitClock || lastState?.arrivalAt != state.arrivalAt ||
            lastState?.chargeStatus != state.chargeStatus || lastState?.chargeLimit != state.chargeLimit ||
            lastState?.chargerKW != state.chargerKW || lastState?.chargeRemainingMinutes != state.chargeRemainingMinutes
        guard changed || Date().timeIntervalSince(lastUpdate) >= 20 else { return }
        if let activity { track(activity) }
        lastUpdate = Date(); lastState = state
        lastPublishedAt = lastUpdate
        status = "실시간 현황 요청됨 · 화면 표시 별도 확인"
        updateTask?.cancel()
        let current = activity
        updateTask = Task { await current?.update(content) }
    }

    func restart() {
        guard UIApplication.shared.applicationState == .active, !restarting else { return }
        restarting = true; updateTask?.cancel(); updateTask = nil
        let existing = Activity<VehicleActivityAttributes>.activities
        activity = nil; lastState = nil; lastUpdate = .distantPast; failedUntil = .distantPast
        status = "실시간 현황 다시 시작 중"
        if existing.isEmpty {
            restarting = false
            if let state = latestInput { update(state, enabled: latestEnabled) }
            else { status = "차량 연결·길안내·충전 시작 후 표시 가능" }
            return
        }
        Task {
            for current in existing { await current.end(nil, dismissalPolicy: .immediate) }
            restarting = false
            guard let state = latestInput else { status = "차량 연결·길안내·충전 시작 후 표시 가능"; return }
            update(state, enabled: latestEnabled)
        }
    }
    private func end() {
        updateTask?.cancel(); updateTask = nil
        stateTask?.cancel(); stateTask = nil; trackedID = nil; lifecycle = "활동 없음"
        let current = activity
        activity = nil; lastState = nil
        guard let current else { return }
        endingIDs.insert(current.id)
        Task {
            await current.end(nil, dismissalPolicy: .immediate)
            endingIDs.remove(current.id)
        }
    }
}
