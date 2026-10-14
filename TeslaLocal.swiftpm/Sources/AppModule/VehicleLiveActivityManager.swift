import ActivityKit
import UIKit

@MainActor
final class VehicleLiveActivityManager {
    static let shared = VehicleLiveActivityManager()
    private var activity: Activity<VehicleActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastState: VehicleActivityAttributes.ContentState?
    private var failedUntil = Date.distantPast
    private var updateTask: Task<Void, Never>?

    func update(_ state: VehicleActivityAttributes.ContentState, enabled: Bool) {
        if activity == nil {
            activity = Activity<VehicleActivityAttributes>.activities.first {
                $0.activityState == .active || $0.activityState == .stale
            }
        }
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { end(); return }
        if let current = activity, current.activityState == .dismissed || current.activityState == .ended {
            activity = nil; lastState = nil
            // Respect the user's dismissal until the next foreground visit.
            guard UIApplication.shared.applicationState == .active else { return }
        }
        let hasSession = state.connected || state.guiding
        guard hasSession || activity != nil else { return }
        if !hasSession, Date().timeIntervalSince(state.observedAt) > 90 { end(); return }
        let content = ActivityContent(state: state, staleDate: state.observedAt.addingTimeInterval(30))
        if activity == nil {
            guard UIApplication.shared.applicationState == .active, hasSession, Date() >= failedUntil else { return }
            do {
                activity = try Activity.request(attributes: VehicleActivityAttributes(), content: content, pushType: nil)
                lastUpdate = Date(); lastState = state
            } catch { failedUntil = Date().addingTimeInterval(60) }
            return
        }
        let changed = lastState?.connected != state.connected || lastState?.guiding != state.guiding ||
            lastState?.instruction != state.instruction || lastState?.remainingMinutes != state.remainingMinutes ||
            lastState?.destination != state.destination || lastState?.batteryPercent != state.batteryPercent
        guard changed || Date().timeIntervalSince(lastUpdate) >= 20 else { return }
        lastUpdate = Date(); lastState = state
        updateTask?.cancel()
        let current = activity
        updateTask = Task { await current?.update(content) }
    }

    private func end() {
        updateTask?.cancel(); updateTask = nil
        let current = activity
        activity = nil; lastState = nil
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }
}
