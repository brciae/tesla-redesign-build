import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject private var manager = ChargeNotificationManager.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage("notify.charge.start") private var start = true
    @AppStorage("notify.charge.complete") private var complete = true
    @AppStorage("notify.charge.limit") private var limit = true
    @AppStorage("notify.charge.stop") private var stop = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InfoCard {
                    Text(manager.status).font(.headline)
                    if !manager.allowed { Button("알림 받기") { Task { await manager.requestAuthorization() } } }
                    Button("iOS 알림 설정 열기") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) } }
                }
                NavigationLink { AutomationUtilitiesView(title: "출발 알림") } label: { Label("매일 출발 알림", systemImage: "clock") }
                Text("충전 알림").font(.headline).foregroundStyle(.purple)
                VStack(spacing: 20) {
                    Toggle(isOn: $start) { item("충전 시작", "차량이 충전을 시작했을 때") }
                    Toggle(isOn: $complete) { item("충전 완료", "설정한 한도에서 차량이 완료를 보고했을 때") }
                    Toggle(isOn: $limit) { item("목표 잔량 도달", "설정한 충전 한도에 도달했을 때") }
                    Toggle(isOn: $stop) { item("충전 중지·전원 변경", "충전 중 케이블 해제나 중지 상태로 바뀌었을 때") }
                }.disabled(!manager.allowed)
                InfoCard {
                    Button("10초 뒤 시험 알림") { Task { await manager.testNotification() } }.disabled(!manager.allowed)
                    if !manager.lastEvent.isEmpty { Caption(manager.lastEvent) }
                    Caption("시험 알림을 누른 뒤 홈 화면으로 나가거나 화면을 잠가 전달 상태를 확인할 수 있습니다.")
                }
                InfoNote("백그라운드 수신", "예약된 알림은 iOS가 전달합니다. 차량 상태 알림은 BLE 또는 Fleet에서 새 상태가 들어올 때 생성됩니다. 앱이 중단된 동안 원격 상태를 계속 감지하려면 Telemetry 서버와 원격 푸시 연결이 필요합니다.")
            }.padding(20)
        }.background(Theme.bg).navigationTitle("알림 설정").toggleStyle(CompanionToggleStyle())
        .task { await manager.refreshAuthorization() }
        .onChange(of: phase) { _, value in if value == .active { Task { await manager.refreshAuthorization() } } }
    }
    private func item(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(Theme.muted) }
    }
}
