import SwiftUI
import WidgetKit

struct VehicleActivityIcon: View {
    var body: some View {
        Image("IslandAppIcon").renderingMode(.original).resizable().scaledToFit()
            .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
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

/// Dedicated Lock Screen presentation. Vehicle connectivity is independent of phone guidance.
struct VehicleNavigationCard: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    private func distance(_ metres: Int) -> String {
        metres >= 1000 ? String(format: "%.1f km", Double(metres) / 1000) : "\(metres) m"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                VehicleActivityIcon()
                Text("길안내").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if !stale, let arrival = state.arrivalAt {
                    HStack(spacing: 3) {
                        Text(arrival, style: .time).monospacedDigit()
                        Text("도착")
                    }.font(.caption).foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("live.navigation.arrival")
                }
            }
            HStack(spacing: 14) {
                Image(systemName: stale ? "location.slash" : state.turnSymbol ?? "location.fill")
                    .font(.system(size: 34, weight: .bold)).frame(width: 46)
                    .accessibilityLabel(stale ? "위치 갱신 대기" : "다음 진행 방향")
                VStack(alignment: .leading, spacing: 2) {
                    if !stale, let metres = state.turnMetres {
                        Text(distance(metres)).font(.system(size: 28, weight: .bold)).monospacedDigit()
                            .accessibilityIdentifier("live.navigation.distance")
                    }
                    GuidanceCardLabel(text: stale ? "길안내 업데이트 대기" : state.instruction,
                                      symbol: state.turnSymbol ?? "", exitClock: state.exitClock ?? 0)
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("live.navigation.instruction")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14).foregroundStyle(.black)
        .accessibilityElement(children: .contain)
    }
}

struct VehicleActivityCompact: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        if stale { Image(systemName: "clock") }
        else if state.guiding {
            HStack(spacing: 3) {
                Image(systemName: state.turnSymbol ?? "location.fill").foregroundStyle(.cyan)
                if let metres = state.turnMetres {
                    Text(metres >= 1000 ? String(format: "%.1fk", Double(metres) / 1000) : "\(metres)m")
                } else if let minutes = state.remainingMinutes { Text("\(minutes)분") }
            }.font(.caption.bold()).monospacedDigit()
                .accessibilityIdentifier("live.activity.compact")
        } else { Image(systemName: state.connected ? "link" : "link.badge.plus") }
    }
}

/// iOS uses this small presentation when music or another activity shares the island.
struct VehicleActivityMinimal: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        Group {
            if stale { Image(systemName: "clock").foregroundStyle(.orange) }
            else if state.guiding {
                Image(systemName: state.turnSymbol ?? "location.fill").foregroundStyle(.cyan)
                    .font(.system(size: 17, weight: .bold))
            } else { VehicleActivityIcon() }
        }.frame(width: 20, height: 20)
            .accessibilityLabel(stale ? "YL Companion 업데이트 대기" : state.guiding ? "YL Companion \(state.instruction)" : "YL Companion")
            .accessibilityIdentifier("live.activity.minimal")
    }
}
