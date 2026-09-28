import Foundation
import CoreFoundation

/// Korea Environment Corporation EvCharger guide v1.25. IDs stay strings, including leading zeroes.
struct PublicCharger: Codable {
    var fields: [String: String]
    var id: String { value("statId") + ":" + value("chgerId") }
    func value(_ key: String) -> String { fields[key] ?? "" }
    var category: String {
        if value("busiId") == "TE", value("statNm").contains("슈퍼차저") || value("statNm").lowercased().contains("supercharger") { return "슈퍼차저" }
        if ["02", "08"].contains(value("chgerType")) { return "완속" }
        if ["01", "03", "04", "05", "06", "07", "09", "10", "11"].contains(value("chgerType")) { return "급속" }
        return "충전소"
    }
}

enum PublicChargingData {
    struct Page { let rows: [PublicCharger]; let total: Int }
    static func failure(_ message: String) -> NSError { NSError(domain: "PublicCharging", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func decode(_ data: Data) throws -> Page {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("충전소 API 응답 형식을 확인하지 못했습니다. 인증키 승인 상태를 확인하세요.") }
        let root = json["response"] as? [String: Any] ?? json
        let header = root["header"] as? [String: Any] ?? root
        let code = String(describing: header["resultCode"] ?? "")
        guard ["00", "0"].contains(code) else { throw failure("충전소 API 조회가 거절되었습니다. 인증키·승인 상태·호출 한도를 확인하세요.") }
        let body = root["body"] as? [String: Any] ?? root
        let items = body["items"] as? [String: Any]
        let raw = items?["item"] ?? body["items"]
        let rows = raw as? [[String: Any]] ?? (raw as? [String: Any]).map { [$0] } ?? []
        let values = rows.map { row in PublicCharger(fields: row.reduce(into: [:]) { dict, item in
            if let text = item.value as? String { dict[item.key] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            else if let number = item.value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { dict[item.key] = number.stringValue }
        }) }.filter { !$0.value("statId").isEmpty && !$0.value("chgerId").isEmpty }
        let total = Int(String(describing: body["totalCount"] ?? header["totalCount"] ?? 0)) ?? 0
        return Page(rows: values, total: max(0, total))
    }
    static func merge(_ existing: [PublicCharger], _ updates: [PublicCharger]) -> [PublicCharger] {
        var records: [String: PublicCharger] = [:]
        for row in existing + updates {
            let incomingValid = row.value("statUpdDt").range(of: "^[0-9]{14}$", options: .regularExpression) != nil
            if let old = records[row.id], !old.value("statUpdDt").isEmpty, incomingValid,
               old.value("statUpdDt") > row.value("statUpdDt") { continue }
            var fields = records[row.id]?.fields ?? [:]
            let preserveStatus = records[row.id]?.value("statUpdDt").isEmpty == false && !incomingValid
            row.fields.forEach {
                if preserveStatus && ["stat", "statUpdDt", "lastTsdt", "lastTedt", "nowTsdt"].contains($0.key) { return }
                fields[$0.key] = $0.value
            }
            records[row.id] = PublicCharger(fields: fields)
        }
        return records.values.sorted { $0.id < $1.id }
    }
    static func sites(_ rows: [PublicCharger], fetchedAt: Date, now: Date = Date()) -> [NearbyChargingSite] {
        let active = merge([], rows).filter { $0.value("delYn") != "Y" }
        let groups = Dictionary(grouping: active, by: { $0.value("statId") })
        let fresh = now.timeIntervalSince(fetchedAt) >= -5 && now.timeIntervalSince(fetchedAt) <= 600
        return groups.keys.sorted().compactMap { id in
            guard let rows = groups[id], let first = rows.first(where: { row in
                guard let lat = Double(row.value("lat")), let lon = Double(row.value("lng")) else { return false }
                return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) && !(lat == 0 && lon == 0)
            }), let lat = Double(first.value("lat")), let lon = Double(first.value("lng")) else { return nil }
            let kinds = Array(Set(rows.map(\.category))).sorted()
            let known = rows.filter { ["2", "3", "4", "5", "6"].contains($0.value("stat")) }
            let available = rows.filter { $0.value("stat") == "2" && $0.value("limitYn") != "Y" }.count
            let detail = kinds.map { kind in
                let group = rows.filter { $0.category == kind }
                let count = group.filter { $0.value("stat") == "2" && $0.value("limitYn") != "Y" }.count
                let allKnown = group.allSatisfy { ["2", "3", "4", "5", "6"].contains($0.value("stat")) }
                return fresh && allKnown ? "\(kind) \(count)/\(group.count)대" : "\(kind) \(group.count)대"
            }.joined(separator: " · ")
            let restrictions = Set(rows.filter { $0.value("limitYn") == "Y" }.map { $0.value("limitDetail").isEmpty ? "이용 제한" : $0.value("limitDetail") })
            var site = NearbyChargingSite(id: "keco:" + id, name: first.value("statNm"), latitude: lat, longitude: lon,
                kind: kinds.joined(separator: "·"), available: fresh && known.count == rows.count ? available : nil, total: rows.count,
                powerKW: rows.compactMap { Double($0.value("output")) }.filter { $0.isFinite && $0 > 0 }.max())
            site.address = first.value("addr"); site.source = "한국환경공단"; site.fetchedAt = fetchedAt
            site.providerID = first.value("busiId")
            site.chargingDetail = detail + (known.count < rows.count ? " · 상태 확인 필요 \(rows.count - known.count)대" : "")
            if fresh {
                for kind in kinds {
                    let group = rows.filter { $0.category == kind }
                    if group.allSatisfy({ ["2", "3", "4", "5", "6"].contains($0.value("stat")) }) {
                        site.categoryAvailability[kind] = "\(group.filter { $0.value("stat") == "2" && $0.value("limitYn") != "Y" }.count)/\(group.count)"
                    }
                }
            }
            site.restriction = restrictions.sorted().joined(separator: " · ")
            return site
        }
    }
}
