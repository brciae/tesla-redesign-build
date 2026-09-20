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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    NavigationLink(value: Page.connection) {
                        HStack(spacing: 10) {
                            Text(model.settings.string("name", "Model Y L")).font(.title.weight(.semibold)).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.muted)
                        }.frame(minHeight: 44)
                    }.accessibilityLabel("차량 프로필 및 연결 설정")
                    Spacer(minLength: 4)
                    NavigationLink(value: Page.briefing) { Image(systemName: "bubble.left").font(.system(size: 23)).frame(width: 44, height: 44) }
                        .accessibilityLabel("오늘의 브리핑")
                    NavigationLink(value: Page.connection) { Image(systemName: "line.3.horizontal").font(.system(size: 22)).frame(width: 44, height: 44) }
                        .accessibilityLabel("연결 설정 및 백업")
                }.buttonStyle(MotionButtonStyle())
                // Jijijik-style top-right combined Battery & Range readout
                HStack {
                    HStack(spacing: 8) {
                        BatteryGauge(level: c.number("soc")).accessibilityHidden(true)
                        Text(valueText(c.number("soc"), suffix: "%")).monospacedDigit()
                            .contentTransition(.numericText()).animation(reduced ? nil : .easeOut(duration: 0.28), value: c.number("soc"))
                        Text(c.string("label", "미수신")).font(.caption)
                    }.foregroundStyle(c.string("mode") == "example" ? .orange : c.string("mode") == "recent" ? .white : Theme.muted)
                        .accessibilityElement(children: .combine)
                    Spacer()
                    let socVal = c.number("soc") ?? 53
                    let rangeVal = c.number("rangeKm") ?? 296
                    HStack(spacing: 6) {
                        Text("\(Int(round(socVal)))% · \(Int(round(rangeVal)))km")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                        Image(systemName: "battery.75")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.45))
                    }
                    .padding(.trailing, 4)
                }.padding(.top, 2)
                NavigationLink(value: Page.connection) {
                    HStack(spacing: 7) {
                        Image(systemName: link.authentic && !model.demo ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        Text(model.demo ? "예시 모드 · 실차와 분리" : link.status)
                        if link.busy || link.refreshing { ProgressView().controlSize(.mini).accessibilityLabel("차량 정보 최신화 중") }
                    }.font(.caption).foregroundStyle(Theme.muted).frame(minHeight: 44, alignment: .leading)
                }.buttonStyle(MotionButtonStyle())
                HStack(spacing: 2) {
                    Caption("배터리 자료 시각 \(dateText(c.number("at")))")
                    InfoNote("배터리 표시", "차량에서 마지막으로 받은 값임. 최신 상태는 차량 근처에서 연결된 뒤 갱신됨. 예시 모드에서는 실제 차량과 무관한 자료가 표시됨.")
                }
                if let storageStatus = model.storageStatus {
                    Text(storageStatus).font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("recordStorageStatus").padding(.vertical, 8)
                }
                Vehicle3DPanel(link: link, compact: true).padding(.top, 2)
                
                // Jijijik-style TESLA wordmark + Model selector pill
                VStack(spacing: 10) {
                    Text("T E S L A")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white.opacity(0.9))

                    NavigationLink(value: Page.connection) {
                        HStack(spacing: 6) {
                            Text("대표")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(model.settings.string("name", "Model Y 2026"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(white: 0.12).opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                    }
                    .buttonStyle(MotionButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)



                HStack(spacing: 2) {
                    Caption("빠른 제어")
                    InfoNote("빠른 제어", "각 화면에서 버튼을 고르고 확인 창에서 한 번 더 전송을 눌러야 차량에 명령이 나감. 잠금 센서 상태는 수집하지 않으므로 실제 잠금은 차량에서 확인해야 함.")
                }
                let isCharging = (c.number("chargerKW") ?? 0) > 0.5 || c.flag("charging")
                HStack {
                    quickControl(.security, "lock.fill", "잠금 제어")
                    quickControl(.climate, "fanblades.fill", "공조 제어")
                    quickControl(.charging, "bolt.fill", "충전 제어", highlight: isCharging)
                    quickControl(.controls, "car.side.rear.open.fill", "트렁크 제어")
                }.padding(.bottom, 14)

                // Tesla Official App Charging Card
                TeslaOfficialChargingCardView(c: c, link: link)
                    .padding(.bottom, 18)
                driveButton
                SmartParkingCard(link: link)
                briefing
                let controls = layout.shown.filter(\.isControl)
                let records = layout.shown.filter { !$0.isControl }
                ForEach(controls) { module in
                    menu(module.page, module.icon,
                         subtitle: module == .location ? p.object("location").string("subtitle", "위치 미수신") : module.subtitle,
                         title: module.title)
                }
                if !records.isEmpty {
                    LinearGradient(colors: [.clear, Color.white.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1).padding(.top, 18).padding(.bottom, 24)
                    Text("기록·설정").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).padding(.bottom, 12)
                    ForEach(records) { module in
                        menu(module.page, module.icon, subtitle: module.subtitle, title: module.title)
                    }
                }
                Button { editing = true } label: {
                    Label("홈 메뉴 편집", systemImage: "square.grid.2x2").frame(minHeight: 44)
                }.buttonStyle(.bordered).padding(.top, 16)
                LinearGradient(colors: [.clear, Color.white.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1).padding(.vertical, 26)
                Text(model.settings.string("model", "Model Y L").uppercased()).font(.system(size: 19, weight: .light, design: .rounded)).tracking(4)
                Caption("YL COMPANION · v0.43").padding(.top, 6)
                if model.demo { Button("예시 모드 종료") { model.exitDemo() }.frame(minHeight: 44).padding(.top, 12) }
            }.frame(maxWidth: HomeVisualStyle.contentWidth).padding(.horizontal, HomeVisualStyle.gutter).padding(.top, HomeVisualStyle.headerTop).padding(.bottom, 40).frame(maxWidth: .infinity)
        }.background(Theme.bg).toolbar(.hidden, for: .navigationBar)
            .refreshable { model.refreshVehicle() }
            .sheet(isPresented: $editing) { HomeLayoutEditor() }
    }
    private func quickControl(_ page: Page, _ symbol: String, _ label: String, highlight: Bool = false) -> some View {
        NavigationLink(value: page) {
            Image(systemName: symbol).font(.system(size: 25)).frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(highlight ? Color(red: 0.28, green: 0.88, blue: 0.42) : Theme.muted)
        }
        .buttonStyle(MotionButtonStyle()).accessibilityLabel(label)
    }
    /// Full-screen driving view. Styled like the rest of the list instead of a filled system button.
    private var driveButton: some View {
        Button { model.navigation.presented = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("운전 대시보드").font(.title3.weight(.semibold))
                    Text("전체 화면 주행·내비 표시").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.forward").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(MotionButtonStyle())
        .foregroundStyle(.white)
        .padding(.bottom, 14)
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
    private func menu(_ page: Page, _ icon: String, subtitle: String?, title: String? = nil) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 21) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(Theme.muted).frame(width: 30).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title ?? page.rawValue).font(.title2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.5)).accessibilityHidden(true)
            }.frame(minHeight: 40).padding(.vertical, 20).contentShape(Rectangle())
        }.buttonStyle(MotionButtonStyle())
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

private struct TeslaOfficialChargingCardView: View {
    let c: Object
    @ObservedObject var link: VehicleLink
    @State private var targetLimit: Double = 80
    @State private var currentAmps: Int = 32
    @State private var maxAmps: Int = 32
    @State private var isStoppingCharge = false

    var body: some View {
        let soc = Int(round(c.number("soc") ?? 56))
        let chargerKW = c.number("chargerKW") ?? 6.0
        let addedKWh = c.number("addedKWh") ?? 12.0
        let isCharging = chargerKW > 0.5 || c.flag("charging")
        let voltage = chargerKW > 0 ? Int(round(Double(chargerKW) * 1000.0 / Double(max(1, currentAmps)))) : 211

        VStack(spacing: 0) {
            // Main Card Body
            VStack(alignment: .leading, spacing: 12) {
                // Line 1: 충전 한도: 80% · 충전 중
                HStack {
                    Text("충전 한도: \(Int(targetLimit))% · \(isCharging ? "충전 중" : "충전 완료")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }

                // Line 2: 6 kW · +12 kWh · 32/32A · 211V
                HStack {
                    Text("\(Int(round(chargerKW))) kW · +\(Int(round(addedKWh))) kWh · \(currentAmps)/\(maxAmps)A · \(voltage)V")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Spacer()
                }

                // Line 3: Charge Limit Slider
                GeometryReader { geo in
                    let w = geo.size.width
                    let targetFrac = CGFloat(targetLimit / 100.0)
                    let socFrac = CGFloat(Double(soc) / 100.0)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(white: 0.18))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color(red: 0.28, green: 0.88, blue: 0.42))
                            .frame(width: max(6, w * socFrac), height: 6)
                        if targetFrac > socFrac {
                            Capsule()
                                .fill(Color(white: 0.28))
                                .frame(width: max(0, w * (targetFrac - socFrac)), height: 6)
                                .offset(x: w * socFrac)
                        }
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            .offset(x: min(w - 20, max(0, w * targetFrac - 10)))
                    }
                }
                .frame(height: 20)
                .padding(.vertical, 4)

                // Line 4: Current Stepper Pill (< 32 A >)
                HStack {
                    Button {
                        if currentAmps > 5 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            currentAmps -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(currentAmps > 5 ? Color.white.opacity(0.8) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 42)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("\(currentAmps) A")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if currentAmps < maxAmps {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            currentAmps += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(currentAmps < maxAmps ? Color.white.opacity(0.8) : Color.white.opacity(0.25))
                            .frame(width: 44, height: 42)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(height: 42)
                .background(Color(white: 0.15).opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundStyle(Color.white.opacity(0.8))
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
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(white: 0.10).opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
