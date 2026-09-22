import SwiftUI

extension AppModel {
    func requestVehicleControl(_ action: String, title: String, args: Object = [:]) {
        guard !demo, UIApplication.shared.applicationState == .active else { errorMessage = "데모 또는 백그라운드에서는 차량 제어할 수 없습니다."; return }
        guard !link.controlBusy, !link.preparingControl, link.confirmation == nil, !fleet.isSendingCommand else { errorMessage = "앞선 제어 요청을 완료하거나 취소해 주세요."; return }
        if action != "chargeAmps", link.authentic && link.controlEnabled { link.askControl(action, title: title, args: args); return }
        guard fleet.isAuthenticated else { errorMessage = "BLE 제어 키 또는 Fleet 원격 제어 설정이 필요합니다."; return }
        Task { @MainActor in
            do {
                let command: String
                var parameters: Object = [:]
                switch action {
                case "lock": command = "door_lock"
                case "unlock": command = "door_unlock"
                case "frunkOpen": command = "actuate_trunk"; parameters = ["which_trunk": "front"]
                case "trunkMove": command = "actuate_trunk"; parameters = ["which_trunk": "rear"]
                case "climateOn": command = "auto_conditioning_start"
                case "climateOff": command = "auto_conditioning_stop"
                case "temperature":
                    guard let value = args.number("value"), value.isFinite, (16...28).contains(value) else { throw FleetCommandPolicy.failure("온도 입력 확인 필요") }
                    command = "set_temps"; parameters = ["driver_temp": value, "passenger_temp": value]
                case "chargeStart": command = "charge_start"
                case "chargeStop": command = "charge_stop"
                case "portOpen": command = "charge_port_door_open"
                case "portClose": command = "charge_port_door_close"
                case "chargeLimit", "chargeAmps":
                    guard let value = args.number("value"), value.isFinite, (action == "chargeLimit" ? 50...100 : 1...48).contains(value) else { throw FleetCommandPolicy.failure("충전 설정값 확인 필요") }
                    command = action == "chargeLimit" ? "set_charge_limit" : "set_charging_amps"
                    parameters = [action == "chargeLimit" ? "percent" : "charging_amps": Int(value)]
                case "flash": command = "flash_lights"
                case "honk": command = "honk_horn"
                default: throw FleetCommandPolicy.failure("이 제어는 원격 전송이 구현되지 않았습니다.")
                }
                _ = try await fleet.sendCommand(command: command, parameters: parameters)
                voice.say("\(title) 승인 응답을 받았습니다.", category: "voiceControl", manual: true)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
