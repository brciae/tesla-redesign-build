import SwiftUI
import CoreLocation

// The same presentation contract drives the header and all new status pages.
func homePresentation(_ model: AppModel, _ link: VehicleLink) -> Object {
    var result = (try? model.runtime.call("home", ["connected": link.connected, "authenticated": link.authentic,
        "sessionStartedAt": link.sessionStartedAt, "demo": model.demo])) as? Object ?? [:]
    if !model.demo, !link.authentic, model.fleet.isAuthenticated {
        result["charge"] = ["mode": "missing", "label": "Fleet 미수신"]
        result["climate"] = ["mode": "missing", "label": "Fleet 미수신"]
        result["location"] = ["mode": "missing", "label": "Fleet 위치 미수신", "hasCoordinates": false]
        if let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == model.fleet.selectedVin {
            for (key, value) in snapshot.homeOverlay() { result[key] = value }
        }
        result["connection"] = model.fleet.vehicleDisplayStatus
    }
    // Use Fleet for a display group that BLE has not delivered. Never inject it into BLE command evidence.
    if !model.demo, link.authentic, let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == model.fleet.selectedVin {
        for (name, value) in snapshot.homeOverlay() {
            guard let group = value as? Object else { continue }
            let existing = result.object(name)
            if existing.string("mode") != "recent", group.string("mode") == "recent" {
                result[name] = group
            } else if name == "location", !existing.flag("hasCoordinates"), group.flag("hasCoordinates") {
                // v91: a parked car's fix is old by definition — drive_state stops
                // ticking the moment it parks, so the Fleet location group is never
                // "recent" again and this loop used to drop it. BLE carries no usable
                // position while the car sleeps, so the app showed 위치 미수신 while
                // holding a perfectly good coordinate. The stored fix is the answer to
                // "where is it"; it keeps Fleet's own mode and timestamp, so the screen
                // still says how old it is rather than claiming it is live.
                result[name] = group
            } else if name == "drive", existing.string("gear").isEmpty, !group.string("gear").isEmpty {
                // Same for the gear behind 주차 중 / 정차 중.
                result[name] = group
            }
        }
    }
    if !model.demo {
        for (name, raw) in FleetTelemetryData.homeOverlay(model.archiveReadings, vin: model.fleet.selectedVin) {
            guard let group = raw as? Object else { continue }
            let existing = result.object(name)
            let newer = existing.string("mode") == "missing" || (group.number("at") ?? 0) > (existing.number("at") ?? 0)
            guard newer else { continue }
            // v91: this used to swap the whole group. FleetTelemetryData.homeOverlay
            // only writes keys whose reading is present and valid, so a NAS update
            // carrying a fresh Soc but no TimeToFullCharge replaced BLE's chargerKW,
            // addedKWh and limit with nothing. Merge per key: the NAS wins where it
            // has a value, and everything it is silent about survives. The
            // Fleet-snapshot merge above is already careful this way; this one was
            // not, and it gets more likely the more continuous the NAS feed becomes.
            var merged = existing
            for (key, value) in group { merged[key] = value }
            result[name] = merged
        }
    }
    // v91: whichever drive group won above may have come from Fleet or the NAS
    // archive, which carry gear and speed but not the 주차 중 / 정차 중 wording.
    // Running the winner back through the one rule in home.js keeps a
    // Fleet-sourced state from drifting away from a BLE-sourced one.
    let drive = model.rememberMotion(result.object("drive"))
    if !drive.isEmpty, let fields = (try? model.runtime.call("homeMotion", drive)) as? Object {
        var merged = drive
        for (key, value) in fields { merged[key] = value }
        result["drive"] = merged
    }
    return result
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var summaryOpen = false

    var body: some View {
        let p = homePresentation(model, link), c = p.object("charge")
        let climate = p.object("climate")
        let isCharging = (c.string("mode") == "recent" || model.demo) && c.chargingNow

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top Header Bar
                headerView(p: p, c: c)
                if !model.demo, model.fleet.isAuthenticated { fleetStatusCard }

                // 3D Vehicle Hero Panel
                Vehicle3DPanel(link: link, compact: true)
                    .background(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .padding(.top, 2)

                // Quick Controls: 4 Tactile Glass Action Tiles (Official Tesla App layout)
                HStack(spacing: 10) {
                    quickControlTile(
                        .security,
                        "lock.fill",
                        "도어 잠금",
                        highlight: false
                    )
                    let insideC = climate.number("insideC")
                    quickControlTile(
                        .climate,
                        "fanblades.fill",
                        insideC != nil ? "\(Int(round(insideC!)))°C" : "실내온도",
                        highlight: false
                    )
                    quickControlTile(
                        .charging,
                        "bolt.fill",
                        isCharging ? "충전 중" : "충전",
                        highlight: isCharging
                    )
                    quickControlTile(
                        .controls,
                        "car.side.rear.open.fill",
                        "트렁크",
                        highlight: false
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(white: 0.12).opacity(0.72))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                )

                // Driving Dashboard Banner
                driveButton

                // Active Charging Indicator (Only shown when vehicle is charging)
                if isCharging {
                    let soc = c.number("soc")
                    NavigationLink(value: Page.charging) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.2))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color(red: 0.28, green: 0.88, blue: 0.42))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(soc != nil ? "충전 중 · \(Int(round(soc!)))%" : "충전 중")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                if let kmH = c.number("chargeKmH"), kmH > 0 {
                                    Text("+\(Int(kmH)) km/h · 충전 설정 보기")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                } else {
                                    Text("충전 상세 설정 보기")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(white: 0.12).opacity(0.75))
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(MotionButtonStyle())
                }

                // Minimal Vehicle Footer
                VStack(spacing: 4) {
                    Text(model.settings.string("model", "Model Y L").uppercased())
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Color.white.opacity(0.6))
                    Caption("YL COMPANION · v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    if model.demo {
                        Button("예시 모드 종료") { model.exitDemo() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: HomeVisualStyle.contentWidth)
            .padding(.horizontal, HomeVisualStyle.gutter)
            .padding(.top, HomeVisualStyle.headerTop)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { model.refreshVehicle() }
    }

    private var fleetStatusCard: some View { FleetStatusCard() }

    // v92: the header ran to three stacked lines with the briefing controls
    // marooned across an empty row. Name and briefing share the top line; the
    // state and connection chips sit together on the second, which is how a
    // phone app's header reads — identity above, status below.
    private func headerView(p: Object, c: Object) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                NavigationLink(value: Page.connection) {
                    HStack(spacing: 6) {
                        Text(model.settings.string("name", "Model Y"))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(MotionButtonStyle())
                .accessibilityLabel("차량 프로필 및 연결 설정")

                Spacer(minLength: 8)
                ScreenBriefingControls(scope: .home, compact: true)
            }

            HStack(spacing: 8) {
                VehicleMotionBadge(drive: p.object("drive"), compact: true)
                Text("·").foregroundStyle(Color.white.opacity(0.25))
                connectionChip
                Spacer(minLength: 0)
            }
        }
    }

    // Display only — the vehicle profile above is the single route to 연결 상태.
    private var connectionChip: some View {
        let live = link.authentic && !model.demo
        let tint = live ? Color(red: 0.28, green: 0.88, blue: 0.42) : (model.demo ? Color.orange : Color.gray)
        return HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .shadow(color: tint.opacity(0.7), radius: 4)
            Text(model.demo ? "예시 모드" : (link.authentic ? "BLE 연결됨" : (model.fleet.isAuthenticated ? model.fleet.vehicleDisplayStatus : "계정 미연결")))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Color.white.opacity(0.85))
            if link.refreshing || model.fleet.isReadingVehicle {
                ProgressView().controlSize(.mini)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func quickControlTile(_ page: Page, _ symbol: String, _ title: String, highlight: Bool = false) -> some View {
        NavigationLink(value: page) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.5) : Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42) : .white)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MotionButtonStyle())
        .accessibilityLabel(title)
    }

    private var driveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.navigation.activateWorkspace(model: model)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.15, green: 0.45, blue: 0.95), Color(red: 0.25, green: 0.65, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 2)
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("운전 대시보드")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("전체 화면 3D 주행 및 카카오 길안내")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.75))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
        }
        .buttonStyle(MotionButtonStyle())
        .accessibilityLabel("운전 대시보드 열기")
    }

    private var briefing: some View {
        InfoCard {
            HStack(spacing: 6) {
                Button {
                    withAnimation(reduced ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { summaryOpen.toggle() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").foregroundStyle(Theme.muted)
                        Text("오늘의 브리핑").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(summaryOpen ? 180 : 0)).foregroundStyle(Theme.muted)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(MotionButtonStyle()).accessibilityValue(summaryOpen ? "펼쳐짐" : "접힘")
                InfoNote("오늘의 브리핑", "차량에서 받은 최신 값과 앱에 저장된 기록을 함께 요약함. 최신 차량 상태가 없으면 저장된 자료 기준으로 안내하며, 각 상세 화면의 자료 시각으로 확인할 수 있음.")
            }
            if summaryOpen {
                VStack(alignment: .leading, spacing: 12) {
                    Caption(model.output.string("briefing"))
                    HStack { NavigationLink("브리핑 열기", value: Page.briefing); Spacer(); Button("읽어주기") { model.speak() } }.frame(minHeight: 44)
                }.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.sensoryFeedback(.selection, trigger: summaryOpen).padding(.bottom, 12)
    }
}

struct GlassMenuCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.75))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .padding(.bottom, 6)
    }
}

func glassMenuItem(_ page: Page, _ icon: String, title: String, subtitle: String?, colors: [Color], isLast: Bool = false) -> some View {
    VStack(spacing: 0) {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .shadow(color: colors.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MotionButtonStyle())

        if !isLast {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.leading, 64)
        }
    }
}

struct StatusTimestamp: View {
    let section: Object
    var body: some View { Caption("\(section.string("label", "미수신")) · 자료 시각 \(dateText(section.number("at")))") }
}
struct ReadOnlyNotice: View {
    var body: some View { EmptyView() }
}
struct ControlsView: View {
    @ObservedObject var link: VehicleLink
    var body: some View {
        TeslaInteractiveControlsView(link: link)
            .navigationTitle("차량 제어")
    }
}

struct ClimateStatusView: View {
    @ObservedObject var link: VehicleLink
    var body: some View {
        TeslaInteractiveClimateView(link: link)
            .navigationTitle("실내 공조")
    }
}

/// v91: 주차 중 / 정차 중 / 주행 중, with how old the reading is. Other Tesla
/// apps lead with this and the app already had the gear and speed in hand; it
/// simply never rendered them, so the car's state read 상태 미수신 even when a
/// good response had just arrived.
struct VehicleMotionBadge: View {
    let drive: Object
    var compact = false
    private var motion: String { drive.string("motion") }
    private var icon: String {
        switch motion {
        case "parked": return "parkingsign.circle.fill"
        case "driving": return "steeringwheel"
        case "stopped": return "pause.circle.fill"
        default: return "questionmark.circle"
        }
    }
    private var tint: Color {
        switch motion {
        case "parked": return Theme.green
        case "driving": return Color(red: 0.35, green: 0.65, blue: 1.0)
        case "stopped": return Color.orange
        default: return Theme.muted
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: compact ? 11 : 13, weight: .semibold))
            Text(drive.string("motionLabel", "상태 미수신")).font(.system(size: compact ? 12 : 14, weight: .semibold))
            if let at = drive.number("at") {
                Text(dateText(at)).font(.system(size: compact ? 11 : 12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

/// v92: the old card showed "상태 미수신 · 위치 정보를 수신하지 못했습니다" while a
/// saved parking record with a full address sat two cards below it on the same
/// screen. A car that is not reporting right now was still somewhere the last
/// time it did, and that is the answer to "where is my car" — so the saved
/// position is used when no live one is available, labelled as what it is.
/// v92: this was four stacked lines of running text — "배터리 34%  주행가능 190 km"
/// then "잠금 상태 미수신" then a full timestamp sentence. The numbers are the
/// point, so they are tiles; the lock state is a chip; and the reception time is
/// a caption on the title row instead of a sentence of its own.
struct FleetStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let snapshot = model.fleet.vehicleSnapshot.flatMap { $0.vin == model.fleet.selectedVin ? $0 : nil }
        VStack(alignment: .leading, spacing: 14) {
            titleRow(snapshot)
            if let snapshot {
                HStack(spacing: 0) {
                    tile(snapshot.soc.map { "\(Int($0))" }, "%", "배터리")
                    divider
                    tile(snapshot.rangeKm.map { "\(Int($0))" }, "km", "주행 가능")
                    divider
                    let bleTemperature = model.output.object("fresh").flag("climate") ? model.groups.object("climate").number("insideC") : nil
                    let temperature = bleTemperature ?? snapshot.insideC
                    tile(temperature.map { "\(Int($0.rounded()))" }, "°C", "실내 온도")
                }
                lockChip(snapshot.locked)
            }
            notice
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func titleRow(_ snapshot: FleetVehicleSnapshot?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
            Text(model.fleet.vehicleDisplayStatus)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            if let at = snapshot?.receivedAt {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Button {
                model.refreshVehicle()
            } label: {
                Group {
                    if model.fleet.isReadingVehicle || model.link.refreshing { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)) }
                }
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: Circle())
                .foregroundStyle(.white)
            }
            .disabled(model.fleet.isReadingVehicle || model.link.refreshing)
            .accessibilityLabel("차량 상태 새로고침")
        }
    }

    private func tile(_ value: String?, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "미수신")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(value == nil ? Theme.muted : .white)
                if value != nil {
                    Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                }
            }
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private func lockChip(_ locked: Bool?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: locked == nil ? "lock.slash" : (locked! ? "lock.fill" : "lock.open.fill"))
                .font(.system(size: 11, weight: .semibold))
            Text(locked.map { $0 ? "도어 잠김" : "도어 잠금 해제" } ?? "잠금 미수신")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(locked == nil ? Theme.muted : (locked! ? Theme.green : Color.orange))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    @ViewBuilder private var notice: some View {
        if let error = model.fleet.vehicleReadError {
            Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.fleet.vehicleReadStatus == "차량 절전 중" || model.fleet.vehicleReadStatus == "차량 오프라인" {
            Text("차량이 깨어나면 새로고침해서 현재 상태를 가져옵니다.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct VehicleLocationCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject private var parking = SmartParkingManager.shared
    let location: Object
    let drive: Object
    @Binding var address: String

    private enum Source { case live, remembered, phone }
    private struct Fix { let latitude: Double; let longitude: Double; let at: Date?; let source: Source }

    private var fix: Fix? {
        if location.flag("hasCoordinates"), let lat = location.number("latitude"), let lon = location.number("longitude") {
            return Fix(latitude: lat, longitude: lon,
                       at: (location.number("gpsAt") ?? location.number("at")).map { Date(timeIntervalSince1970: $0 / 1000) },
                       source: .live)
        }
        if let record = parking.latestRecord, record.vehicleID == parking.selectedVehicleID, let lat = record.effectiveLatitude, let lon = record.effectiveLongitude {
            return Fix(latitude: lat, longitude: lon, at: record.timestamp, source: .remembered)
        }
        if let record = parking.latestRecord, record.vehicleID == nil || record.vehicleID == parking.selectedVehicleID,
           let lat = record.mobile.mobileLatitude, let lon = record.mobile.mobileLongitude {
            return Fix(latitude: lat, longitude: lon, at: record.timestamp, source: .phone)
        }
        return nil
    }

    var body: some View {
        GlassMenuCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let fix {
                    placeName(fix)
                    chips(fix)
                    actions(fix)
                } else {
                    waiting
                    refreshButton
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.65, blue: 1.0))
            Text("차량 위치").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            VehicleMotionBadge(drive: drive, compact: true)
        }
    }

    @ViewBuilder private func placeName(_ fix: Fix) -> some View {
        let saved = parking.latestRecord
        let title: String = {
            if !address.isEmpty { return address }
            if fix.source != .live, let saved { return saved.displayTitle }
            return "위치 확인 중…"
        }()
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if fix.source == .remembered, let saved, !saved.displaySubtitle.isEmpty, saved.displaySubtitle != title {
                Text(saved.displaySubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .task(id: "\(fix.latitude),\(fix.longitude)") { await resolveAddress(fix) }
    }

    private func chips(_ fix: Fix) -> some View {
        HStack(spacing: 6) {
            if let at = fix.at { chip(elapsed(at), "clock") }
            chip(fix.source == .live ? "차량 수신" : fix.source == .phone ? "저장 당시 휴대폰 위치" : "마지막 주차 위치",
                 fix.source == .live ? "antenna.radiowaves.left.and.right" : "parkingsign")
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.72))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func actions(_ fix: Fix) -> some View {
        HStack(spacing: 10) {
            if !model.demo, let url = URL(string: "https://maps.apple.com/?ll=\(fix.latitude),\(fix.longitude)") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                        Text("지도 보기")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color(red: 0.18, green: 0.50, blue: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
            }
            refreshButton.frame(width: 56)
        }
    }

    private var refreshButton: some View {
        Button {
            model.refreshVehicle()
        } label: {
            Group {
                if link.refreshing || model.fleet.isReadingVehicle {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(model.demo || (!link.authentic && !model.fleet.isAuthenticated) || link.refreshing)
        .accessibilityLabel("위치 정보 새로고침")
    }

    /// Name what is actually missing rather than "수신하지 못했습니다".
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(location.string("diagnostic").isEmpty ? "차량이 아직 좌표를 보고하지 않음" : location.string("diagnostic"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(link.authentic || model.fleet.isAuthenticated
                 ? "저장된 주차 기록도 아직 없습니다. 차량이 깨어나 좌표를 보고하면 여기에 표시됩니다."
                 : "차량 계정 또는 블루투스를 먼저 연결해 주세요.")
                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func elapsed(_ at: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(at))
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        if seconds < 86400 { return "\(seconds / 3600)시간 전" }
        return dateText(at.timeIntervalSince1970 * 1000, time: false)
    }

    private func resolveAddress(_ fix: Fix) async {
        let point = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        if let marks = try? await CLGeocoder().reverseGeocodeLocation(point, preferredLocale: Locale(identifier: "ko_KR")),
           let mark = marks.first {
            let parts = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare]
                .compactMap { $0 }.filter { !$0.isEmpty }
            let joined = parts.joined(separator: " ")
            if !joined.isEmpty { address = joined; return }
            if let name = mark.name, !name.isEmpty { address = name; return }
        }
        address = String(format: "%.4f, %.4f", fix.latitude, fix.longitude)
    }
}

struct LocationStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject private var parking = SmartParkingManager.shared
    @State private var roadAddress: String = ""
    var body: some View {
        let p = homePresentation(model, link)
        PageBody(title: "차량 위치", briefing: .location, briefingText: {
            if !p.object("location").flag("hasCoordinates"), let record = parking.latestRecord,
               record.vehicleID == nil || record.vehicleID == parking.selectedVehicleID {
                if record.vehicleID == parking.selectedVehicleID, record.effectiveLatitude != nil, record.effectiveLongitude != nil {
                    return record.briefingLines.joined(separator: " ")
                }
                if record.mobile.mobileLatitude != nil, record.mobile.mobileLongitude != nil {
                    return "저장 당시 휴대폰 위치입니다. " + record.briefingLines.prefix(2).joined(separator: " ")
                }
            }
            return model.screenBriefing(.location, address: roadAddress)
        }) {
            VStack(spacing: 16) {
                VehicleLocationCard(link: link, location: p.object("location"), drive: p.object("drive"), address: $roadAddress)

                // Smart Parking Card (Floor, Pillar, Photo, Memo)
                SmartParkingCard(link: link)

                GlassMenuCard {
                    VStack(alignment: .leading, spacing: 12) {
                        // v90: 길안내 lives in this tab's first segment, so only 주차 기록 remains here.
                        CardTitle(title: "주차 기록", systemImage: "parkingsign.circle.fill")
                        NavigationLink(value: Page.parking) {
                            HStack {
                                Image(systemName: "parkingsign.circle.fill")
                                    .foregroundStyle(Color.green)
                                Text("주차 위치 및 사진 기록")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct ChargeStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var add = false
    var body: some View {
        let c = homePresentation(model, link).object("charge")
        let isCharging = c.chargingNow
        let isPlugged = isCharging || c.flag("plugged")
        PageBody(title: "충전", briefing: .charging) {
            VStack(spacing: 16) {
                // 3D Charging Vehicle (only connects cable/energy when plugged/charging)
                Vehicle3DPanel(link: link, compact: true, chargingMode: true, isCharging: isCharging, isPlugged: isPlugged)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Official Charging & Power Flow Visualizer Card
                TeslaOfficialChargingCardView(c: c, link: link)

                // Detailed Controls
                GlassMenuCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "충전 제어", systemImage: "bolt.badge.clock.fill")
                        ControlPanel(link: link, category: "charge")
                    }
                    .padding(16)
                }

                // History & Battery Analytics
                GlassMenuCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            add = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.green)
                                Text("충전 기록 및 영수증 추가")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $add) { ChargeForm() }
    }
}

struct SecurityStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    var body: some View {
        PageBody(title: "보안 및 잠금", briefing: .security) {
            NavigationLink { FleetSupplementView(fleet: model.fleet, kind: .drivers) } label: { Label("차량 접근 운전자", systemImage: "person.2") }
            VStack(spacing: 16) {
                GlassMenuCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "차량 잠금 제어", systemImage: "lock.shield.fill")
                        ControlPanel(link: link, category: "security")
                    }
                    .padding(16)
                }

                GlassMenuCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardTitle(title: "차량 키 및 통신", systemImage: "key.radiowaves.forward.fill")
                        HStack {
                            Text("연결 상태")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.65))
                            Spacer()
                            Text(homePresentation(model, link).string("connection", "확인 중"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Divider().background(Color.white.opacity(0.08))
                        NavigationLink(value: Page.connection) {
                            HStack {
                                Text("연결 및 키 설정")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}


// MARK: - Tesla Official App Charging Card

// MARK: - Tesla Official App Charging Card & Power Visualization

struct PowerFlowGraphView: View {
    let chargerKW: Double
    let isCharging: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("실시간 전력 흐름")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(isCharging ? String(format: "%.1f kW 충전 중", chargerKW) : "대기 상태")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCharging ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.white.opacity(0.5))
            }

            Canvas { context, size in
                let w = size.width
                let h = size.height
                var path = Path()

                let points = 24
                let baseline = h * 0.65
                path.move(to: CGPoint(x: 0, y: baseline))

                for i in 0...points {
                    let x = w * CGFloat(i) / CGFloat(points)
                    let normalizedX = CGFloat(i) / CGFloat(points)
                    let amplitude = isCharging ? CGFloat(min(12.0, max(4.0, chargerKW * 1.5))) : 2.0
                    let wave = sin(normalizedX * .pi * 3.5) * amplitude
                    let y = baseline + wave
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Stroke curve
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: isCharging ? [Color.cyan, Color(red: 0.28, green: 0.88, blue: 0.42)] : [Color.gray.opacity(0.4), Color.gray.opacity(0.2)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ),
                    lineWidth: isCharging ? 2.5 : 1.5
                )

                // Fill under curve
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: w, y: h))
                fillPath.addLine(to: CGPoint(x: 0, y: h))
                fillPath.closeSubpath()

                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: isCharging ? [Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.22), Color.clear] : [Color.white.opacity(0.03), Color.clear]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: h)
                    )
                )
            }
            .frame(height: 52)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 0.8))
        }
    }
}

private struct TeslaOfficialChargingCardView: View {
    @EnvironmentObject private var model: AppModel
    let c: Object
    @ObservedObject var link: VehicleLink
    @State private var targetLimit: Double = 80
    @State private var currentAmps: Int = 32
    @State private var maxAmps: Int = 32
    @State private var isStoppingCharge = false
    @State private var isDraggingThumb = false
    @State private var isLeftPressed = false
    @State private var isRightPressed = false

    var body: some View {
        let soc = Int(round(c.number("soc") ?? 0))
        let rangeKm = c.number("rangeKm").map { String(Int($0.rounded())) } ?? "—"
        let chargerKW = c.number("chargerKW") ?? 0.0
        let addedKWh = c.number("addedKWh") ?? 0.0
        let isCharging = (model.demo || c.string("mode") == "recent") && c.chargingNow
        let voltage = c.number("chargerVoltage").map { String(Int($0.rounded())) } ?? "—"

        VStack(spacing: 0) {
            // Main Card Body
            VStack(alignment: .leading, spacing: 14) {
                // Readout Header: SOC % & Range km + Live Status Badge
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(c.number("soc") == nil ? "—" : "\(soc)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("%")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Text("·")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.horizontal, 4)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(rangeKm)")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                        Text("km")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }

                    Spacer()

                    // Status Pill
                    HStack(spacing: 5) {
                        if isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.28, green: 0.88, blue: 0.42))
                            Text("\(Int(round(chargerKW))) kW")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(red: 0.28, green: 0.88, blue: 0.42))
                        } else {
                            Circle()
                                .fill(Color(red: 0.35, green: 0.85, blue: 0.45))
                                .frame(width: 7, height: 7)
                            Text(c.string("mode") == "recent" ? "충전 대기" : "상태 미확인")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                }

                // Battery SOC Gradient Progress Bar with Target Limit Thumb
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let targetFrac = CGFloat(targetLimit / 100.0)
                        let socFrac = CGFloat(Double(soc) / 100.0)

                        ZStack(alignment: .leading) {
                            // Background Track
                            Capsule()
                                .fill(Color(white: 0.16))
                                .frame(height: 8)

                            // Target Limit Allowed Zone
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: max(8, w * targetFrac), height: 8)

                            // Current SOC Fill with Vibrant Gradient
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.22, green: 0.88, blue: 0.55), Color(red: 0.15, green: 0.75, blue: 0.95)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, w * min(socFrac, targetFrac)), height: 8)
                                .shadow(color: Color(red: 0.22, green: 0.88, blue: 0.55).opacity(0.4), radius: 3, x: 0, y: 0)

                            // Target Limit Marker Line / Thumb
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                                .scaleEffect(isDraggingThumb ? 1.25 : 1.0)
                                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDraggingThumb)
                                .offset(x: min(w - 20, max(0, w * targetFrac - 10)))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            isDraggingThumb = true
                                            let frac = max(0.5, min(1.0, value.location.x / w))
                                            let newLimit = round(frac * 100.0 / 5.0) * 5.0
                                            if newLimit != targetLimit {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                targetLimit = newLimit
                                            }
                                        }
                                        .onEnded { _ in
                                            isDraggingThumb = false
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                )
                        }
                    }
                    .frame(height: 22)

                    HStack {
                        Text("충전 한도: \(Int(targetLimit))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                        Spacer()
                        Text(isCharging ? "충전기 출력 \(Int(round(chargerKW))) kW · +\(c.number("addedKWh").map { String(Int($0.rounded())) } ?? "—") kWh" : (c.string("mode") == "recent" ? "충전 대기 상태" : "충전 상태 미확인"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }

                // Power Flow & Energy Waveform Visualization (Only when actively charging)
                if isCharging {
                    PowerFlowGraphView(chargerKW: chargerKW, isCharging: isCharging)
                }

                // Current Stepper Pill (< 32 A >)
                HStack {
                    Button {
                        if currentAmps > 5 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                isLeftPressed = true
                                currentAmps -= 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                isLeftPressed = false
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(currentAmps > 5 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 40)
                            .scaleEffect(isLeftPressed ? 0.85 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("요청 \(currentAmps) A · \(voltage) V")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if currentAmps < maxAmps {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                isRightPressed = true
                                currentAmps += 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                isRightPressed = false
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(currentAmps < maxAmps ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 40)
                            .scaleEffect(isRightPressed ? 0.85 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(height: 40)
                .background(Color(white: 0.14).opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            }
            .padding(16)

            // Divider Line
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            Button("선택 전류 적용") { model.requestVehicleControl("chargeAmps", title: "충전 전류 설정", args: ["value": currentAmps]) }.buttonStyle(.bordered)
            // Bottom Action Buttons (충전 제어 | 충전 포트)
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isCharging {
                        model.requestVehicleControl("chargeStop", title: "충전 중지")
                    } else {
                        model.requestVehicleControl("chargeStart", title: "충전 시작")
                    }
                } label: {
                    Text(isCharging ? "충전 중지" : "충전 시작")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCharging ? Color(red: 1.0, green: 0.38, blue: 0.38) : Color(red: 0.28, green: 0.88, blue: 0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PlainButtonStyle())

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 48)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.requestVehicleControl("portOpen", title: isCharging ? "충전 포트 잠금 해제" : "충전 포트 열기")
                } label: {
                    Text(isCharging ? "충전 포트 잠금 해제" : "충전 포트 열기")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.11).opacity(0.85))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }
}

// MARK: - 5-Tab Navigation Root Views

struct ControlsTabRootView: View {
    @ObservedObject var link: VehicleLink
    @State private var selectedSection = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("컨트롤 구분", selection: $selectedSection) {
                Text("차량 제어").tag(0)
                Text("실내 공조").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.bg)

            if selectedSection == 0 {
                ControlsView(link: link)
            } else {
                ClimateStatusView(link: link)
            }
        }
        .background(Theme.bg)
    }
}

struct EnergyTabRootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @AppStorage("energy.section") private var selectedSection = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("에너지 구분", selection: $selectedSection) {
                Text("충전 제어").tag(0)
                Text("TeslaMate").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.bg)

            if selectedSection == 0 {
                ChargeStatusView(link: link)
            } else {
                // Battery analysis, cost, calendar and all history live under one TeslaMate section.
                TeslaMateView()
            }
        }
        .background(Theme.bg)
    }
}

struct DriveTabRootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var navigation: EmbeddedNavigation
    @State private var selectedSection = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("운행 구분", selection: $selectedSection) {
                Text("길안내").tag(0)
                Text("위치·주차").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.bg)

            if selectedSection == 0 {
                NavigationLandingView(navigation: navigation)
            } else {
                LocationStatusView(link: link)
            }
        }
        .background(Theme.bg)
    }
}

struct MenuTabRootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject var navigation: EmbeddedNavigation

    var body: some View {
        PageBody(title: "메뉴 및 설정", briefing: .menu) {
            VStack(spacing: 16) {
                // Vehicle Identity & Connection Status Card
                vehicleStatusHeader

                // Group 1: 차량 커스텀 & 점검
                VStack(alignment: .leading, spacing: 8) {
                    Text("차량 관리")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.leading, 6)

                    GlassMenuCard {
                        glassMenuItem(.fleetInsights, "checkmark.shield", title: "차량 상태·보증", subtitle: "사양 · 보증 · 경고", colors: [Color.cyan, Color.blue])
                        glassMenuItem(.care, "wrench.and.screwdriver.fill", title: "타이어·정비", subtitle: "공기압 · 소모품 주기", colors: [Color.orange, Color.yellow])
                        glassMenuItem(.security, "shield.fill", title: "보안 및 운전자", subtitle: "감시 모드 · 운전자", colors: [Color.blue, Color.cyan], isLast: true)
                    }
                }

                // Group 2: 스마트 기능 & 설정
                VStack(alignment: .leading, spacing: 8) {
                    Text("설정")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.leading, 6)

                    GlassMenuCard {
                        glassMenuItem(.connection, "antenna.radiowaves.left.and.right", title: "차량·NAS 연결", subtitle: "계정 · 블루투스 · 서버", colors: [Color.cyan, Color.blue])
                        glassMenuItem(.navigation, "map", title: "내비게이션", subtitle: "지도 · 위치 권한 · 하이패스", colors: [Color.blue, Color.cyan])
                        glassMenuItem(.chargingSettings, "bolt.fill", title: "충전 계획·요금", subtitle: "충전 기준 · 전기 단가", colors: [Color.green, Color.mint])
                        glassMenuItem(.recordSettings, "externaldrive", title: "기록·백업", subtitle: "내보내기 · 복원", colors: [Color.blue, Color.cyan])
                        glassMenuItem(.appearance, "paintbrush.fill", title: "3D 차꾸미기", subtitle: "외장 · 휠 · 실내", colors: [Color.purple, Color.pink])
                        glassMenuItem(.automation, "bolt.circle.fill", title: "스마트 자동화", subtitle: "상황별 음성 안내 · 자동 제어", colors: [Color.green, Color.mint])
                        glassMenuItem(.notifications, "bell.badge.fill", title: "알림 설정", subtitle: "충전 알림 · 권한", colors: [Color.purple, Color.blue])
                        glassMenuItem(.displaySettings, "textformat.size", title: "화면·표시 단위", subtitle: "배경 · 거리 · 온도 단위", colors: [Color.gray, Color.white])
                        glassMenuItem(.preferences, "gearshape.fill", title: "음성·내비 안내", subtitle: "목소리 · 빈도 · 음량", colors: [Color.gray, Color.white], isLast: true)
                    }
                }
            }
        }
    }

    private var vehicleStatusHeader: some View {
        let vin = model.settings.string("vin")
        let cleanVin = vin.isEmpty ? "VIN 미등록" : vin
        let isConnected = link.authentic || (model.fleet.vehicleSnapshot?.isRecent() == true && model.fleet.vehicleReadError == nil)
        let connText = link.authentic ? "차량 BLE 정상 연결" : (model.fleet.isAuthenticated ? model.fleet.vehicleDisplayStatus : "차량 연결 대기 중")
        let connColor = isConnected ? Color.green : Color.orange

        return HStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Tesla Model Y")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                Text(cleanVin)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))

                HStack(spacing: 6) {
                    Circle()
                        .fill(connColor)
                        .frame(width: 7, height: 7)
                    Text(connText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(connColor)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct NavigationLandingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var navigation: EmbeddedNavigation
    @State private var searching = false
    @State private var selected: SavedNavigationPlace?
    @State private var nearby = false
    @State private var recent: [SavedNavigationPlace] = []
    var body: some View {
        NavigationLandingPanel(guiding: navigation.guiding, recent: recent,
            search: { selected = nil; searching = true },
            dashboard: { navigation.activateWorkspace(model: model) },
            charging: { nearby = true },
            naver: { model.openInNaverMap() }, tmap: { model.openInTMap() },
            select: { selected = $0; searching = true }, externalEnabled: !model.demo)
        .onAppear { loadRecent() }
        .sheet(isPresented: $searching, onDismiss: loadRecent) {
            DestinationSearchView(navigation: navigation, initialPlace: selected).environmentObject(model)
        }
        .navigationDestination(isPresented: $nearby) { FleetSupplementView(fleet: model.fleet, kind: .nearbyCharging) }
    }
    private func loadRecent() {
        recent = UserDefaults.standard.data(forKey: "navigation.recent").flatMap { try? JSONDecoder().decode([SavedNavigationPlace].self, from: $0) } ?? []
    }
}
