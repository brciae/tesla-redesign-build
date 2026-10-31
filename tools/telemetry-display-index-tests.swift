import Foundation

/// Differential oracle is frozen from Build178 before adding the index.
@main struct TelemetryDisplayIndexTests {
    static func canonical(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func row(_ vin: String = "A", _ field: String, _ seconds: Double,
                 _ number: Double? = nil, _ text: String = "", invalid: Bool = false) -> FleetTelemetryReading {
            .init(vin: vin, field: field, at: now.addingTimeInterval(seconds), number: number, text: text, invalid: invalid)
        }
        let good = "{\"locationValue\":{\"latitude\":37.5,\"longitude\":127.1}}"
        let other = "{\"locationValue\":{\"latitude\":35.1,\"longitude\":129.1}}"
        let gear = "{\"stringValue\":\"P\"}"
        let charging = "{\"detailedChargeStateValue\":\"DetailedChargeStateCharging\"}"
        let cases: [[FleetTelemetryReading]] = [
            [],
            [row("A", "Soc", -10, 60), row("B", "Soc", -10, 20), row("A", "Gear", -10, nil, gear)],
            [row("A", "Location", -30, nil, good), row("A", "Location", -10, nil, "", invalid: true)],
            [row("A", "Location", -30, nil, good), row("A", "Location", -10, nil, "{\"locationValue\":{\"latitude\":0,\"longitude\":0}}")],
            [row("A", "Location", -30, nil, good), row("A", "Location", 100, nil, other), row("A", "Soc", -5, 60), row("A", "Soc", 100, 90)],
            [row("A", "Location", 0, nil, "", invalid: true), row("A", "Location", 0, nil, good), row("A", "Location", 0, nil, other)],
            [row("A", "Location", 0, nil, good), row("A", "Location", 0, nil, "", invalid: true)],
            [row("A", "Soc", 0, 60), row("A", "Soc", 0, nil, invalid: true), row("A", "Gear", 0, nil, gear)],
            [row("A", "DetailedChargeState", -100, nil, charging), row("A", "Soc", -100, 60), row("A", "ACChargingPower", -130, 7), row("A", "ChargeLimitSoc", -1000, 80), row("A", "InsideTemp", -200, 20), row("A", "OutsideTemp", 0, 10)]
        ]
        let offsets: [Double] = [-150, -5.001, -5, 0, 115, 120, 120.001, 121, 200]
        var comparisons = 0
        for rows in cases {
            let index = FleetTelemetryDisplayIndex(rows)
            let decodes = index.locationDecodeCount
            for vin in ["A", "B", "ABSENT", ""] {
                let oldLatest = FleetTelemetryData.latest(rows, vin: vin)
                let indexedLatest = index.latest(vin: vin)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let oldLatestData = try encoder.encode(oldLatest), indexedLatestData = try encoder.encode(indexedLatest)
                precondition(oldLatestData == indexedLatestData, "Latest fields must retain equal-time last event, invalid and future values")
                for offset in offsets {
                    let time = now.addingTimeInterval(offset)
                    let expected = try canonical(legacyHomeOverlay(rows, vin: vin, now: time))
                    let actual = try canonical(FleetTelemetryData.homeOverlay(index: index, vin: vin, now: time))
                    precondition(actual == expected, "Indexed display changed Build178 semantics for \(vin) at \(offset)")
                    comparisons += 1
                }
            }
            precondition(index.locationDecodeCount == decodes, "Display queries must not decode raw locations again")
        }
        let invalidIndex = FleetTelemetryDisplayIndex(cases[2])
        let invalidLocation = FleetTelemetryData.homeOverlay(index: invalidIndex, vin: "A", now: now)["location"] as! [String: Any]
        precondition(invalidLocation["latitude"] as? Double == 37.5 && invalidLocation["mode"] as? String == "cached" && invalidLocation["positionStatus"] as? String == "gpsUnavailable", "Keep last valid location but disclose newer invalid evidence")
        let futureIndex = FleetTelemetryDisplayIndex(cases[4])
        precondition(FleetTelemetryData.homeOverlay(index: futureIndex, vin: "A", now: now)["charge"] == nil, "Future latest SOC must not silently fall back to an older value")
        let futureLocation = FleetTelemetryData.homeOverlay(index: futureIndex, vin: "A", now: now)["location"] as! [String: Any]
        precondition(futureLocation["latitude"] as? Double == 37.5, "Future location must not hide eligible past coordinate")
        precondition((FleetTelemetryData.homeOverlay(index: futureIndex, vin: "A", now: now.addingTimeInterval(96))["location"] as! [String: Any])["latitude"] as? Double == 35.1, "Time eligibility must advance without rebuilding the index")
        var large: [FleetTelemetryReading] = []
        large.reserveCapacity(50_000)
        for i in 0..<50_000 {
            let vin = i % 3 == 0 ? "B" : "A", offset = Double(i - 49_990) / 2
            switch i % 10 {
            case 0: large.append(row(vin, "Location", offset, nil, i % 100 == 0 ? "" : good, invalid: i % 100 == 0))
            case 1: large.append(row(vin, "Soc", offset, Double(i % 100)))
            case 2: large.append(row(vin, "Odometer", offset, Double(i)))
            case 3: large.append(row(vin, "Gear", offset, nil, gear))
            case 4: large.append(row(vin, "InsideTemp", offset, 20))
            case 5: large.append(row(vin, "ACChargingPower", offset, 7))
            case 6: large.append(row(vin, "DetailedChargeState", offset, nil, charging))
            default: large.append(row(vin, "Other\(i % 13)", offset, Double(i)))
            }
        }
        let buildStart = Date.timeIntervalSinceReferenceDate
        let index = FleetTelemetryDisplayIndex(large)
        let buildSeconds = Date.timeIntervalSinceReferenceDate - buildStart
        precondition(index.sourceRecordCount == 50_000 && index.locationDecodeCount == 4_500)
        for vin in ["A", "B", "ABSENT"] {
            for offset in [-100.0, 0, 121, 1000] {
                let time = now.addingTimeInterval(offset)
                let expected = try canonical(legacyHomeOverlay(large, vin: vin, now: time))
                let actual = try canonical(FleetTelemetryData.homeOverlay(index: index, vin: vin, now: time))
                precondition(expected == actual, "50k differential result differs")
                comparisons += 1
            }
        }
        let repetitions = 20
        var checksum = 0
        let oldStart = Date.timeIntervalSinceReferenceDate
        for _ in 0..<repetitions { checksum += legacyHomeOverlay(large, vin: "A", now: now).count }
        let oldSeconds = Date.timeIntervalSinceReferenceDate - oldStart
        let indexedStart = Date.timeIntervalSinceReferenceDate
        for _ in 0..<repetitions { checksum += FleetTelemetryData.homeOverlay(index: index, vin: "A", now: now).count }
        let indexedSeconds = Date.timeIntervalSinceReferenceDate - indexedStart
        precondition(checksum > 0 && index.locationDecodeCount == 4_500)
        print("PASS: \(comparisons) exact differential overlays; immutable 50k index; VIN/invalid/equal-time/future/freshness preserved")
        print(String(format: "PERF synthetic 50000 records: build %.6fs; legacy %d lookups %.6fs; indexed %d lookups %.6fs; decode count stays %d", buildSeconds, repetitions, oldSeconds, repetitions, indexedSeconds, index.locationDecodeCount))
    }

    static func legacyHomeOverlay(_ records: [FleetTelemetryReading], vin: String, now: Date = Date()) -> [String: Any] {
        let latest = FleetTelemetryData.latest(records, vin: vin)
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
        if let r = records.filter({ $0.vin == vin && $0.field == "Location" && !$0.invalid && now.timeIntervalSince($0.at) >= -5 && FleetTelemetryData.coordinate($0) != nil }).max(by: { $0.at < $1.at }),
           let point = FleetTelemetryData.coordinate(r) {
            let stamp = r.at.timeIntervalSince1970 * 1000
            let lastLocation = records.filter { $0.vin == vin && $0.field == "Location" && now.timeIntervalSince($0.at) >= -5 }.max { $0.at < $1.at }
            let unavailable = lastLocation.map { $0.at >= r.at && ($0.invalid || FleetTelemetryData.coordinate($0) == nil) } ?? false
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
           let raw = FleetTelemetryData.firstStringValue(r)?.replacingOccurrences(of: "ShiftState", with: ""),
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

}

