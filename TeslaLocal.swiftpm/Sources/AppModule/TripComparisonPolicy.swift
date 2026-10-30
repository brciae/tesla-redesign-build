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
    var routePoints: [TripRoutePoint] = []
    var outsideC: Double?
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
    /// Symmetric geometry check; matching endpoints alone must not imply the same road.
    func routeOverlap(as other: Self) -> Double? {
        func sampled(_ points: [TripRoutePoint]) -> [TripRoutePoint] {
            guard points.count > 2 else { return [] }
            return stride(from: 0, to: min(points.count, 10000), by: max(1, min(points.count, 10000) / 40)).map { points[$0] }
        }
        let a = sampled(routePoints), b = sampled(other.routePoints)
        guard a.count >= 3, b.count >= 3 else { return nil }
        func fraction(_ from: [TripRoutePoint], _ to: [TripRoutePoint]) -> Double {
            Double(from.filter { point in to.contains { (point.distance(to: $0) ?? .infinity) <= 200 } }.count) / Double(from.count)
        }
        return min(fraction(a, b), fraction(b, a))
    }
    func comparable(as other: Self) -> Bool {
        guard !partial, !other.partial, sameEndpoints(as: other) == true, let a = distanceKm, let b = other.distanceKm,
              a > 0, b > 0, abs(a - b) / max(a, b) <= 0.15, let overlap = routeOverlap(as: other), overlap >= 0.75 else { return false }
        if let a = outsideC, let b = other.outsideC, abs(a - b) > 10 { return false }
        return true
    }
    func comparisonReason(as other: Self) -> String {
        if partial || other.partial { return "일부 구간 미확인 · 완전한 주행끼리 우선 비교 필요" }
        guard sameEndpoints(as: other) == true else { return "출발·도착 위치가 다르거나 위치 자료 부족" }
        guard let overlap = routeOverlap(as: other) else { return "출도착 유사 · 실제 경로 일치도 자료 부족" }
        var parts = [String(format: "관측 경로 겹침 %.0f%%", overlap * 100)]
        if let a = distanceKm, let b = other.distanceKm, max(a, b) > 0 { parts.append(String(format: "거리 차이 %.0f%%", abs(a - b) / max(a, b) * 100)) }
        if let a = outsideC, let b = other.outsideC { parts.append(String(format: "외기온 차이 %.0f°C", abs(a - b))) } else { parts.append("외기온 비교 미확인") }
        return parts.joined(separator: " · ")
    }
}
