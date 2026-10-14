import SwiftUI
import ActivityKit

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
