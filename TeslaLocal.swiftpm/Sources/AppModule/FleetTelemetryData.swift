import Foundation
import CoreFoundation

/// The wire value and timestamp are retained; invalid values explicitly supersede earlier data.
struct FleetTelemetryReading: Codable, Identifiable {
    let vin: String
    let field: String
    let at: Date
    let number: Double?
    let text: String
    let invalid: Bool
    var id: String { vin + ":" + field + ":" + String(at.timeIntervalSince1970) }
}

enum FleetTelemetryData {
    static func decode(_ data: Data, vin: String, now: Date = Date()) throws -> [FleetTelemetryReading] {
        guard !vin.isEmpty, data.count <= 5_000_000 else { throw failure("차량 선택과 파일 크기를 확인해 주세요. 최대 5 MB입니다.") }
        let json = try JSONSerialization.jsonObject(with: data)
        let payloads: [[String: Any]]
        if let array = json as? [[String: Any]] { payloads = array }
        else if let object = json as? [String: Any] { payloads = [object] }
        else { throw failure("Tesla Telemetry Payload JSON 또는 Payload 배열이 필요합니다.") }
        guard payloads.count <= 5000 else { throw failure("한 번에 최대 5,000개 메시지를 가져올 수 있습니다.") }
        let iso = ISO8601DateFormatter()
        let fractions = ISO8601DateFormatter(); fractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var result: [FleetTelemetryReading] = []
        for payload in payloads {
            guard payload["vin"] as? String == vin else { throw failure("선택 차량과 다른 VIN의 메시지는 가져오지 않습니다.") }
            let stamp = payload["createdAt"] ?? payload["created_at"]
            var date: Date?
            if let text = stamp as? String { date = fractions.date(from: text) ?? iso.date(from: text) }
            if let parts = stamp as? [String: Any] {
                let seconds = (parts["seconds"] as? NSNumber)?.doubleValue ?? (parts["seconds"] as? String).flatMap(Double.init)
                if let seconds, seconds.isFinite { date = Date(timeIntervalSince1970: seconds) }
            }
            guard let at = date, at.timeIntervalSince1970 > 0, at <= now.addingTimeInterval(5),
                  let values = payload["data"] as? [[String: Any]], values.count <= 1000 else {
                throw failure("메시지의 원본 시각과 data 배열을 확인해 주세요. 미래 시각은 가져오지 않습니다.")
            }
            for datum in values {
                guard let field = datum["key"] as? String, !field.isEmpty, field.count <= 100,
                      let value = datum["value"] as? [String: Any] else { throw failure("필드 이름과 형식이 잘못된 Telemetry 값입니다.") }
                let invalid = value["invalid"] as? Bool == true
                let numericKeys = ["doubleValue", "double_value", "floatValue", "float_value", "intValue", "int_value", "longValue", "long_value"]
                var number: Double?
                if !invalid {
                    for key in numericKeys {
                        if let item = value[key] as? NSNumber, CFGetTypeID(item) != CFBooleanGetTypeID(), item.doubleValue.isFinite { number = item.doubleValue; break }
                        if let item = value[key] as? String, let parsed = Double(item), parsed.isFinite { number = parsed; break }
                    }
                }
                let raw = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                let text = invalid ? "차량에서 유효하지 않다고 보고함" : String(data: raw, encoding: .utf8) ?? ""
                result.append(FleetTelemetryReading(vin: vin, field: field, at: at, number: number, text: text, invalid: invalid))
                guard result.count <= 50000 else { throw failure("필드 수가 너무 많습니다. 기간을 나누어 가져와 주세요.") }
            }
        }
        guard !result.isEmpty else { throw failure("가져올 측정값이 없습니다.") }
        return result
    }
    static func merge(_ existing: [FleetTelemetryReading], _ incoming: [FleetTelemetryReading], limit: Int = 50000) -> [FleetTelemetryReading] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for reading in incoming { byID[reading.id] = reading }
        return Array(byID.values.sorted { $0.at == $1.at ? $0.field < $1.field : $0.at < $1.at }.suffix(limit))
    }
    static func latest(_ records: [FleetTelemetryReading], vin: String) -> [String: FleetTelemetryReading] {
        var result: [String: FleetTelemetryReading] = [:]
        for reading in records where reading.vin == vin {
            if result[reading.field].map({ $0.at <= reading.at }) ?? true { result[reading.field] = reading }
        }
        return result
    }
    static func pairedDifference(_ first: FleetTelemetryReading?, _ second: FleetTelemetryReading?, maximumSkew: TimeInterval = 2) -> Double? {
        guard let first, let second, first.vin == second.vin, !first.invalid, !second.invalid,
              abs(first.at.timeIntervalSince(second.at)) <= maximumSkew,
              let high = first.number, let low = second.number, high >= low else { return nil }
        return high - low
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "FleetTelemetry", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
