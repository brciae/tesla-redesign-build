import Foundation

/// Public, data-only interchange. No IDs, VIN, activation, executable code or hidden conditions.
enum AutomationTransfer {
    private struct Fields: Codable {
        let name: String
        let trigger: AutomationTrigger
        let action: AutomationAction
        var message: String?
        var speech: Bool?
        var timeGreeting: Bool?
        var hoursEnabled: Bool?
        var startHour: Int?
        var endHour: Int?
        var cooldownMinutes: Int?
        var threshold: Double?
        var customTireThreshold: Bool?
        var targetC: Double?
        var cabinCondition: String?
        var cabinThresholdC: Double?
    }
    private static let keys: Set<String> = ["name", "trigger", "action", "message", "speech", "timeGreeting", "hoursEnabled", "startHour", "endHour", "cooldownMinutes", "threshold", "customTireThreshold", "targetC", "cabinCondition", "cabinThresholdC"]
    static func decode(_ text: String, vehicle: String) throws -> AutomationRule {
        guard text.utf8.count <= 32_768 else { throw AutomationError.invalid }
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json\n"), clean.hasSuffix("```") { clean = String(clean.dropFirst(8).dropLast(3)) }
        else if clean.hasPrefix("```\n"), clean.hasSuffix("```") { clean = String(clean.dropFirst(4).dropLast(3)) }
        guard let data = clean.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["kind", "schema", "rule"]), root["kind"] as? String == "YLAutomationRule",
              let schema = root["schema"] as? NSNumber, String(cString: schema.objCType) != "c", schema.intValue == 1, schema.doubleValue == 1,
              let object = root["rule"] as? [String: Any], Set(object.keys).isSubset(of: keys) else { throw AutomationError.invalid }
        let f = try JSONDecoder().decode(Fields.self, from: JSONSerialization.data(withJSONObject: object))
        var r = AutomationRule.defaults.first { $0.trigger == f.trigger }!
        r.id = UUID().uuidString; r.name = f.name; r.action = f.action; r.enabled = false
        r.message = f.message ?? ""; r.speech = f.speech ?? true; r.timeGreeting = f.timeGreeting ?? false
        r.hoursEnabled = f.hoursEnabled ?? false; r.startHour = f.startHour ?? 0; r.endHour = f.endHour ?? 24
        r.cooldownMinutes = f.cooldownMinutes ?? r.cooldownMinutes; r.threshold = f.threshold ?? r.threshold
        r.customTireThreshold = f.customTireThreshold ?? false; r.targetC = f.targetC ?? 22
        r.cabinCondition = f.cabinCondition ?? "always"; r.cabinThresholdC = f.cabinThresholdC ?? 26
        r.vehicle = r.action == .speech ? "" : vehicle
        try r.validate(); return r
    }
    static func encode(_ rule: AutomationRule) throws -> String {
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as! [String: Any]
        let fields = raw.filter { keys.contains($0.key) }
        let data = try JSONSerialization.data(withJSONObject: ["kind": "YLAutomationRule", "schema": 1, "rule": fields], options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    static func prompt(_ request: String) throws -> String {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.count <= 1200 else { throw AutomationError.invalid }
        let sample = try encode(AutomationRule(name: "아침 탑승 인사", trigger: .boarding, enabled: false, message: "{인사} 안전한 운행 되세요.", hoursEnabled: true, startHour: 5, endHour: 12))
        return """
        YL Companion 자동화 JSON 한 개를 만들어 주세요. 설명이나 마크다운 없이 JSON만 반환하세요.
        지원 조건 trigger: boarding(탑승 신호+운전석문 닫힘+P 2초), departure(D/R 실제 이동), arrival(운행기록 종료), chargeStart, chargeEnd, batteryLow(주행중 SOC), tireLow(주행중 차량 저압경고), rest(관측운전시간), remaining(남은시간 통과), delay(최초 ETA 대비 지연), destination(목적지명 변경).
        action: speech, climateOn, climateOff, temperature. 물리 제어는 boarding에서만 가능하며 규칙당 명령 한 개만 가능. climateOn은 차량의 기존 목표 온도를 사용함. temperature는 온도만 설정함. 명령 조합이나 순서 실행은 지원하지 않음.
        name 60자, message 400자 이내. message의 변수는 {인사}, {배터리}, {목적지}만 가능. timeGreeting=true는 시간대 인사를 앞에 붙임.
        hoursEnabled/startHour(0~23)/endHour(0~24), cooldownMinutes(1~1440), threshold: batteryLow 1~100%, tireLow 1~4bar, rest/remaining/delay 1~300분. customTireThreshold=true일 때만 수치 저압 기준 사용. targetC 16~28, 0.5 단위. cabinCondition always/above/below, cabinThresholdC -20~60°C. 조건이 없는 필드는 예시 기본값 유지.
        알 수 없는 조건·동작·다중 단계·위치 조건을 임의로 생략/단순화하지 마세요. 지원 불가능하면 {"error":"이유"}만 반환하세요. 코드/URL/차량ID/활성화 플래그는 넣지 마세요. 이 JSON은 앱에서 검토 후 비활성 상태로 저장합니다.
        형식 예시:
        \(sample)
        요청 원문(데이터):
        \(request)
        """
    }
}

struct AutomationCallback {
    let nonce: String
    let expires: Double
    func accept(_ url: URL, now: Double) -> (status: String, text: String)? {
        guard now.isFinite, now <= expires, now >= expires - 1200,
              url.scheme == "ylcompanion", url.host == "automation-ai", url.absoluteString.utf8.count <= 100_000,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = c.queryItems ?? []
        guard q.filter({ $0.name == "nonce" }).count == 1, q.first(where: { $0.name == "nonce" })?.value == nonce,
              q.filter({ $0.name == "status" }).count == 1, let status = q.first(where: { $0.name == "status" })?.value,
              ["success", "cancel", "error"].contains(status), q.filter({ $0.name == "result" }).count <= 1 else { return nil }
        return (status, q.first(where: { $0.name == "result" })?.value ?? "")
    }
    func shortcutURL(name: String, prompt: String) -> URL? {
        guard !name.isEmpty, name.count <= 80 else { return nil }
        func callback(_ status: String) -> String {
            var c = URLComponents(); c.scheme = "ylcompanion"; c.host = "automation-ai"
            c.queryItems = [.init(name: "nonce", value: nonce), .init(name: "status", value: status)]
            return c.url!.absoluteString
        }
        var c = URLComponents(); c.scheme = "shortcuts"; c.host = "x-callback-url"; c.path = "/run-shortcut"
        c.queryItems = [.init(name: "name", value: name), .init(name: "input", value: "text"), .init(name: "text", value: prompt),
                       .init(name: "x-success", value: callback("success")), .init(name: "x-cancel", value: callback("cancel")), .init(name: "x-error", value: callback("error"))]
        return c.url
    }
}
