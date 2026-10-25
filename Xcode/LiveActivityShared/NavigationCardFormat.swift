import Foundation

enum NavigationCardFormat {
    static func distance(_ metres: Int) -> String {
        guard metres >= 0 else { return "—" }
        return metres >= 1000 ? String(format: "%.1f km", Double(metres) / 1000) : "\(metres) m"
    }
    static func stale(observedAt: Date, now: Date = Date()) -> Bool {
        !(-2..<30).contains(now.timeIntervalSince(observedAt))
    }
}
