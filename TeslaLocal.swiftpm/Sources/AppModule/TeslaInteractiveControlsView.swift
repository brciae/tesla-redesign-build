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
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var isLocked = true
    @State private var isPortOpen = false
    @State private var enrollment = false
    @State private var remoteStartAlert = false
    @State private var tokenSheet = false
    @State private var statusToast: String? = nil
    @State private var isExecutingRemote = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Live Status / Toast Banner
                if let statusToast {
                    HStack(spacing: 8) {
                        Image(systemName: isExecutingRemote ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(statusToast)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            self.statusToast = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.14).opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
                }

                // Control Busy Progress Banner
                if link.controlBusy || link.preparingControl || isExecutingRemote || model.fleet.isSendingCommand {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(link.controlBusy ? "BLE 근거리 명령 전송 중…" : (isExecutingRemote || model.fleet.isSendingCommand ? "LTE 클라우드 원격 전송 중…" : "제어 세션 준비 중…"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.4), lineWidth: 1))
                }

                // Hybrid Connection Scope Notice Card
                hybridConnectionNotice

                // Centerpiece Interactive Vehicle Body Stage
                interactiveVehicleStage

                // Secondary Quick Controls Grid (LTE & Hybrid)
                secondaryControlsGrid

                // Tesla Fleet Cloud & BLE Authentication Management
                fleetAndBleManagementSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
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
            TeslaFleetTokenSheet(fleet: model.fleet)
        }
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
                        ? "하이브리드 제어 준비 완료"
                        : (bleActive
                            ? "BLE 근거리 직통 연결됨"
                            : (fleetActive ? "LTE 원격 클라우드 연결됨" : "차량 통신 대기 중")))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

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

                Text(bleActive && fleetActive
                    ? "차량 근거리에서는 지연 없는 BLE로 직접 제어하며, 멀리 떨어져 있을 때는 테슬라 Fleet API(LTE)를 통해 전 세계 어디서든 차량을 원격 제어합니다."
                    : (bleActive
                        ? "차량 근거리에서 암호화된 블루투스 명령(잠금, 프렁크, 트렁크, 충전구)을 직접 전송합니다. 원격 제어를 원하시면 하단에서 테슬라 Fleet 토큰을 등록하세요."
                        : (fleetActive
                            ? "테슬라 공식 Fleet API 및 차량 내장 LTE 모뎀으로 원격 제어(원격 시동, 전조등, 경적, 잠금, 공조)를 전송합니다."
                            : "차량 근거리(BLE)로 접근하거나, 하단 설정에서 테슬라 공식 Fleet API 토큰을 입력하시면 원격 LTE 제어가 활성화됩니다."
                        )
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineSpacing(3)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Interactive Vehicle Stage

    private var interactiveVehicleStage: some View {
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

            // Top-View Vehicle Body Graphic (High-Resolution 3D Tesla Render)
            vehicleTopSilhouette

            // Front Hood Hotspot (Frunk)
            hotspotPill(
                title: "프렁크 열기",
                icon: "car.side.front.open.fill",
                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
            ) {
                dispatchHybridAction(
                    title: "프렁크 열기",
                    bleAction: "frunkOpen",
                    fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "front") }
                )
            }
            .offset(y: -140)

            // Center Roof Hotspot (Lock / Unlock)
            centerLockHotspot
                .offset(y: -15)

            // Rear Left Charge Port Hotspot
            hotspotPill(
                title: isPortOpen ? "포트 닫기" : "충전 포트",
                icon: isPortOpen ? "bolt.slash.fill" : "bolt.fill",
                accent: isPortOpen ? Color.orange : Color(red: 0.28, green: 0.88, blue: 0.42)
            ) {
                withAnimation { isPortOpen.toggle() }
                dispatchHybridAction(
                    title: isPortOpen ? "포트 닫기" : "포트 열기",
                    bleAction: isPortOpen ? "portClose" : "portOpen",
                    fleetAction: { try await model.fleet.chargePortDoor(open: !isPortOpen) }
                )
            }
            .offset(x: -80, y: 145)

            // Rear Trunk Hotspot
            hotspotPill(
                title: "트렁크 동작",
                icon: "car.side.rear.open.fill",
                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
            ) {
                dispatchHybridAction(
                    title: "트렁크 동작",
                    bleAction: "trunkMove",
                    fleetAction: { try await model.fleet.actuateTrunk(whichTrunk: "rear") }
                )
            }
            .offset(x: 80, y: 145)
        }
        .frame(height: 440)
    }

    // MARK: - Vehicle Silhouette

    private var vehicleTopSilhouette: some View {
        ZStack {
            Image("TeslaTopExterior")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 380)
                .shadow(color: Color.black.opacity(0.85), radius: 20, y: 10)
        }
    }

    // MARK: - Center Lock Hotspot

    private var centerLockHotspot: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isLocked.toggle()
                dispatchHybridAction(
                    title: isLocked ? "차량 잠금" : "잠금 해제",
                    bleAction: isLocked ? "lock" : "unlock",
                    fleetAction: { try await (isLocked ? model.fleet.doorLock() : model.fleet.doorUnlock()) }
                )
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            isLocked
                                ? Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.2)
                                : Color.orange.opacity(0.25)
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(
                                    isLocked
                                        ? Color(red: 0.28, green: 0.88, blue: 0.42)
                                        : Color.orange,
                                    lineWidth: 2
                                )
                        )
                        .shadow(
                            color: (isLocked ? Color.green : Color.orange).opacity(0.4),
                            radius: 12
                        )

                    Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(isLocked ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.orange)
                }

                Text(isLocked ? "도어 잠김" : "잠금 해제됨")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(MotionButtonStyle())
    }

    // MARK: - Hotspot Buttons

    private func hotspotPill(
        title: String,
        icon: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.12).opacity(0.9), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(accent.opacity(0.5), lineWidth: 1.2)
            )
            .shadow(color: accent.opacity(0.25), radius: 8)
        }
        .buttonStyle(MotionButtonStyle())
    }

    // MARK: - Secondary Quick Controls Grid (Fleet LTE & Hybrid)

    private var secondaryControlsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("빠른 실행 (LTE 원격 & 공조)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                if model.fleet.isAuthenticated {
                    Text("LTE 연결됨")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.cyan)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickTile(title: "원격 시동", icon: "key.fill", accent: Color(red: 0.28, green: 0.88, blue: 0.42)) {
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
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 0.8))
        }
        .buttonStyle(MotionButtonStyle())
    }

    // MARK: - Fleet Cloud & BLE Authentication Section

    private var fleetAndBleManagementSection: some View {
        VStack(spacing: 12) {
            // Tesla Fleet Cloud API Card
            HStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.icloud.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(model.fleet.isAuthenticated ? Color.cyan : Color.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 3) {
                    Text("테슬라 Fleet 클라우드 (LTE 원격 제어)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text(model.fleet.isAuthenticated
                        ? (model.fleet.selectedVin.isEmpty ? "토큰 등록됨 · 차량 선택 필요" : "연동 활성 · VIN: \(model.fleet.selectedVin)")
                        : "토큰을 등록하면 전 세계 어디서든 차량 LTE로 원격 제어 가능"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()

                Button {
                    tokenSheet = true
                } label: {
                    Text(model.fleet.isAuthenticated ? "설정 변경" : "토큰 등록")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.2), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                        .foregroundStyle(Color.cyan)
                }
            }
            .padding(14)
            .background(Color(white: 0.09).opacity(0.8), in: RoundedRectangle(cornerRadius: 16))

            // BLE Key Management Disclosure
            DisclosureGroup("로컬 블루투스(BLE) 인증 관리") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("이 기기의 차량 제어 기능 활성화", isOn: Binding(
                        get: { link.controlEnabled },
                        set: { link.enableControls($0) }
                    ))
                    .disabled(model.demo || link.controlBusy)

                    HStack(spacing: 10) {
                        Button("BLE 제어 키 등록 요청") { enrollment = true }
                            .disabled(model.demo || !link.connected || link.controlBusy || link.confirmation != nil)
                            .buttonStyle(.bordered)

                        Button("차량 승인 후 재개") { link.authenticate() }
                            .disabled(model.demo || !link.connected || link.controlBusy)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .padding(14)
            .background(Color(white: 0.08).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Smart Hybrid Action Dispatcher

    private func dispatchHybridAction(
        title: String,
        bleAction: String,
        fleetAction: @escaping () async throws -> Bool
    ) {
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
        guard model.fleet.isAuthenticated else {
            statusToast = "원격(LTE) 제어를 위해 테슬라 Fleet API 토큰 설정이 필요합니다."
            tokenSheet = true
            return
        }
        isExecutingRemote = true
        statusToast = "\(title) (LTE 원격 전송 중…)"
        Task {
            do {
                _ = try await action()
                await MainActor.run {
                    isExecutingRemote = false
                    statusToast = "\(title) 차량으로 전달되었습니다."
                }
            } catch {
                await MainActor.run {
                    isExecutingRemote = false
                    statusToast = "원격 실패: \(error.localizedDescription)"
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
    @State private var isLoading = false
    @State private var message: String? = nil
    @State private var showTokenGuide = false

    var body: some View {
        NavigationStack {
            Form {
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
                                    Text("원격에서 차량을 제어하려면 테슬라 공식 토큰을 등록하세요.")
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

                // MARK: - Fleet API Token Input Section
                Section("원격 Fleet API 토큰 등록") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bearer Access Token (또는 Refresh Token)")
                            .font(.caption.weight(.semibold))
                        TextField("테슬라 계정 토큰 입력", text: $tokenText)
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
                vinText = fleet.selectedVin
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

