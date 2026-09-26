import Foundation
import UserNotifications
import Combine

@MainActor final class ChargeNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ChargeNotificationManager()
    @Published private(set) var status = "알림 권한 확인 중"
    @Published private(set) var allowed = false
    @Published private(set) var lastEvent = ""
    private var previous: [String: ChargeObservation] = [:]
    private let stateKey = "YL.charge.observations"
    override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["notify.charge.start": true, "notify.charge.complete": true, "notify.charge.limit": true, "notify.charge.stop": true])
        if let data = UserDefaults.standard.data(forKey: stateKey), let saved = try? JSONDecoder().decode([String: ChargeObservation].self, from: data) { previous = saved }
        UNUserNotificationCenter.current().delegate = self
    }
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if allowed {
            status = settings.alertSetting == .enabled ? "시스템 알림 허용" : "알림 허용 · 배너 표시 설정 확인"
        } else { status = settings.authorizationStatus == .denied ? "iOS 설정에서 알림이 꺼져 있습니다" : "알림 받기를 켜 주세요" }
    }
    func requestAuthorization() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await refreshAuthorization() }
        catch { status = "알림 권한 요청 실패: " + error.localizedDescription }
    }
    func observe(_ current: ChargeObservation) {
        let now = Date()
        guard !current.vin.isEmpty, now.timeIntervalSince(current.at) >= -5, now.timeIntervalSince(current.at) <= 120,
              previous[current.vin].map({ current.at > $0.at }) ?? true else { return }
        let event = ChargeEventPolicy.event(previous: previous[current.vin], current: current, now: now)
        previous[current.vin] = current
        if previous.count > 5 { previous = Dictionary(uniqueKeysWithValues: previous.values.sorted { $0.at > $1.at }.prefix(5).map { ($0.vin, $0) }) }
        if let data = try? JSONEncoder().encode(previous) { UserDefaults.standard.set(data, forKey: stateKey) }
        guard let event, UserDefaults.standard.bool(forKey: "notify.charge." + event.kind) else { return }
        Task { await deliver(event, id: "YL.charge.\(current.vin).\(event.kind).\(Int(current.at.timeIntervalSince1970))") }
    }
    private func deliver(_ event: ChargeEvent, id: String, delay: TimeInterval? = nil) async {
        await refreshAuthorization()
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title; content.body = event.body; content.sound = .default
        content.threadIdentifier = "YL.charging"
        content.userInfo = ["destination": "charging"]
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            lastEvent = event.title + " · 알림 센터에 전달됨"
        } catch { status = "알림 등록 실패: " + error.localizedDescription }
    }
    func testNotification() async {
        await deliver(ChargeEvent(kind: "test", title: "알림 동작 확인", body: "이 알림은 시험용입니다. 앱 전환·화면 잠금 상태에서도 표시되는지 확인할 수 있습니다."), id: "YL.notification.test", delay: 10)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .list]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.content.userInfo["destination"] as? String == "charging" {
                UserDefaults.standard.set(true, forKey: "YL.openChargingPending")
                NotificationCenter.default.post(name: Notification.Name("YL.openChargingFromNotification"), object: nil)
            }
            completionHandler()
        }
    }
}
