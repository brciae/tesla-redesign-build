import Foundation
@main struct PerformanceRegressionTests {
    static func canonical(_ value: [String: Any]?) throws -> Data { try JSONSerialization.data(withJSONObject: value ?? [:], options: [.sortedKeys]) }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1793430000), vin = "TEST";
        func row(_ field: String, _ seconds: Double, _ n: Double? = nil, _ text: String = "", invalid: Bool = false, vehicle: String = "TEST") -> FleetTelemetryReading { .init(vin: vehicle, field: field, at: now.addingTimeInterval(seconds), number: n, text: text, invalid: invalid) }
        var cases: [[FleetTelemetryReading]] = [[]]
        for status in ["Charging", "Stopped", "Disconnected", "Unknown"] {
            let base = [row("DetailedChargeState", -300, nil, "{\"stringValue\":\"DetailedChargeState" + status + "\"}"), row("Soc", -5, 60), row("ChargeLimitSoc", -1000, 80)]
            for age in [-10.0, 0, 5, 6, 200] {
                for delta in [0.0, 2.0] {
                    cases.append(base + [row("ACChargingEnergyIn", -60, 10), row("ACChargingEnergyIn", age, 10 + delta), row("DCChargingEnergyIn", -100, 20), row("DCChargingEnergyIn", -20, 20 + delta), row("ACChargingEnergyIn", age, 999, invalid: true), row("Soc", -2, 99, vehicle: "OTHER")])
                }
            }
        }
        for rows in cases { for selected in [vin, "OTHER", "MISSING"] {
            let actual = FleetTelemetryData.liveActivityCharge(index: FleetTelemetryDisplayIndex(rows), vin: selected, now: now)
            let result = try canonical(actual), original = try canonical(legacyLiveActivityCharge(rows, vin: selected, now: now))
            assert(result == original)
        } }
        let charges: [[String: Any]] = (0..<300).map { i -> [String: Any] in
            let start = now.timeIntervalSince1970 * 1000 - Double(i + 1000) * 3600000
            return ["at": start, "end": start + 1800000]
        }
        let records: [FleetTelemetryReading] = (0..<50000).map { i -> FleetTelemetryReading in
            let field: String = i % 3 == 0 ? "Soc" : (i % 3 == 1 ? "BatteryLevel" : "Gear")
            return row(field, -Double(i), Double(i % 100), invalid: i % 13 == 0)
        }
        let start = Date(); let expected = legacySOC(records, vin: vin, charges: charges); let oldTime = Date().timeIntervalSince(start)
        let next = Date(); let actual = FleetTelemetryData.chargeSOCReadings(records, vin: vin, charges: charges); let newTime = Date().timeIntervalSince(next)
        assert(expected.map(\.id) == actual.map(\.id))
        for stamp in [0.0, -120001, -120000, 120000, 120001, 500000] {
            let special = [row("Soc", stamp / 1000, 50), row("BatteryLevel", stamp / 1000, 60, invalid: true), row("Soc", stamp / 1000, 70, vehicle: "OTHER")]
            for endpoints in [[], [["end": now.timeIntervalSince1970 * 1000]], [["at": now.timeIntervalSince1970 * 1000, "end": now.timeIntervalSince1970 * 1000 + 1000000]]] as [[[String: Any]]] {
                assert(legacySOC(special, vin: vin, charges: endpoints).map(\.id) == FleetTelemetryData.chargeSOCReadings(special, vin: vin, charges: endpoints).map(\.id))
            }
        }
        let worker = LatestTelemetryIndexWorker { rows in Thread.sleep(forTimeInterval: 0.04); return FleetTelemetryDisplayIndex(rows) }
        var received = -1, callbacks = 0
        for count in 1...100 { worker.submit(Array(records.prefix(count))) { index in received = index.sourceRecordCount; callbacks += 1 } }
        let deadline = Date().addingTimeInterval(3)
        while received != 100 && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
        assert(received == 100 && callbacks == 1 && worker.buildCount == 2 && worker.replacedPendingCount == 98)
        let recorder = AppPerformanceRecorder(); recorder.setGraphicsSuspended(true)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in recorder.record("parallel", seconds: 0.001, main: false) }
        for _ in 0..<200 { recorder.record("slow", seconds: 0.1, main: true) }
        let snapshot = recorder.snapshot(), events = snapshot["slowEvents"] as! [[String: Any]], operations = snapshot["operations"] as! [[String: Any]]
        assert(events.count == 120 && events.allSatisfy { $0["suspended3D"] as? Bool == true })
        assert(operations.first { $0["name"] as? String == "parallel" }?["count"] as? Int == 1000)
        let serialized = try JSONSerialization.data(withJSONObject: snapshot)
        assert(serialized.count < 100000)
        recorder.setGraphicsSuspended(false); recorder.record("slow", seconds: 0.2, main: true)
        let modes = (recorder.snapshot()["operations"] as! [[String: Any]]).filter { $0["name"] as? String == "slow" }
        assert(modes.count == 2)
        assert(modes.first { $0["suspended3D"] as? Bool == true }?["maximumMilliseconds"] as? Double == 100)
        assert(modes.first { $0["suspended3D"] as? Bool == false }?["maximumMilliseconds"] as? Double == 200)
        let executing = recorder.begin("unfinished")
        assert((recorder.snapshot()["executing"] as! [[String: Any]]).count == 1)
        recorder.end(executing)
        assert((recorder.snapshot()["executing"] as! [[String: Any]]).isEmpty)
        for i in 0..<100 { recorder.record("bounded\(i)", seconds: 0.001, main: false) }
        assert((recorder.snapshot()["operations"] as! [[String: Any]]).count <= 160)
        print("PASS: \(cases.count * 3) exact live-activity comparisons; SOC endpoint evidence boundaries/invalid/VIN/order; coalesced100 snapshots ->2 builds/1 latest publication; bounded thread-safe diagnostics")
        print(String(format: "PERF synthetic 50k records/300 charges SOC selection: legacy %.6fs indexed %.6fs", oldTime, newTime))
    }
    static func legacySOC(_ records: [FleetTelemetryReading], vin: String, charges: [[String: Any]]) -> [FleetTelemetryReading] {
        func number(_ v: Any?) -> Double? { guard let x = (v as? NSNumber)?.doubleValue, x.isFinite else { return nil }; return x }
        let intervals = charges.filter { number($0["end"]) != nil }
        return records.filter { r in r.vin == vin && ["Soc", "BatteryLevel"].contains(r.field) && intervals.contains { c in let stamp = r.at.timeIntervalSince1970 * 1000; return abs(stamp - (number(c["at"]) ?? 0)) <= 120000 || abs(stamp - (number(c["end"]) ?? 0)) <= 120000 } }
    }
    static func legacyLiveActivityCharge(_ records: [FleetTelemetryReading], vin: String, now: Date = Date()) -> [String: Any]? {
        let fields = FleetTelemetryData.latest(records, vin: vin)
        guard let state = [fields["DetailedChargeState"], fields["ChargeState"]].compactMap({ $0 })
            .filter({ !$0.invalid && $0.at <= now.addingTimeInterval(5) }).max(by: { $0.at < $1.at }),
            let raw = FleetTelemetryData.firstStringValue(state) else { return nil }
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
                let counters = records.filter { $0.vin == vin && $0.field == field && !$0.invalid &&
                    $0.at >= state.at && $0.at <= now.addingTimeInterval(5) &&
                    $0.number.map { $0.isFinite && $0 >= 0 } == true }.sorted { $0.at > $1.at }
                guard let last = counters.first, fresh(last),
                      let before = counters.dropFirst().first(where: { $0.at < last.at }),
                      last.at.timeIntervalSince(before.at) <= 600,
                      last.number! > before.number! + 0.001 else { continue }
                at = max(at, last.at)
            }
        }
        row["at"] = at.timeIntervalSince1970 * 1000
        row["mode"] = (-5...120).contains(now.timeIntervalSince(at)) ? "recent" : "cached"
        return row
    }
}
