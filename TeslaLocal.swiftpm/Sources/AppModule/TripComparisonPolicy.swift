import Foundation

struct TripRoutePoint {
    var latitude: Double
    var longitude: Double
    func distance(to other: Self) -> Double? {
        guard latitude.isFinite, longitude.isFinite, other.latitude.isFinite, other.longitude.isFinite,
              (-90...90).contains(latitude), (-90...90).contains(other.latitude),
              (-180...180).contains(longitude), (-180...180).contains(other.longitude) else { return nil }
        let rad = Double.pi / 180, a = latitude * rad, b = other.latitude * rad
        let h = pow(sin((b - a) / 2), 2) + cos(a) * cos(b) * pow(sin((other.longitude - longitude) * rad / 2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
struct TripRecordMetrics: Identifiable {
    var id: String
    var start: Date?
    var end: Date?
    var distanceKm: Double?
    var energyKWh: Double?
    var startSOC: Double?
    var endSOC: Double?
    var partial = false
    var startPoint: TripRoutePoint?
    var endPoint: TripRoutePoint?
    var minutes: Double? { guard let start, let end, end > start else { return nil }; return end.timeIntervalSince(start) / 60 }
    var efficiency: Double? {
        guard let km = distanceKm, let kwh = energyKWh, km.isFinite, km > 0, kwh.isFinite, kwh > 0 else { return nil }; return km / kwh
    }
    var averageSpeed: Double? { guard let km = distanceKm, km.isFinite, km >= 0, let minutes, minutes > 0 else { return nil }; return km / minutes * 60 }
    func sameEndpoints(as other: Self) -> Bool? {
        guard let a = startPoint, let b = endPoint, let c = other.startPoint, let d = other.endPoint,
              let startDistance = a.distance(to: c), let endDistance = b.distance(to: d) else { return nil }
        return startDistance <= 500 && endDistance <= 500
    }
    func efficiencyChange(from other: Self) -> Double? {
        guard let current = efficiency, let previous = other.efficiency, previous > 0 else { return nil }; return (current / previous - 1) * 100
    }
}
