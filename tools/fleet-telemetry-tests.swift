import Foundation

@main struct FleetTelemetryTests {
    static func main() throws {
        let anchor = Date(timeIntervalSince1970: 1_790_000_000)
        func reading(_ seconds: Double, _ field: String, _ value: String) -> FleetTelemetryReading {
            FleetTelemetryReading(vin: "WINDOW", field: field, at: anchor.addingTimeInterval(seconds), number: nil, text: "{\"stringValue\":\"\(value)\"}", invalid: false)
        }
        let oldWindow = [reading(0, "ChargeState", "Charging"), reading(60, "Soc", "40"), reading(120, "ChargeState", "Complete"), reading(130, "Soc", "80")]
        let currentWindow = [reading(10000, "ChargeState", "Charging"), reading(10060, "Soc", "50"), reading(10120, "ChargeState", "Complete")]
        let window = FleetTelemetryData.historyWindow(oldWindow + currentWindow, vin: "WINDOW", since: anchor.addingTimeInterval(10060))
        precondition(window.start == anchor.addingTimeInterval(10000), "Continue current session from its start")
        precondition(!window.rows.contains(where: { $0.at == anchor.addingTimeInterval(60) }), "Do not replay unrelated historical samples")
        let delayed = FleetTelemetryData.historyWindow(oldWindow + currentWindow, vin: "WINDOW", since: anchor.addingTimeInterval(10130))
        precondition(delayed.start == anchor.addingTimeInterval(10000), "A late final counter needs the completed session context")
        let lateOld = FleetTelemetryData.historyWindow(oldWindow + currentWindow, vin: "WINDOW", since: anchor.addingTimeInterval(90))
        precondition(lateOld.start == anchor, "Late data is selected by source time, not only newest timestamp")
        precondition(FleetTelemetryData.historyWindow(oldWindow, vin: "OTHER", since: anchor).rows.isEmpty)
        let displayNow = Date(timeIntervalSince1970: 1_800_000_000)
        let displayRecords = [FleetTelemetryReading(vin: "DISPLAY", field: "Soc", at: displayNow, number: 31, text: "", invalid: false), FleetTelemetryReading(vin: "OTHER", field: "Soc", at: displayNow, number: 90, text: "", invalid: false)]
        let display = FleetTelemetryData.homeOverlay(displayRecords, vin: "DISPLAY", now: displayNow)
        precondition((display["charge"] as? [String: Any])?["soc"] as? Double == 31)
        precondition((FleetTelemetryData.homeOverlay(displayRecords, vin: "DISPLAY", now: displayNow.addingTimeInterval(121))["charge"] as? [String: Any])?["mode"] as? String == "cached")
        precondition(FleetTelemetryData.homeOverlay(displayRecords, vin: "ABSENT", now: displayNow).isEmpty)

        let stalePower = FleetTelemetryReading(vin: "DISPLAY", field: "DCChargingPower", at: displayNow.addingTimeInterval(-3600), number: 100, text: "", invalid: false)
        let staleETA = FleetTelemetryReading(vin: "DISPLAY", field: "TimeToFullCharge", at: displayNow.addingTimeInterval(-3600), number: 1, text: "", invalid: false)
        let chargeDisplay = FleetTelemetryData.homeOverlay(displayRecords + [stalePower, staleETA], vin: "DISPLAY", now: displayNow)["charge"] as! [String: Any]
        precondition(chargeDisplay["chargerKW"] == nil && chargeDisplay["minutesToLimit"] == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let stableLocation = FleetTelemetryReading(vin: "DISPLAY", field: "Location", at: now.addingTimeInterval(-3600), number: nil, text: "{\"locationValue\":{\"latitude\":37.5,\"longitude\":127.1}}", invalid: false)
        let stableState = FleetTelemetryReading(vin: "DISPLAY", field: "DetailedChargeState", at: now.addingTimeInterval(-3600), number: nil, text: "{\"stringValue\":\"DetailedChargeStateComplete\"}", invalid: false)
        let frequentSOC = (0..<20).map { FleetTelemetryReading(vin: "DISPLAY", field: "Soc", at: now.addingTimeInterval(Double($0)), number: 80, text: "", invalid: false) }
        let retained = FleetTelemetryData.merge([stableLocation, stableState], frequentSOC, limit: 5)
        precondition(retained.count == 5 && retained.contains(where: { $0.id == stableLocation.id }) && retained.contains(where: { $0.id == stableState.id }))
        precondition(retained.last?.at == frequentSOC.last?.at)
        precondition(ChargeEventPolicy.remainingMinutes(reported: nil, soc: 50, limit: 80, powerKW: 7.5, capacityKWh: 75)?.minutes == 180)
        precondition(ChargeEventPolicy.remainingMinutes(reported: 42, soc: 50, limit: 80, powerKW: 7.5, capacityKWh: 75)?.estimated == false)
        precondition(ChargeEventPolicy.remainingMinutes(reported: nil, soc: 50, limit: 80, powerKW: 0, capacityKWh: 75) == nil)

        precondition(ChargeEventPolicy.bleState(5) == "Charging" && ChargeEventPolicy.bleState(6) == "Complete")
        let previousCharge = ChargeObservation(vin: "A", at: now.addingTimeInterval(-30), state: "Charging", soc: 79, limit: 80)
        let completeCharge = ChargeObservation(vin: "A", at: now, state: "Complete", soc: 80, limit: 80)
        let completed = ChargeEventPolicy.event(previous: previousCharge, current: completeCharge, now: now)
        let suspended = ChargeObservation(vin: "A", at: now.addingTimeInterval(-3600), state: "Charging", soc: 40, limit: 80)
        precondition(ChargeEventPolicy.event(previous: suspended, current: completeCharge, now: now)?.kind == "complete")
        precondition(completed?.kind == "complete" && completed!.body.contains("80%") && !completed!.body.contains("100%"))
        precondition(ChargeEventPolicy.event(previous: nil, current: completeCharge, now: now) == nil)
        precondition(ChargeEventPolicy.event(previous: previousCharge, current: completeCharge, now: now.addingTimeInterval(600)) == nil)
        func packet(_ second: Int, _ values: [[String: Any]], vin: String = "CAR-A") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["vin": vin, "createdAt": ["seconds": second], "data": values])
        }
        let valid = try FleetTelemetryData.decode(packet(1_800_000_000, [["key": "ModuleTempMax", "value": ["doubleValue": 32.5]]]), vin: "CAR-A", now: now)
        precondition(valid.first?.number == 32.5)
        let invalid = try FleetTelemetryData.decode(packet(1_800_000_030, [["key": "ModuleTempMax", "value": ["invalid": true]]]), vin: "CAR-A", now: now)
        let merged = FleetTelemetryData.merge(valid, invalid + valid)
        precondition(merged.count == 2 && FleetTelemetryData.latest(merged, vin: "CAR-A")["ModuleTempMax"]?.invalid == true)
        precondition(FleetTelemetryData.latest(merged, vin: "CAR-B").isEmpty)
        do { _ = try FleetTelemetryData.decode(packet(1_800_000_000, [], vin: "CAR-B"), vin: "CAR-A", now: now); preconditionFailure("Cross-VIN import") } catch {}
        do { _ = try FleetTelemetryData.decode(packet(1_800_010_000, []), vin: "CAR-A", now: now); preconditionFailure("Future timestamp accepted") } catch {}
        var parking: [FleetTelemetryReading] = []
        for second in [0, 30, 60] {
            parking += try FleetTelemetryData.decode(packet(1_800_000_000 + second, [
                ["key": "Gear", "value": ["stringValue": "P"]],
                ["key": "ChargeState", "value": ["stringValue": "Disconnected"]],
                ["key": "SentryMode", "value": ["booleanValue": true]],
                ["key": "HvacPower", "value": ["booleanValue": false]],
                ["key": "LifetimeEnergyUsed", "value": ["doubleValue": 100.0 + Double(second) / 3600]]
            ]), vin: "CAR-A", now: now)
        }
        let buckets = FleetParkingAnalysis.buckets(parking, vin: "CAR-A", from: Date(timeIntervalSince1970: 1_800_000_000), to: now)
        precondition(buckets.count == 1 && buckets[0].id == "sentry" && buckets[0].seconds == 60)
        precondition(abs(buckets[0].measuredKWh - 1.0 / 60) < 0.00001)
        precondition(FleetParkingAnalysis.buckets(parking, vin: "CAR-B", from: .distantPast, to: now).isEmpty)
        let comparison = OwnershipAnalysis.cost(distanceKm: 100, energyKWh: 20, electricity: 300, gasoline: 1800, gasolineEfficiency: 12)!
        precondition(abs(comparison.electric - 6000) < 0.001 && abs(comparison.gasoline - 15000) < 0.001 && abs(comparison.savings - 9000) < 0.001)
        precondition(OwnershipAnalysis.cost(distanceKm: nil, energyKWh: 20, electricity: 300, gasoline: 1800, gasolineEfficiency: 12) == nil)
        print("PASS: VIN/time/invalid telemetry, idempotent import, observed parking attribution, comparable energy costs")
    }
}
