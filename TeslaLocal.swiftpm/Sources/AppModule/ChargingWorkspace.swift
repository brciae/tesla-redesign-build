import SwiftUI
import Combine

/// Dedicated full-screen charging dashboard modeled after the official Tesla iOS application.
/// Includes 3D rear-quarter vehicle view, connected charging cable, animated flowing energy pulses,
/// interactive charge limit slider with spring physics, amperage stepper, and quick hardware actions.
struct ChargingWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced

    @State private var targetLimit: Double = 80
    @State private var currentAmps: Int = 32
    @State private var maxAmps: Int = 32
    @State private var isLeftChevronPressed = false
    @State private var isRightChevronPressed = false
    @State private var isSliderDragging = false

    var body: some View {
        let p = homePresentation(model, link)
        let c = p.object("charge")
        let soc = c.number("soc")
        let chargerKW = c.number("chargerKW")
        let minutesToLimit = c.number("minutesToLimit")
        let addedKWh = c.number("addedKWh")
        let isCharging = (model.demo || c.string("mode") == "recent") && c.chargingNow
        let isPlugged = isCharging || c.flag("plugged")
        let voltage = c.number("chargerVoltage").map { Int($0.rounded()) }

        let hours = Int(minutesToLimit ?? 0) / 60
        let mins = Int(minutesToLimit ?? 0) % 60
        let remainingText: String = {
            if isCharging {
                guard minutesToLimit != nil else { return "충전 중 · 남은 시간 미수신" }
                if hours > 0 {
                    return "충전 한도까지 \(hours)시간 \(mins)분 남음"
                } else {
                    return "충전 한도까지 \(mins)분 남음"
                }
            } else {
                return c.string("mode") == "recent" ? "충전 대기 중" : "충전 상태 미확인"
            }
        }()

        ZStack {
            // OLED True Dark Theme background
            Color(red: 13/255, green: 14/255, blue: 17/255)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ScreenBriefingControls(scope: .charging).padding(.horizontal, 20)
                    headerBar(soc: soc, isCharging: isCharging, remainingText: remainingText)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    // 3D Vehicle Charging View with plugged-in cable & flowing green neon pulses
                    ZStack(alignment: .bottom) {
                        Vehicle3DPanel(link: link, compact: true, chargingMode: true, isCharging: isCharging, isPlugged: isPlugged)

                        // Soft ground shadow & ambient reflection (only when charging)
                        if isCharging {
                            RadialGradient(
                                colors: [Color.green.opacity(0.12), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 120
                            )
                            .frame(width: 220, height: 60)
                            .blur(radius: 12)
                            .offset(y: -10)
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.top, 4)

                    // 4 Quick Control Action Icons (matching official Tesla layout)
                    quickActionRow(isCharging: isCharging)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)

                    // Official Tesla Charging Control Card
                    chargingControlCard(
                        soc: soc,
                        chargerKW: chargerKW,
                        addedKWh: addedKWh,
                        voltage: voltage,
                        isCharging: isCharging
                    )
                    .padding(.horizontal, 16)

                    // Sub-action Cards
                    VStack(spacing: 12) {
                        // Dashcam / Sentry Clips Card
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.white.opacity(0.8))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("최근 영상 클립 보기")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("블랙박스에 저장되었습니다")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(white: 0.12).opacity(0.85))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Controls Shortcut Card
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isPresented = false
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.white.opacity(0.8))

                                Text("컨트롤")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(white: 0.12).opacity(0.85))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Header
    private func headerBar(soc: Double?, isCharging: Bool, remainingText: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.settings.string("name", "Model Y"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                HStack(spacing: 6) {
                    // Battery capsule icon
                    HStack(spacing: 2) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
                                .frame(width: 24, height: 12)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isCharging ? Color(red: 0.0, green: 0.9, blue: 0.45) : Color.white)
                                .frame(width: max(0, 21 * CGFloat((soc ?? 0) / 100.0)), height: 8)
                                .padding(.leading, 1.5)
                        }
                    }

                    Text(soc.map { "\(Int($0.rounded()))%" } ?? "—%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isCharging ? Color(red: 0.0, green: 0.9, blue: 0.45) : .white)

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 0.45))
                    }
                }

                Text(remainingText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .padding(.top, 2)
            }

            Spacer()

            // Close / Dismiss Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    // MARK: - Quick Actions
    private func quickActionRow(isCharging: Bool) -> some View {
        HStack {
            quickActionIcon("lock.fill", active: false) {
                model.requestVehicleControl("lock", title: "차량 잠금")
            }
            Spacer()
            quickActionIcon("fanblades.fill", active: false) {
                model.requestVehicleControl("climateOn", title: "실내 공조")
            }
            Spacer()
            quickActionIcon("bolt.fill", active: true) {
                // Already in charging
            }
            Spacer()
            quickActionIcon("car.side.rear.open.fill", active: false) {
                model.requestVehicleControl("trunkMove", title: "트렁크")
            }
        }
    }

    private func quickActionIcon(_ systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(active ? 0.0 : 0.08))
                    .frame(width: 52, height: 52)

                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(active ? Color(red: 0.0, green: 0.9, blue: 0.45) : Color.white.opacity(0.85))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Charging Control Card
    private func chargingControlCard(
        soc: Double?,
        chargerKW: Double?,
        addedKWh: Double?,
        voltage: Int?,
        isCharging: Bool
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("충전 한도: \(Int(targetLimit))% · \(isCharging ? "충전 중" : "충전 대기")")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(chargerKW.map { String(format: "%.1f", $0) } ?? "—") kW · +\(addedKWh.map { String(format: "%.1f", $0) } ?? "—") kWh · \(voltage.map(String.init) ?? "—") V")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                // Interactive Charging Limit Slider with Spring Knob
                GeometryReader { geo in
                    let w = geo.size.width
                    let targetFrac = CGFloat(targetLimit / 100.0)
                    let socFrac = CGFloat((soc ?? 0) / 100.0)

                    ZStack(alignment: .leading) {
                        // Background full track
                        Capsule()
                            .fill(Color(white: 0.20))
                            .frame(height: 7)

                        // Allowed Limit track
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: max(7, w * targetFrac), height: 7)

                        // Active Glowing Green Progress
                        Capsule()
                            .fill(Color(red: 0.0, green: 0.9, blue: 0.45))
                            .frame(width: max(0, w * min(socFrac, targetFrac)), height: 7)
                            .shadow(color: Color(red: 0.0, green: 0.9, blue: 0.45).opacity(0.6), radius: 4, x: 0, y: 0)

                        // Draggable Limit Knob
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                            .scaleEffect(isSliderDragging ? 1.25 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSliderDragging)
                            .offset(x: min(w - 22, max(0, w * targetFrac - 11)))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isSliderDragging = true
                                        let frac = max(0.5, min(1.0, value.location.x / w))
                                        let newLimit = round(frac * 100.0 / 5.0) * 5.0
                                        if newLimit != targetLimit {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            targetLimit = newLimit
                                        }
                                    }
                                    .onEnded { _ in
                                        isSliderDragging = false
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        model.requestVehicleControl("chargeLimit", title: "충전 한도 설정", args: ["value": Int(targetLimit)])
                                    }
                            )
                    }
                }
                .frame(height: 24)

                // Amperage Stepper (< 32 A >)
                HStack {
                    Button {
                        if currentAmps > 6 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                isLeftChevronPressed = true
                                currentAmps -= 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                isLeftChevronPressed = false
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(currentAmps > 6 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 50, height: 44)
                            .scaleEffect(isLeftChevronPressed ? 0.85 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text("요청 \(currentAmps) A")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if currentAmps < maxAmps {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                isRightChevronPressed = true
                                currentAmps += 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                isRightChevronPressed = false
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(currentAmps < maxAmps ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                            .frame(width: 50, height: 44)
                            .scaleEffect(isRightChevronPressed ? 0.85 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(height: 44)
                .background(Color(white: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(18)

            Button("선택 전류 적용") { model.requestVehicleControl("chargeAmps", title: "충전 전류 설정", args: ["value": currentAmps]) }.buttonStyle(.bordered)
            // Divider Line
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Split Action Buttons ([ 충전 중지 ] | [ 충전 포트 잠금 해제 ])
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
                        .foregroundStyle(isCharging ? Color.white.opacity(0.85) : Color(red: 0.0, green: 0.9, blue: 0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PlainButtonStyle())

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 50)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.requestVehicleControl("portOpen", title: "충전 포트 잠금 해제")
                } label: {
                    Text("충전 포트 잠금 해제")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.9))
        )
    }
}
