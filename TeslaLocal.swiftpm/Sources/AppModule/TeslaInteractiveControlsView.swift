import SwiftUI

/// Tesla official-style interactive vehicle exterior body control view.
/// Features a top-view vehicle silhouette with interactive control hotspots directly positioned on the car body:
/// - Front Hood: Frunk Open
/// - Center Roof: Lock / Unlock toggle
/// - Rear Trunk: Trunk Move / Close
/// - Rear Left Flap: Charge Port Open / Close
/// - Side Windows: Window Venting
struct TeslaInteractiveControlsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @State private var isLocked = true
    @State private var isPortOpen = false
    @State private var windowsVented = false
    @State private var sentryMode = true
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

                // Centerpiece Interactive Vehicle Body Stage
                interactiveVehicleStage

                // Secondary Quick Control Grid (Flash, Horn, Vent, Sentry)
                secondaryControlsGrid

                // Key Management & Permissions Section (Clean disclosure)
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

                // Center Roof Hotspot (Lock / Unlock) & Side Window Hotspots
                HStack(spacing: 20) {
                    // Left Window Vent
                    sideHotspotButton(
                        icon: windowsVented ? "arrow.down.to.line.compact" : "arrow.up.and.down.and.sparkles",
                        title: windowsVented ? "창문 닫기" : "창문 환기",
                        isActive: windowsVented
                    ) {
                        withAnimation { windowsVented.toggle() }
                    }

                    // Large Center Roof Padlock
                    centerLockHotspot

                    // Right Window Vent
                    sideHotspotButton(
                        icon: "lock.shield.fill",
                        title: sentryMode ? "감시 켜짐" : "감시 꺼짐",
                        isActive: sentryMode
                    ) {
                        withAnimation { sentryMode.toggle() }
                    }
                }

                Spacer()

                // Rear Trunk & Charge Port Row
                HStack(alignment: .center, spacing: 24) {
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
                        title: "트렁크",
                        icon: "car.side.rear.open.fill",
                        accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                    ) {
                        link.askControl("trunkMove", title: "트렁크 동작")
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .frame(height: 480)
    }

    // MARK: - Vehicle Silhouette

    private var vehicleTopSilhouette: some View {
        ZStack {
            // Vehicle Outer Shadow & Glow
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: 140, height: 350)
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
                .frame(width: 136, height: 340)
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
                .frame(width: 104, height: 210)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                )

            // Front Windshield Curve
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 90, height: 40)
                .offset(y: -75)

            // Rear Glass Curve
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 90, height: 44)
                .offset(y: 75)
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
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(
                            isLocked
                                ? Color(red: 0.28, green: 0.88, blue: 0.42).opacity(0.2)
                                : Color.orange.opacity(0.25)
                        )
                        .frame(width: 60, height: 60)
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
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isLocked ? Color(red: 0.28, green: 0.88, blue: 0.42) : Color.orange)
                }

                Text(isLocked ? "잠김" : "잠금 해제됨")
                    .font(.system(size: 12, weight: .bold))
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

    private func sideHotspotButton(
        icon: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isActive ? Color.cyan : Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background(
                        isActive ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(isActive ? Color.cyan.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? .white : Color.white.opacity(0.55))
            }
        }
        .buttonStyle(MotionButtonStyle())
        .disabled(blocked)
    }

    // MARK: - Secondary Quick Controls Grid

    private var secondaryControlsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("빠른 실행")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickTile(title: "전조등 깜빡임", icon: "headlight.high.beam.fill", accent: Color.yellow) {
                    link.askControl("flash", title: "전조등")
                }
                quickTile(title: "경적 울리기", icon: "speaker.wave.3.fill", accent: Color.cyan) {
                    link.askControl("honk", title: "경적")
                }
                quickTile(title: "원격 시동", icon: "key.fill", accent: Color(red: 0.28, green: 0.88, blue: 0.42)) {
                    link.askControl("remoteStart", title: "원격 시동")
                }
                quickTile(title: "성에 제거", icon: "snowflake", accent: Color(red: 0.35, green: 0.65, blue: 1.0)) {
                    link.askControl("defrost", title: "성에 제거")
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
        .disabled(blocked)
    }

    // MARK: - Key Management Section

    private var keyManagementSection: some View {
        DisclosureGroup("제어 키 및 보안 관리") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("이 차량의 원격 제어 활성화", isOn: Binding(
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
