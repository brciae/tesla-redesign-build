import SwiftUI

/// Tesla Model Y official in-car touchscreen climate & comfort control view.
/// Recreated directly from Tesla Model Y Owner's Manual (실내 온도 조절 화면):
/// - Top HVAC Toolbar: Power (I), Auto, A/C, Fan Speed Stepper, Air Distribution (Face/Body/Foot), Defrost & Defog, Recirculation, Bioweapon Defense
/// - Interior Cabin Stage: 3D Model Y Interior with SSS Seat Heat & Vent controls, Steering Wheel Heat, Wiper Defrost, All Off
/// - Temperature Control: Stepper with non-truncating fixed-size display
/// - Rear Climate & Tesla Special Modes: Keep, Dog Mode, Camp Mode
struct TeslaInteractiveClimateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var link: VehicleLink

    // HVAC Primary States (Matching Tesla Model Y Manual [1, 2, 16, 15, 17, 13, 14, 11])
    @State private var isPowerOn = true
    @State private var isAuto = true
    @State private var isAC = true
    @State private var fanSpeed = 2
    @State private var ventFace = true
    @State private var ventBody = true
    @State private var ventFoot = false
    @State private var frontDefrost = false
    @State private var rearDefog = false
    @State private var isRecirculate = false
    @State private var isBioweapon = false

    // Front seats: Dual-mode Heating (0...3) and Ventilation (0...3) (Manual [3, 9, 10])
    @State private var driverSeatHeat = 0
    @State private var driverSeatVent = 0
    @State private var passengerSeatHeat = 0
    @State private var passengerSeatVent = 0

    // Rear seats: Heating (0...3) (Manual [9])
    @State private var rearLeftHeat = 0
    @State private var rearCenterHeat = 0
    @State private var rearRightHeat = 0

    // Steering wheel & wipers (Manual [4, 5])
    @State private var steeringWheelHeat = false
    @State private var wiperHeat = false

    // Cabin target temperatures (Manual [6, 15])
    @State private var targetTemperature = 21.5
    @State private var rearTemperature = 21.5
    @State private var rearPower = true
    @State private var rearFan = 1
    @State private var rearAuto = true

    // Special modes: 0 (Off), 1 (Keep), 2 (Dog), 3 (Camp) (Manual [7])
    @State private var specialMode = 0

    private var blocked: Bool {
        if model.fleet.isAuthenticated { return false }
        return model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    var body: some View {
        let climate = homePresentation(model, link).object("climate")
        let inside = climate.number("insideC")
        let outside = climate.number("outsideC")

        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Top HVAC Controls Grid (Matching Tesla Screen Top Bar [1, 2, 16, 15, 17, 13, 14, 11])
                teslaTopHVACBar

                // Temperature Stepper Banner (Guaranteed Zero Truncation)
                temperatureBanner(inside: inside, outside: outside)

                // Centerpiece Interior Cabin Stage (Manual [4, 5, 8, 9, 10])
                teslaInteriorCabinStage

                // Rear Climate Control Row (Manual [6])
                teslaRearClimateRow

                // Special Tesla Climate Modes (Manual [7]: Keep, Dog, Camp)
                teslaSpecialModesBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .onAppear {
            if let ins = inside {
                targetTemperature = min(28.0, max(16.0, (ins * 2.0).rounded() / 2.0))
                rearTemperature = targetTemperature
            }
        }
    }

    // MARK: - Top HVAC Controls Bar (Tesla Manual Items 1, 2, 16, 15, 17, 13, 14, 11)

    private var teslaTopHVACBar: some View {
        VStack(spacing: 8) {
            // Row 1: Power, Auto, A/C, Fan Stepper, Recirculate, Bioweapon
            HStack(spacing: 6) {
                // [1] Power Toggle
                teslaTileButton(
                    icon: "power",
                    label: "전원",
                    isActive: isPowerOn,
                    activeColor: Color(red: 0.20, green: 0.48, blue: 0.98)
                ) {
                    toggleClimatePower()
                }

                // [2] Auto Toggle
                teslaTileButton(
                    icon: "a.circle.fill",
                    label: "자동",
                    isActive: isAuto,
                    activeColor: Color(red: 0.20, green: 0.48, blue: 0.98)
                ) {
                    withAnimation { isAuto.toggle() }
                }

                // [16] A/C Compressor Toggle
                teslaTileButton(
                    icon: "snowflake",
                    label: "A/C",
                    isActive: isAC,
                    activeColor: Color(red: 0.20, green: 0.48, blue: 0.98)
                ) {
                    withAnimation { isAC.toggle() }
                }

                // [15] Fan Speed Stepper
                HStack(spacing: 4) {
                    Button {
                        if fanSpeed > 1 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            fanSpeed -= 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 38)
                    }
                    .disabled(fanSpeed <= 1)

                    HStack(spacing: 2) {
                        Image(systemName: "fanblades.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isPowerOn ? Color.cyan : Color.white.opacity(0.4))
                        Text("\(fanSpeed)")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    Button {
                        if fanSpeed < 5 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            fanSpeed += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 38)
                    }
                    .disabled(fanSpeed >= 5)
                }
                .padding(.horizontal, 4)
                .frame(height: 42)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 0.8))

                // [14] Recirculation
                teslaTileButton(
                    icon: "arrow.triangle.2.circlepath",
                    label: "순환",
                    isActive: isRecirculate,
                    activeColor: Color(red: 0.20, green: 0.48, blue: 0.98)
                ) {
                    withAnimation { isRecirculate.toggle() }
                }

                // [11] Bioweapon Defense Mode
                teslaTileButton(
                    icon: "allergens",
                    label: "바이오",
                    isActive: isBioweapon,
                    activeColor: Color(red: 0.20, green: 0.48, blue: 0.98)
                ) {
                    withAnimation { isBioweapon.toggle() }
                }
            }

            // Row 2: Airflow Distribution [17] & Defrost / Defog [13]
            HStack(spacing: 6) {
                // Airflow 3-Way Selector [17]
                HStack(spacing: 2) {
                    teslaVentDirButton(title: "윈드실드", icon: "windshield.front.and.heat.waves", isActive: $ventFace)
                    Divider().frame(height: 18).background(Color.white.opacity(0.2))
                    teslaVentDirButton(title: "정면", icon: "person.wave.2.fill", isActive: $ventBody)
                    Divider().frame(height: 18).background(Color.white.opacity(0.2))
                    teslaVentDirButton(title: "발밑", icon: "figure.walk", isActive: $ventFoot)
                }
                .padding(2)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 0.8))

                Spacer()

                // [13] Front Defrost & Rear Defog Pair
                HStack(spacing: 4) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            frontDefrost.toggle()
                            model.voice.say(frontDefrost ? "전면 성에 제거를 켰습니다." : "전면 성에 제거를 껐습니다.", key: "climate.defrost", category: "voiceControl", priority: 3, ttl: 5, manual: true)
                            if model.fleet.isAuthenticated {
                                Task { try? await model.fleet.setPreconditioningMax(on: frontDefrost) }
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "windshield.front.and.heat.waves")
                                .font(.system(size: 14))
                            Text("전면 성에")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(frontDefrost ? Color(red: 1.0, green: 0.45, blue: 0.1) : Color.white.opacity(0.65))
                        .frame(width: 58, height: 42)
                        .background(
                            frontDefrost
                                ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.25)
                                : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            rearDefog.toggle()
                            model.voice.say(rearDefog ? "후면 열선을 켰습니다." : "후면 열선을 껐습니다.", key: "climate.reardefog", category: "voiceControl", priority: 3, ttl: 5, manual: true)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "windshield.rear.and.heat.waves")
                                .font(.system(size: 14))
                            Text("후면 열선")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(rearDefog ? Color(red: 1.0, green: 0.45, blue: 0.1) : Color.white.opacity(0.65))
                        .frame(width: 58, height: 42)
                        .background(
                            rearDefog
                                ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.25)
                                : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(2)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
        }
        .padding(10)
        .background(Color(white: 0.10).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func teslaTileButton(
        icon: String,
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(isActive ? .white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                isActive ? activeColor : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? activeColor : Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .buttonStyle(MotionButtonStyle())
    }

    private func teslaVentDirButton(
        title: String,
        icon: String,
        isActive: Binding<Bool>
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { isActive.wrappedValue.toggle() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isActive.wrappedValue ? .white : Color.white.opacity(0.55))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                isActive.wrappedValue ? Color(red: 0.20, green: 0.48, blue: 0.98) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Temperature Stepper Banner (Non-Truncating Guaranteed)

    private func temperatureBanner(inside: Double?, outside: Double?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("목표 실내 온도")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                HStack(spacing: 6) {
                    if let inside {
                        Label("실내 \(String(format: "%.1f", inside))°C", systemImage: "thermometer.medium")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let outside {
                        Label("외기 \(String(format: "%.1f", outside))°C", systemImage: "sun.max.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            Spacer(minLength: 4)

            // Temperature Display with - / + Buttons (Rebalanced to prevent overflow)
            HStack(spacing: 8) {
                Button {
                    adjustTemperature(-0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(blocked || targetTemperature <= 16.0)

                // Fixed-size text container so numbers NEVER truncate into ellipsis
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", targetTemperature))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("°C")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    adjustTemperature(0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(blocked || targetTemperature >= 28.0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.10).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func adjustTemperature(_ delta: Double) {
        let newTemp = min(28.0, max(16.0, targetTemperature + delta))
        guard newTemp != targetTemperature else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        targetTemperature = newTemp
        rearTemperature = newTemp
        model.voice.say("실내 온도를 \(String(format: "%.1f", targetTemperature))도로 설정했습니다.", key: "climate.temp", category: "voiceControl", priority: 2, ttl: 4, manual: true)
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
        model.voice.say(isPowerOn ? "공조를 켰습니다." : "공조를 껐습니다.", key: "climate.power", category: "voiceControl", priority: 3, ttl: 5, manual: true)
        if !model.demo && link.authentic && link.controlEnabled && !link.controlBusy {
            link.askControl(isPowerOn ? "climateOn" : "climateOff", title: isPowerOn ? "공조 켜기" : "공조 끄기")
        } else if model.fleet.isAuthenticated {
            Task {
                try? await model.fleet.setAutoConditioning(on: isPowerOn)
            }
        }
    }

    // MARK: - Interior Cabin Stage (Tesla Manual Items 4, 5, 8, 9, 10)

    private var teslaInteriorCabinStage: some View {
        ZStack {
            // Dark Base Stage
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.11), Color(white: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.12), lineWidth: 1))

            // 3D Interior Graphic
            Image("TeslaTopInterior")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 380)
                .shadow(color: Color.black.opacity(0.9), radius: 16, y: 6)

            // Left Side Controls: Wiper Defrost [4] & Steering Wheel Heat [5]
            VStack(spacing: 8) {
                // [4] Wiper Defrost
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { wiperHeat.toggle() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "wiper")
                            .font(.system(size: 14))
                        Text("와이퍼")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(wiperHeat ? Color.orange : Color.white.opacity(0.65))
                    .frame(width: 44, height: 44)
                    .background(
                        wiperHeat ? Color.orange.opacity(0.25) : Color(white: 0.14).opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(wiperHeat ? Color.orange : Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())

                // [5] Steering Wheel Heater
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        steeringWheelHeat.toggle()
                        model.voice.say(steeringWheelHeat ? "스티어링 휠 열선을 켰습니다." : "스티어링 휠 열선을 껐습니다.", key: "climate.wheel", category: "voiceControl", priority: 3, ttl: 5, manual: true)
                        if model.fleet.isAuthenticated {
                            Task { try? await model.fleet.setSteeringWheelHeater(on: steeringWheelHeat) }
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 2) {
                            Image(systemName: "steeringwheel")
                                .font(.system(size: 14, weight: .bold))
                            if steeringWheelHeat {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                            }
                        }
                        Text("핸들열선")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(steeringWheelHeat ? Color.orange : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(
                        steeringWheelHeat ? Color.orange.opacity(0.3) : Color(white: 0.14).opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(steeringWheelHeat ? Color.orange : Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .offset(x: -145, y: -90)

            // Right Side Controls: [8] All Off (전체 끄기)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    driverSeatHeat = 0
                    driverSeatVent = 0
                    passengerSeatHeat = 0
                    passengerSeatVent = 0
                    rearLeftHeat = 0
                    rearCenterHeat = 0
                    rearRightHeat = 0
                    steeringWheelHeat = false
                    wiperHeat = false
                    // Turn off via Fleet API
                    if model.fleet.isAuthenticated {
                        Task {
                            try? await model.fleet.setSeatHeater(seatPosition: 0, level: 0)
                            try? await model.fleet.setSeatCooler(seatPosition: 0, level: 0)
                            try? await model.fleet.setSeatHeater(seatPosition: 1, level: 0)
                            try? await model.fleet.setSeatCooler(seatPosition: 1, level: 0)
                            try? await model.fleet.setSeatHeater(seatPosition: 2, level: 0)
                            try? await model.fleet.setSeatHeater(seatPosition: 4, level: 0)
                            try? await model.fleet.setSeatHeater(seatPosition: 5, level: 0)
                            try? await model.fleet.setSteeringWheelHeater(on: false)
                        }
                    }
                }
            } label: {
                Text("All Off")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.16).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 135, y: 70)

            // 1열 운전석 (Driver Seat): Dual Heat ♨️ & Vent 💨 [3, 9]
            teslaSeatControl(
                title: "운전석",
                heat: $driverSeatHeat,
                vent: $driverSeatVent,
                seatPosition: 0
            )
            .offset(x: -78, y: -15)

            // 1열 조수석 (Front Passenger Seat): Dual Heat ♨️ & Vent 💨 [9, 10]
            teslaSeatControl(
                title: "조수석",
                heat: $passengerSeatHeat,
                vent: $passengerSeatVent,
                seatPosition: 1
            )
            .offset(x: 78, y: -15)

            // 2열 좌측 시트 (Rear Left): 3단계 열선 [9]
            teslaRearSeatControl(
                title: "후열 좌",
                heat: $rearLeftHeat,
                seatPosition: 2
            )
            .offset(x: -82, y: 112)

            // 2열 중앙 시트 (Rear Center): 3단계 열선 [9]
            teslaRearSeatControl(
                title: "후열 중",
                heat: $rearCenterHeat,
                seatPosition: 4
            )
            .offset(x: 0, y: 112)

            // 2열 우측 시트 (Rear Right): 3단계 열선 [9]
            teslaRearSeatControl(
                title: "후열 우",
                heat: $rearRightHeat,
                seatPosition: 5
            )
            .offset(x: 82, y: 112)
        }
        .frame(height: 410)
    }

    // MARK: - Tesla Authentic Seat Control with SSS Heat / Vent (Manual Item 9)

    private func teslaSeatControl(
        title: String,
        heat: Binding<Int>,
        vent: Binding<Int>,
        seatPosition: Int
    ) -> some View {
        let isHeatActive = heat.wrappedValue > 0
        let isVentActive = vent.wrappedValue > 0

        return VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))

            HStack(spacing: 3) {
                // Heated Seat Button (♨️ SSS: Red 3-2-1-Off)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        let next = heat.wrappedValue == 0 ? 3 : (heat.wrappedValue - 1)
                        heat.wrappedValue = next
                        if next > 0 { vent.wrappedValue = 0 }
                        sendSeatCommand(seatPosition: seatPosition, heat: next, vent: vent.wrappedValue)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                        teslaSSSIndicator(count: heat.wrappedValue, activeColor: Color(red: 1.0, green: 0.35, blue: 0.1))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        isHeatActive ? Color(red: 1.0, green: 0.35, blue: 0.1).opacity(0.28) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHeatActive ? Color(red: 1.0, green: 0.35, blue: 0.1).opacity(0.8) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundStyle(isHeatActive ? Color(red: 1.0, green: 0.45, blue: 0.1) : Color.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())

                // Ventilated Seat Button (💨 SSS: Blue 3-2-1-Off)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        let next = vent.wrappedValue == 0 ? 3 : (vent.wrappedValue - 1)
                        vent.wrappedValue = next
                        if next > 0 { heat.wrappedValue = 0 }
                        sendSeatCommand(seatPosition: seatPosition, heat: heat.wrappedValue, vent: next)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "fanblades.fill")
                            .font(.system(size: 11, weight: .bold))
                        teslaSSSIndicator(count: vent.wrappedValue, activeColor: Color.cyan)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        isVentActive ? Color.cyan.opacity(0.28) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isVentActive ? Color.cyan.opacity(0.8) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundStyle(isVentActive ? Color.cyan : Color.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(3)
            .background(Color(white: 0.12).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func teslaRearSeatControl(
        title: String,
        heat: Binding<Int>,
        seatPosition: Int
    ) -> some View {
        let isHeatActive = heat.wrappedValue > 0

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                let next = heat.wrappedValue == 0 ? 3 : (heat.wrappedValue - 1)
                heat.wrappedValue = next
                sendSeatCommand(seatPosition: seatPosition, heat: next, vent: 0)
            }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))

                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    teslaSSSIndicator(count: heat.wrappedValue, activeColor: Color(red: 1.0, green: 0.4, blue: 0.1))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    isHeatActive ? Color(red: 1.0, green: 0.35, blue: 0.1).opacity(0.28) : Color(white: 0.14).opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHeatActive ? Color(red: 1.0, green: 0.45, blue: 0.1).opacity(0.8) : Color.white.opacity(0.15), lineWidth: 1)
                )
                .foregroundStyle(isHeatActive ? Color(red: 1.0, green: 0.45, blue: 0.1) : Color.white.opacity(0.6))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Tesla Authentic 3-Bar Wavy Indicator (SSS) matching manual
    private func teslaSSSIndicator(count: Int, activeColor: Color) -> some View {
        HStack(spacing: 1.5) {
            ForEach(1...3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index <= count ? activeColor : Color.white.opacity(0.2))
                    .frame(width: 2.5, height: 9)
            }
        }
    }

    private func sendSeatCommand(seatPosition: Int, heat: Int, vent: Int) {
        let seatName = (seatPosition == 0 ? "운전석" : (seatPosition == 1 ? "조수석" : "후열"))
        if heat > 0 {
            model.voice.say("\(seatName) 시트 열선을 \(heat)단계로 설정했습니다.", key: "climate.seat", category: "voiceControl", priority: 3, ttl: 4, manual: true)
        } else if vent > 0 {
            model.voice.say("\(seatName) 시트 통풍을 \(vent)단계로 설정했습니다.", key: "climate.vent", category: "voiceControl", priority: 3, ttl: 4, manual: true)
        }
        if model.fleet.isAuthenticated {
            Task {
                if heat > 0 {
                    try? await model.fleet.setSeatHeater(seatPosition: seatPosition, level: heat)
                } else if vent > 0 {
                    try? await model.fleet.setSeatCooler(seatPosition: seatPosition, level: vent)
                } else {
                    try? await model.fleet.setSeatHeater(seatPosition: seatPosition, level: 0)
                    try? await model.fleet.setSeatCooler(seatPosition: seatPosition, level: 0)
                }
            }
        }
    }

    // MARK: - Rear Climate Control Row (Tesla Manual Item 6)

    private var teslaRearClimateRow: some View {
        HStack(spacing: 8) {
            // Power (I) Rear
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation { rearPower.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                    Text("후열 (Rear)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(rearPower ? .white : Color.white.opacity(0.5))
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(rearPower ? Color.white.opacity(0.12) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Rear Fan Stepper [-] 🪭 {fan} [+]
            HStack(spacing: 4) {
                Button {
                    if rearFan > 1 { rearFan -= 1 }
                } label: {
                    Image(systemName: "minus").font(.caption2.bold()).foregroundStyle(.white).frame(width: 20, height: 38)
                }
                HStack(spacing: 2) {
                    Image(systemName: "fanblades").font(.caption2).foregroundStyle(Color.cyan)
                    Text("\(rearFan)").font(.caption.bold()).foregroundStyle(.white)
                }
                Button {
                    if rearFan < 5 { rearFan += 1 }
                } label: {
                    Image(systemName: "plus").font(.caption2.bold()).foregroundStyle(.white).frame(width: 20, height: 38)
                }
            }
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Rear Temp Stepper [-] {temp}° [+]
            HStack(spacing: 4) {
                Button {
                    rearTemperature = max(16.0, rearTemperature - 0.5)
                } label: {
                    Image(systemName: "minus").font(.caption2.bold()).foregroundStyle(.white).frame(width: 20, height: 38)
                }
                Text(String(format: "%.1f°", rearTemperature))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
                Button {
                    rearTemperature = min(28.0, rearTemperature + 0.5)
                } label: {
                    Image(systemName: "plus").font(.caption2.bold()).foregroundStyle(.white).frame(width: 20, height: 38)
                }
            }
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Rear Auto
            Button {
                withAnimation { rearAuto.toggle() }
            } label: {
                Text("Auto")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(rearAuto ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(rearAuto ? Color(red: 0.20, green: 0.48, blue: 0.98) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(10)
        .background(Color(white: 0.10).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Tesla Special Modes Bar (Manual Item 7: Keep, Dog, Camp)

    private var teslaSpecialModesBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                specialModeButton(title: "유지 (Keep)", icon: "fanblades", modeIndex: 1)
                specialModeButton(title: "애견 (Dog)", icon: "pawprint.fill", modeIndex: 2)
                specialModeButton(title: "캠프 (Camp)", icon: "tent.fill", modeIndex: 3)
            }

            Text("※ 차량에서 내린 후에도 실내 공조가 계속 유지됩니다.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 2)
        }
        .padding(10)
        .background(Color(white: 0.10).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func specialModeButton(title: String, icon: String, modeIndex: Int) -> some View {
        let isSelected = specialMode == modeIndex

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                specialMode = isSelected ? 0 : modeIndex
                let modeText: String
                switch specialMode {
                case 1: modeText = "실내 온도 유지 모드를 켰습니다."
                case 2: modeText = "애견 모드를 켰습니다. 실내 온도를 안전하게 유지합니다."
                case 3: modeText = "캠프 모드를 켰습니다. 실내 온도와 전원이 유지됩니다."
                default: modeText = "특수 모드를 껐습니다."
                }
                model.voice.say(modeText, key: "climate.mode", category: "voiceControl", priority: 3, ttl: 5, manual: true)
                if model.fleet.isAuthenticated {
                    Task { try? await model.fleet.setClimateKeeperMode(mode: specialMode) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isSelected ? Color(red: 0.20, green: 0.48, blue: 0.98) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.20, green: 0.48, blue: 0.98) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
