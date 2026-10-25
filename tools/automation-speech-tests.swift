import Foundation
@main struct AutomationSpeechTests {
    static func main() throws {
        let context = AutomationSpeechContext(trigger: "boarding", hour: 8, insideC: 35, scope: "PRIVATE-VIN")
        let base = "배터리 82퍼센트입니다. 공조 실행 결과는 아직 미확인입니다."
        let options = AutomationSpeechPolicy.options(base: base, context: context)
        precondition(options.count == 3 && options.allSatisfy { $0.contains(base) })
        precondition(options[2].contains("실내 온도가 높습니다"))
        let selected = AutomationSpeechPolicy.selected("{\"choice\":2}", options: options)
        precondition(selected == options[2] && selected!.contains("미확인"))
        for reply in ["{\"choice\":true}", "{\"choice\":1.5}", "{\"choice\":3}", "{\"choice\":-1}",
                      "{\"choice\":1,\"command\":\"unlock\"}", "공조를 켰습니다.", "```json\n{\"choice\":1}\n```"] {
            precondition(AutomationSpeechPolicy.selected(reply, options: options) == nil)
        }
        let prompt = try AutomationSpeechPolicy.prompt(options: options, context: context)
        precondition(!prompt.contains(context.scope) && !prompt.contains("latitude"))
        let stale = AutomationSpeechContext(trigger: "boarding", hour: 19, insideC: nil, scope: "")
        precondition(!AutomationSpeechPolicy.options(base: base, context: stale).contains { $0.contains("실내 온도") })
        precondition(AutomationSpeechPolicy.canOmitRoutine(base: "탑승을 환영합니다.", context: context))
        precondition(AutomationSpeechPolicy.canOmitRoutine(base: "좋은 오후입니다.", context: context))
        precondition(AutomationSpeechPolicy.canOmitRoutine(base: "좋은 아침입니다. 탑승을 환영합니다.", context: context))
        precondition(!AutomationSpeechPolicy.canOmitRoutine(base: base, context: context))
        precondition(!AutomationSpeechPolicy.canOmitRoutine(base: "차량 잠금이 확인되지 않았습니다.", context: context))
        let routineOptions = AutomationSpeechPolicy.options(base: "탑승을 환영합니다.", context: context, allowRoutineOmission: true)
        precondition(AutomationSpeechPolicy.selected("{\"choice\":3}", options: routineOptions) == "")
        print("PASS: AI context phrase selection preserves facts/outcome, rejects commands/new text and omits vehicle identity/unknown temperature")
    }
}
