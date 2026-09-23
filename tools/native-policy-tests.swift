import Foundation

@main struct NativePolicyTests {
    static func main() {
        let expired = Date(timeIntervalSince1970: 10)
        let afterSynthesis = Date(timeIntervalSince1970: 45)
        for key in ["manual", "preview", "climate.temp"] {
            precondition(VoiceItem(key: key, text: "report", expires: expired, priority: 2, manual: true).canStartPlayback(at: afterSynthesis))
        }
        for key in ["navigation.turn", "navigation.safety", "dashboard.start"] {
            precondition(!VoiceItem(key: key, text: "expired", expires: expired, priority: 4, manual: true).canStartPlayback(at: afterSynthesis))
        }
        precondition(!VoiceItem(key: "automatic", text: "expired", expires: expired, priority: 1, manual: false).canStartPlayback(at: afterSynthesis))
        let spokenUnits = ["실내 22°C": "실내 섭씨 이십이 도", "21.5 ° C": "섭씨 이십일 점 오 도", "-5℃": "섭씨 영하 오 도", "72°F": "화씨 칠십이 도", "80%": "팔십 퍼센트", "60 km/h": "시속 육십 킬로미터", "2.8 bar": "이 점 팔 바", "68도": "육십팔 도"]
        for (input, expected) in spokenUnits {
            precondition(SpeechText.prepare(input) == expected, "Speech unit: \(input)")
            precondition(SpeechText.prepare(SpeechText.prepare(input)) == expected)
        }
        precondition(SpeechText.prepare("MC 빌딩으로 안내를 시작합니다.") == "MC 빌딩으로 안내를 시작합니다.")
        precondition(SpeechText.prepare("온도22°C로 설정") == "온도섭씨 이십이 도로 설정")
        for (input, expected) in ["3.0m": "삼 미터", "3.00 미터": "삼 미터", "3.50km": "삼 점 오 킬로미터", "0.05m": "영 점 영 오 미터", "22.0°C": "섭씨 이십이 도", "80.0%": "팔십 퍼센트", "2.0kWh": "이 킬로와트시", "3.0 버전": "3.0 버전"] {
            precondition(SpeechText.prepare(input) == expected, "Speech decimal: \(input)")
        }
        let phrases = ["climateOn": "공조를 시작합니다.", "climateOff": "공조를 끕니다.", "chargeStart": "충전을 시작합니다.", "chargeStop": "충전을 중지합니다.", "portOpen": "충전 포트를 엽니다.", "portClose": "충전 포트를 닫습니다.", "lock": "차량 문을 잠급니다.", "unlock": "차량 문 잠금을 해제합니다.", "trunkMove": "트렁크를 작동합니다.", "trunkClose": "트렁크를 닫습니다.", "frunkOpen": "프렁크를 엽니다."]
        for (action, text) in phrases { precondition(ControlVoice.message(action: action, result: .accepted) == text) }
        precondition(ControlVoice.message(action: "temperature", value: 22.5, units: VehicleUnits(), result: .accepted) == "실내 온도를 22.5도로 설정합니다.")
        precondition(ControlVoice.message(action: "temperature", value: 20, units: VehicleUnits(temperature: "F"), result: .accepted) == "실내 온도를 화씨 68도로 설정합니다.")
        precondition(ControlVoice.message(action: "chargeLimit", value: 80, result: .accepted) == "충전 한도를 80퍼센트로 설정합니다.")
        precondition(ControlVoice.message(action: "climateOn", result: .rejected) == "지금은 차량에서 실행할 수 없습니다.")
        precondition(ControlVoice.message(action: "frunkOpen", result: .unknown) == "차량 응답을 확인하지 못했습니다.")
        precondition(ControlVoice.message(action: "chargeStop", result: .failed) == "선택한 기능을 실행하지 못했습니다.")
        precondition(Array(VehicleReadPlan.initial.prefix(2)) == ["drive", "location"])
        precondition(VehicleReadPlan.regular.count == 21 && VehicleReadPlan.regular.filter { $0 == "location" }.count == 7 && VehicleReadPlan.regular.filter { $0 == "charge" }.count == 2 && VehicleReadPlan.regular.filter { $0 == "media" }.count == 1)
        precondition(Set(VehicleReadPlan.initial) == Set(VehicleReadPlan.regular))
        precondition(VehicleReadPlan.enteredPark(previous: "D", gear: "P", at: 100000, now: 100000))
        precondition(!VehicleReadPlan.enteredPark(previous: "P", gear: "P", at: 100000, now: 100000))
        precondition(!VehicleReadPlan.enteredPark(previous: "D", gear: "P", at: 100000, now: 140001))
        func close(_ actual: Double, _ expected: Double) { precondition(abs(actual - expected) < 0.00001) }
        let si = VehicleUnits(), us = VehicleUnits(distance: "mi", temperature: "F", pressure: "psi")
        close(us.distanceValue(160.9344), 100); close(us.temperatureValue(-40), -40)
        close(us.temperatureValue(0), 32); close(us.pressureValue(2.5), 36.2594344325)
        close(VehicleUnits(pressure: "kPa").pressureValue(2.5), 250)
        precondition(si.format(nil, suffix: "bar") == "—")
        precondition(si.format(.nan, suffix: "°C") == "—")
        precondition(us.format(100, suffix: "%") == "100%")
        precondition(us.format(160.9344, suffix: " km") == "100 mi")
        precondition(us.format(0, suffix: "°C") == "32°F")
        precondition(us.format(2.5, suffix: " bar") == "36.3 psi")
        precondition(VoiceQueue.quiet(hour: 23, start: 22, end: 7))
        precondition(VoiceQueue.quiet(hour: 6, start: 22, end: 7))
        precondition(!VoiceQueue.quiet(hour: 7, start: 22, end: 7))
        precondition(!VoiceQueue.quiet(hour: 23, start: 7, end: 7))
        precondition(VoiceQueue.quiet(hour: 13, start: 12, end: 16))
        var q = VoiceQueue(); let now = Date(timeIntervalSince1970: 1000)
        func item(_ key: String, _ priority: Int = 1, _ ttl: Double = 15) -> VoiceItem { VoiceItem(key: key, text: key, expires: now.addingTimeInterval(ttl), priority: priority, manual: false) }
        q.add(item("expired", 9, -1), now: now); precondition(q.items.isEmpty)
        q.add(item("brief"), now: now); q.add(item("brief"), now: now); precondition(q.items.count == 1)
        q.add(item("urgent", 3), now: now); precondition(q.next(now: now)?.key == "urgent")
        precondition(q.next(now: now.addingTimeInterval(16)) == nil)
        for i in 0..<20 { q.add(item("event\(i)"), now: now) }; precondition(q.items.count == 6)
        q.clear(); precondition(q.items.isEmpty)
        q.add(item("automatic"), now: now)
        q.add(VoiceItem(key: "preview", text: "manual", expires: now.addingTimeInterval(30), priority: 3, manual: true), now: now)
        q.clearAutomatic(); precondition(q.items.count == 1 && q.items[0].manual)
        precondition(q.next(now: now)?.key == "preview")
        q.add(item("later"), now: now); q.clearAutomatic(); precondition(q.items.isEmpty)
        q.add(VoiceItem(key: "navigation.turn", text: "좌회전", expires: now.addingTimeInterval(10), priority: 4, manual: true), now: now)
        q.add(VoiceItem(key: "navigation.safety", text: "방지턱", expires: now.addingTimeInterval(10), priority: 5, manual: true), now: now)
        q.pruneNavigation(forKey: "navigation.turn")
        precondition(q.items.count == 1 && q.items[0].key == "navigation.safety")
        q.add(VoiceItem(key: "navigation.turn", text: "우회전", expires: now.addingTimeInterval(10), priority: 4, manual: true), now: now)
        precondition(q.next(now: now)?.key == "navigation.safety")
        q.clearNavigation(); precondition(q.items.isEmpty)
        q.add(item("first"), now: now); q.add(item("second"), now: now)
        precondition(q.next(now: now)?.key == "first")
        precondition(q.next(now: now)?.key == "second")
        let parts = VehicleUnits().displayParts(8.02, suffix: " km/kWh", digits: 2)
        precondition(parts.0 == "8.02" && parts.1 == " km/kWh")
        print("PASS: natural action voice, location read priority, native unit conversions, unknown values, quiet hours, priority, dedupe, TTL and queue bound")
    }
}
