import Foundation

/// Main-thread submission; one running snapshot and one replaceable latest snapshot only.
final class LatestTelemetryIndexWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "YLCompanion.displayIndex", qos: .userInitiated)
    private let build: @Sendable ([FleetTelemetryReading]) -> FleetTelemetryDisplayIndex
    private var running = false
    private var pending: ([FleetTelemetryReading], (FleetTelemetryDisplayIndex) -> Void)?
    private(set) var buildCount = 0
    private(set) var replacedPendingCount = 0
    init(build: @escaping @Sendable ([FleetTelemetryReading]) -> FleetTelemetryDisplayIndex = { FleetTelemetryDisplayIndex($0) }) { self.build = build }
    func submit(_ records: [FleetTelemetryReading], completion: @escaping (FleetTelemetryDisplayIndex) -> Void) {
        precondition(Thread.isMainThread)
        if running {
            if pending != nil { replacedPendingCount += 1 }
            pending = (records, completion); return
        }
        run(records, completion: completion)
    }
    private func run(_ records: [FleetTelemetryReading], completion: @escaping (FleetTelemetryDisplayIndex) -> Void) {
        running = true; buildCount += 1
        queue.async { [self] in
            let index = build(records)
            DispatchQueue.main.async { [self] in
                running = false
                if let next = pending {
                    pending = nil; run(next.0, completion: next.1)
                } else { completion(index) }
            }
        }
    }
}
import CoreFoundation

/// The wire value and timestamp are retained; invalid values explicitly supersede earlier data.
struct FleetTelemetryReading: Codable, Identifiable, Sendable {
    let vin: String
    let field: String
    let at: Date
    let number: Double?
    let text: String
    let invalid: Bool
    var origin: String? = nil
    var id: String { vin + ":" + field + ":" + String(at.timeIntervalSince1970) }
}

/// Immutable display lookup, rebuilt only when archive records change. It does not provide
/// command evidence. Source timestamps stay intact; freshness is evaluated at lookup time.
struct FleetTelemetryDisplayIndex: Sendable {
    struct Coordinate: Sendable { let latitude: Double; let longitude: Double }
    struct Location: Sendable {
        let reading: FleetTelemetryReading
        let coordinate: Coordinate?
    }
    private let fieldsByVIN: [String: [String: FleetTelemetryReading]]
    private let locationsByVIN: [String: [Location]]
    private let validLocationsByVIN: [String: [Location]]
    private let chargeCountersByVIN: [String: [String: [FleetTelemetryReading]]]
    let sourceRecordCount: Int
    let locationDecodeCount: Int

    init(_ records: [FleetTelemetryReading]) {
        var fields: [String: [String: FleetTelemetryReading]] = [:]
        var locations: [String: [Date: Location]] = [:]
        var validLocations: [String: [Date: Location]] = [:]
        var decoded = 0
        var counters: [String: [String: [FleetTelemetryReading]]] = [:]
        for reading in records {
            if ["ACChargingEnergyIn", "DCChargingEnergyIn"].contains(reading.field), !reading.invalid,
               let value = reading.number, value.isFinite, value >= 0 {
                counters[reading.vin, default: [:]][reading.field, default: []].append(reading)
            }
            let previous = fields[reading.vin]?[reading.field]
            if previous == nil || previous!.at <= reading.at {
                fields[reading.vin, default: [:]][reading.field] = reading
            }
            guard reading.field == "Location" else { continue }
            let coordinate: Coordinate?
            if !reading.invalid {
                decoded += 1
                coordinate = FleetTelemetryData.coordinate(reading).map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
            } else { coordinate = nil }
            let location = Location(reading: reading, coordinate: coordinate)
            // max(by: <) in the original location selection retains the first equal-date
            // event. Latest field selection above deliberately retains the last instead.
            if locations[reading.vin]?[reading.at] == nil { locations[reading.vin, default: [:]][reading.at] = location }
            if coordinate != nil, validLocations[reading.vin]?[reading.at] == nil {
                validLocations[reading.vin, default: [:]][reading.at] = location
            }
        }
        fieldsByVIN = fields
        locationsByVIN = locations.mapValues { $0.values.sorted { $0.reading.at < $1.reading.at } }
        validLocationsByVIN = validLocations.mapValues { $0.values.sorted { $0.reading.at < $1.reading.at } }
        chargeCountersByVIN = counters.mapValues { $0.mapValues { $0.sorted { $0.at > $1.at } } }
        sourceRecordCount = records.count; locationDecodeCount = decoded
    }
    func latest(vin: String) -> [String: FleetTelemetryReading] { fieldsByVIN[vin] ?? [:] }
    func counterPair(vin: String, field: String, since: Date, through: Date) -> (FleetTelemetryReading, FleetTelemetryReading)? {
        guard let rows = chargeCountersByVIN[vin]?[field], !rows.isEmpty else { return nil }
        func first(before date: Date, strict: Bool) -> Int {
            var low = 0, high = rows.count
            while low < high {
                let middle = (low + high) / 2
                if strict ? rows[middle].at >= date : rows[middle].at > date { low = middle + 1 } else { high = middle }
            }
            return low
        }
        let latest = first(before: through, strict: false)
        guard latest < rows.count, rows[latest].at >= since else { return nil }
        let previous = first(before: rows[latest].at, strict: true)
        guard previous < rows.count, rows[previous].at >= since else { return nil }
        return (rows[latest], rows[previous])
    }
    func locations(vin: String, now: Date) -> (valid: Location?, last: Location?) {
        let ceiling = now.addingTimeInterval(5)
        func lastEligible(_ locations: [Location]) -> Location? {
            var low = 0, high = locations.count
            while low < high {
                let middle = low + (high - low) / 2
                if locations[middle].reading.at <= ceiling { low = middle + 1 } else { high = middle }
            }
            return low > 0 ? locations[low - 1] : nil
        }
        return (lastEligible(validLocationsByVIN[vin] ?? []), lastEligible(locationsByVIN[vin] ?? []))
    }
}

enum FleetTelemetryData {
    /// A displayed/cached gear is a historical observation, never a new live packet.
    static func mainMotionPayload(_ drive: [String: Any], vin: String, now: Date = Date()) -> Data? {
        guard !vin.isEmpty, let gear = drive["gear"] as? String, ["P", "D", "R", "N"].contains(gear),
              let at = drive["at"] as? Double, at.isFinite, at > 0, at <= now.timeIntervalSince1970 * 1000 + 5000 else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let packet: [String: Any] = ["vin": vin, "origin": "appMain", "createdAt": formatter.string(from: Date(timeIntervalSince1970: at / 1000)),
            "data": [["key": "Gear", "value": ["stringValue": gear]]]]
        return try? JSONSerialization.data(withJSONObject: packet)
    }
    /// Rebuild only sessions affected by new/late data, with previous field values as context.
    static func historyWindow(_ records: [FleetTelemetryReading], vin: String, since: Date) -> (rows: [FleetTelemetryReading], start: Date) {
        let ordered = records.filter { $0.vin == vin }.sorted { $0.at < $1.at }
        var chargeStart: Date?, driveStart: Date?, recentChargeStart: Date?, chargeEnd: Date?
        var recentDriveStart: Date?, driveEnd: Date?, parkingStart: Date?, recentParkingStart: Date?, parkingEnd: Date?
        var chargeState = "", gear = ""
        for row in ordered where row.at < since && !row.invalid {
            if ["ChargeState", "DetailedChargeState"].contains(row.field), let raw = firstStringValue(row) {
                let state = raw.replacingOccurrences(of: "DetailedChargeState", with: "")
                guard ["Charging", "Starting", "Complete", "Stopped", "Disconnected", "NoPower"].contains(state) else { continue }
                if state == "Charging", chargeState != "Charging" { chargeStart = row.at }
                if ["Complete", "Stopped", "Disconnected"].contains(state), chargeStart != nil {
                    recentChargeStart = chargeStart; chargeEnd = row.at; chargeStart = nil
                }
                chargeState = state
            }
            if row.field == "Gear", let raw = firstStringValue(row) {
                let state = raw.replacingOccurrences(of: "ShiftState", with: "")
                if state == "P", gear != "P" { parkingStart = row.at }
                if ["D", "R", "N"].contains(state), let parked = parkingStart {
                    recentParkingStart = parked; parkingEnd = row.at; parkingStart = nil
                }
                if ["D", "R", "N"].contains(state), !["D", "R", "N"].contains(gear) { driveStart = row.at }
                if state == "P", let started = driveStart { recentDriveStart = started; driveEnd = row.at; driveStart = nil }
                gear = state
            }
        }
        var start = min(since, chargeStart ?? since, driveStart ?? since, parkingStart ?? since)
        if let end = parkingEnd, since.timeIntervalSince(end) <= 120, let previous = recentParkingStart { start = min(start, previous) }
        if let end = chargeEnd, since.timeIntervalSince(end) <= 120, let previous = recentChargeStart { start = min(start, previous) }
        if let end = driveEnd, since.timeIntervalSince(end) <= 120, let previous = recentDriveStart { start = min(start, previous) }
        var seed: [String: FleetTelemetryReading] = [:]
        for row in ordered where row.at < start { seed[row.field] = row }
        return (Array(seed.values) + ordered.filter { $0.at >= start }, start)
    }
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
                result.append(FleetTelemetryReading(vin: vin, field: field, at: at, number: number, text: text, invalid: invalid,
                    origin: payload["origin"] as? String == "appMain" ? "appMain" : nil))
                guard result.count <= 50000 else { throw failure("필드 수가 너무 많습니다. 기간을 나누어 가져와 주세요.") }
            }
        }
        guard !result.isEmpty else { throw failure("가져올 측정값이 없습니다.") }
        return result
    }
    static func merge(_ existing: [FleetTelemetryReading], _ incoming: [FleetTelemetryReading], limit: Int = 50000) -> [FleetTelemetryReading] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for reading in incoming { byID[reading.id] = reading }
        let ordered = byID.values.sorted { $0.at == $1.at ? $0.field < $1.field : $0.at < $1.at }
        guard ordered.count > limit, limit > 0 else { return limit > 0 ? ordered : [] }
        // Stable signals (parked coordinates, charge state) may not be emitted again for hours.
        // Retain their actual timestamps instead of letting frequent SOC packets evict them.
        var latestByField: [String: FleetTelemetryReading] = [:]
        for reading in ordered { latestByField[reading.vin + ":" + reading.field] = reading }
        var kept = Dictionary(latestByField.values.sorted { $0.at > $1.at }.prefix(limit).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for reading in ordered.reversed() where kept.count < limit { kept[reading.id] = reading }
        return kept.values.sorted { $0.at == $1.at ? $0.field < $1.field : $0.at < $1.at }
    }
    static func latest(_ records: [FleetTelemetryReading], vin: String) -> [String: FleetTelemetryReading] {
        var result: [String: FleetTelemetryReading] = [:]
        for reading in records where reading.vin == vin {
            if result[reading.field].map({ $0.at <= reading.at }) ?? true { result[reading.field] = reading }
        }
        return result
    }
    static func chargeObservation(_ records: [FleetTelemetryReading], vin: String, now: Date = Date()) -> ChargeObservation? {
        let fields = latest(records, vin: vin)
        guard let state = [fields["DetailedChargeState"], fields["ChargeState"]].compactMap({ $0 }).filter({ !$0.invalid }).max(by: { $0.at < $1.at }),
              now.timeIntervalSince(state.at) >= -5, now.timeIntervalSince(state.at) <= 120,
              let value = firstStringValue(state) else { return nil }
        let name = value.replacingOccurrences(of: "DetailedChargeState", with: "")
        guard ["Disconnected", "NoPower", "Starting", "Charging", "Complete", "Stopped", "Calibrating"].contains(name) else { return nil }
        func number(_ key: String) -> Double? {
            guard let r = fields[key], !r.invalid, now.timeIntervalSince(r.at) <= 120, now.timeIntervalSince(r.at) >= -5 else { return nil }
            return r.number
        }
        return ChargeObservation(vin: vin, at: state.at, state: name, soc: number("Soc") ?? number("BatteryLevel"), limit: number("ChargeLimitSoc"))
    }
    /// Telemetry is change-based: a stable Charging enum is not a polling heartbeat.
    /// Only fresh positive power or a measured energy-counter increase renews an old Charging state.
    static func liveActivityCharge(_ records: [FleetTelemetryReading], vin: String, now: Date = Date()) -> [String: Any]? {
        liveActivityCharge(index: FleetTelemetryDisplayIndex(records), vin: vin, now: now)
    }
    static func liveActivityCharge(index: FleetTelemetryDisplayIndex, vin: String, now: Date = Date()) -> [String: Any]? {
        let fields = index.latest(vin: vin)
        guard let state = [fields["DetailedChargeState"], fields["ChargeState"]].compactMap({ $0 })
            .filter({ !$0.invalid && $0.at <= now.addingTimeInterval(5) }).max(by: { $0.at < $1.at }),
            let raw = firstStringValue(state) else { return nil }
        let status = raw.replacingOccurrences(of: "DetailedChargeState", with: "")
        guard ["Charging", "Stopped", "Complete", "Disconnected", "NoPower", "Starting", "Calibrating"].contains(status) else { return nil }
        func fresh(_ reading: FleetTelemetryReading) -> Bool {
            !reading.invalid && (-5...120).contains(now.timeIntervalSince(reading.at)) && reading.number?.isFinite == true
        }
        var at = state.at
        var row: [String: Any] = ["status": status]
        for (field, key, scale) in [("Soc", "soc", 1.0), ("BatteryLevel", "soc", 1.0),
            ("ChargeLimitSoc", "limit", 1.0), ("TimeToFullCharge", "minutesToLimit", 60.0)] {
            guard let reading = fields[field], !reading.invalid, let number = reading.number, number.isFinite,
                  reading.at <= now.addingTimeInterval(5), key == "limit" || fresh(reading) else { continue }
            if row[key] == nil { row[key] = number * scale }
        }
        if let power = [fields["ACChargingPower"], fields["DCChargingPower"], fields["ChargePower"]]
            .compactMap({ $0 }).filter({ fresh($0) && (0...500).contains($0.number!) }).max(by: { $0.at < $1.at }) {
            row["chargerKW"] = power.number!
            if status == "Charging", power.number! > 0.1 { at = max(at, power.at) }
        }
        if status == "Charging" {
            for field in ["ACChargingEnergyIn", "DCChargingEnergyIn"] {
                guard let (last, before) = index.counterPair(vin: vin, field: field, since: state.at, through: now.addingTimeInterval(5)), fresh(last),
                      last.at.timeIntervalSince(before.at) <= 600,
                      last.number! > before.number! + 0.001 else { continue }
                at = max(at, last.at)
            }
        }
        row["at"] = at.timeIntervalSince1970 * 1000
        row["mode"] = (-5...120).contains(now.timeIntervalSince(at)) ? "recent" : "cached"
        return row
    }
    /// Same +/-120s endpoint evidence as the original nested scan, with bounded date lookup.
    static func chargeSOCReadings(_ records: [FleetTelemetryReading], vin: String, charges: [[String: Any]]) -> [FleetTelemetryReading] {
        func number(_ value: Any?) -> Double? {
            guard let value = (value as? NSNumber)?.doubleValue, value.isFinite else { return nil }; return value
        }
        let endpoints = charges.flatMap { charge -> [Double] in
            guard let end = number(charge["end"]) else { return [] }
            return [number(charge["at"]) ?? 0, end]
        }.sorted()
        guard !endpoints.isEmpty else { return [] }
        return records.filter { reading in
            guard reading.vin == vin, reading.field == "Soc" || reading.field == "BatteryLevel" else { return false }
            let stamp = reading.at.timeIntervalSince1970 * 1000
            guard stamp.isFinite else { return false }
            var low = 0, high = endpoints.count
            while low < high { let middle = (low + high) / 2; if endpoints[middle] < stamp { low = middle + 1 } else { high = middle } }
            return (low < endpoints.count && abs(stamp - endpoints[low]) <= 120000) || (low > 0 && abs(stamp - endpoints[low - 1]) <= 120000)
        }
    }
    static func pairedDifference(_ first: FleetTelemetryReading?, _ second: FleetTelemetryReading?, maximumSkew: TimeInterval = 2) -> Double? {
        guard let first, let second, first.vin == second.vin, !first.invalid, !second.invalid,
              abs(first.at.timeIntervalSince(second.at)) <= maximumSkew,
              let high = first.number, let low = second.number, high >= low else { return nil }
        return high - low
    }
    /// Display-only projection: never supplies evidence for vehicle commands.
    static func homeOverlay(_ records: [FleetTelemetryReading], vin: String, now: Date = Date()) -> [String: Any] {
        homeOverlay(index: FleetTelemetryDisplayIndex(records), vin: vin, now: now)
    }
    /// Reuses decoded location history and latest-field selection without visiting raw records.
    static func homeOverlay(index: FleetTelemetryDisplayIndex, vin: String, now: Date = Date()) -> [String: Any] {
        let latest = index.latest(vin: vin)
        var result: [String: Any] = [:]
        let maps: [(String, [(String, String, Double)])] = [
            // v91: ChargerVoltage and ChargeAmps were ingested and then had no
            // consumer, so the charging card rendered "요청 32 A · — V" forever.
            ("charge", [("Soc", "soc", 1), ("BatteryLevel", "soc", 1), ("RatedRange", "rangeKm", 1.609344), ("ChargeLimitSoc", "limit", 1), ("TimeToFullCharge", "minutesToLimit", 60),
                        ("ChargerVoltage", "chargerVoltage", 1), ("ChargeAmps", "chargerAmps", 1), ("ACChargingPower", "chargerKW", 1), ("DCChargingPower", "chargerKW", 1), ("ChargePower", "chargerKW", 1)]),
            ("climate", [("InsideTemp", "insideC", 1), ("OutsideTemp", "outsideC", 1)])
        ]
        for (group, fields) in maps {
            var values: [String: Any] = [:]
            var fieldAt: [String: Double] = [:]
            for (field, key, scale) in fields {
                guard let r = latest[field], !r.invalid, let n = r.number,
                      now.timeIntervalSince(r.at) >= -5 else { continue }
                if ["minutesToLimit", "chargerKW", "chargerVoltage", "chargerAmps"].contains(key), now.timeIntervalSince(r.at) > 120 { continue }
                guard n.isFinite, fieldAt[key].map({ r.at.timeIntervalSince1970 * 1000 > $0 }) ?? true else { continue }
                values[key] = n * scale; fieldAt[key] = r.at.timeIntervalSince1970 * 1000
            }
            if group == "charge", let r = latest["DetailedChargeState"], !r.invalid,
               now.timeIntervalSince(r.at) >= -5,
               let data = r.text.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let state = raw["detailedChargeStateValue"] as? String {
                values["charging"] = state == "DetailedChargeStateCharging"
                values["isCharging"] = state == "DetailedChargeStateCharging"
                fieldAt["charging"] = r.at.timeIntervalSince1970 * 1000
                fieldAt["isCharging"] = r.at.timeIntervalSince1970 * 1000
            }
            let nowMS = now.timeIntervalSince1970 * 1000
            if group == "charge", fieldAt.contains(where: { $0.key != "limit" && nowMS - $0.value <= 120000 }) {
                for (key, at) in Array(fieldAt) where key != "limit" && nowMS - at > 120000 { values.removeValue(forKey: key); fieldAt.removeValue(forKey: key) }
            }
            let measured = fieldAt.filter { $0.key != "limit" }.map(\.value)
            if let at = group == "charge" ? measured.max() ?? fieldAt.values.max() : fieldAt.values.min() {
                values["at"] = at
                values["fieldAt"] = fieldAt
                values["mode"] = nowMS - at <= 120000 ? "recent" : "cached"
                values["label"] = nowMS - at <= 120000 ? "NAS 차량 수신" : "NAS 마지막 측정"
                result[group] = values
            }
        }

        // v91: Location arrives as a nested object, so the generic decoder leaves
        // `number` nil and keeps only the text — and nothing ever looked it up.
        // That is why the NAS could know exactly where the car parked while the
        // app said 위치 미수신. A parked car's fix is old by definition, so age
        // marks it cached rather than discarding it.
        let locations = index.locations(vin: vin, now: now)
        if let location = locations.valid, let point = location.coordinate {
            let r = location.reading
            let stamp = r.at.timeIntervalSince1970 * 1000
            let unavailable = locations.last.map { $0.reading.at >= r.at && ($0.reading.invalid || $0.coordinate == nil) } ?? false
            let fresh = now.timeIntervalSince(r.at) <= 120 && !unavailable
            result["location"] = [
                "latitude": point.latitude, "longitude": point.longitude, "hasCoordinates": true,
                "gpsAt": stamp, "at": stamp, "positionStatus": unavailable ? "gpsUnavailable" : "available",
                "mode": fresh ? "recent" : "cached",
                "label": fresh ? "NAS 차량 수신" : "NAS 마지막 측정",
                "subtitle": fresh ? "NAS 차량 수신 · 좌표 확인" : "NAS 마지막 측정 · 좌표 확인"
            ]
        }

        // The gear and speed behind 주차 중 / 정차 중 / 주행 중. The wording itself
        // stays in home.js; this only supplies the raw values it reads.
        var drive: [String: Any] = [:]
        var driveStamps: [Date] = []
        if let r = latest["Gear"], !r.invalid, now.timeIntervalSince(r.at) >= -5,
           let raw = firstStringValue(r)?.replacingOccurrences(of: "ShiftState", with: ""),
           ["P", "D", "R", "N"].contains(raw) {
            drive["gear"] = raw; driveStamps.append(r.at)
        }
        for (field, key) in [("VehicleSpeed", "speedKmh"), ("Odometer", "odometerKm")] {
            guard let r = latest[field], !r.invalid, let n = r.number, n >= 0,
                  now.timeIntervalSince(r.at) >= -5 else { continue }
            drive[key] = n * 1.609344; driveStamps.append(r.at)
        }
        if let oldest = driveStamps.min() {
            drive["at"] = oldest.timeIntervalSince1970 * 1000
            let fresh = now.timeIntervalSince(oldest) <= 120
            drive["mode"] = fresh ? "recent" : "cached"
            drive["label"] = fresh ? "NAS 차량 수신" : "NAS 마지막 측정"
            result["drive"] = drive
        }
        return result
    }

    /// Tesla sends Location as {"locationValue":{"latitude":…,"longitude":…}}.
    /// Nothing else in the payload is a coordinate pair, so a reading that does
    /// not carry both finite values in range is simply not a position.
    static func coordinate(_ reading: FleetTelemetryReading) -> (latitude: Double, longitude: Double)? {
        guard let data = reading.text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let point = raw["locationValue"] as? [String: Any] else { return nil }
        func value(_ keys: [String]) -> Double? {
            for key in keys {
                if let n = point[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return n.doubleValue }
                if let text = point[key] as? String, let parsed = Double(text), parsed.isFinite { return parsed }
            }
            return nil
        }
        guard let lat = value(["latitude", "lat"]), let lon = value(["longitude", "lon", "lng"]),
              (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) else { return nil }
        return (lat, lon)
    }

    /// The enum wrapper key differs per field (shiftStateValue, stringValue, …),
    /// so take the payload's single string value rather than guessing its name.
    static func firstStringValue(_ reading: FleetTelemetryReading) -> String? {
        guard let data = reading.text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for (key, value) in raw where key != "invalid" {
            if let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }
    static func mergeDisplay(_ existing: [String: Any], _ incoming: [String: Any]) -> [String: Any] {
        guard let stamps = incoming["fieldAt"] as? [String: Double] else {
            guard existing["mode"] as? String == "missing" || (incoming["at"] as? Double ?? 0) > (existing["at"] as? Double ?? 0) else { return existing }
            return existing.merging(incoming) { _, value in value }
        }
        var result = existing, kept = existing["fieldAt"] as? [String: Double] ?? [:]
        var changed = false, measurementChanged = false
        if let newest = stamps.filter({ $0.key != "limit" }).map(\.value).max() {
            for key in ["soc", "rangeKm", "minutesToLimit", "chargerKW", "chargerVoltage", "chargerAmps", "charging", "isCharging", "status", "addedKWh"] {
                let at = kept[key] ?? (existing["at"] as? Double ?? 0)
                if newest - at > 120000 { result.removeValue(forKey: key); kept.removeValue(forKey: key) }
            }
        }
        for (key, at) in stamps where incoming[key] != nil {
            let oldAt = kept[key] ?? (existing["at"] as? Double ?? 0)
            if existing[key] == nil || at > oldAt {
                result[key] = incoming[key]; kept[key] = at; changed = true
                if key != "limit" { measurementChanged = true }
            }
        }
        if changed {
            result["fieldAt"] = kept
            if measurementChanged, (incoming["at"] as? Double ?? 0) >= (existing["at"] as? Double ?? 0) {
                for key in ["at", "mode", "label"] { result[key] = incoming[key] }
            }
        }
        return result
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "FleetTelemetry", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
