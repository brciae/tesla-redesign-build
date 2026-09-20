import SwiftUI

// The same presentation contract drives the header and all new status pages.
func homePresentation(_ model: AppModel, _ link: VehicleLink) -> Object {
    (try? model.runtime.call("home", ["connected": link.connected, "authenticated": link.authentic,
        "sessionStartedAt": link.sessionStartedAt, "demo": model.demo])) as? Object ?? [:]
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var summaryOpen = false
    @State private var editing = false
    @ObservedObject private var layout = HomeLayoutStore.shared

    var body: some View {
        let p = homePresentation(model, link), c = p.object("charge")
        let climate = p.object("climate")
        let isCharging = (c.number("chargerKW") ?? 0) > 0.5 || c.flag("charging")

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top Header Bar
                headerView(p: p, c: c)

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

                // Tesla Wordmark & Vehicle Selector
                VStack(spacing: 8) {
                    Text("T E S L A")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white.opacity(0.85))

                    NavigationLink(value: Page.connection) {
                        HStack(spacing: 6) {
                            Text("대표")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white.opacity(0.85))
                            Text(model.settings.string("name", "Model Y 2026"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.14).opacity(0.85))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                    }
                    .buttonStyle(MotionButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)

                // Quick Controls: 4 Tactile Glass Action Tiles
                HStack(spacing: 10) {
                    quickControlTile(
                        .security,
                        "lock.fill",
                        "잠금",
                        link.authentic ? "보안 켬" : "잠금",
                        highlight: false
                    )
                    let insideC = climate.number("insideC")
                    quickControlTile(
                        .climate,
                        "fanblades.fill",
                        "실내온도",
                        insideC != nil ? "\(Int(round(insideC!)))°C" : "공조 제어",
                        highlight: false
                    )
                    quickControlTile(
                        .charging,
                        "bolt.fill",
                        "충전",
                        isCharging ? "충전 중" : "충전 포트",
                        highlight: isCharging
                    )
                    quickControlTile(
                        .controls,
                        "car.side.rear.open.fill",
                        "트렁크",
                        "개폐 제어",
                        highlight: false
                    )
                }

                // Battery & Power Visualization Card (Tesla Official / Jijijik)
                TeslaOfficialChargingCardView(c: c, link: link)

                // Driving Dashboard Banner
                driveButton

                // Smart Parking Card
                SmartParkingCard(link: link)

                // Daily Briefing
                briefing

                // Grouped Menu Cards (Frosted Glass)
                let controls = layout.shown.filter(\.isControl)
                let records = layout.shown.filter { !$0.isControl }

                if !controls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("차량 제어 및 상태")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.leading, 4)

                        GlassMenuCard {
                            ForEach(Array(controls.enumerated()), id: \.element.id) { index, module in
                                let subtitle = (module == .location ? p.object("location").string("subtitle", "위치 미수신") : module.subtitle)
                                glassMenuItem(
                                    module.page,
                                    module.icon,
                                    title: module.title,
                                    subtitle: subtitle,
                                    colors: moduleColors(module),
                                    isLast: index == controls.count - 1
                                )
                            }
                        }
                    }
                }

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("기록 및 스마트 기능")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.leading, 4)

                        GlassMenuCard {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, module in
                                glassMenuItem(
                                    module.page,
                                    module.icon,
                                    title: module.title,
                                    subtitle: module.subtitle,
                                    colors: moduleColors(module),
                                    isLast: index == records.count - 1
                                )
                            }
                        }
                    }
                }

                // Edit Layout & Footer
                Button { editing = true } label: {
                    Label("홈 메뉴 편집", systemImage: "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(MotionButtonStyle())
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(model.settings.string("model", "Model Y L").uppercased())
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Color.white.opacity(0.6))
                    Caption("YL COMPANION · v0.46")
                    if model.demo {
                        Button("예시 모드 종료") { model.exitDemo() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
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
        .sheet(isPresented: $editing) { HomeLayoutEditor() }
    }

    private func headerView(p: Object, c: Object) -> some View {
        HStack(spacing: 8) {
            // Vehicle profile pill
            NavigationLink(value: Page.connection) {
                HStack(spacing: 8) {
                    Text(model.settings.string("name", "Model Y"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(MotionButtonStyle())
            .accessibilityLabel("차량 프로필 및 연결 설정")

            Spacer()

            // Live Connection Status Badge
            NavigationLink(value: Page.connection) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(link.authentic && !model.demo ? Color(red: 0.28, green: 0.88, blue: 0.42) : (model.demo ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)
                        .shadow(color: (link.authentic && !model.demo ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.orange).opacity(0.7), radius: 4)
                    Text(model.demo ? "예시 모드" : (link.authentic ? "연결됨" : "대기 중"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    if link.busy || link.refreshing {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(white: 0.14).opacity(0.8))
                        .background(.ultraThinMaterial, in: Capsule())
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            }
            .buttonStyle(MotionButtonStyle())

            // Briefing button
            NavigationLink(value: Page.briefing) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(white: 0.14).opacity(0.8))
                            .background(.ultraThinMaterial, in: Circle())
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            }
            .buttonStyle(MotionButtonStyle())
            .accessibilityLabel("오늘의 브리핑")

            // Settings button
            NavigationLink(value: Page.preferences) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(white: 0.14).opacity(0.8))
                            .background(.ultraThinMaterial, in: Circle())
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            }
            .buttonStyle(MotionButtonStyle())
            .accessibilityLabel("설정")
        }
    }

    private func quickControlTile(_ page: Page, _ symbol: String, _ title: String, _ subtitle: String, highlight: Bool = false) -> some View {
        NavigationLink(value: page) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42) : .white)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.75))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
        }
        .buttonStyle(MotionButtonStyle())
        .accessibilityLabel("\(title) \(subtitle)")
    }

    private var driveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.navigation.presented = true
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

    private func glassMenuItem(_ page: Page, _ icon: String, title: String, subtitle: String?, colors: [Color], isLast: Bool = false) -> some View {
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

    private func moduleColors(_ module: HomeModule) -> [Color] {
        switch module {
        case .controls: return [Color(red: 0.15, green: 0.45, blue: 0.95), Color(red: 0.25, green: 0.65, blue: 1.0)]
        case .climate: return [Color(red: 0.05, green: 0.70, blue: 0.85), Color(red: 0.20, green: 0.85, blue: 0.95)]
        case .charging: return [Color(red: 0.15, green: 0.75, blue: 0.35), Color(red: 0.30, green: 0.90, blue: 0.50)]
        case .location: return [Color(red: 0.95, green: 0.45, blue: 0.15), Color(red: 1.0, green: 0.65, blue: 0.25)]
        case .security: return [Color(red: 0.90, green: 0.25, blue: 0.30), Color(red: 1.0, green: 0.45, blue: 0.45)]
        case .trips: return [Color(red: 0.40, green: 0.30, blue: 0.90), Color(red: 0.55, green: 0.45, blue: 1.0)]
        case .battery: return [Color(red: 0.10, green: 0.65, blue: 0.55), Color(red: 0.25, green: 0.85, blue: 0.75)]
        case .care: return [Color(red: 0.35, green: 0.40, blue: 0.50), Color(red: 0.50, green: 0.55, blue: 0.65)]
        case .appearance: return [Color(red: 0.85, green: 0.25, blue: 0.65), Color(red: 0.95, green: 0.45, blue: 0.80)]
        case .automation: return [Color(red: 0.55, green: 0.25, blue: 0.85), Color(red: 0.70, green: 0.40, blue: 0.95)]
        case .preferences: return [Color(red: 0.40, green: 0.45, blue: 0.50), Color(red: 0.55, green: 0.60, blue: 0.65)]
        case .connection: return [Color(red: 0.15, green: 0.60, blue: 0.70), Color(red: 0.30, green: 0.75, blue: 0.85)]
        case .schedule: return [Color(red: 0.80, green: 0.50, blue: 0.10), Color(red: 0.95, green: 0.65, blue: 0.25)]
        case .drive: return [Color(red: 0.20, green: 0.50, blue: 0.85), Color(red: 0.35, green: 0.65, blue: 0.95)]
        case .navigation: return [Color(red: 0.10, green: 0.70, blue: 0.60), Color(red: 0.25, green: 0.85, blue: 0.75)]
        }
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

struct StatusTimestamp: View {
    let section: Object
    var body: some View { Caption("\(section.string("label", "미수신")) · 자료 시각 \(dateText(section.number("at")))") }
}
struct ReadOnlyNotice: View {
    var body: some View { Label("상태 조회는 자동 · 차량 제어는 직접 확인 후 전송", systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.muted) }
}
struct ControlsView: View {
    @ObservedObject var link: VehicleLink
    var body: some View {
        PageBody(title: "컨트롤") {
            CardTitle(title: "수동 제어", systemImage: "car.front.waves.up",
                      info: "상태 조회는 자동, 차량 제어는 확인 창에서 직접 전송함. 아래 3D 개폐는 화면 표시만 바뀌며 명령을 보내지 않음. 일반 도어 전동 열기·경적·원격 시동은 제공하지 않음.")
            ControlPanel(link: link)
            Vehicle3DPanel(link: link)
        }
    }
}
struct ClimateStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    var body: some View {
        let c = homePresentation(model, link).object("climate")
        PageBody(title: "실내 온도") {
            Image(systemName: "fanblades").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 20).accessibilityHidden(true)
            HStack { Metric(title: "실내", value: c.number("insideC"), digits: 1, suffix: "°C"); Metric(title: "외기", value: c.number("outsideC"), digits: 1, suffix: "°C") }
            HStack(spacing: 2) {
                StatusTimestamp(section: c)
                InfoNote("실내 온도", "차량에서 받은 온도임. 화면의 팬 아이콘은 장식이며 공조 작동 상태가 아님. 공조를 제어한 뒤에는 실제 온도 변화로 확인해야 함.")
            }
            ControlPanel(link: link, category: "climate")
        }
    }
}
struct LocationStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    var body: some View {
        let l = homePresentation(model, link).object("location")
        PageBody(title: "위치") {
            InfoCard {
                CardTitle(title: "마지막 차량 좌표", systemImage: "location.north",
                          info: "차량이 마지막으로 보고한 좌표임. 지도를 열면 그 좌표가 지도 앱에 전달됨. 저장된 위치는 현재 위치와 다를 수 있고, 지하 주차장 층수는 차량이 제공하지 않으므로 주차 기록에서 직접 입력해야 함.")
                StatusTimestamp(section: l)
                if !l.string("diagnostic").isEmpty { Text(l.string("diagnostic")).font(.subheadline).foregroundStyle(Theme.muted) }
                if !l.string("coordinateSource").isEmpty { Caption(l.string("coordinateSource")) }
                if let gpsAt = l.number("gpsAt") { Caption("차량 GPS 측정 \(dateText(gpsAt))") }
                if !l.string("gpsNote").isEmpty { Caption(l.string("gpsNote")) }
                if l.flag("hasCoordinates"), let lat = l.number("latitude"), let lng = l.number("longitude") {
                    Text("\(valueText(lat, digits: 5)), \(valueText(lng, digits: 5))").monospacedDigit().textSelection(.enabled)
                    if !model.demo, let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)") { Link("지도에서 저장 좌표 보기", destination: url).frame(minHeight: 44) }
                } else { Text("위치 미수신").foregroundStyle(Theme.muted) }
                Button("차량 위치 다시 받기") { link.refreshNow(retryUnavailable: true) }.disabled(model.demo || !link.authentic || link.refreshing)
            }
            InfoCard {
                CardTitle(title: "카카오 내장 내비", systemImage: "arrow.triangle.turn.up.right.diamond",
                          info: "차량 목적지를 앱 내 카카오 길안내로 시작함. 위치는 휴대폰 GPS를 사용함.")
                NavigationLink("내장 내비·화면 방향 설정", value: Page.navigation).frame(minHeight: 44)
            }
            NavigationLink("주차 위치·사진 기록", value: Page.care).frame(minHeight: 44)
        }
    }
}
struct ChargeStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var add = false
    var body: some View {
        let c = homePresentation(model, link).object("charge")
        PageBody(title: "충전") {
            HStack { Metric(title: "배터리 잔량", value: c.number("soc"), suffix: "%"); Metric(title: "표시 주행 가능 거리", value: c.number("rangeKm"), suffix: " km") }
            HStack(spacing: 2) {
                StatusTimestamp(section: c)
                InfoNote("충전 표시", "차량이 표시하는 주행 가능 거리는 최근 주행 효율로 계산된 값이라 실제 주행 거리와 다를 수 있음. 상태 조회는 자동이고, 제어는 확인 창에서 직접 전송함.")
            }
            InfoCard {
                CardTitle(title: "차량에서 받은 설정", systemImage: "bolt.badge.clock",
                          info: "차량에 현재 설정된 충전 한도와 충전기 출력임. 아래에서 보내는 값과는 별개이며, 전송 후 이 값이 갱신되는지로 확인함.")
                HStack { Metric(title: "충전 한도", value: c.number("limit"), suffix: "%"); Metric(title: "충전 출력", value: c.number("chargerKW"), suffix: " kW") }
            }
            ControlPanel(link: link, category: "charge")
            Button { add = true } label: { Label("충전 기록·영수증 추가", systemImage: "plus.circle").frame(maxWidth: .infinity).frame(minHeight: 44) }.buttonStyle(.bordered)
            NavigationLink("충전 이력·배터리 추정 보기", value: Page.battery).frame(minHeight: 44)
        }.sheet(isPresented: $add) { ChargeForm() }
    }
}
struct SecurityStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    var body: some View {
        PageBody(title: "보안 및 운전자") {
            InfoCard {
                CardTitle(title: "잠금 제어", systemImage: "checkmark.shield.fill",
                          info: "잠금 명령의 처리 응답은 받지만 잠금 센서 값은 수집하지 않으므로, 실제 잠금은 차량이나 공식 Tesla 앱에서 확인해야 함. 문이 닫힌 상태와 잠금은 다름. 자동 휴대폰 키·운전자 관리는 제공하지 않으며 이 앱은 Tesla 공식 앱이 아님.")
                ControlPanel(link: link, category: "security")
            }
            InfoCard {
                CardTitle(title: "조회 키 연결", systemImage: "key.radiowaves.forward",
                          info: "차량 근처에서 상태를 읽기 위한 인증 경로임. 조회 키 등록은 연결 화면의 요청과 차량 키카드 승인이 필요함.")
                Text(homePresentation(model, link).string("connection", "연결 상태 확인"))
                NavigationLink("연결·조회 키 설정", value: Page.connection).frame(minHeight: 44)
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
    let c: Object
    @ObservedObject var link: VehicleLink
    @State private var targetLimit: Double = 80
    @State private var currentAmps: Int = 32
    @State private var maxAmps: Int = 32
    @State private var isStoppingCharge = false

    var body: some View {
        let soc = Int(round(c.number("soc") ?? 56))
        let rangeKm = Int(round(c.number("rangeKm") ?? 296))
        let chargerKW = c.number("chargerKW") ?? 6.0
        let addedKWh = c.number("addedKWh") ?? 12.0
        let isCharging = chargerKW > 0.5 || c.flag("charging")
        let voltage = chargerKW > 0 ? Int(round(Double(chargerKW) * 1000.0 / Double(max(1, currentAmps)))) : 211

        VStack(spacing: 0) {
            // Main Card Body
            VStack(alignment: .leading, spacing: 14) {
                // Readout Header: SOC % & Range km + Live Status Badge
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(soc)")
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
                            Text("충전 대기")
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
                                .frame(width: max(8, w * min(socFrac, targetFrac)), height: 8)
                                .shadow(color: Color(red: 0.22, green: 0.88, blue: 0.55).opacity(0.4), radius: 3, x: 0, y: 0)

                            // Target Limit Marker Line / Thumb
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                                .offset(x: min(w - 20, max(0, w * targetFrac - 10)))
                                .gesture(
                                    DragGesture().onChanged { value in
                                        let frac = max(0.5, min(1.0, value.location.x / w))
                                        let newLimit = round(frac * 100.0 / 5.0) * 5.0
                                        if newLimit != targetLimit {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            targetLimit = newLimit
                                        }
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
                        Text("충전기 출력 \(Int(round(chargerKW))) kW · +\(Int(round(addedKWh))) kWh")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }

                // Power Flow & Energy Waveform Visualization
                PowerFlowGraphView(chargerKW: chargerKW, isCharging: isCharging)

                // Current Stepper Pill (< 32 A >)
                HStack {
                    Button {
                        if currentAmps > 5 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            currentAmps -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(currentAmps > 5 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 40)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("\(currentAmps) / \(maxAmps) A · \(voltage) V")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if currentAmps < maxAmps {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            currentAmps += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(currentAmps < maxAmps ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 40)
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

            // Bottom Action Buttons (충전 중지 | 충전 포트 잠금 해제)
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isStoppingCharge.toggle()
                    let action = isStoppingCharge ? "chargeStart" : "chargeStop"
                    link.askControl(action, title: isStoppingCharge ? "충전 시작" : "충전 중지")
                } label: {
                    Text(isStoppingCharge ? "충전 시작" : "충전 중지")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PlainButtonStyle())

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 48)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    link.askControl("portOpen", title: "충전 포트 잠금 해제")
                } label: {
                    Text("충전 포트 잠금 해제")
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
