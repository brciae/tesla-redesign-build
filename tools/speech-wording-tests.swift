import Foundation

@main struct SpeechWordingTests {
    static func main() {
        let cases = ["충전 종료": "충전이 끝났습니다.", "공조 꺼짐": "공조가 꺼져 있습니다.",
                     "문 열림": "문이 열려 있습니다.", "차량 연결됨": "차량이 연결되었습니다.",
                     "휴식 필요": "휴식이 필요합니다.", "충전량 미확인": "충전량이 확인되지 않았습니다.",
                     "목적지 미설정": "목적지가 설정되지 않았습니다.", "차량 정보 미수신": "차량 정보를 아직 받지 못했습니다.",
                     "배터리가 82.5퍼센트 남았습니다.": "배터리가 82.5퍼센트 남았습니다.",
                     "창문을 확인하세요!": "창문을 확인하세요!", "기록 없음": "기록이 없습니다.",
                     "책임": "책임입니다.", "성함": "성함입니다."]
        for (source, expected) in cases {
            let actual = SpeechEnding.natural(source)
            precondition(actual == expected, "Natural fragment: \(source) => \(actual)")
            precondition(SpeechEnding.natural(actual) == actual, "Grammar preparation must be idempotent")
        }
        var sample = AutomationSample(now: 0, vehicle: "TEST")
        sample.driveFresh = true; sample.chargeFresh = true; sample.soc = 12
        for destination in ["학교", "서울역", "반포대교", "서울", "101동"] {
            sample.destination = destination
            let rule = AutomationRule(name: "목적지 변경", trigger: .destination)
            let text = AutomationPolicy.renderedText(for: rule, sample: sample)
            precondition(text == "목적지를 변경했습니다. \(destination)까지 안내합니다.", "Destination name must not select a fixed wrong particle")
        }
        for (trigger, fragment) in [(AutomationTrigger.chargeEnd, "충전이 끝났습니다."), (.batteryLow, "배터리가 12퍼센트 남았습니다."), (.tireLow, "타이어 공기압이 낮습니다.")] {
            let text = AutomationPolicy.renderedText(for: AutomationRule(name: "검증", trigger: trigger), sample: sample)
            precondition(text.contains(fragment))
        }
        var custom = AutomationRule(name: "사용자 문구", trigger: .destination)
        custom.message = "학교로 안내해 주세요!"
        precondition(AutomationPolicy.renderedText(for: custom, sample: sample) == custom.message)
        precondition(SpeechText.prepare(SpeechEnding.natural("배터리가 82.5% 남았습니다.")) == "배터리가 팔십이 점 오 퍼센트 남았습니다.")
        print("PASS: complete spoken sentences, particles, decimal preservation, idempotence, destination names and user message preservation")
    }
}
