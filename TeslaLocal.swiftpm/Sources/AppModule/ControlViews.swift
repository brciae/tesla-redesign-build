import SwiftUI

struct ControlPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var link: VehicleLink
    var category = "body"
    @State private var temperature = 22.0
    @State private var limit = 80
    @State private var enrollment = false

    private var blocked: Bool {
        model.demo || !link.authentic || !link.controlEnabled || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Live Control In-Flight Status
            if link.controlBusy || link.preparingControl {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(link.controlBusy ? "차량에 명령 전송 중…" : "제어 세션 준비 중…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }

            // Body & Security Control Grid
            if category == "body" || category == "security" {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        controlTile(
                            action: "lock",
                            title: "차량 잠금",
                            icon: "lock.fill",
                            accent: Color(red: 0.28, green: 0.88, blue: 0.42)
                        )
                        controlTile(
                            action: "unlock",
                            title: "잠금 해제",
                            icon: "lock.open.fill",
                            accent: Color.orange
                        )
                    }

                    if category == "body" {
                        HStack(spacing: 10) {
                            controlTile(
                                action: "trunkMove",
                                title: "트렁크 동작",
                                icon: "car.side.rear.open.fill",
                                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                            )
                            controlTile(
                                action: "frunkOpen",
                                title: "프렁크 열기",
                                icon: "car.side.front.open.fill",
                                accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                            )
                        }
                    }
                }
            }

            // Climate Controls
            if category == "climate" {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        controlTile(
                            action: "climateOn",
                            title: "공조 켜기",
                            icon: "power",
                            accent: Color(red: 0.28, green: 0.88, blue: 0.42)
                        )
                        controlTile(
                            action: "climateOff",
                            title: "공조 끄기",
                            icon: "power",
                            accent: Color.red.opacity(0.85)
                        )
                    }

                    // Temperature Adjuster Card
                    VStack(spacing: 12) {
                        HStack {
                            Text("희망 실내 온도")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Spacer()
                            Text(units.format(temperature, suffix: "°C", digits: 1))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        HStack(spacing: 12) {
                            Button {
                                if temperature > 16.0 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    temperature -= 0.5
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || temperature <= 16.0)

                            Button {
                                if temperature < 28.0 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    temperature += 0.5
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || temperature >= 28.0)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                link.askControl("temperature", title: "온도 설정", args: ["value": temperature])
                            } label: {
                                Text("설정 적용")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 42)
                                    .background(Color(red: 0.18, green: 0.50, blue: 0.95), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || !link.controlsReady(category: "climate"))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                }
            }

            // Charge Controls
            if category == "charge" {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        controlTile(
                            action: "chargeStart",
                            title: "충전 시작",
                            icon: "play.fill",
                            accent: Color(red: 0.28, green: 0.88, blue: 0.42)
                        )
                        controlTile(
                            action: "chargeStop",
                            title: "충전 중지",
                            icon: "stop.fill",
                            accent: Color.orange
                        )
                    }

                    HStack(spacing: 10) {
                        controlTile(
                            action: "portOpen",
                            title: "포트 열기",
                            icon: "bolt.fill",
                            accent: Color(red: 0.35, green: 0.65, blue: 1.0)
                        )
                        controlTile(
                            action: "portClose",
                            title: "포트 닫기",
                            icon: "bolt.slash.fill",
                            accent: Color.white.opacity(0.6)
                        )
                    }

                    // Charge Limit Stepper Card
                    VStack(spacing: 12) {
                        HStack {
                            Text("충전 한도")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Spacer()
                            Text("\(limit)%")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.28, green: 0.88, blue: 0.42))
                        }

                        HStack(spacing: 12) {
                            Button {
                                if limit > 50 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    limit -= 5
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || limit <= 50)

                            Button {
                                if limit < 100 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    limit += 5
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || limit >= 100)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                link.askControl("chargeLimit", title: "충전 한도 설정", args: ["value": limit])
                            } label: {
                                Text("한도 적용")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 42)
                                    .background(Color(red: 0.28, green: 0.88, blue: 0.42), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || !link.controlsReady(category: "charge"))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                }
            }

            // Driver Key & Permissions (Minimal & Clean)
            DisclosureGroup("제어 키 관리") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("이 차량의 제어 기능 활성화", isOn: Binding(
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
        }
        .confirmationDialog("별도 제어 키 등록을 요청하시겠습니까?", isPresented: $enrollment, titleVisibility: .visible) {
            Button("등록 요청") { link.enrollControlKey() }
            Button("취소", role: .cancel) {}
        }
    }

    private func controlTile(action: String, title: String, icon: String, accent: Color, args: Object = [:]) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            link.askControl(action, title: title, args: args)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(blocked || !link.controlsReady(category: category))
        .opacity(blocked || !link.controlsReady(category: category) ? 0.45 : 1.0)
    }
}
