import SwiftUI

/// Tesla authentic vehicle exterior body control view.
/// Smart Hybrid Architecture:
/// - Near vehicle (BLE connected): Zero-latency, end-to-end encrypted direct Bluetooth control.
/// - Remote / Anywhere (LTE Fleet API): Cloud command transmission via Tesla's official Fleet API.
/// Supported actions:
/// - Front Hood: Frunk Open (`frunkOpen` / `actuateTrunk front`)
/// - Center Roof: Lock / Unlock toggle (`lock` / `unlock` / `doorLock` / `doorUnlock`)
/// - Rear Trunk: Trunk Move / Close (`trunkMove` / `actuateTrunk rear`)
/// - Rear Left Flap: Charge Port Open / Close (`portOpen` / `portClose` / `chargePortDoor`)
/// - Secondary Quick Grid: Remote Start (`remoteStartDrive`), Flash Lights (`flashLights`),
///   Honk Horn (`honkHorn`), Defrost Max (`setPreconditioningMax`).
struct TeslaInteractiveControlsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject private var appearanceStore = VehicleAppearanceStore.shared
    @State private var enrollment = false
    @State private var remoteStartAlert = false
    @State private var tokenSheet = false
    @State private var statusToast: String? = nil
    @State private var isExecutingRemote = false
    @State private var focus: VehicleCameraCommand? = nil

    private var currentAppearance: VehicleAppearance {
        appearanceStore.value(for: VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                ScreenBriefingControls(scope: .controls)
                // Live Status / Toast Banner
                if let statusToast {
                    HStack(spacing: 8) {
                        Image(systemName: isExecutingRemote ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(statusToast)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Button {
                            self.statusToast = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.fill(0.14).opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
                }

                // Control Busy Progress Banner
                if link.controlBusy || link.preparingControl || isExecutingRemote || model.fleet.isSendingCommand {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(link.controlBusy ? "BLE 근거리 명령 전송 중…" : (isExecutingRemote || model.fleet.isSendingCommand ? "LTE 클라우드 원격 전송 중…" : "제어 세션 준비 중…"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.4), lineWidth: 1))
                }

                // v1.22: canvas layout — status card, big lock button, 4×2 action grid.
                closureStatusCard
                lockButton
                actionGrid

                // Hybrid Connection Scope Notice Card
                hybridConnectionNotice

                // Tesla Fleet Cloud & BLE Authentication Management

            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .confirmationDialog("별도 BLE 제어 키 등록을 요청하시겠습니까?", isPresented: $enrollment, titleVisibility: .visible) {
            Button("등록 요청") { link.enrollControlKey() }
            Button("취소", role: .cancel) {}
        }
        .alert("원격 시동 승인", isPresented: $remoteStartAlert) {
            Button("승인 (2분간 운행 가능)", role: .none) {
                executeFleetAction(title: "원격 시동 승인") {
                    try await model.fleet.remoteStartDrive()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("테슬라 공식 Fleet API(LTE)를 통해 차량 컴퓨터로 원격 시동 명령을 전송합니다. 승인 후 2분 이내에 브레이크를 밟고 기어를 변속하면 키 없이 주행할 수 있습니다.")
        }
        .sheet(isPresented: $tokenSheet) {
            NavigationStack { ConnectionView(link: link) }.environmentObject(model)
        }
    }

    // MARK: - v1.22 Canvas Layout

    private var snapshot: FleetVehicleSnapshot? {
        guard let s = model.fleet.vehicleSnapshot, s.vin == model.fleet.selectedVin else { return nil }
        return s
    }
    /// v1.41: plugged/charging → the 3D car shows the cable (doors still animate).
    private var chargeNow: (charging: Bool, plugged: Bool) {
        let c = homePresentation(model, link).object("charge")
        let charging = c.chargingNow
        return (charging, charging || c.flag("plugged") || portText.0 == "연결")
    }
    private var lockState: Bool? {
        if model.output.object("fresh").flag("closures"), let v = model.groups.object("closures")["locked"] as? Bool { return v }
        return snapshot?.locked
    }
    private func openCount(_ keys: [String]) -> Int? {
        guard let s = snapshot else { return nil }
        let values = keys.compactMap { s.number("vehicle_state", $0) }
        return values.isEmpty ? nil : values.filter { $0 > 0 }.count
    }
    /// v1.41: live BLE closure state (what the 3D model shows) wins over a Fleet snapshot without body data.
    private func bleOpenCount(_ parts: [String]) -> Int? {
        // v1.42: same rule as the 3D model (received in the last 2 min), not the stricter verified-session flag.
        let g = model.groups.object("closures")
        let received = g.number("receivedAt") ?? g.number("at") ?? 0
        guard !parts.isEmpty, model.output.object("fresh").flag("closures") || Date().timeIntervalSince1970 * 1000 - received <= 120_000 else { return nil }
        let v = parts.compactMap { g[$0] as? Bool }
        return v.count == parts.count ? v.filter { $0 }.count : nil
    }
    private func closureText(_ keys: [String], ble: [String] = [], all: Bool) -> (String, Color) {
        guard let n = bleOpenCount(ble) ?? openCount(keys) else { return ("미수신", Color.secondary) }
        if n == 0 { return (all ? "모두 닫힘" : "닫힘", Color.primary) }
        return (keys.count > 1 ? "\(n)개 열림" : "열림", Color.orange)
    }
    private var portText: (String, Color) {
        guard let s = snapshot else { return ("미수신", Color.secondary) }
        let charge = s.payload.object("charge_state")
        if let cable = charge["conn_charge_cable"] as? String, !cable.isEmpty, cable != "<invalid>" { return ("연결", Color.green) }
        if let open = charge["charge_port_door_open"] as? Bool { return open ? ("열림", Color.orange) : ("닫힘", Color.primary) }
        return ("미수신", Color.secondary)
    }

    private var closureStatusCard: some View {
        let rows: [(String, (String, Color))] = [
            ("문", closureText(["df", "pf", "dr", "pr"], ble: ["driverFront", "passengerFront", "driverRear", "passengerRear"], all: true)),
            ("창문", closureText(["fd_window", "fp_window", "rd_window", "rp_window"], all: true)),
            ("프렁크", closureText(["ft"], ble: ["frunk"], all: false)),
            ("트렁크", closureText(["rt"], ble: ["trunk"], all: false)),
            ("충전구", portText)
        ]
        return VStack(spacing: 12) {
            // v1.26: live 3D model (same as home) on a white card; actions swing the camera to the part.
            Vehicle3DPanel(link: link, compact: true, chargingMode: true, isCharging: chargeNow.charging, isPlugged: chargeNow.plugged, focus: focus)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1.0).foregroundStyle(row.1.1).fontWeight(.medium)
                    }
                    .font(.system(size: 15))
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var lockButton: some View {
        let locked = lockState
        let unlocked = locked == false
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if locked == false {
                dispatchHybridAction(title: "차량 잠금", bleAction: "lock", fleetAction: { try await model.fleet.doorLock() })
            } else {
                dispatchHybridAction(title: "잠금 해제", bleAction: "unlock", fleetAction: { try await model.fleet.doorUnlock() })
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill").font(.system(size: 26, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(locked == nil ? "잠금 상태 미수신" : (unlocked ? "잠금 해제됨" : "잠김")).font(.system(size: 17, weight: .semibold))
                    Text(unlocked ? "눌러서 잠그기" : "눌러서 잠금 해제").font(.system(size: 13)).opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(unlocked ? Color.white : Color.primary)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(unlocked ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(MotionButtonStyle())
    }

    private func focusCamera(yaw: Float, pitch: Float) {
        focus = VehicleCameraCommand(serial: (focus?.serial ?? 0) + 1, action: "angle", yaw: yaw, pitch: pitch, zoom: nil)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
            gridButton("프렁크", "car.side.front.open.fill") { focusCamera(yaw: 0, pitch: 1.1); dispatchHybridAction(title: "프렁크 열기", bleAction: "frunkOpen", fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "front") }) }
            gridButton("트렁크", "car.side.rear.open.fill") { focusCamera(yaw: .pi, pitch: 1.1); dispatchHybridAction(title: "트렁크 동작", bleAction: "trunkMove", fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "rear") }) }
            Menu {
                Button("충전구 열기") { focusCamera(yaw: 2.38, pitch: 0.32); dispatchHybridAction(title: "충전구 열기", bleAction: "portOpen", fleetAction: { try await model.fleet.chargePortDoor(open: true) }) }
                Button("충전구 닫기") { focusCamera(yaw: 2.38, pitch: 0.32); dispatchHybridAction(title: "충전구 닫기", bleAction: "portClose", fleetAction: { try await model.fleet.chargePortDoor(open: false) }) }
            } label: { gridLabel("충전구", "bolt.fill") }
            gridButton("전조등", "headlight.high.beam.fill") { executeFleetAction(title: "전조등 깜빡임") { try await model.fleet.flashLights() } }
            gridButton("경적", "speaker.wave.3.fill") { executeFleetAction(title: "경적 울리기") { try await model.fleet.honkHorn() } }
            gridButton("성에 제거", "snowflake") { executeFleetAction(title: "최대 성에 제거") { try await model.fleet.setPreconditioningMax(on: true) } }
            gridButton("원격 시동", "key.fill") {
                model.voice.say("원격 시동을 준비합니다.", key: "controls.remotestart", category: "voiceControl", priority: 3, ttl: 4, manual: true)
                if model.fleet.isAuthenticated { remoteStartAlert = true }
                else { statusToast = "원격 시동(LTE)을 위해 테슬라 Fleet API 토큰 설정이 필요합니다."; tokenSheet = true }
            }
            gridButton("공조 켜기", "fanblades.fill") { dispatchHybridAction(title: "공조 가동", bleAction: "climateOn", fleetAction: { try await model.fleet.setAutoConditioning(on: true) }) }
        }
    }

    private func gridButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: { gridLabel(title, icon) }
        .buttonStyle(MotionButtonStyle())
    }

    private func gridLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium))
            Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.5)
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Hybrid Connection Notice

    private var hybridConnectionNotice: some View {
        let bleActive = link.authentic
        let fleetActive = model.fleet.isAuthenticated

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: bleActive ? "antenna.radiowaves.left.and.right" : (fleetActive ? "bolt.horizontal.icloud.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(bleActive ? Color(red: 0.28, green: 0.88, blue: 0.42) : (fleetActive ? Color.cyan : Color.orange))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bleActive && fleetActive
                        ? "BLE 연결 · Fleet 인증됨"
                        : (bleActive
                            ? "BLE 근거리 직통 연결됨"
                            : (fleetActive ? "Fleet 인증됨 · 제어 준비 별도" : "차량 통신 대기 중")))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary)

                    if fleetActive {
                        Text("LTE Fleet")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.3), in: Capsule())
                    }
                    if bleActive {
                        Text("BLE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.3), in: Capsule())
                    }
                }

                Text(fleetActive ? model.fleet.commandStatus : "근거리 제어는 BLE 제어 키, 원격 제어는 Fleet 인증·서명 서버·차량 가상키 등록이 필요합니다.")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.68))
                .lineSpacing(3)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.fill(0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Interactive Vehicle Stage

    private var interactiveVehicleStage: some View {
        VStack(spacing: 12) {
            ZStack {
                // Dark Stage Ambient Base
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.fill(0.10), Theme.fill(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                // Top-View Vehicle Body Graphic (Rotated 180° so Front Hood is at Top)
                vehicleTopSilhouette

            }
            .frame(height: 320)

            // Tesla Official-Style Horizontal Quick Action Bar
            teslaQuickActionBar
        }
    }

    // MARK: - Vehicle Silhouette

    private var vehicleTopSilhouette: some View {
        let isCustomized = currentAppearance.enabled
        let paintColor = Color(uiColor: UIColor(appearanceHex: currentAppearance.paint).normalizedForTint)
        let hasStripes = isCustomized && currentAppearance.wrap == .stripes
        let stripeColor = Color(uiColor: UIColor(appearanceHex: currentAppearance.accent))
        let plateText = isCustomized ? currentAppearance.plate.trimmingCharacters(in: .whitespaces) : ""
        let plateColor = Color(uiColor: UIColor(appearanceHex: currentAppearance.plateColor))

        return ZStack {
            // Base Tesla Top Graphic tinted with vehicle paint
            Image("TeslaTopExterior")
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(180))
                .frame(maxHeight: 360)
                .colorMultiply(isCustomized ? paintColor : Color.white)
                .shadow(color: Color.black.opacity(0.85), radius: 20, y: 10)

            // Racing Stripes Overlay (if selected in wrap)
            if hasStripes {
                HStack(spacing: 8) {
                    stripeColor.frame(width: 4, height: 260)
                    stripeColor.frame(width: 4, height: 260)
                }
                .opacity(0.85)
                .blendMode(.overlay)
            }

            // Plate Badge at Rear Bumper (if configured)
            if !plateText.isEmpty {
                VStack {
                    Spacer()
                    Text(plateText)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(plateColor, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .offset(y: -14)
                }
                .frame(maxHeight: 360)
            }
        }
    }


    // MARK: - Center Lock Hotspot

    // MARK: - Tesla Official-Style Horizontal Quick Action Bar

    private var teslaQuickActionBar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 3 : 5), spacing: 6) {
            Menu {
                Button("도어 잠그기") { dispatchHybridAction(title: "차량 잠금", bleAction: "lock", fleetAction: { try await model.fleet.doorLock() }) }
                Button("도어 잠금 해제") { dispatchHybridAction(title: "잠금 해제", bleAction: "unlock", fleetAction: { try await model.fleet.doorUnlock() }) }
            } label: { quickLabel("도어 잠금", icon: "lock.fill", accent: .green) }

            teslaQuickButton(
                icon: "fanblades.fill",
                title: "실내 공조",
                accent: Color.cyan
            ) {
                dispatchHybridAction(
                    title: "공조 가동",
                    bleAction: "climateOn",
                    fleetAction: { try await model.fleet.setAutoConditioning(on: true) }
                )
            }

            Menu {
                Button("충전구 열기") { focusCamera(yaw: 2.38, pitch: 0.32); dispatchHybridAction(title: "충전구 열기", bleAction: "portOpen", fleetAction: { try await model.fleet.chargePortDoor(open: true) }) }
                Button("충전구 닫기") { focusCamera(yaw: 2.38, pitch: 0.32); dispatchHybridAction(title: "충전구 닫기", bleAction: "portClose", fleetAction: { try await model.fleet.chargePortDoor(open: false) }) }
            } label: { quickLabel("충전구", icon: "bolt.fill", accent: .green) }

            teslaQuickButton(
                icon: "car.side.front.open.fill",
                title: "프렁크",
                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
            ) {
                dispatchHybridAction(
                    title: "프렁크 열기",
                    bleAction: "frunkOpen",
                    fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "front") }
                )
            }

            teslaQuickButton(
                icon: "car.side.rear.open.fill",
                title: "트렁크",
                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
            ) {
                dispatchHybridAction(
                    title: "트렁크 동작",
                    bleAction: "trunkMove",
                    fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "rear") }
                )
            }
        }
        .padding(10)
        .background(Theme.fill(0.10).opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func teslaQuickButton(
        icon: String,
        title: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            quickLabel(title, icon: icon, accent: accent)
        }
        .buttonStyle(MotionButtonStyle())
    }

    private func quickLabel(_ title: String, icon: String, accent: Color) -> some View {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Secondary Quick Controls Grid (Fleet LTE & Hybrid)

    private var secondaryControlsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("빠른 실행 (LTE 원격 & 공조)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                Spacer()
                if model.fleet.isAuthenticated {
                    Text("Fleet 인증됨")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.cyan)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickTile(title: "원격 시동", icon: "key.fill", accent: Color(red: 0.28, green: 0.88, blue: 0.42)) {
                    model.voice.say("원격 시동을 준비합니다.", key: "controls.remotestart", category: "voiceControl", priority: 3, ttl: 4, manual: true)
                    if model.fleet.isAuthenticated {
                        remoteStartAlert = true
                    } else {
                        statusToast = "원격 시동(LTE)을 위해 테슬라 Fleet API 토큰 설정이 필요합니다."
                        tokenSheet = true
                    }
                }

                quickTile(title: "전조등 깜빡임", icon: "headlight.high.beam.fill", accent: Color.yellow) {
                    executeFleetAction(title: "전조등 깜빡임") {
                        try await model.fleet.flashLights()
                    }
                }

                quickTile(title: "경적 울리기", icon: "speaker.wave.3.fill", accent: Color.cyan) {
                    executeFleetAction(title: "경적 울리기") {
                        try await model.fleet.honkHorn()
                    }
                }

                quickTile(title: "최대 성에 제거", icon: "snowflake", accent: Color(red: 0.35, green: 0.65, blue: 1.0)) {
                    executeFleetAction(title: "최대 성에 제거") {
                        try await model.fleet.setPreconditioningMax(on: true)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.fill(0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func quickTile(
        title: String,
        icon: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
        }
        .buttonStyle(MotionButtonStyle())
    }

    // MARK: - Fleet Cloud & BLE Authentication Section

    // MARK: - Smart Hybrid Action Dispatcher

    private func dispatchHybridAction(
        title: String,
        bleAction: String,
        fleetAction: @escaping () async throws -> Bool
    ) {
        guard !model.demo else { statusToast = "데모에서는 차량 제어할 수 없습니다."; return }
        guard !link.controlBusy, !link.preparingControl, link.confirmation == nil, !model.fleet.isSendingCommand else { statusToast = "앞선 명령 처리 중입니다."; return }
        if !model.demo && link.authentic && link.controlEnabled && !link.controlBusy {
            // BLE Prioritized
            link.askControl(bleAction, title: title)
        } else if model.fleet.isAuthenticated {
            // Fleet API (LTE) Fallback
            executeFleetAction(title: title, action: fleetAction)
        } else {
            if !link.authentic {
                statusToast = "차량 근처(BLE)로 접근하거나 테슬라 Fleet API 토큰을 설정해주세요."
                tokenSheet = true
            } else {
                link.askControl(bleAction, title: title)
            }
        }
    }

    private func executeFleetAction(
        title: String,
        action: @escaping () async throws -> Bool
    ) {
        guard !model.demo, !isExecutingRemote, model.fleet.isAuthenticated else {
            statusToast = "원격(LTE) 제어를 위해 테슬라 Fleet API 토큰 설정이 필요합니다."
            tokenSheet = true
            return
        }
        isExecutingRemote = true
        statusToast = "\(title) (LTE 원격 전송 중…)"
        Task {
            do {
                guard try await action() else { throw FleetCommandPolicy.failure("차량이 명령을 승인하지 않았습니다.") }
                await MainActor.run {
                    isExecutingRemote = false
                    statusToast = "\(title) 승인 응답 수신"
                    model.voice.say("\(title) 승인 응답을 받았습니다.", category: "voiceControl", manual: true)
                    CharacterReact.send("nod")
                }
            } catch {
                await MainActor.run {
                    isExecutingRemote = false
                    statusToast = "원격 실패: \(error.localizedDescription)"
                    CharacterReact.send("shake")
                }
            }
        }
    }
}

// MARK: - Tesla Fleet Token Sheet

struct TeslaFleetTokenSheet: View {
    @ObservedObject var fleet: TeslaFleetClient
    @Environment(\.dismiss) private var dismiss

    @State private var tokenText = ""
    @State private var vinText = ""
    @State private var authCodeText = ""
    @State private var clientIdText = TeslaFleetClient.defaultClientId
    @State private var redirectUriText = TeslaFleetClient.defaultRedirectUri
    @State private var clientSecretText = ""
    @State private var isExchanging = false
    @State private var isLoading = false
    @State private var message: String? = nil
    @State private var showTokenGuide = false
    @State private var isRegisteringPartner = false
    @State private var proxyText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("원격 제어 준비") {
                    Text(fleet.commandStatus)
                    TextField("HTTPS 명령 서명 서버 주소", text: $proxyText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("저장한 서버로 차량 명령 실행 시 Tesla 액세스 토큰과 VIN을 전송합니다. 직접 운영하거나 신뢰하는 서버만 입력하세요. 서버 개인키에 대응하는 가상키를 차량에 등록해야 합니다.").font(.caption)
                    Button("이 서버를 신뢰하고 주소 저장") {
                        do { try fleet.saveCommandProxy(proxyText); message = "서명 서버 주소 저장됨. 차량 가상키 등록 후 제어를 확인하세요." }
                        catch { message = error.localizedDescription }
                    }
                    Link("Tesla 가상키 등록 안내", destination: URL(string: "https://developer.tesla.com/docs/fleet-api/virtual-keys/developer-guide")!)
                    Button("차량 깨우기 요청") {
                        guard !isLoading else { return }
                        isLoading = true
                        Task { @MainActor in
                            defer { isLoading = false }
                            do {
                                let online = try await fleet.wakeUp()
                                message = online ? "차량 온라인 응답 수신" : "깨우기 요청됨 · 잠시 후 차량 조회 필요"
                                if online { await fleet.refreshVehicleSnapshot(force: true) }
                            } catch { message = error.localizedDescription }
                        }
                    }.disabled(isLoading || !fleet.isAuthenticated)
                }
                // MARK: - Dual Connection Architecture Guide
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("스마트 듀얼 통신 시스템", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("근거리 BLE 직결 제어 (기본 & 상시 활성)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("차량 근처에서는 서버나 토큰 없이 아이폰 블루투스(BLE)로 100% 무료, 실시간 즉시 제어됩니다.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider().padding(.vertical, 4)

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.blue)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("원격 LTE 클라우드 제어 (Fleet API)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("원격에서 차량을 제어하려면 테슬라 공식 계정 로그인을 진행하세요.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Button {
                            showTokenGuide = true
                        } label: {
                            Label("토큰 발급 방법 안내 (1분 소요)", systemImage: "questionmark.circle")
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .sheet(isPresented: $showTokenGuide) {
                    tokenGuideSheet
                }

                // MARK: - Official Tesla Developer OAuth 2.0 Login Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("테슬라 공식 개발자 로그인 (OAuth 2.0)")
                                    .font(.system(size: 15, weight: .bold))
                                Text("공식 테슬라 웹페이지에서 로그인 후 인증 코드를 교환합니다.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Client ID, Redirect URI & Client Secret
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("OAuth 2.0 Client ID:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(clientIdText.prefix(12) + "…" + clientIdText.suffix(6))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            HStack {
                                Text("리다이렉트 URI:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(redirectUriText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            Divider().padding(.vertical, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("개발자 앱 Client Secret (필수 · 계정 비밀번호 아님):")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if !clientSecretText.isEmpty {
                                        Text("저장됨")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                SecureField("테슬라 개발자 포털의 Client Secret 입력", text: $clientSecretText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(6)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    .onChange(of: clientSecretText) { newVal in
                                        fleet.saveClientSecret(newVal)
                                    }
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                        // Step 1: Web Login Button (Generates fresh PKCE and opens Safari)
                        Button {
                            fleet.saveClientId(clientIdText)
                            fleet.saveRedirectUri(redirectUriText)
                            fleet.saveClientSecret(clientSecretText)
                            authCodeText = ""
                            if let authURL = fleet.startWebAuthorization() {
                                UIApplication.shared.open(authURL)
                            } else { message = fleet.lastError ?? "로그인 설정 확인 필요" }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "safari.fill")
                                Text("1단계: 테슬라 공식 웹 로그인 (브라우저 열기)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)


                        Divider().padding(.vertical, 2)

                        // Step 2: Code / Callback URL Input
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("2단계: 이번 로그인 완료 후 전체 URL 붙여넣기")
                                    .font(.caption.weight(.bold))
                                Spacer()
                                Button("클립보드 붙여넣기") {
                                    if let clip = UIPasteboard.general.string {
                                        authCodeText = clip
                                    }
                                }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            TextField("https://.../callback?code=...&state=... 전체 주소", text: $authCodeText)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(8)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }

                        // Step 3: Automatic Token Exchange
                        Button {
                            exchangeCodeAndConnect()
                        } label: {
                            HStack {
                                Spacer()
                                if isExchanging {
                                    ProgressView().controlSize(.small).padding(.trailing, 6)
                                }
                                Text("3단계: 토큰 자동 발급 및 계정 연동")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(authCodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("테슬라 공식 개발자 연동 (추천)")
                }

                // MARK: - Server Region Selection
                Section("테슬라 Fleet 서버 리전") {
                    Picker("통신 서버 리전", selection: $fleet.selectedRegion) {
                        ForEach(FleetRegion.allCases) { region in
                            Text(region.rawValue).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: fleet.selectedRegion) { newRegion in
                        fleet.saveRegion(newRegion)
                    }

                    Text("※ 한국·아시아(중국 제외)는 공식 NA 서버를 사용합니다. 차량 생산지나 VIN으로 리전을 변경하지 않습니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("차량 조회 HTTP 412 · 개발자 앱 등록") {
                    Text("계정 로그인과 개발자 앱 등록은 별도입니다. 위에 입력한 개발자 정보와 리다이렉트 도메인을 사용해 현재 Fleet 리전에 앱을 등록합니다. 도메인의 공개 키가 먼저 게시되어 있어야 합니다.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(isRegisteringPartner ? "등록 처리 중…" : "현재 리전에 개발자 앱 등록") {
                        isRegisteringPartner = true
                        message = "개발자 앱 등록 중…"
                        fleet.saveClientId(clientIdText)
                        fleet.saveClientSecret(clientSecretText)
                        fleet.saveRedirectUri(redirectUriText)
                        Task { @MainActor in
                            defer { isRegisteringPartner = false }
                            do {
                                try await fleet.registerPartnerAccount()
                                await fleet.refreshVehicleSnapshot(force: true)
                                message = fleet.vehicleReadError.map { "앱 등록 응답 수신 · " + $0 } ?? "앱 등록 응답 수신 · " + fleet.vehicleDisplayStatus
                            } catch { message = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRegisteringPartner || isExchanging || isLoading)
                }

                // MARK: - Manual Token Input Section (Secondary / Fallback)
                Section("서드파티 토큰 직접 입력 (보조용)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bearer Access Token (직접 입력)")
                            .font(.caption.weight(.semibold))
                        TextField("Auth for Tesla 등에서 발급받은 토큰", text: $tokenText)
                            .font(.system(size: 13, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("차량 식별번호 (VIN)")
                            .font(.caption.weight(.semibold))
                        HStack {
                            TextField("17자리 VIN 입력 (예: 5YJ3E1EB...)", text: $vinText)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)

                            Button("목록 조회") {
                                fetchVehicleList()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message.contains("실패") || message.contains("오류") ? Color.red : Color.green)
                    }
                }

                if !fleet.vehicles.isEmpty {
                    Section("계정에 등록된 차량 선택") {
                        ForEach(fleet.vehicles.indices, id: \.self) { idx in
                            let v = fleet.vehicles[idx]
                            let name = v["display_name"] as? String ?? "Tesla"
                            let vin = v["vin"] as? String ?? ""
                            Button {
                                vinText = vin
                                fleet.saveVin(vin)
                                message = "선택된 차량: \(name) (\(vin))"
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(name).font(.headline).foregroundStyle(.primary)
                                        Text(vin).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if vinText == vin {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        saveConfiguration()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().controlSize(.small)
                                    .padding(.trailing, 6)
                            }
                            Text("설정 저장 및 연결 테스트")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(isLoading || tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if fleet.isAuthenticated {
                        Button(role: .destructive) {
                            fleet.clearToken()
                            tokenText = ""
                            vinText = ""
                            message = "토큰이 삭제되었습니다."
                        } label: {
                            HStack {
                                Spacer()
                                Text("토큰 등록 해제")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("테슬라 Fleet 연동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                tokenText = fleet.getStoredToken() ?? ""
                proxyText = fleet.commandProxy
                vinText = fleet.selectedVin
                clientIdText = fleet.getClientId()
                redirectUriText = fleet.getRedirectUri()
                clientSecretText = fleet.getClientSecret() ?? ""
            }
        }
    }

    private func exchangeCodeAndConnect() {
        let code = authCodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isExchanging else { return }
        isExchanging = true
        message = "테슬라 인증 서버에서 토큰 교환 중…"

        Task {
            do {
                fleet.saveClientId(clientIdText)
                fleet.saveRedirectUri(redirectUriText)
                fleet.saveClientSecret(clientSecretText)
                _ = try await fleet.exchangeAuthorizationCode(code: code)
                await MainActor.run { authCodeText = "" }
                let list = try await fleet.fetchVehicles()
                await MainActor.run {
                    isExchanging = false
                    tokenText = fleet.getStoredToken() ?? ""
                    if let first = list.first?["vin"] as? String {
                        vinText = first
                        fleet.saveVin(first)
                    }
                    message = "🎉 테슬라 공식 계정 연동 성공! (\(list.count)대 차량 확인됨)"
                }
            } catch {
                await MainActor.run {
                    isExchanging = false
                    message = fleet.isAuthenticated ? "토큰 저장됨 · 차량 조회 실패: \(error.localizedDescription)" : "인증 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveConfiguration() {
        let cleanToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVin = vinText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanToken.isEmpty else { return }

        isLoading = true
        message = "연결 확인 중…"
        fleet.saveToken(accessToken: cleanToken)
        if !cleanVin.isEmpty {
            fleet.saveVin(cleanVin)
        }

        Task {
            do {
                let vehicles = try await fleet.fetchVehicles()
                await MainActor.run {
                    isLoading = false
                    message = "테슬라 Fleet API 연결 성공! (\(vehicles.count)대 차량 확인됨)"
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    message = "연결 테스트 결과: \(error.localizedDescription)"
                }
            }
        }
    }

    private func fetchVehicleList() {
        let cleanToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        fleet.saveToken(accessToken: cleanToken)

        isLoading = true
        message = "차량 목록 조회 중…"
        Task {
            do {
                let list = try await fleet.fetchVehicles()
                await MainActor.run {
                    isLoading = false
                    if let first = list.first?["vin"] as? String {
                        vinText = first
                        fleet.saveVin(first)
                    }
                    message = "\(list.count)대의 테슬라 차량을 확인했습니다."
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    message = "목록 조회 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private var tokenGuideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LocalBriefingControls(title: "토큰 발급 안내") { [fleet.isAuthenticated ? "현재 계정 인증 완료 상태입니다." : "현재 계정 인증이 완료되지 않았습니다."] }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("테슬라 공식 토큰 발급 안내")
                            .font(.title2.weight(.bold))
                        Text("테슬라 본사는 보안상 미등록 타사 앱의 직접 로그인을 차단하며, 본인 인증을 거친 안전한 토큰(Token) 통신만 허용합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("가장 쉽고 안전한 발급 방법 (1분 소요)")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 12) {
                            Text("1")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(Color.blue.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("iOS App Store 'Auth for Tesla' 설치")
                                    .font(.subheadline.weight(.semibold))
                                Text("전세계 테슬라 차주들이 사용하는 100% 온디바이스 토큰 생성 앱입니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("2")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(Color.blue.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("공식 테슬라 로그인 후 토큰 복사")
                                    .font(.subheadline.weight(.semibold))
                                Text("앱에서 테슬라 로그인 후 생성된 [Access Token] 또는 [Refresh Token]을 복사합니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("3")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(Color.blue.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("본 앱의 토큰 입력창에 붙여넣기")
                                    .font(.subheadline.weight(.semibold))
                                Text("토큰을 붙여넣고 [목록 조회]를 누르면 내 테슬라 차량이 즉시 연동됩니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("안전성 및 개인정보 보호", systemImage: "lock.shield.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("사용자 계정 비밀번호는 본 앱에 절대 저장되지 않으며, 등록된 토큰은 애플 기기 보안 영역(iOS Keychain)에만 암호화되어 안전하게 보관됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .navigationTitle("토큰 발급 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인") { showTokenGuide = false }
                }
            }
        }
    }
}
