import Foundation

// Storage and commands stay in km, km/h, Celsius and bar. Conversion is presentation-only.
struct VehicleUnits: Equatable {
    var distance = "km"
    var temperature = "C"
    var pressure = "bar"
    var speedLabel: String { distance == "mi" ? "mph" : "km/h" }
    var temperatureLabel: String { temperature == "F" ? "°F" : "°C" }
    func distanceValue(_ km: Double) -> Double { distance == "mi" ? km / 1.609344 : km }
    func temperatureValue(_ celsius: Double) -> Double { temperature == "F" ? celsius * 9 / 5 + 32 : celsius }
    func pressureValue(_ bar: Double) -> Double {
        pressure == "psi" ? bar * 14.503773773 : pressure == "kPa" ? bar * 100 : bar
    }
    func format(_ value: Double?, suffix: String, digits: Int = 0) -> String {
        let parts = displayParts(value, suffix: suffix, digits: digits)
        return parts.0 + parts.1
    }
    func displayParts(_ value: Double?, suffix: String, digits: Int = 0) -> (String, String) {
        guard let value, value.isFinite else { return ("—", "") }
        var number = value, unit = suffix, precision = digits
        switch suffix.trimmingCharacters(in: .whitespaces) {
        case "km": number = distanceValue(value); unit = " " + distance
        case "km/h": number = distanceValue(value); unit = " " + speedLabel
        case "°C": number = temperatureValue(value); unit = temperatureLabel
        case "bar": number = pressureValue(value); unit = " " + pressure; precision = pressure == "bar" ? 2 : pressure == "psi" ? 1 : 0
        default: break
        }
        return (String(format: "%.*f", precision, number), unit)
    }
    static var saved: VehicleUnits {
        let d = UserDefaults.standard
        return VehicleUnits(distance: d.string(forKey: "unitDistance") ?? "km", temperature: d.string(forKey: "unitTemperature") ?? "C", pressure: d.string(forKey: "unitPressure") ?? "bar")
    }
}

/// Display glyphs must never reach either speech engine's language frontend.
/// Only known numeric units are expanded; destination names and arbitrary text stay intact.
enum SpeechText {
    static func prepare(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "℃", with: "°C").replacingOccurrences(of: "℉", with: "°F")
        let patterns: [(String, String, String)] = [
            (#"°\s*C"#, "섭씨 ", " 도"), (#"°\s*F"#, "화씨 ", " 도"),
            (#"km/h|㎞/h"#, "시속 ", " 킬로미터"), (#"mph"#, "시속 ", " 마일"),
            (#"kWh"#, "", " 킬로와트시"), (#"kW"#, "", " 킬로와트"),
            (#"km|㎞"#, "", " 킬로미터"), (#"mi"#, "", " 마일"), (#"m|ｍ"#, "", " 미터"),
            (#"kPa"#, "", " 킬로파스칼"), (#"psi"#, "", " 피에스아이"), (#"bar"#, "", " 바"),
            // v43: Korean unit words too, not only the Latin abbreviations. The recorded voice speaks a
            // number as its own clip, so "60킬로미터" has to become "육십 킬로미터" before it is matched.
            (#"킬로와트시"#, "", " 킬로와트시"), (#"킬로와트"#, "", " 킬로와트"),
            (#"킬로미터"#, "", " 킬로미터"), (#"미터"#, "", " 미터"),
            (#"%|퍼센트"#, "", " 퍼센트"), (#"도"#, "", " 도")
        ]
        for (unit, prefix, suffix) in patterns {
            let pattern = #"(?<![A-Za-z\d.])([−-]?\d+(?:\.\d+)?)\s*(?:"# + unit + #")(?![A-Za-z])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let source = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
                let raw = source.substring(with: match.range(at: 1)).replacingOccurrences(of: "−", with: "-")
                let negative = raw.hasPrefix("-")
                let value = negative ? String(raw.dropFirst()) : raw
                guard let spoken = number(value) else { continue }
                let sign = negative ? (prefix.contains("씨") ? "영하 " : "마이너스 ") : ""
                text = (text as NSString).replacingCharacters(in: match.range, with: prefix + sign + spoken + suffix)
            }
        }
        return text
    }
    private static func number(_ raw: String) -> String? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(parts[0]), (0...99999999).contains(whole) else { return nil }
        let digits = ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
        func group(_ n: Int) -> String {
            var result = ""
            for (divisor, unit) in [(1000, "천"), (100, "백"), (10, "십"), (1, "")] {
                let digit = n / divisor % 10
                if digit > 0 { result += (digit == 1 && divisor > 1 ? "" : digits[digit]) + unit }
            }
            return result
        }
        let high = whole / 10000, low = whole % 10000
        var result = whole == 0 ? "영" : (high > 0 ? (high == 1 ? "" : group(high)) + "만" : "") + group(low)
        if parts.count == 2 {
            var fraction = String(parts[1])
            while fraction.last == "0" { fraction.removeLast() }
            if !fraction.isEmpty { result += " 점 " + fraction.compactMap { $0.wholeNumberValue.map { digits[$0] } }.joined(separator: " ") }
        }
        return result
    }
}

enum ControlVoiceResult { case accepted, rejected, failed, unknown }
enum ControlVoice {
    static func message(action: String, value: Double? = nil, units: VehicleUnits = .saved, result: ControlVoiceResult) -> String {
        // ACK means accepted, not physical completion. Use present-tense action cues.
        if case .unknown = result { return "차량 응답을 확인하지 못했습니다." }
        if case .rejected = result { return "지금은 차량에서 실행할 수 없습니다." }
        if case .failed = result { return "선택한 기능을 실행하지 못했습니다." }
        let amount: String = {
            guard let value, value.isFinite else { return "" }
            let n = action == "temperature" ? units.temperatureValue(value) : value
            return n == n.rounded() ? String(format: "%.0f", n) : String(format: "%.1f", n)
        }()
        switch action {
        case "climateOn": return "공조를 시작합니다."
        case "climateOff": return "공조를 끕니다."
        case "chargeStart": return "충전을 시작합니다."
        case "chargeStop": return "충전을 중지합니다."
        case "portOpen": return "충전 포트를 엽니다."
        case "portClose": return "충전 포트를 닫습니다."
        case "lock": return "차량 문을 잠급니다."
        case "unlock": return "차량 문 잠금을 해제합니다."
        case "trunkMove": return "트렁크를 작동합니다." // Toggle can open, stop or reverse.
        case "trunkClose": return "트렁크를 닫습니다."
        case "frunkOpen": return "프렁크를 엽니다."
        case "temperature": return amount.isEmpty ? "실내 온도를 설정합니다." : "실내 온도를 \(units.temperature == "F" ? "화씨 " : "")\(amount)도로 설정합니다."
        case "chargeLimit": return amount.isEmpty ? "충전 한도를 설정합니다." : "충전 한도를 \(amount)퍼센트로 설정합니다."
        default: return "선택한 기능을 실행합니다."
        }
    }
}

enum VehicleReadPlan {
    static let initial = ["drive", "location", "closures", "charge", "climate", "tire", "media"]
    /// Response groups counted in the status line (media returns media + mediaDetail).
    static let groupCount = 8
    // Same total read rate; location is no longer starved behind every other group.
    // v29: drive/location every 2nd slot (navigation + trip continuity), charge 2×/cycle; slow groups once.
    // Must stay inside the per-group TTLs in analysis.js (drive 30 s … tire 15 min) at ~2.5 s per reply.
    static let regular = ["drive", "location", "charge", "drive", "location", "closures", "drive", "location", "charge", "drive", "location", "climate", "drive", "location", "closures", "drive", "location", "tire", "drive", "location", "media"]
    static func enteredPark(previous: String?, gear: String, at: Double?, now: Double) -> Bool {
        guard let at, at.isFinite, at <= now + 5000, now - at <= 30000 else { return false }
        return gear == "P" && previous != "P"
    }
}

struct VoiceItem {
    let key: String
    let text: String
    let expires: Date
    let priority: Int
    let manual: Bool
}

struct VoiceQueue {
    var items: [VoiceItem] = []
    mutating func pruneNavigation(forKey key: String) {
        items.removeAll { $0.key == key }
        if items.contains(where: { $0.key.hasPrefix("navigation.") }) {
            items.removeAll { $0.key.hasPrefix("navigation.") }
        }
    }
    private var last: [String: Date] = [:]
    mutating func add(_ item: VoiceItem, now: Date, cooldown: TimeInterval = 20) {
        guard !item.text.isEmpty, item.expires > now else { return }
        if !item.manual, let date = last[item.key], now.timeIntervalSince(date) < cooldown { return }
        last[item.key] = now
        last = last.filter { now.timeIntervalSince($0.value) < 600 }
        items.removeAll { $0.key == item.key || $0.expires <= now }
        let insertion = items.firstIndex { $0.priority < item.priority } ?? items.endIndex
        items.insert(item, at: insertion)
        if items.count > 6 { items.removeLast(items.count - 6) }
    }
    mutating func next(now: Date) -> VoiceItem? {
        items.removeAll { $0.expires <= now }
        return items.isEmpty ? nil : items.removeFirst()
    }
    mutating func clear() { items.removeAll() }
    mutating func clearNavigation() { items.removeAll { $0.key.hasPrefix("navigation.") } }
    mutating func clearAutomatic() { items.removeAll { !$0.manual } }
    static func quiet(hour: Int, start: Int, end: Int) -> Bool {
        start == end ? false : start < end ? hour >= start && hour < end : hour >= start || hour < end
    }
}
