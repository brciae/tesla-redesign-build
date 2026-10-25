import SwiftUI
import UIKit

/// Shared production settings content; the simulator exercises this exact panel.
struct LiveActivitySettingsPanel: View {
    var refresh: () -> Void
    @AppStorage("liveActivityEnabled") private var enabled = true
    @AppStorage("navigation.floatingCard") private var floating = true
    @ObservedObject private var pip = NavigationPictureInPicture.shared
    @ObservedObject private var manager = VehicleLiveActivityManager.shared
    var body: some View {
        Section("백그라운드 길안내") {
            Toggle("플로팅 길안내", isOn: $floating).onChange(of: floating) { _, _ in refresh() }
                .accessibilityIdentifier("navigation.floating.enabled")
            Button("플로팅 안내 시작") { refresh(); pip.start() }
            Text(pip.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            Caption("다른 앱 위에 회전·차선·도착 요약 표시. 길안내 종료 시 닫힘.")
        }
        Section("길안내·충전 카드") {
            Toggle("실시간 현황 표시", isOn: $enabled)
                .onChange(of: enabled) { _, _ in refresh() }
            Text(manager.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("실시간 현황 다시 시작") { refresh(); manager.restart() }
            Button("iPhone 앱 설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            InfoRow("표시 방식", "잠금화면에 길안내 또는 충전 상태 표시. 카드를 누르면 해당 화면으로 이동함.")
            Caption("처음에는 앱을 연 상태에서 시작해야 함. iPhone 설정에서 이 앱의 실시간 현황 허용 필요함. 백그라운드 수신이 중단되면 마지막 값 대신 갱신 대기를 표시함.")
            DisclosureGroup("설치·활동 상태") {
                Caption(manager.installationSummary)
                Caption(manager.lifecycle)
                if let at = manager.lastPublishedAt {
                    HStack { Text("최근 갱신"); Spacer(); Text(at, style: .time).monospacedDigit() }.font(.caption)
                }
                Caption("검은 화면만 지속되면 확장 프로그램의 서명·실행 오류 확인 필요함. 활동 활성 표시는 위젯 화면 렌더링 성공을 의미하지 않음.")
            }
        }
    }
}
