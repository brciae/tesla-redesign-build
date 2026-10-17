import Foundation
@main struct TripComparisonTests {
    static func main() throws {
        let start = Date()
        let a = TripRecordMetrics(id: "a", start: start, end: start.addingTimeInterval(40 * 60), distanceKm: 28, energyKWh: 4,
            startSOC: 80, endSOC: 75, startPoint: .init(latitude: 37.3, longitude: 127.2), endPoint: .init(latitude: 37.4, longitude: 127.3))
        let b = TripRecordMetrics(id: "b", start: start, end: start.addingTimeInterval(38 * 60), distanceKm: 28, energyKWh: 3.5,
            startSOC: 80, endSOC: 75, startPoint: .init(latitude: 37.3001, longitude: 127.2), endPoint: .init(latitude: 37.4, longitude: 127.3001))
        precondition(a.minutes! - b.minutes! == 2 && a.efficiency == 7)
        precondition(a.efficiencyChange(from: b) == -12.5 && a.sameEndpoints(as: b) == true)
        var unknown = b; unknown.startPoint = nil; precondition(a.sameEndpoints(as: unknown) == nil)
        var different = b; different.endPoint = .init(latitude: 37.5, longitude: 127.4); precondition(a.sameEndpoints(as: different) == false)
        var invalid = b; invalid.energyKWh = 0; invalid.end = start
        precondition(invalid.efficiency == nil && invalid.minutes == nil && invalid.averageSpeed == nil)
        invalid.startPoint = .init(latitude: .nan, longitude: 127); precondition(a.sameEndpoints(as: invalid) == nil)
        print("PASS: trip comparison units, signed differences, endpoint uncertainty, different routes and missing-value exclusion")
    }
}
