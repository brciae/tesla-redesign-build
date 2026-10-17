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
    @Published private(set) var status = "실시간 현황 대기"
    var installationSummary: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let path = Bundle.main.builtInPlugInsURL?.appendingPathComponent("VehicleLiveActivity.appex")
        let extensionBundle = path.flatMap { Bundle(url: $0) }
        let extensionBuild = extensionBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "없음"
        return "앱 \(build) · 위젯 \(extensionBuild) · iOS \(UIDevice.current.systemVersion) · 서명 유효성은 기기 로그로 확인"
    }

    func update(_ state: VehicleActivityAttributes.ContentState, enabled: Bool) {
        latestInput = state; latestEnabled = enabled
        guard !restarting else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if enabled, UIApplication.shared.applicationState == .active,
           UserDefaults.standard.string(forKey: "liveActivity.rendererBuild") != build {
            UserDefaults.standard.set(build, forKey: "liveActivity.rendererBuild")
            restart(); return
        }
        if activity == nil {
            activity = Activity<VehicleActivityAttributes>.activities.first {
                $0.activityState == .active || $0.activityState == .stale
            }
        }
        guard enabled else { end(); status = "실시간 현황 꺼짐"; return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end(); status = "iPhone 설정에서 실시간 현황 허용 필요"; return
        }
        if let current = activity, current.activityState == .dismissed || current.activityState == .ended {
            activity = nil; lastState = nil
            // Respect the user's dismissal until the next foreground visit.
            guard UIApplication.shared.applicationState == .active else { return }
        }
        let hasSession = state.connected || state.guiding
        guard hasSession || activity != nil else { status = "차량 연결 또는 길안내 시작 후 표시 가능"; return }
        if !hasSession, Date().timeIntervalSince(state.observedAt) > 90 { end(); return }
        let content = ActivityContent(state: state, staleDate: state.observedAt.addingTimeInterval(30),
                                      relevanceScore: state.guiding ? 100 : state.connected ? 50 : 0)
        if activity == nil {
            guard UIApplication.shared.applicationState == .active, hasSession, Date() >= failedUntil else { return }
            do {
                activity = try Activity.request(attributes: VehicleActivityAttributes(), content: content, pushType: nil)
                lastUpdate = Date(); lastState = state
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
            lastState?.turnSymbol != state.turnSymbol || lastState?.turnMetres != state.turnMetres
        guard changed || Date().timeIntervalSince(lastUpdate) >= 20 else { return }
        lastUpdate = Date(); lastState = state
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
        Task {
            for current in existing { await current.end(nil, dismissalPolicy: .immediate) }
            restarting = false
            guard let state = latestInput else { status = "차량 연결 또는 길안내 시작 후 표시 가능"; return }
            update(state, enabled: latestEnabled)
        }
    }
    private func end() {
        updateTask?.cancel(); updateTask = nil
        let current = activity
        activity = nil; lastState = nil
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }
}
