import SwiftUI
import WidgetKit

struct VehicleActivityIcon: View {
    var body: some View {
        Image("IslandAppIcon").resizable().scaledToFit()
            .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("YL Companion")
    }
}

struct VehicleActivitySummary: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    private var connection: String { stale ? "업데이트 대기" : state.connected ? "차량 연결됨" : "재연결 대기" }
    var body: some View {
        HStack(spacing: 12) {
            VehicleActivityIcon()
            VStack(alignment: .leading, spacing: 5) {
                Text(state.guiding ? (state.destination.isEmpty ? "길안내 중" : state.destination) : "YL Companion")
                    .font(.headline).lineLimit(1)
                Text(stale ? "앱을 열어 최신 상태 확인" : state.guiding ? state.instruction : connection)
                    .font(.subheadline).lineLimit(2)
                Label(connection, systemImage: stale ? "clock" : state.connected ? "link" : "link.badge.plus")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                if !stale, let minutes = state.remainingMinutes, state.guiding {
                    Text("\(minutes)분").font(.title3.bold()).monospacedDigit()
                }
                if !stale, let battery = state.batteryPercent {
                    Text("배터리 \(battery)%").font(.caption).monospacedDigit()
                }
            }
        }.padding(14)
    }
}

struct VehicleActivityCompact: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        if stale { Image(systemName: "clock") }
        else if state.guiding, let minutes = state.remainingMinutes {
            Text("\(minutes)분").font(.caption.bold()).monospacedDigit()
        } else { Image(systemName: state.connected ? "link" : "link.badge.plus") }
    }
}
