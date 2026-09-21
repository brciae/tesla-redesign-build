import SwiftUI

/// Tesla authentic vehicle exterior body control view.
/// Strictly implements only genuine, supported Bluetooth (BLE) vehicle commands:
/// - Front Hood: Frunk Open (`frunkOpen`)
/// - Center Roof: Lock / Unlock toggle (`lock` / `unlock`)
/// - Rear Trunk: Trunk Move / Close (`trunkMove`)
/// - Rear Left Flap: Charge Port Open / Close (`portOpen` / `portClose`)
struct TeslaInteractiveControlsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var isLocked = true
    @State private var isPortOpen = false
    @State private var enrollment = false

    private var blocked: Bool {
        model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Live Control Status Banner
                if link.controlBusy || link.preparingControl {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(link.controlBusy ? "차량에 명령 전송 중…" : "제어 세션 준비 중…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.18, green: 0.50, blue: 0.95).opacity(0.4), lineWidth: 1))
                }

                // BLE Connection Status & Capability Notice Card
                connectionScopeNotice

                // Centerpiece Interactive Vehicle Body Stage
                interactiveVehicleStage

                // Key Management & Authentication Section
                keyManagementSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .confirmationDialog("별도 제어 키 등록을 요청하시겠습니까?", isPresented: $enrollment, titleVisibility: .visible) {
            Button("등록 요청") { link.enrollControlKey() }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: - Connection Scope Notice

    private var connectionScopeNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: link.authentic ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(link.authentic ? Color(red: 0.28, green: 0.88, blue: 0.42) : (model.demo ? Color.orange : Color.gray))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(link.authentic ? "차량 BLE 근거리 제어 준비됨" : (model.demo ? "예시 모드 동작 중" : "차량 BLE 통신 대기 중"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                Text(link.authentic
                    ? "차량 근거리에서 암호화된 블루투스 명령(잠금, 프렁크, 트렁크, 충전구)을 직접 전송합니다."
                    : "블루투스(BLE) 근거리 직접 통신으로만 작동합니다. 원격 시동 및 서먼(Summon) 등 테슬라 공식 클라우드 서버 기능은 로컬 앱 정책상 제외되며, 실차량 인근에서 인증된 하드웨어 제어만 안전하게 지원합니다."
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.65))
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
                        colors: [Color(white: 0.09), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            // Top-View Vehicle Body Graphic Representation
            VStack {
                Spacer()
                vehicleTopSilhouette
                Spacer()
            }

            // Interactive Hotspots Layer
            VStack {
                // Front Hood Hotspot (Frunk)
                hotspotPill(
                    title: "프렁크 열기",
                    icon: "car.side.front.open.fill",
                    accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                ) {
                    link.askControl("frunkOpen", title: "프렁크 열기")
                }
                .padding(.top, 28)

                Spacer()

                // Center Roof Hotspot (Lock / Unlock)
                centerLockHotspot

                Spacer()

                // Rear Trunk & Charge Port Row
                HStack(alignment: .center, spacing: 20) {
                    // Charge Port Hotspot (Rear Left)
                    hotspotPill(
                        title: isPortOpen ? "포트 닫기" : "충전 포트",
                        icon: isPortOpen ? "bolt.slash.fill" : "bolt.fill",
                        accent: isPortOpen ? Color.orange : Color(red: 0.28, green: 0.88, blue: 0.42)
                    ) {
                        withAnimation { isPortOpen.toggle() }
                        link.askControl(isPortOpen ? "portClose" : "portOpen", title: isPortOpen ? "포트 닫기" : "포트 열기")
                    }

                    // Rear Trunk Hotspot
                    hotspotPill(
                        title: "트렁크 동작",
                        icon: "car.side.rear.open.fill",
                        accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                    ) {
                        link.askControl("trunkMove", title: "트렁크 동작")
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .frame(height: 440)
    }

    // MARK: - Vehicle Silhouette

    private var vehicleTopSilhouette: some View {
        ZStack {
            // Vehicle Outer Shadow & Glow
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: 140, height: 340)
                .blur(radius: 12)

            // Car Body Metallic Outline
            RoundedRectangle(cornerRadius: 64, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.20), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 136, height: 330)
                .overlay(
                    RoundedRectangle(cornerRadius: 64, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                )

            // Glass Roof Area
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.08), Color(white: 0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 104, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                )

            // Front Windshield Curve
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 90, height: 38)
                .offset(y: -70)

            // Rear Glass Curve
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 90, height: 40)
                .offset(y: 70)
        }
    }

    // MARK: - Center Lock Hotspot

    private var centerLockHotspot: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isLocked.toggle()
                link.askControl(isLocked ? "lock" : "unlock", title: isLocked ? "차량 잠금" : "잠금 해제")
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
        .disabled(blocked)
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
        .disabled(blocked)
    }

    // MARK: - Key Management Section

    private var keyManagementSection: some View {
        DisclosureGroup("제어 키 및 BLE 인증 관리") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("이 기기의 차량 제어 기능 활성화", isOn: Binding(
                    get: { link.controlEnabled },
                    set: { link.enableControls($0) }
                ))
                .disabled(model.demo || link.controlBusy)

                HStack(spacing: 10) {
                    Button("제어 키 등록 요청") { enrollment = true }
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.08).opacity(0.6))
        )
    }
}
