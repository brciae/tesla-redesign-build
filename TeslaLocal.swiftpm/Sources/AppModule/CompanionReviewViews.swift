import SwiftUI

struct CompanionReadinessCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var voice: VoiceCoordinator
    @ObservedObject private var notifications = ChargeNotificationManager.shared
    @State private var expanded = false
    private var voiceIssue: String? {
        let d = UserDefaults.standard
        if !d.bool(forKey: "voiceEnabled") { return "음성 안내 꺼짐" }
        if !TypecastClient.shared.isEnabled { return "AI 음성 꺼짐" }
        if d.double(forKey: "voiceVolume") <= 0 { return "브리핑 음량 0 · 음성 설정 확인" }
        if d.bool(forKey: "navVoiceEnabled") && d.double(forKey: "navVoiceVolume") <= 0 { return "길안내 음량 0 · 음성 설정 확인" }
        if TypecastClient.shared.activeApiKey.isEmpty { return "새 음성 생성용 키 미등록" }
        return nil
    }
    private var ready: Bool { let display = homePresentation(model, link); return !model.demo && display.object("drive").string("mode") == "recent" && display.object("charge").string("mode") == "recent" }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Label(link.status, systemImage: "antenna.radiowaves.left.and.right")
                Label(voiceIssue ?? (voice.notice.isEmpty ? voice.playbackState : voice.notice), systemImage: "speaker.wave.2")
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
                    Text(voiceIssue ?? (voice.notice.isEmpty ? "연결 · 안내 소리 · 알림" : voice.notice)).font(.caption).foregroundStyle(.secondary)
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
    private func receptionStatus(_ group: Object, recent: Bool) -> String {
        guard let at = group.number("at"), at > 0,
              !["missing", "invalid"].contains(group.string("mode")) else { return "미수신" }
        if model.demo { return "예시 데이터" }
        return group.string("mode") == "recent" || recent ? "최근 수신" : "저장값"
    }
    var body: some View {
        let presentation = homePresentation(model, link)
        ScrollView {
            VStack(spacing: 16) {
                CompanionSection(title: "차량 데이터", symbol: "antenna.radiowaves.left.and.right") {
                    ForEach(["drive", "charge", "climate", "tire", "location", "closures"], id: \.self) { key in
                        let display = presentation.object(key)
                        let group = display.isEmpty ? model.groups.object(key) : display
                        let status = receptionStatus(group, recent: display.isEmpty && model.output.object("fresh").flag(key))
                        HStack(alignment: .top) {
                            Text(["drive":"주행", "charge":"충전", "climate":"공조", "tire":"타이어", "location":"위치", "closures":"개폐"][key] ?? key)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(status)
                                if !group.string("label").isEmpty && group.string("label") != status { Text(group.string("label")).font(.caption).foregroundStyle(.secondary) }
                                if let at = group.number("at"), at > 0 { Text(dateText(at)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.font(.subheadline)
                    }
                    Text("해당 항목의 관측 시각 기준임. 저장된 주차 위치는 현재 위치 측정과 구분됨.").font(.caption).foregroundStyle(.secondary)
                    if model.demo { Text("예시 데이터 · 실제 차량 수신 상태가 아님").font(.caption).foregroundStyle(.orange) }
                    Button("지금 최신화") { model.refreshVehicle() }.disabled(model.demo || link.controlBusy)
                }
                CompanionSection(title: "안내·연결 복구", symbol: "speaker.wave.2") {
                    Text(voice.notice.isEmpty ? voice.playbackState : voice.notice).font(.subheadline)
                    VoiceStatus(voice: voice)
                    NavigationSourceStatus(navigation: model.navigation)
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
                    NavigationLink { RecordCoverageView() } label: { Text("최근 24시간 수집 관측") }
                    NavigationLink(value: Page.recordSettings) { Text("백업·기록 관리") }
                }
                CompanionSection(title: "데이터 지원 범위", symbol: "sensor") {
                    Text("BLE·Fleet API·NAS는 실제 받은 항목만 표시함. 저장값과 최근 수신을 구분하며, 값이 없는 항목은 정상이나 0으로 가정하지 않음.").font(.caption).foregroundStyle(.secondary)
                    Text("모터·브레이크 온도 등 추가 장치 데이터는 현재 별도 공급원과 호환성이 확인되지 않아 표시하지 않음.").font(.caption).foregroundStyle(.secondary)
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

private struct NavigationSourceStatus: View {
    @ObservedObject var navigation: EmbeddedNavigation
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(navigation.routeSourceSummary).font(.subheadline)
            if navigation.guiding || navigation.busy { Text(navigation.energyDestination).font(.subheadline.bold()) }
            Caption("차량 경로와 앱에서 선택한 경로의 기준을 구분함. 최신 차량 목적지가 바뀌면 현재 경로 정책에 따라 갱신되며, 오래된 경로 패킷은 새 목적지로 취급하지 않음.")
        }
    }
}
