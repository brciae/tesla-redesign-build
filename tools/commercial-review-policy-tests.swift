import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
@main struct ReviewPolicyTests {
    static func main() {
        check(ArrivalEnergyWarningPolicy.level(arrival: 17, low: 14, reserve: 20) == 1, "configured reserve should warn below lower forecast")
        check(ArrivalEnergyWarningPolicy.level(arrival: 21, low: 18, reserve: 20) == 1, "forecast lower bound is shared with screen")
        check(ArrivalEnergyWarningPolicy.level(arrival: 9, low: 5, reserve: 20) == 2, "escalation")
        check(ArrivalEnergyWarningPolicy.level(arrival: 14, low: 12, reserve: 10) == 0, "no hardcoded 15 threshold")
        check(ArrivalEnergyWarningPolicy.level(arrival: .nan, low: nil, reserve: 20) == 0, "invalid forecast")
        var policy = ChargingAvailabilityPolicy()
        let now = Date()
        check(!policy.observe(id:"a",available:2,at:now,now:now), "initial available is not a transition")
        check(!policy.observe(id:"a",available:0,at:now.addingTimeInterval(1),now:now.addingTimeInterval(1)), "arm")
        check(policy.observe(id:"a",available:1,at:now.addingTimeInterval(61),now:now.addingTimeInterval(61)), "zero to available")
        check(!policy.observe(id:"a",available:1,at:now.addingTimeInterval(61),now:now.addingTimeInterval(61)), "duplicate receipt")
        check(!policy.observe(id:"b",available:0,at:now,now:now), "arm b")
        check(!policy.observe(id:"b",available:nil,at:nil,now:now), "invalidate gap")
        check(!policy.observe(id:"b",available:2,at:now.addingTimeInterval(61),now:now.addingTimeInterval(61)), "unknown to available cannot notify")
        let parsed = ChargeImportParser.parse("Start Time,Energy,Amount,Currency,Location\r\n2026-10-30 12:00:00,25,12,USD,\"A, \"\"quoted\"\" station\"\r\n")
        check(parsed.rows.count == 1 && parsed.rejected == 0, "quoted CSV")
        check(parsed.rows[0]["storedKWh"] == nil && parsed.rows[0]["importedEnergyKWh"] as? Double == 25, "generic energy is unclassified")
        check(parsed.rows[0]["cost"] == nil, "USD is not KRW")
        check(ChargeImportParser.csv("a,b\n\"unterminated,x") == nil, "malformed CSV")
        let multiline = ChargeImportParser.csv("a,b\n\"two\nlines\",ok")
        check(multiline?.count == 2 && multiline?[1][0] == "two\nlines", "multiline CSV")
        let a = TripRoutePoint(latitude:37,longitude:127), b = TripRoutePoint(latitude:37.01,longitude:127.01)
        let direct = [a, TripRoutePoint(latitude:37.005,longitude:127.005), b]
        let detour = [a, TripRoutePoint(latitude:37.03,longitude:127), b]
        var trip = TripRecordMetrics(id:"a",distanceKm:5,startPoint:a,endPoint:b)
        trip.routePoints = direct
        var other = TripRecordMetrics(id:"b",distanceKm:5,startPoint:a,endPoint:b)
        other.routePoints = detour
        check(trip.sameEndpoints(as:other) == true && !trip.comparable(as:other), "same endpoints do not imply same road")
        other.routePoints = direct
        check(trip.comparable(as:other), "matching geometry")
        other.partial = true; check(!trip.comparable(as:other), "partial records are not default comparisons")
        print("PASS: reserve warning, availability transitions, import CSV/units, geometry-aware comparison")
    }
}
