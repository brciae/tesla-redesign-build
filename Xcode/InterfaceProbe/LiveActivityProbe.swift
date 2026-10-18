import SwiftUI
import ActivityKit

/// Uses the production ActivityKit manager and installed widget, not an in-app card preview.
struct SystemActivityProbe: View {
    @State private var charge = ProcessInfo.processInfo.arguments.contains("system-charging-probe")
    @State private var ended = false
    @State private var stale = false
    @State private var progress = false
    @ObservedObject private var manager = VehicleLiveActivityManager.shared
    private var state: VehicleActivityAttributes.ContentState {
        let at = Date().addingTimeInterval(stale ? -180 : 0)
        return .init(connected: false, guiding: !charge && !ended, destination: "고등기술연구원",
            instruction: "오크밸리1길 우회전", remainingMinutes: 15, batteryPercent: progress ? 62 : 60,
            observedAt: at, turnSymbol: "arrow.turn.up.right", turnMetres: progress ? 200 : 300,
            arrivalAt: at.addingTimeInterval(900), chargeStatus: charge && !ended ? "Charging" : "Stopped",
            chargeObservedAt: at, chargeLimit: 80, chargerKW: 7.2, chargeRemainingMinutes: progress ? 100 : 120)
    }
    var body: some View {
        VStack(spacing: 22) {
            Text(charge ? "충전 시스템 카드 시험" : "길안내 시스템 카드 시험")
            Text(manager.status).accessibilityIdentifier("system.activity.status")
            Button("상태 갱신") { progress = true; publish() }
            Button("수신 지연") { stale = true; publish() }
            Button("세션 종료") { ended = true; publish() }
        }.padding().onAppear { publish() }
    }
    private func publish() { manager.update(state, enabled: true) }
}

struct CopyReadabilityProbe: View {
    @State private var addresses = false
    private let note = "주행·충전 기록을 바탕으로 계산한 참고값임. " + String(repeating: "계산 근거와 누락 항목은 상세 기록에서 확인할 수 있음. ", count: 12) + "상세 설명 끝."
    var body: some View {
        VStack(spacing: 16) {
            Button(addresses ? "설명 보기" : "긴 주소 보기") { addresses.toggle() }
            if addresses {
                NavigationLandingPanel(guiding: false, recent: [.init(name: "힐스테이트 용인둔전역 아파트 정문",
                    address: "경기도 용인시 처인구 포곡읍 둔전리 힐스테이트 용인둔전역 아파트 단지 정문 주차장 입구",
                    latitude: 37.3, longitude: 127.2)], search: {}, dashboard: {}, charging: {}, naver: {}, tmap: {}, select: { _ in })
            } else {
                Text("기록 요약").font(.title2)
                Caption("최근 20회 주행 기준")
                Caption(note)
                InfoNote("계산 근거", note)
                Spacer()
            }
        }.padding(16)
    }
}

struct LockScreenNavigationProbe: View {
    @State private var state = VehicleActivityAttributes.ContentState(connected: false, guiding: true,
        destination: "힐스테이트 용인둔전역 아파트 정문", instruction: "회전교차로에서 9시 방향 출구로 진출",
        remainingMinutes: 18, batteryPercent: nil, observedAt: Date(),
        turnSymbol: "arrow.triangle.2.circlepath", turnMetres: 2400,
        arrivalAt: Date().addingTimeInterval(1080), exitClock: 9)
    @State private var stale = false
    @ObservedObject private var manager = VehicleLiveActivityManager.shared
    var body: some View {
        VStack(spacing: 18) {
            Text("잠금화면 길안내 카드").font(.headline)
            if state.guiding {
                VehicleNavigationCard(state: state, stale: stale)
                    .environment(\.colorScheme, .light)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
            } else { Text("길안내 종료됨").accessibilityIdentifier("live.navigation.ended") }
            Button("차량 없이 카드 시작") { publish() }
            Button("다음 안내 수신") {
                state.instruction = "오크밸리1길 우회전"; state.turnSymbol = "arrow.turn.up.right"
                state.turnMetres = 300; state.remainingMinutes = 15; state.exitClock = nil
                state.arrivalAt = Date().addingTimeInterval(900); stale = false; publish()
            }
            Button("위치 수신 중단") {
                stale = true; state.observedAt = Date().addingTimeInterval(-60)
                manager.update(state, enabled: true)
            }
            Button("안내 종료") { state.guiding = false; manager.update(state, enabled: true) }
            Text(manager.status).font(.caption).accessibilityIdentifier("live.navigation.status")
            Text("실제 잠금화면과 동일한 뷰·상태를 사용하는 화면 검증용 예시")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
    private func publish() {
        state.observedAt = Date(); manager.update(state, enabled: true)
    }
}

struct LiveActivityProbe: View {
    private let state = VehicleActivityAttributes.ContentState(connected: true, guiding: true,
        destination: "고등기술연구원", instruction: "300미터 앞 우회전", remainingMinutes: 18,
        batteryPercent: 72, observedAt: Date(), turnSymbol: "arrow.turn.up.right", turnMetres: 300)
    @ObservedObject private var manager = VehicleLiveActivityManager.shared
    @State private var gain = 1.0
    var body: some View {
        VStack(spacing: 14) {
            Text("실시간 현황 표시 검증").font(.title2)
            HStack { VehicleActivityIcon(); Spacer(); VehicleActivityCompact(state: state) }
                .padding().background(.black, in: Capsule()).frame(width: 230)
            HStack { Text("음악과 동시 표시"); VehicleActivityMinimal(state: state) }
            VehicleActivitySummary(state: state).background(.black, in: RoundedRectangle(cornerRadius: 24))
            VehicleActivitySummary(state: state, stale: true).background(.black, in: RoundedRectangle(cornerRadius: 24))
            Text("실제 Dynamic Island 표시와 별도인 공통 뷰 검증")
                .font(.caption).foregroundStyle(.secondary)
            VoiceVolumeControl(title: "길안내 음량", value: $gain)
            Button("실제 실시간 현황 시작") {
                var current = state; current.observedAt = Date(); manager.update(current, enabled: true)
            }
            Button("음악 동시 표시 시험") {
                var current = state; current.observedAt = Date(); current.turnMetres = 280
                manager.update(current, enabled: true)
                UIApplication.shared.open(URL(string: "http://127.0.0.1:18757/music.html")!)
            }
            Text(manager.status).accessibilityIdentifier("live.activity.status")
            Button("실시간 현황 다시 시작") { manager.restart() }
        }.padding().accessibilityElement(children: .contain)
    }
}

struct TrafficRefreshProbe: View {
    @State private var refreshing = false
    @State private var status = "기존 경로 안내 중"
    var body: some View {
        VStack(spacing: 20) {
            Text("기존 경로 A")
            NavigationTrafficRefreshButton(enabled: true, refreshing: refreshing) {
                refreshing = true; status = "재탐색 중"
            }
            Text(status)
            if refreshing {
                Button("응답 실패") { refreshing = false; status = "갱신 지연 · 기존 경로 유지" }
            }
        }.padding()
    }
}
