import SwiftUI

/// Tesla official-style interactive vehicle cabin climate & seat comfort control view.
/// Allows drivers to tap directly on vehicle seats and steering wheel to control seat heating/ventilation,
/// adjust target cabin temperature with sleek glass controls, and toggle defrost/power modes.
struct TeslaInteractiveClimateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var link: VehicleLink

    // Seat heat levels: 0 (Off), 1 (Low), 2 (Medium), 3 (High)
    @State private var driverSeatHeat = 0
    @State private var passengerSeatHeat = 0
    @State private var rearLeftHeat = 0
    @State private var rearCenterHeat = 0
    @State private var rearRightHeat = 0
    @State private var steeringWheelHeat = false
    @State private var frontDefrost = false

    @State private var targetTemperature = 21.5
    @State private var isPowerOn = true

    private var blocked: Bool {
        if model.fleet.isAuthenticated { return false }
        return model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    var body: some View {
        let climate = homePresentation(model, link).object("climate")
        let inside = climate.number("insideC")
        let outside = climate.number("outsideC")

        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Top Floating Temperature Glass Card
                temperatureControlHeader(inside: inside, outside: outside)

                // Interactive Cabin Graphic with Direct Seat Touch
                interiorCabinView

                // Bottom Quick Climate Control Bar
                quickClimateBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .onAppear {
            if let ins = inside {
                targetTemperature = min(28.0, max(16.0, (ins * 2.0).rounded() / 2.0))
            }
        }
    }

    // MARK: - Temperature Header

    private func temperatureControlHeader(inside: Double?, outside: Double?) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("목표 실내 온도")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                    HStack(spacing: 12) {
                        if let inside {
                            Label("실내 \(String(format: "%.1f", inside))°C", systemImage: "thermometer.medium")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        if let outside {
                            Label("외기 \(String(format: "%.1f", outside))°C", systemImage: "sun.max.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                }
                Spacer()

                // Climate State Indicator Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPowerOn ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(isPowerOn ? "공조 작동 중" : "꺼짐")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPowerOn ? .white : Color.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.8))
            }

            // Large Temperature Display with Stepper Buttons
            HStack(spacing: 24) {
                Button {
                    adjustTemperature(-0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(blocked || targetTemperature <= 16.0)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", targetTemperature))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("°C")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .layoutPriority(1)

                Spacer()

                Button {
                    adjustTemperature(0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(blocked || targetTemperature >= 28.0)
            }
            .padding(.vertical, 8)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func adjustTemperature(_ delta: Double) {
        let newTemp = min(28.0, max(16.0, targetTemperature + delta))
        guard newTemp != targetTemperature else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        targetTemperature = newTemp
        if !model.demo && link.authentic && link.controlEnabled && !link.controlBusy {
            link.askControl("temperature", title: "온도 설정", args: ["value": targetTemperature])
        } else if model.fleet.isAuthenticated {
            Task {
                try? await model.fleet.setTemps(driverTemp: targetTemperature, passengerTemp: targetTemperature)
            }
        }
    }

    private func toggleClimatePower() {
        isPowerOn.toggle()
        if !model.demo && link.authentic && link.controlEnabled && !link.controlBusy {
            link.askControl(isPowerOn ? "climateOn" : "climateOff", title: isPowerOn ? "공조 켜기" : "공조 끄기")
        } else if model.fleet.isAuthenticated {
            Task {
                try? await model.fleet.setAutoConditioning(on: isPowerOn)
            }
        }
    }

    // MARK: - Interactive Interior Cabin View

    // MARK: - Interactive Interior Cabin View

    private var interiorCabinView: some View {
        ZStack {
            // Dark Stage Ambient Base
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.10), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            // High-Resolution 3D Tesla Cabin Interior Render
            Image("TeslaTopInterior")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 370)
                .shadow(color: Color.black.opacity(0.85), radius: 18, y: 8)

            // Steering Wheel Heater Button (In front of driver seat)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    steeringWheelHeat.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "steeringwheel")
                        .font(.system(size: 15, weight: .bold))
                    if steeringWheelHeat {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(steeringWheelHeat ? Color(red: 1.0, green: 0.5, blue: 0.1) : Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    steeringWheelHeat
                        ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.3)
                        : Color(white: 0.15).opacity(0.75),
                    in: Capsule()
                )
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            steeringWheelHeat
                                ? Color(red: 1.0, green: 0.5, blue: 0.1).opacity(0.7)
                                : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: steeringWheelHeat ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.5) : .clear,
                    radius: 8
                )
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: -80, y: -105)

            // Driver Seat Hotspot
            seatHotspot(title: "운전석", level: $driverSeatHeat)
                .offset(x: -74, y: -20)

            // Front Passenger Seat Hotspot
            seatHotspot(title: "조수석", level: $passengerSeatHeat)
                .offset(x: 74, y: -20)

            // Rear Left Seat Hotspot
            seatHotspot(title: "후열 좌", level: $rearLeftHeat)
                .offset(x: -82, y: 105)

            // Rear Center Seat Hotspot
            seatHotspot(title: "후열 중", level: $rearCenterHeat)
                .offset(x: 0, y: 105)

            // Rear Right Seat Hotspot
            seatHotspot(title: "후열 우", level: $rearRightHeat)
                .offset(x: 82, y: 105)
        }
        .frame(height: 390)
    }

    // MARK: - Seat Hotspot Component

    private func seatHotspot(title: String, level: Binding<Int>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                level.wrappedValue = (level.wrappedValue + 1) % 4
            }
        } label: {
            let active = level.wrappedValue > 0
            VStack(spacing: 3) {
                HStack(spacing: 2) {
                    Image(systemName: active ? "flame.fill" : "flame")
                        .font(.system(size: 14, weight: .bold))
                    if active {
                        Text("\(level.wrappedValue)")
                            .font(.system(size: 12, weight: .black))
                    }
                }
                .foregroundStyle(
                    active
                        ? Color(red: 1.0, green: 0.45, blue: 0.1)
                        : Color.white.opacity(0.65)
                )

                Text(active ? "\(level.wrappedValue)단" : "꺼짐")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(active ? .white : Color.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                active
                    ? Color(red: 1.0, green: 0.42, blue: 0.08).opacity(0.28)
                    : Color(white: 0.12).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        active
                            ? Color(red: 1.0, green: 0.5, blue: 0.1).opacity(0.8)
                            : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: active ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.45) : .clear,
                radius: 10
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Quick Climate Control Bar

    private var quickClimateBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Front Windshield Defrost Max
                quickBarButton(
                    icon: "windshield.front.and.heat.waves",
                    title: frontDefrost ? "성에 끄기" : "최대 성에",
                    isActive: frontDefrost,
                    activeColor: Color(red: 1.0, green: 0.5, blue: 0.1)
                ) {
                    withAnimation {
                        frontDefrost.toggle()
                        if model.fleet.isAuthenticated {
                            Task { try? await model.fleet.setPreconditioningMax(on: frontDefrost) }
                        }
                    }
                }

                // Climate Power On/Off
                quickBarButton(
                    icon: "power",
                    title: isPowerOn ? "공조 끄기" : "공조 켜기",
                    isActive: isPowerOn,
                    activeColor: Color(red: 0.28, green: 0.88, blue: 0.42)
                ) {
                    withAnimation {
                        toggleClimatePower()
                    }
                }

                // Preset Comfort Temperature (21.5°C)
                quickBarButton(
                    icon: "sparkles",
                    title: "쾌적 21.5°C",
                    isActive: targetTemperature == 21.5,
                    activeColor: Color(red: 0.35, green: 0.65, blue: 1.0)
                ) {
                    adjustTemperature(21.5 - targetTemperature)
                }
            }

            Text("※ 스마트 하이브리드 제어: 차 근처에서는 초고속 BLE로, 멀리서는 테슬라 Fleet API(LTE)로 전송됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func quickBarButton(
        icon: String,
        title: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.white.opacity(0.55))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? .white : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                isActive ? activeColor.opacity(0.16) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isActive ? activeColor.opacity(0.5) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(MotionButtonStyle())
        .disabled(blocked)
    }
}
