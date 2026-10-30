import SwiftUI

struct CompanionReadinessCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var voice: VoiceCoordinator
    @ObservedObject private var notifications = ChargeNotificationManager.shared
    @State private var expanded = false
    private var ready: Bool { !model.demo && model.output.object("fresh").flag("drive") && model.output.object("fresh").flag("charge") }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Label(link.status, systemImage: "antenna.radiowaves.left.and.right")
                Label(voice.notice.isEmpty ? voice.playbackState : voice.notice, systemImage: "speaker.wave.2")
                Label(notifications.status, systemImage: notifications.allowed ? "bell" : "bell.slash")
                if model.demo { Text("예시 데이터 · 실제 차량 상태가 아님").foregroundStyle(.orange) }
                NavigationLink { CompanionHealthView(link: link, voice: voice) } label: {
                    Label("수신 상태·문제 해결", systemImage: "checkmark.shield")
                }
            }.font(.subheadline).padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(ready ? Theme.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ready ? "차량 정보 수신 중" : "출발 전 상태 확인").font(.subheadline.bold())
                    Text(voice.notice.isEmpty ? "연결 · 안내 소리 · 알림" : voice.notice).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("home.readiness")
    }
}

struct CompanionHealthView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var voice: VoiceCoordinator
    @ObservedObject private var archive = FleetArchiveClient.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CompanionSection(title: "차량 데이터", symbol: "antenna.radiowaves.left.and.right") {
                    ForEach(["drive", "charge", "climate", "tire", "location", "closures"], id: \.self) { key in
                        let group = model.groups.object(key)
                        HStack(alignment: .top) {
                            Text(["drive":"주행", "charge":"충전", "climate":"공조", "tire":"타이어", "location":"위치", "closures":"개폐"][key] ?? key)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(model.output.object("fresh").flag(key) ? "최근 수신" : group.isEmpty ? "미수신" : "저장값")
                                Text(dateText(group.number("at"))).font(.caption).foregroundStyle(.secondary)
                            }
                        }.font(.subheadline)
                    }
                    Text("해당 항목의 관측 시각 기준임. 저장된 주차 위치는 현재 위치 측정과 구분됨.").font(.caption).foregroundStyle(.secondary)
                    Button("지금 최신화") { model.refreshVehicle() }.disabled(model.demo || link.controlBusy)
                }
                CompanionSection(title: "안내·연결 복구", symbol: "speaker.wave.2") {
                    Text(voice.notice.isEmpty ? voice.playbackState : voice.notice).font(.subheadline)
                    VoiceStatus(voice: voice)
                    NavigationLink(value: Page.preferences) { Text("출력 경로·음량 시험") }
                    NavigationLink(value: Page.connection) { Text("Bluetooth·계정 연결 확인") }
                    NavigationLink(value: Page.notifications) { Text("알림 권한·시험 알림") }
                    NavigationLink(value: Page.liveActivity) { Text("잠금화면·플로팅 상태 확인") }
                }
                CompanionSection(title: "기록 연속성", symbol: "externaldrive") {
                    Text(archive.status).font(.subheadline)
                    LabeledContent("저장된 주행", value: "\(model.state.rows("trips").count)회")
                    LabeledContent("저장된 충전", value: "\(model.state.rows("charges").count)회")
                    if let status = model.storageStatus { Text(status).font(.caption).foregroundStyle(.orange) }
                    Text("앱이 받지 못한 구간은 NAS 수집 상태에 따라 보완됨. 연결됨 표시는 과거 모든 구간의 수집 완료를 뜻하지 않음.").font(.caption).foregroundStyle(.secondary)
                    NavigationLink(value: Page.recordSettings) { Text("백업·기록 관리") }
                }
                CompanionSection(title: "자동 시작 설정", symbol: "bolt.circle") {
                    Text("단축어 → 자동화 → Bluetooth → 차량 연결 시 → 즉시 실행 → YL Companion 조회 재개").font(.subheadline)
                    Caption("조회 재개는 화면을 열지 않고 등록된 차량에 읽기 전용으로 재접속함. 처음 차량 등록·키 승인·재부팅 후 최초 잠금 해제는 별도 필요함. 앱 강제 종료·iOS 실행 제한에서는 자동 수신을 보장하지 않음.").font(.caption).foregroundStyle(.secondary)
                    Text("차량 앱 열기는 화면을 표시하는 별도 단축어임.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Theme.bg).navigationTitle("수신 상태·문제 해결")
    }
}
