import Foundation

@main struct FleetTelemetryTests {
    static func main() throws {
        let displayNow = Date(timeIntervalSince1970: 1_800_000_000)
        let displayRecords = [FleetTelemetryReading(vin: "DISPLAY", field: "Soc", at: displayNow, number: 31, text: "", invalid: false), FleetTelemetryReading(vin: "OTHER", field: "Soc", at: displayNow, number: 90, text: "", invalid: false)]
        let display = FleetTelemetryData.homeOverlay(displayRecords, vin: "DISPLAY", now: displayNow)
        precondition((display["charge"] as? [String: Any])?["soc"] as? Double == 31)
        precondition((FleetTelemetryData.homeOverlay(displayRecords, vin: "DISPLAY", now: displayNow.addingTimeInterval(121))["charge"] as? [String: Any])?["mode"] as? String == "cached")
        precondition(FleetTelemetryData.homeOverlay(displayRecords, vin: "ABSENT", now: displayNow).isEmpty)

        let now = Date(timeIntervalSince1970: 1_800_000_100)
        precondition(ChargeEventPolicy.bleState(5) == "Charging" && ChargeEventPolicy.bleState(6) == "Complete")
        let previousCharge = ChargeObservation(vin: "A", at: now.addingTimeInterval(-30), state: "Charging", soc: 79, limit: 80)
        let completeCharge = ChargeObservation(vin: "A", at: now, state: "Complete", soc: 80, limit: 80)
        let completed = ChargeEventPolicy.event(previous: previousCharge, current: completeCharge, now: now)
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
