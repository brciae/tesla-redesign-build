import SwiftUI
import WidgetKit

struct VehicleActivityIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.cyan)
            Image(systemName: "car.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
            Image("IslandAppIcon").renderingMode(.original).resizable().scaledToFit()
        }
            .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("YL Companion")
    }
}

struct VehicleActivitySummary: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    private var connection: String { stale ? "업데이트 대기" : state.connected ? "차량 연결됨" : "재연결 대기" }
    var body: some View {
        if state.charging && !state.guiding {
            VehicleChargingCard(state: state, stale: stale || state.chargingStale)
        } else {
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
}

struct VehicleChargingCard: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: stale ? "clock" : "bolt.fill").foregroundStyle(stale ? Color.gray : Color.green)
                Text(stale ? "충전 업데이트 대기" : "충전 중").font(.headline)
                    .accessibilityIdentifier("live.charging.status")
                Spacer(minLength: 0)
                if !stale, let minutes = state.chargeRemainingMinutes {
                    Text(minutes == 0 ? "곧 완료" : "약 \(minutes)분 남음").font(.caption).monospacedDigit()
                }
            }
            if stale {
                Text("앱을 열어 최신 상태 확인").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    if let battery = state.batteryPercent {
                        Text("\(battery)%").font(.system(size: 28, weight: .bold)).monospacedDigit()
                            .accessibilityIdentifier("live.charging.battery")
                    }
                    if let limit = state.chargeLimit { Text("목표 \(limit)%").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    if let kw = state.chargerKW {
                        Text(String(format: "%.1f kW", kw)).font(.subheadline.bold()).monospacedDigit()
                    }
                }
                if let battery = state.batteryPercent { ProgressView(value: Double(battery), total: 100).tint(.green) }
            }
        }.padding(14).accessibilityElement(children: .contain)
    }
}

/// Two-step guidance and trip summary; only measured route values are displayed.
struct VehicleNavigationCard: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: stale ? "location.slash" : state.turnSymbol ?? "location.fill")
                    .font(.system(size: 38, weight: .bold)).frame(width: 48)
                    .accessibilityLabel(stale ? "위치 갱신 대기" : "다음 진행 방향")
                VStack(alignment: .leading, spacing: 2) {
                    if !stale, let metres = state.turnMetres {
                        Text(NavigationCardFormat.distance(metres)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .accessibilityIdentifier("live.navigation.distance")
                    }
                    GuidanceCardTwoLineLabel(text: stale ? "길안내 업데이트 대기" : state.instruction,
                                      symbol: state.turnSymbol ?? "", exitClock: state.exitClock ?? 0)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityIdentifier("live.navigation.instruction")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !stale, let next = state.nextTurnMetres, let symbol = state.nextTurnSymbol, !symbol.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: symbol).font(.system(size: 23, weight: .semibold))
                        Text(NavigationCardFormat.distance(next)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }.frame(width: 62).padding(.vertical, 8)
                        .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("그다음 \(NavigationCardFormat.distance(next)) \(state.nextInstruction ?? "")")
                        .accessibilityIdentifier("live.navigation.next")
                }
            }
            if !stale, let progress = state.routeProgress, progress.isFinite, (0...1).contains(progress) {
                ProgressView(value: progress).tint(.blue).accessibilityLabel("경로 진행률")
            }
            if !stale, state.arrivalAt != nil || state.remainingMinutes != nil || state.remainingMetres != nil {
                Divider().overlay(Color.black.opacity(0.06))
                HStack(spacing: 12) {
                    if let arrival = state.arrivalAt {
                        Text(arrival, style: .time).monospacedDigit()
                            .accessibilityLabel("도착 예상")
                            .accessibilityIdentifier("live.navigation.arrival")
                    }
                    Spacer(minLength: 0)
                    if let minutes = state.remainingMinutes {
                        Text("\(minutes)분").monospacedDigit().accessibilityIdentifier("live.navigation.remainingTime")
                    }
                    Spacer(minLength: 0)
                    if let metres = state.remainingMetres {
                        Text(NavigationCardFormat.distance(metres)).monospacedDigit()
                            .accessibilityIdentifier("live.navigation.remainingDistance")
                    }
                }.font(.system(size: 14, weight: .semibold))
            }
        }.padding(14).foregroundStyle(.black)
            .accessibilityElement(children: .contain)
    }
}

struct VehicleActivityCompact: View {
    let state: VehicleActivityAttributes.ContentState
    var stale = false
    var body: some View {
        if stale { Image(systemName: "clock").foregroundStyle(.orange) }
        else if state.guiding {
            HStack(spacing: 3) {
                Image(systemName: state.turnSymbol ?? "location.fill").foregroundStyle(.cyan)
                if let metres = state.turnMetres {
                    Text(metres >= 1000 ? String(format: "%.1fk", Double(metres) / 1000) : "\(metres)m")
                } else if let minutes = state.remainingMinutes { Text("\(minutes)분") }
            }.font(.caption.bold()).monospacedDigit()
                .accessibilityIdentifier("live.activity.compact")
        } else if state.charging {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill").foregroundStyle(.green)
                if let battery = state.batteryPercent { Text("\(battery)%").monospacedDigit() }
            }.font(.caption.bold())
        } else { Image(systemName: state.connected ? "link" : "link.badge.plus").foregroundStyle(.cyan) }
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
            } else if state.charging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
            else { VehicleActivityIcon() }
        }.frame(width: 20, height: 20)
            .accessibilityLabel(stale ? "YL Companion 업데이트 대기" : state.guiding ? "YL Companion \(state.instruction)" : "YL Companion")
            .accessibilityIdentifier("live.activity.minimal")
    }
}
