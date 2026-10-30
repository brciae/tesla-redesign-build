import Foundation
import CoreFoundation

struct ChargeImportPreview {
    var rows: [[String: Any]] = []
    var rejected = 0
    var warnings: [String] = []
}

/// Formats share a preview, but never silently share an energy definition or currency.
enum ChargeImportParser {
    static func parse(_ text: String, expectedVIN: String = "") -> ChargeImportPreview {
        var result = ChargeImportPreview()
        guard text.utf8.count <= 10_000_000 else { result.warnings = ["파일은 10 MB 이하로 선택 필요함"]; return result }
        let body = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))
        var input: [[String: Any]] = []
        if body.hasPrefix("[") || body.hasPrefix("{") {
            guard let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { result.warnings = ["JSON 형식 오류 · 기존 기록 변경 없음"]; return result }
            input = flatten(json, depth: 0)
        } else {
            guard let matrix = csv(body), let header = matrix.first, Set(header.map(normalize)).count == header.count else { result.warnings = ["CSV 인용부호·중복 열 이름 확인 필요 · 기존 기록 변경 없음"]; return result }
            for values in matrix.dropFirst() where values.contains(where: { !$0.isEmpty }) {
                guard values.count == header.count else { result.rejected += 1; continue }
                input.append(Dictionary(uniqueKeysWithValues: zip(header, values.map { $0 as Any })))
            }
        }
        guard input.count <= 2000 else { result.warnings = ["한 번에 2000건 이하 자료만 가져올 수 있음"]; return result }
        for row in input {
            let pairs = row.map { (normalize($0.key), $0.value) }
            guard Set(pairs.map(\.0)).count == pairs.count else { result.rejected += 1; continue }
            let fields = Dictionary(uniqueKeysWithValues: pairs)
            if let vin = fields["vin"] as? String, !vin.isEmpty, !expectedVIN.isEmpty, vin.uppercased() != expectedVIN { result.rejected += 1; result.warnings.append("현재 차량과 다른 VIN 제외"); continue }
            guard let start = date(value(fields, ["chargestarttimeutc", "chargestarttime", "chargestartdatetime", "starttime", "startdate", "start", "startedat", "at", "date", "시작시각", "시작"])) else { result.rejected += 1; continue }
            let stored = number(value(fields, ["chargeenergyadded", "vehiclereportedkwh", "storedkwh"]))
            let supply = number(value(fields, ["supplykwh", "nassupplykwh", "wallenergykwh"]))
            let unknown = number(value(fields, ["energykwh", "energy", "kwh", "usage", "energyadded", "충전량"]))
            guard [stored, supply, unknown].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 300 }) else { result.rejected += 1; continue }
            var output: [String: Any] = ["at": start.timeIntervalSince1970 * 1000, "note": "Tesla 요청 자료"]
            if let stored { output["storedKWh"] = stored; output["storageVerified"] = true }
            if let supply { output["supplyKWh"] = supply }
            if stored == nil && supply == nil, let unknown { output["importedEnergyKWh"] = unknown; result.warnings.append("의미 미확인 kWh는 배터리 충전량·비용 계산에서 제외") }
            if let end = date(value(fields, ["chargeendtimeutc", "chargeendtime", "chargestopdatetime", "endtime", "end", "endedat", "종료시각", "종료"])) {
                guard end > start else { result.rejected += 1; continue }; output["end"] = end.timeIntervalSince1970 * 1000
            }
            let currency = (value(fields, ["currency", "통화"]) as? String ?? "").uppercased()
            if let cost = number(value(fields, ["totalcost", "totalamount", "amount", "cost", "금액"])) {
                if cost < 0 || cost > 10_000_000 { result.rejected += 1; continue }
                if currency == "KRW" || currency == "원" { output["cost"] = cost }
                else { output["importedAmount"] = cost; output["importedCurrency"] = currency.isEmpty ? "미확인" : String(currency.prefix(8)); result.warnings.append("원화가 확인되지 않은 금액은 원 단위 합계에서 제외") }
            }
            if let place = value(fields, ["sitelocationname", "sitename", "location", "place", "site", "장소"]) as? String { output["place"] = String(place.prefix(120)) }
            if let raw = value(fields, ["chargertype", "chargetype", "type"]) as? String {
                let kind = raw.lowercased()
                if kind.contains("supercharger") { output["chargeType"] = "supercharger" }
                else if kind.contains("dc") || kind.contains("fast") { output["chargeType"] = "dc" }
                else if kind.contains("ac") || kind.contains("slow") { output["chargeType"] = "ac" }
            }
            guard stored != nil || supply != nil || unknown != nil || output["cost"] != nil || output["importedAmount"] != nil else { result.rejected += 1; continue }
            result.rows.append(output)
        }
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }
    private static func normalize(_ key: String) -> String { key.lowercased().filter { $0.isLetter || $0.isNumber } }
    private static func value(_ row: [String: Any], _ aliases: [String]) -> Any? {
        for key in aliases { if let value = row[key], !(value is NSNull) { return value } }; return nil
    }
    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue }
        guard let raw = value as? String else { return nil }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        return Double(clean)
    }
    private static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber, n.doubleValue.isFinite, n.doubleValue > 946684800 {
            return Date(timeIntervalSince1970: n.doubleValue > 1e11 ? n.doubleValue / 1000 : n.doubleValue)
        }
        guard let string = value as? String else { return nil }
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            let iso = ISO8601DateFormatter(); iso.formatOptions = options; if let date = iso.date(from: string) { return date }
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "MM/dd/yyyy HH:mm", "yyyy.MM.dd HH:mm", "yyyy-MM-dd"] { formatter.dateFormat = format; if let date = formatter.date(from: string) { return date } }
        return nil
    }
    private static func flatten(_ value: Any, depth: Int) -> [[String: Any]] {
        guard depth < 8 else { return [] }
        if let list = value as? [Any] { return list.prefix(2001).flatMap { flatten($0, depth: depth + 1) } }
        guard let object = value as? [String: Any] else { return [] }
        if object.keys.contains(where: { ["at", "date", "start", "starttime", "startedat", "chargestarttime", "chargestarttimeutc", "chargestartdatetime", "시작"].contains(normalize($0)) }) { return [object] }
        return object.keys.sorted().prefix(30).flatMap { flatten(object[$0]!, depth: depth + 1) }
    }
    /// RFC 4180 quoted commas, escaped quotes and quoted line breaks. Malformed quoting is rejected.
    static func csv(_ text: String) -> [[String]]? {
        var records: [[String]] = [], row: [String] = [], cell = "", quoted = false, closed = false
        let chars = Array(text); var index = 0
        while index < chars.count {
            let ch = chars[index]
            if quoted {
                if ch == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { cell.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { cell.append(ch) }
            } else if ch == "," { row.append(cell); cell = ""; closed = false }
            else if ch == "\n" || ch == "\r" {
                if ch == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
                row.append(cell); if row.contains(where: { !$0.isEmpty }) { records.append(row) }; row = []; cell = ""; closed = false
            } else if ch == "\"", cell.isEmpty, !closed { quoted = true }
            else if closed || ch == "\"" { return nil }
            else { cell.append(ch) }
            index += 1
            if records.count > 2001 { return nil }
        }
        guard !quoted else { return nil }
        row.append(cell); if row.contains(where: { !$0.isEmpty }) { records.append(row) }
        return records
    }
}
