import Foundation

@main struct FleetTelemetryTests {
    static func main() throws {
        let historyNow = Date(timeIntervalSince1970: 1_800_000_000)
        let originalAt = historyNow.addingTimeInterval(-7200.125)
        let mainPayload = FleetTelemetryData.mainMotionPayload(["gear": "P", "at": originalAt.timeIntervalSince1970 * 1000], vin: "MAIN", now: historyNow)!
        let mainRows = try FleetTelemetryData.decode(mainPayload, vin: "MAIN", now: historyNow)
        precondition(mainRows.count == 1 && mainRows[0].origin == "appMain" && mainRows[0].at == originalAt, "Main P preserves original historical time, never current receipt time")
        precondition(mainRows[0].field == "Gear" && mainRows[0].number == nil, "Do not invent SOC, odometer or zero speed from a displayed P")
        let roundtrip = try JSONDecoder().decode([FleetTelemetryReading].self, from: JSONEncoder().encode(mainRows))
        precondition(roundtrip[0].origin == "appMain")
        let oldEncoded = try JSONSerialization.data(withJSONObject: [["vin":"MAIN", "field":"Gear", "at":originalAt.timeIntervalSinceReferenceDate, "text":"P", "invalid":false]])
        let oldRows = try JSONDecoder().decode([FleetTelemetryReading].self, from: oldEncoded)
        precondition(oldRows[0].origin == nil, "Old history without origin remains readable")
        for invalid in [["gear":"", "at":originalAt.timeIntervalSince1970 * 1000], ["gear":"unknown", "at":originalAt.timeIntervalSince1970 * 1000], ["gear":"P", "at":historyNow.addingTimeInterval(60).timeIntervalSince1970 * 1000]] as [[String: Any]] {
            precondition(FleetTelemetryData.mainMotionPayload(invalid, vin: "MAIN", now: historyNow) == nil)
        }
        do { _ = try FleetTelemetryData.decode(mainPayload, vin: "OTHER", now: historyNow); preconditionFailure("Main cache cross-VIN") } catch {}
        let anchor = Date(timeIntervalSince1970: 1_790_000_000)
        func reading(_ seconds: Double, _ field: String, _ value: String) -> FleetTelemetryReading {
            FleetTelemetryReading(vin: "WINDOW", field: field, at: anchor.addingTimeInterval(seconds), number: nil, text: "{\"stringValue\":\"\(value)\"}", invalid: false)
        }
        let oldWindow = [reading(0, "ChargeState", "Charging"), reading(60, "Soc", "40"), reading(120, "ChargeState", "Complete"), reading(130, "Soc", "80")]
        let parked = [reading(0, "Gear", "P"), reading(3600, "Gear", "D")]
        precondition(FleetTelemetryData.historyWindow(parked, vin: "WINDOW", since: anchor.addingTimeInterval(3500)).start == anchor, "An open parking period rewinds to its P boundary")
        precondition(FleetTelemetryData.historyWindow(parked, vin: "WINDOW", since: anchor.addingTimeInterval(3620)).start == anchor, "Delayed parking endpoint keeps the P start")
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

        let oldInside = FleetTelemetryReading(vin: "DISPLAY", field: "InsideTemp", at: displayNow.addingTimeInterval(-3600), number: 19, text: "", invalid: false)
        let newOutside = FleetTelemetryReading(vin: "DISPLAY", field: "OutsideTemp", at: displayNow, number: 25, text: "", invalid: false)
        let mixedClimate = FleetTelemetryData.homeOverlay([oldInside, newOutside], vin: "DISPLAY", now: displayNow)["climate"] as! [String: Any]
        precondition(mixedClimate["mode"] as? String == "cached", "A new outside reading must not make old cabin temperature live")
        let stalePower = FleetTelemetryReading(vin: "DISPLAY", field: "DCChargingPower", at: displayNow.addingTimeInterval(-3600), number: 100, text: "", invalid: false)
        let staleETA = FleetTelemetryReading(vin: "DISPLAY", field: "TimeToFullCharge", at: displayNow.addingTimeInterval(-3600), number: 1, text: "", invalid: false)
        let chargeDisplay = FleetTelemetryData.homeOverlay(displayRecords + [stalePower, staleETA], vin: "DISPLAY", now: displayNow)["charge"] as! [String: Any]
        precondition(chargeDisplay["chargerKW"] == nil && chargeDisplay["minutesToLimit"] == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let stableLocation = FleetTelemetryReading(vin: "DISPLAY", field: "Location", at: now.addingTimeInterval(-3600), number: nil, text: "{\"locationValue\":{\"latitude\":37.5,\"longitude\":127.1}}", invalid: false)
        let noGPS = FleetTelemetryReading(vin: "DISPLAY", field: "Location", at: now, number: nil, text: "{}", invalid: true)
        let remembered = FleetTelemetryData.homeOverlay([stableLocation, noGPS], vin: "DISPLAY", now: now)["location"] as! [String: Any]
        precondition(remembered["latitude"] as? Double == 37.5 && remembered["mode"] as? String == "cached")
        precondition(remembered["gpsAt"] as? Double == stableLocation.at.timeIntervalSince1970 * 1000)
        let recentLocation = FleetTelemetryReading(vin: "DISPLAY", field: "Location", at: now.addingTimeInterval(-10), number: nil, text: stableLocation.text, invalid: false)
        let lost = FleetTelemetryData.homeOverlay([recentLocation, noGPS], vin: "DISPLAY", now: now)["location"] as! [String: Any]
        precondition(lost["mode"] as? String == "cached" && lost["positionStatus"] as? String == "gpsUnavailable")
        let reacquired = FleetTelemetryReading(vin: "DISPLAY", field: "Location", at: now.addingTimeInterval(1), number: nil, text: stableLocation.text, invalid: false)
        precondition((FleetTelemetryData.homeOverlay([recentLocation, noGPS, reacquired], vin: "DISPLAY", now: now.addingTimeInterval(1))["location"] as! [String: Any])["mode"] as? String == "recent")
        let stableState = FleetTelemetryReading(vin: "DISPLAY", field: "DetailedChargeState", at: now.addingTimeInterval(-3600), number: nil, text: "{\"stringValue\":\"DetailedChargeStateComplete\"}", invalid: false)
        let ongoingState = FleetTelemetryReading(vin: "DISPLAY", field: "DetailedChargeState", at: now.addingTimeInterval(-3600), number: nil, text: "{\"stringValue\":\"DetailedChargeStateCharging\"}", invalid: false)
        func chargeMetric(_ field: String, _ value: Double, _ ago: TimeInterval = 0, _ vin: String = "DISPLAY") -> FleetTelemetryReading {
            .init(vin: vin, field: field, at: now.addingTimeInterval(-ago), number: value, text: "", invalid: false)
        }
        let freshPower = chargeMetric("ACChargingPower", 7.2)
        precondition(FleetTelemetryData.liveActivityCharge([ongoingState, freshPower], vin: "DISPLAY", now: now)?["mode"] as? String == "recent", "Unchanged Charging state plus measured positive power remains current")
        let gain = [chargeMetric("DCChargingEnergyIn", 10, 60), chargeMetric("DCChargingEnergyIn", 10.2)]
        precondition(FleetTelemetryData.liveActivityCharge([ongoingState] + gain, vin: "DISPLAY", now: now)?["mode"] as? String == "recent", "Increasing battery energy confirms sustained charging even if power is unchanged")
        for samples in [[chargeMetric("Soc", 60)], [chargeMetric("ACChargingPower", 0)], [chargeMetric("ACChargingPower", 7.2, 121)], [chargeMetric("ACChargingPower", 7.2, -6)], [chargeMetric("ACChargingPower", 7.2, 0, "OTHER")], [chargeMetric("DCChargingEnergyIn", 10, 60), chargeMetric("DCChargingEnergyIn", 9.9)]] {
            precondition(FleetTelemetryData.liveActivityCharge([ongoingState] + samples, vin: "DISPLAY", now: now)?["mode"] as? String == "cached", "SOC changes, zero/stale/future/other-car power and counter resets cannot renew charging")
        }
        let completeWithPower = FleetTelemetryData.liveActivityCharge([stableState, freshPower], vin: "DISPLAY", now: now)
        precondition(completeWithPower?["status"] as? String == "Complete" && completeWithPower?["mode"] as? String == "cached", "A reported Complete state is never turned into Charging by power")
        precondition(FleetTelemetryData.liveActivityCharge([freshPower], vin: "DISPLAY", now: now) == nil, "Power alone without a known charging state cannot start a card")
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
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let heldNow = start.addingTimeInterval(1000)
        var heldParking = parking.filter { $0.at == start }
        for second in stride(from: 60, through: 600, by: 60) {
            heldParking += try FleetTelemetryData.decode(packet(1_800_000_000 + second, [["key": "LifetimeEnergyUsed", "value": ["doubleValue": 100.0 + Double(second) / 3600]]]), vin: "CAR-A", now: heldNow)
        }
        let heldBuckets = FleetParkingAnalysis.buckets(heldParking, vin: "CAR-A", from: start.addingTimeInterval(60), to: heldNow)
        precondition(heldBuckets.first?.seconds == 540, "Unchanged Gear/Charge/Sentry states survive while energy counters establish continuous coverage")
        let gap = heldParking.filter { $0.at == start || $0.at == start.addingTimeInterval(600) }
        precondition(FleetParkingAnalysis.buckets(gap, vin: "CAR-A", from: start, to: heldNow).isEmpty, "Unobserved gaps do not become measured parking time")
        precondition(buckets.count == 1 && buckets[0].id == "sentry" && buckets[0].seconds == 60)
        precondition(abs(buckets[0].measuredKWh - 1.0 / 60) < 0.00001)
        precondition(FleetParkingAnalysis.buckets(parking, vin: "CAR-B", from: .distantPast, to: now).isEmpty)
        let comparison = OwnershipAnalysis.cost(distanceKm: 100, energyKWh: 20, electricity: 300, gasoline: 1800, gasolineEfficiency: 12)!
        precondition(abs(comparison.electric - 6000) < 0.001 && abs(comparison.gasoline - 15000) < 0.001 && abs(comparison.savings - 9000) < 0.001)
        precondition(OwnershipAnalysis.cost(distanceKm: nil, energyKWh: 20, electricity: 300, gasoline: 1800, gasolineEfficiency: 12) == nil)
        print("PASS: VIN/time/invalid telemetry, idempotent import, observed parking attribution, comparable energy costs")
    }
}
