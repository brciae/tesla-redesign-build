import Foundation
import UserNotifications

/// Manages local push notifications for vehicle charging events (start, complete, limit reached, interrupted).
final class ChargeNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ChargeNotificationManager()

    private var previousChargingState: Int?
    private var previousSOC: Double?
    private var targetLimitNotified = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests notification permissions from the user.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
    }

    /// Evaluates live charge updates and triggers push notifications on state changes.
    func evaluateChargeUpdate(soc: Double?, limit: Double?, charging: Int?, minutesToLimit: Int?) {
        guard let charging else { return }
        let currentSOC = soc ?? 0
        let target = limit ?? 80

        // 1. Charging Started (0 -> 1)
        if (previousChargingState == 0 || previousChargingState == nil) && charging == 1 {
            let minutesText = (minutesToLimit != nil && (minutesToLimit ?? 0) > 0) ? " (완충까지 약 \(minutesToLimit!)분)" : ""
            sendNotification(
                title: "⚡️ 차량 충전 시작",
                body: "배터리 잔량 \(Int(currentSOC))%\(minutesText). 충전이 정상적으로 시작되었습니다."
            )
            targetLimitNotified = false
        }

        // 2. Charging Completed (charging == 2, or SOC reached 100%)
        if (previousChargingState == 1 && charging == 2) || (charging == 1 && currentSOC >= 100 && (previousSOC ?? 0) < 100) {
            sendNotification(
                title: "🔋 배터리 충전 완료",
                body: "배터리 잔량 100%. 완충되었습니다."
            )
        }

        // 3. Target Limit Reached (e.g. reached 80%)
        if charging == 1 && currentSOC >= target && (previousSOC ?? 0) < target && !targetLimitNotified {
            targetLimitNotified = true
            sendNotification(
                title: "🎯 목표 충전량 도달",
                body: "설정한 충전 한도(\(Int(target))%)에 도달했습니다. 현재 배터리 \(Int(currentSOC))%."
            )
        }

        // 4. Charging Interrupted (1 -> 3 or unexpected stop while below target)
        if previousChargingState == 1 && charging == 3 {
            sendNotification(
                title: "⚠️ 충전 중단 경고",
                body: "충전이 비정상적으로 중단되었습니다. 충전기 연결 및 차량 상태를 확인해 주세요."
            )
        }

        previousChargingState = charging
        previousSOC = currentSOC
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "YL.ChargeNotification.\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    // Deliver notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
