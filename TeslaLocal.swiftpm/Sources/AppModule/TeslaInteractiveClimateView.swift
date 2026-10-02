import SwiftUI

/// Restores the cabin overlay and mode tiles while retaining verified command routing.
struct TeslaInteractiveClimateView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject private var appearanceStore = VehicleAppearanceStore.shared
    @State private var requestedTemperature = 22.0
    @State private var busy = false
    @State private var result = ""
    @State private var acceptedLevels: [String: Int] = [:]
    @State private var acceptedMode: Int?

    private var blocked: Bool {
        model.demo || busy || model.fleet.isSendingCommand || link.controlBusy || link.preparingControl || link.confirmation != nil
    }
    private var climate: Object { homePresentation(model, link).object("climate") }
    private var measured: Object {
        guard let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == model.fleet.selectedVin,
              snapshot.sectionIsRecent("climate_state") else { return [:] }
        return snapshot.payload["climate_state"] as? Object ?? [:]
    }
    private var currentAppearance: VehicleAppearance {
        appearanceStore.value(for: VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo))
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ScreenBriefingControls(scope: .climate)
                topControls
                temperatureBanner
                cabinStage
                modeControls
                if !result.isEmpty { Text(result).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }
                Text(model.fleet.commandStatus).font(.caption).foregroundStyle(Theme.muted)
                Caption("숫자는 최근 수신 단계이며, 명령 직후에는 승인된 요청값을 표시합니다. 미수신은 —로 표시합니다.")
                Caption("자동·A/C·풍량·송풍 방향·내외기 순환·뒷좌석 공조는 차량 화면에서 조절해 주세요.")
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 32)
        }.background(Theme.bg)
        .onAppear {
            if let target = climate.number("targetC"), target.isFinite, (16...28).contains(target) { requestedTemperature = target }
        }
    }
    private var topControls: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                VehicleStateButton(title: "공조 전원", icon: "power", state: climate.string("mode") == "recent" ? climate["isOn"] as? Bool : nil) { on in
                    model.requestVehicleControl(on ? "climateOn" : "climateOff", title: on ? "공조 켜기" : "공조 끄기")
                }.accessibilityIdentifier("climate.power")
                VehicleStateButton(title: "성에 제거", icon: "windshield.front.and.heat.waves", state: measured.number("defrost_mode").map { $0 == 2 }) { on in
                    run(on ? "성에 제거 켜기" : "성에 제거 끄기") { try await model.fleet.setPreconditioningMax(on: on) }
                }.accessibilityIdentifier("climate.defrost")
                VehicleStateButton(title: "핸들 열선", icon: "steeringwheel", state: measured["steering_wheel_heater"] as? Bool) { on in
                    run(on ? "핸들 열선 켜기" : "핸들 열선 끄기") { try await model.fleet.setSteeringWheelHeater(on: on) }
                }.accessibilityIdentifier("climate.steering")
            }
        }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16)).disabled(blocked)
    }
    private var temperatureBanner: some View {
        VStack(spacing: 10) {
            HStack {
                Text("실내 \(valueText(climate.number("insideC"), digits: 1))°C")
                Spacer()
                Text("외기 \(valueText(climate.number("outsideC"), digits: 1))°C")
            }.font(.caption).foregroundStyle(Theme.muted)
            HStack {
                VStack(alignment: .leading) {
                    Text("목표 실내 온도").font(.caption)
                    Text("수신 \(valueText(climate.number("targetC"), digits: 1))°C").font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { adjustTemperature(-0.5) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.disabled(blocked || requestedTemperature <= 16)
                Text(String(format: "%.1f°C", requestedTemperature)).font(.system(size: 26, weight: .bold, design: .rounded)).fixedSize()
                Button { adjustTemperature(0.5) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.disabled(blocked || requestedTemperature >= 28)
            }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func adjustTemperature(_ delta: Double) {
        requestedTemperature = min(28, max(16, requestedTemperature + delta))
        model.requestVehicleControl("temperature", title: "온도 설정", args: ["value": requestedTemperature])
    }
    private var cabinStage: some View {
        GeometryReader { geometry in
            let offset = min(68.0, geometry.size.width * 0.21)
            ZStack {
                // v1.30: light mode = plain white stage; the cut-out interior sits on it without a black frame.
                RoundedRectangle(cornerRadius: 26).fill(Color(uiColor: .secondarySystemGroupedBackground))
                Image("TeslaYLInterior").resizable().scaledToFit().frame(maxHeight: 490).accessibilityHidden(true)
                if currentAppearance.enabled && currentAppearance.interiorColor.uppercased() != "17191B" {
                    Image("TeslaYLInterior").resizable().scaledToFit().frame(maxHeight: 490)
                        .colorMultiply(Color(uiColor: UIColor(appearanceHex: currentAppearance.interiorColor))).opacity(0.42).blendMode(.screen).accessibilityHidden(true)
                }
                seatControl("운전석", position: 0, field: "seat_heater_left", coolField: "seat_fan_front_left").offset(x: -offset, y: -50)
                seatControl("조수석", position: 1, field: "seat_heater_right", coolField: "seat_fan_front_right").offset(x: offset, y: -50)
                seatControl("2열 좌", position: 2, field: "seat_heater_rear_left").offset(x: -offset, y: 68)
                seatControl("2열 우", position: 5, field: "seat_heater_rear_right").offset(x: offset, y: 68)
                seatControl("3열 좌", position: 7, field: "seat_heater_third_row_left").offset(x: -offset, y: 186)
                seatControl("3열 우", position: 8, field: "seat_heater_third_row_right").offset(x: offset, y: 186)
            }.frame(width: geometry.size.width, height: 530)
        }.frame(height: 530).disabled(blocked)
        .padding(.top, 30)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(alignment: .top) {
            Text("Model Y L · 6인승").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 10)
        }
    }
    private func seatControl(_ title: String, position: Int, field: String, coolField: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3).background(.regularMaterial, in: Capsule())
            HStack(spacing: 3) {
                seatButton(title, position: position, field: field, cooling: false)
                if let coolField { seatButton(title, position: position, field: coolField, cooling: true) }
            }
        }.padding(3).background(Theme.fill(0.12).opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
    }
    private func seatButton(_ title: String, position: Int, field: String, cooling: Bool) -> some View {
        let measuredLevel = measured.number(field).flatMap { (0...3).contains($0) ? Int($0) : nil }
        let level = acceptedLevels[field] ?? measuredLevel
        let tint: Color = cooling ? .cyan : .orange
        return Button {
            let next = ((level ?? 0) + 1) % 4
            run(title + (cooling ? " 통풍" : " 열선"), accepted: { acceptedLevels[field] = next }) {
                if cooling { return try await model.fleet.setSeatCooler(seatPosition: position, level: next) }
                return try await model.fleet.setSeatHeater(seatPosition: position, level: next)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: cooling ? "fanblades.fill" : "flame.fill")
                Text(level.map { $0 == 0 ? "끔" : String(repeating: "∿", count: $0) } ?? "—").font(.caption2.bold())
            }.frame(width: 36, height: 44).foregroundStyle((level ?? 0) > 0 ? tint : Color.primary.opacity(0.7))
                .background(tint.opacity((level ?? 0) > 0 ? 0.25 : 0.07), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel(title + (cooling ? " 통풍" : " 열선") + (level.map { " \($0)단계, 다음 단계로 변경" } ?? " 상태 미수신, 1단계 요청"))
    }
    private var modeControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                modeButton("유지", icon: "fanblades", index: 1)
                modeButton("반려동물", icon: "pawprint.fill", index: 2)
                modeButton("캠핑", icon: "tent.fill", index: 3)
            }
            Caption("차량에서 내린 후에도 공조를 유지하는 모드입니다. 차량 수신 상태를 확인해 주세요.")
        }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16)).disabled(blocked)
    }
    private func modeButton(_ title: String, icon: String, index: Int) -> some View {
        let modes = ["off": 0, "on": 1, "dog": 2, "camp": 3]
        let current = acceptedMode ?? modes[measured.string("climate_keeper_mode")]
        return tile(title, icon: icon, active: current == index) {
            let next = current == index ? 0 : index
            run(next == 0 ? title + " 모드 끄기" : title + " 모드 켜기", accepted: { acceptedMode = next }) { try await model.fleet.setClimateKeeperMode(mode: next) }
        }
    }
    private func tile(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon); Text(title).font(.caption2.bold()) }
                .frame(maxWidth: .infinity).frame(minHeight: 48).padding(.vertical, 4)
                .background(active ? Color.blue.opacity(0.7) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(MotionButtonStyle())
    }
    private func run(_ title: String, accepted: @escaping () -> Void = {}, action: @escaping () async throws -> Bool) {
        guard !blocked else { return }
        guard model.fleet.isAuthenticated else { result = "이 기능은 Fleet 원격 제어 설정이 필요합니다."; return }
        busy = true; result = title + " 전송 중"
        Task { @MainActor in
            defer { busy = false }
            do {
                guard try await action() else { throw FleetCommandPolicy.failure("차량이 요청을 승인하지 않았습니다.") }
                accepted()
                result = title + " 요청 승인 · 실제 상태는 다음 수신 시 확인"
                model.voice.say(title + " 요청이 승인되었으며, 차량 상태를 다시 확인합니다.", category: "voiceControl", manual: true)
                await model.fleet.refreshVehicleSnapshot(force: true)
                acceptedLevels.removeAll(); acceptedMode = nil
            } catch { result = error.localizedDescription }
        }
    }
}

/// One visible control per feature. Unknown state offers explicit intent without guessing.
struct VehicleStateButton: View {
    let title: String
    let icon: String
    let state: Bool?
    var onTitle = "켜기"
    var offTitle = "끄기"
    var onState = "작동 중"
    var offState = "꺼짐"
    let change: (Bool) -> Void
    private var label: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
            Text(title).font(.caption2.bold())
            Text(state.map { $0 ? onState : offState } ?? "상태 확인 필요").font(.caption2)
        }.frame(maxWidth: .infinity).frame(minHeight: 58).padding(.vertical, 4)
            .background(state == true ? Color.blue.opacity(0.7) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
    var body: some View {
        if let state {
            Button { change(!state) } label: { label }.buttonStyle(MotionButtonStyle())
                .accessibilityHint("누르면 " + (state ? offTitle : onTitle))
        } else {
            Menu {
                Button(title + " " + onTitle) { change(true) }
                Button(title + " " + offTitle) { change(false) }
            } label: { label }
        }
    }
}
