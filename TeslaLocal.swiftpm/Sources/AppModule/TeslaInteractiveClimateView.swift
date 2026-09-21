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
    @State private var rearDefrost = false

    @State private var targetTemperature = 21.5
    @State private var isPowerOn = true

    private var blocked: Bool {
        model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil
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

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", targetTemperature))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("°C")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

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
        link.askControl("temperature", title: "온도 설정", args: ["value": targetTemperature])
    }

    // MARK: - Interactive Interior Cabin View

    private var interiorCabinView: some View {
        VStack(spacing: 16) {
            ZStack {
                // Cabin Glass Enclosure Silhouette
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.08), Color(white: 0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                    )

                VStack(spacing: 24) {
                    // Front Row: Steering Wheel (Driver side) & Front Passenger
                    HStack(spacing: 36) {
                        // Driver Seat & Steering Wheel
                        VStack(spacing: 12) {
                            // Steering Wheel Heater Button
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    steeringWheelHeat.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "steeringwheel")
                                        .font(.system(size: 16, weight: .bold))
                                    if steeringWheelHeat {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 12))
                                    }
                                }
                                .foregroundStyle(steeringWheelHeat ? Color(red: 1.0, green: 0.5, blue: 0.1) : Color.white.opacity(0.7))
                                .frame(width: 80, height: 38)
                                .background(
                                    steeringWheelHeat
                                        ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.2)
                                        : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            steeringWheelHeat
                                                ? Color(red: 1.0, green: 0.5, blue: 0.1).opacity(0.6)
                                                : Color.white.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(
                                    color: steeringWheelHeat ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.35) : .clear,
                                    radius: 8
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Driver Seat
                            seatButton(title: "운전석", level: $driverSeatHeat)
                        }

                        // Center Console Graphic
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 28, height: 44)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 32, height: 70)
                        }

                        // Front Passenger Seat
                        VStack(spacing: 12) {
                            // Spacer to align with steering wheel
                            Color.clear.frame(width: 80, height: 38)
                            seatButton(title: "동승자석", level: $passengerSeatHeat)
                        }
                    }
                    .padding(.top, 24)

                    // Rear Row: 3 Seats (Left, Center, Right)
                    HStack(spacing: 16) {
                        rearSeatButton(title: "후열 좌", level: $rearLeftHeat)
                        rearSeatButton(title: "후열 중", level: $rearCenterHeat)
                        rearSeatButton(title: "후열 우", level: $rearRightHeat)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 360)
        }
    }

    // MARK: - Seat Component

    private func seatButton(title: String, level: Binding<Int>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                level.wrappedValue = (level.wrappedValue + 1) % 4
            }
        } label: {
            ZStack {
                // Leather seat base silhouette
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.18),
                                Color(white: 0.11)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                level.wrappedValue > 0
                                    ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.8)
                                    : Color.white.opacity(0.15),
                                lineWidth: level.wrappedValue > 0 ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: level.wrappedValue > 0
                            ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(Double(level.wrappedValue) * 0.22)
                            : .clear,
                        radius: 12
                    )

                VStack(spacing: 6) {
                    // Headrest
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 16)

                    // Seat Back stitching lines
                    HStack(spacing: 4) {
                        ForEach(0..<level.wrappedValue, id: \.self) { _ in
                            Capsule()
                                .fill(Color(red: 1.0, green: 0.55, blue: 0.15))
                                .frame(width: 4, height: 14)
                        }
                    }
                    .frame(height: 14)

                    // Heat Icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            level.wrappedValue > 0
                                ? Color(red: 1.0, green: 0.50, blue: 0.1)
                                : Color.white.opacity(0.3)
                        )

                    // Level indicator badge
                    Text(level.wrappedValue == 0 ? "꺼짐" : "\(level.wrappedValue)단계")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            level.wrappedValue > 0
                                ? Color(red: 1.0, green: 0.6, blue: 0.2)
                                : Color.white.opacity(0.5)
                        )
                }
                .padding(.vertical, 10)
            }
            .frame(width: 96, height: 120)
        }
        .buttonStyle(MotionButtonStyle())
    }

    private func rearSeatButton(title: String, level: Binding<Int>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                level.wrappedValue = (level.wrappedValue + 1) % 4
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                level.wrappedValue > 0
                                    ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.8)
                                    : Color.white.opacity(0.12),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(
                        color: level.wrappedValue > 0
                            ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(Double(level.wrappedValue) * 0.2)
                            : .clear,
                        radius: 8
                    )

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            level.wrappedValue > 0
                                ? Color(red: 1.0, green: 0.50, blue: 0.1)
                                : Color.white.opacity(0.3)
                        )
                    Text(level.wrappedValue == 0 ? "OFF" : "\(level.wrappedValue)단")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(
                            level.wrappedValue > 0
                                ? Color(red: 1.0, green: 0.6, blue: 0.2)
                                : Color.white.opacity(0.45)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(MotionButtonStyle())
    }

    // MARK: - Quick Climate Control Bar

    private var quickClimateBar: some View {
        HStack(spacing: 12) {
            // Front Windshield Defrost
            quickBarButton(
                icon: "windshield.front.and.heat.waves",
                title: "앞유리 성에",
                isActive: frontDefrost,
                activeColor: Color(red: 1.0, green: 0.5, blue: 0.1)
            ) {
                withAnimation { frontDefrost.toggle() }
            }

            // Climate Power On/Off
            quickBarButton(
                icon: "power",
                title: isPowerOn ? "공조 끄기" : "공조 켜기",
                isActive: isPowerOn,
                activeColor: Color(red: 0.28, green: 0.88, blue: 0.42)
            ) {
                withAnimation {
                    isPowerOn.toggle()
                    link.askControl(isPowerOn ? "climateOn" : "climateOff", title: isPowerOn ? "공조 켜기" : "공조 끄기")
                }
            }

            // Rear Defrost
            quickBarButton(
                icon: "windshield.rear.and.heat.waves",
                title: "뒷유리 열선",
                isActive: rearDefrost,
                activeColor: Color(red: 0.35, green: 0.65, blue: 1.0)
            ) {
                withAnimation { rearDefrost.toggle() }
            }
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
