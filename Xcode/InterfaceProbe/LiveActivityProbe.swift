import SwiftUI

struct LiveActivityProbe: View {
    private let state = VehicleActivityAttributes.ContentState(connected: true, guiding: true,
        destination: "고등기술연구원", instruction: "300미터 앞 우회전", remainingMinutes: 18,
        batteryPercent: 72, observedAt: Date())
    var body: some View {
        VStack(spacing: 24) {
            Text("실시간 현황 표시 검증").font(.title2)
            HStack { VehicleActivityIcon(); Spacer(); VehicleActivityCompact(state: state) }
                .padding().background(.black, in: Capsule()).frame(width: 230)
            VehicleActivitySummary(state: state).background(.black, in: RoundedRectangle(cornerRadius: 24))
            VehicleActivitySummary(state: state, stale: true).background(.black, in: RoundedRectangle(cornerRadius: 24))
            Text("실제 Dynamic Island 표시와 별도인 공통 뷰 검증")
                .font(.caption).foregroundStyle(.secondary)
        }.padding().accessibilityIdentifier("live.activity.preview")
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
