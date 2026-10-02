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
        model.demo || (!model.fleet.isAuthenticated && (!link.authentic || !link.controlEnabled)) || model.fleet.isSendingCommand || link.controlBusy || link.preparingControl || link.confirmation != nil
    }

    private func current(_ section: String, _ key: String) -> Bool? {
        let group = homePresentation(model, link).object(section)
        return group.string("mode") == "recent" ? group[key] as? Bool : nil
    }
    private var currentLock: Bool? {
        if model.output.object("fresh").flag("closures"), let value = model.groups.object("closures")["locked"] as? Bool { return value }
        guard let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == model.fleet.selectedVin, snapshot.sectionIsRecent("vehicle_state") else { return nil }
        return snapshot.locked
    }
    private var currentPort: Bool? {
        guard let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == model.fleet.selectedVin, snapshot.sectionIsRecent("charge_state") else { return nil }
        return snapshot.payload.object("charge_state")["charge_port_door_open"] as? Bool
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Live Control In-Flight Status
            if link.controlBusy || link.preparingControl {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(link.controlBusy ? "차량에 명령 전송 중…" : "제어 세션 준비 중…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
            }

            // Body & Security Control Grid
            if category == "body" || category == "security" {
                VStack(spacing: 10) {
                    VehicleStateButton(title: "차량 잠금", icon: "lock.fill", state: currentLock, onTitle: "잠그기", offTitle: "해제", onState: "잠김", offState: "잠금 해제") { on in
                        model.requestVehicleControl(on ? "lock" : "unlock", title: on ? "차량 잠금" : "잠금 해제")
                    }.disabled(blocked)

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
                    VehicleStateButton(title: "공조 전원", icon: "power", state: current("climate", "isOn")) { on in
                        model.requestVehicleControl(on ? "climateOn" : "climateOff", title: on ? "공조 켜기" : "공조 끄기")
                    }.disabled(blocked)

                    // Temperature Adjuster Card
                    VStack(spacing: 12) {
                        HStack {
                            Text("희망 실내 온도")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.7))
                            Spacer()
                            Text(units.format(temperature, suffix: "°C", digits: 1))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
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
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || temperature >= 28.0)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                model.requestVehicleControl("temperature", title: "온도 설정", args: ["value": temperature])
                            } label: {
                                Text("설정 적용")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 42)
                                    .background(Color(red: 0.18, green: 0.50, blue: 0.95), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || (!model.fleet.isAuthenticated && !link.controlsReady(category: "climate")))
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10), lineWidth: 0.8))
                }
            }

            // Charge Controls
            if category == "charge" {
                VStack(spacing: 12) {
                    VehicleStateButton(title: "충전", icon: "bolt.fill", state: current("charge", "isCharging"), onTitle: "시작", offTitle: "중지", onState: "충전 중", offState: "대기") { on in
                        model.requestVehicleControl(on ? "chargeStart" : "chargeStop", title: on ? "충전 시작" : "충전 중지")
                    }.disabled(blocked)

                    VehicleStateButton(title: "충전 포트", icon: "bolt.circle", state: currentPort, onTitle: "열기", offTitle: "닫기", onState: "열림", offState: "닫힘") { on in
                        model.requestVehicleControl(on ? "portOpen" : "portClose", title: on ? "포트 열기" : "포트 닫기")
                    }.disabled(blocked)

                    // Charge Limit Stepper Card
                    VStack(spacing: 12) {
                        HStack {
                            Text("충전 한도")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.7))
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
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || limit >= 100)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                model.requestVehicleControl("chargeLimit", title: "충전 한도 설정", args: ["value": limit])
                            } label: {
                                Text("한도 적용")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 42)
                                    .background(Color(red: 0.28, green: 0.88, blue: 0.42), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(blocked || (!model.fleet.isAuthenticated && !link.controlsReady(category: "charge")))
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10), lineWidth: 0.8))
                }
            }

        }
        .confirmationDialog("별도 제어 키 등록을 요청하시겠습니까?", isPresented: $enrollment, titleVisibility: .visible) {
            Button("등록 요청") { link.enrollControlKey() }
            Button("취소", role: .cancel) {}
        }
    }

    private func controlTile(action: String, title: String, icon: String, accent: Color, args: Object = [:]) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.requestVehicleControl(action, title: title, args: args)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(MotionButtonStyle())
        .disabled(blocked || (!model.fleet.isAuthenticated && !link.controlsReady(category: category)))
        .opacity(blocked || (!model.fleet.isAuthenticated && !link.controlsReady(category: category)) ? 0.45 : 1.0)
    }
}
