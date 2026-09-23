import Foundation

@main struct FleetTelemetryTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
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
        precondition(comparison.electric == 6000 && comparison.gasoline == 15000 && comparison.savings == 9000)
        precondition(OwnershipAnalysis.cost(distanceKm: nil, energyKWh: 20, electricity: 300, gasoline: 1800, gasolineEfficiency: 12) == nil)
        print("PASS: VIN/time/invalid telemetry, idempotent import, observed parking attribution, comparable energy costs")
    }
}
