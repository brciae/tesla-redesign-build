import SwiftUI

/// Read-only, explicit playback: never dispatches a vehicle or automation command.
struct ScreenBriefingControls: View {
    @EnvironmentObject private var model: AppModel
    let screen: String
    var compact = false
    var body: some View {
        HStack(spacing: 8) {
            Button { model.speak(model.screenBriefing(screen)) } label: {
                if compact { Image(systemName: "waveform").frame(width: 44, height: 44) }
                else { Label("현재 상태 브리핑", systemImage: "waveform").frame(minHeight: 44) }
            }
            .accessibilityLabel("\(screen) 현재 상태 브리핑")
            .accessibilityIdentifier("briefing.play.\(screen)")
            Button { model.stopSpeech() } label: {
                Image(systemName: "stop.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("브리핑 중지")
        }
        .buttonStyle(.borderless)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
}

extension AppModel {
    func screenBriefing(_ screen: String) -> String {
        let home = homePresentation(self, link)
        let charge = home.object("charge"), climate = home.object("climate")
        let fresh = output.object("fresh")
        let drive = groups.object("drive")
        func measurement(_ values: Object, key: String, label: String, unit: String) -> String {
            guard let value = values.number(key), value.isFinite else { return "\(label)은 미확인입니다." }
            let mode = values.string("mode")
            guard demo || mode == "recent" || mode == "cached" else { return "\(label)은 미확인입니다." }
            let age = mode == "cached" ? "마지막 수신 자료 기준 " : ""
            return age + label + " \(Int(value.rounded()))" + unit + "입니다."
        }
        let connection = demo ? "예시 모드의 자료입니다." : (link.authentic ? "블루투스로 차량에 연결되어 있습니다." : "Fleet 상태는 \(fleet.vehicleDisplayStatus)입니다.")
        let battery = measurement(charge, key: "soc", label: "배터리 잔량", unit: "퍼센트")
        let inside = measurement(climate, key: "insideC", label: "실내 온도", unit: "도")
        var details: [String] = []
        switch screen {
        case "자동화":
            details = ["전체 \(automations.rules.count)개 중 \(automations.rules.filter(\.enabled).count)개 규칙이 활성 상태입니다.", automations.presence, automations.status]
            if let last = automations.logs.first { details.append("최근 기록은 \(last.rule), \(last.status)입니다.") }
            else { details.append("아직 실행 기록이 없습니다.") }
        case "실내 공조", "공조":
            details = [inside, measurement(climate, key: "outsideC", label: "외부 온도", unit: "도")]
        case "충전", "에너지", "배터리":
            details = [battery, measurement(charge, key: "chargerKW", label: "충전 전력", unit: "킬로와트"), measurement(charge, key: "limit", label: "충전 한도", unit: "퍼센트")]
        case "주행", "운행", "운전 대시보드":
            details = [battery]
            if fresh.flag("drive") {
                if let speed = drive.number("speedKmh"), speed.isFinite {
                    details.append("차량 수신 속도는 시속 \(Int(speed.rounded()))킬로미터입니다.")
                } else { details.append("차량 수신 속도는 미확인입니다.") }
                let destination = drive.string("destination")
                details.append(destination.isEmpty ? "차량 내비 목적지는 미설정입니다." : "차량 내비 목적지는 \(destination)입니다.")
            } else { details.append("차량 속도와 내비 목적지는 최신 수신값이 없습니다.") }
        case "표시·음성 설정":
            let defaults = UserDefaults.standard
            details = [defaults.bool(forKey: "voiceEnabled") ? "음성 안내가 켜져 있습니다." : "음성 안내가 꺼져 있습니다.", "선택한 타입캐스트 음성을 사용합니다.", "하단 메뉴 불투명도는 \(Int((defaults.object(forKey: "tabBarOpacity") as? Double ?? 1) * 100))퍼센트입니다."]
        default:
            details = [battery, inside]
        }
        if screen == "차량 제어" || screen == "홈" {
            if let snapshot = fleet.vehicleSnapshot, snapshot.vin == fleet.selectedVin, snapshot.isRecent(), let locked = snapshot.locked, !link.authentic {
                details.append(locked ? "차량은 잠겨 있습니다." : "차량 잠금이 해제되어 있습니다.")
            } else if fresh.flag("closures"), let locked = groups.object("closures")["locked"] as? Bool {
                details.append(locked ? "차량은 잠겨 있습니다." : "차량 잠금이 해제되어 있습니다.")
            } else { details.append("차량 잠금 상태는 미확인입니다.") }
        }
        return (["\(screen) 현재 상태입니다.", connection] + details).joined(separator: " ")
    }
}
