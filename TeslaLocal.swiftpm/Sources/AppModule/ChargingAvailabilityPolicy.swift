import Foundation

struct ChargingAvailabilityPolicy {
    private var observations: [String: (at: Date, count: Int)] = [:]
    private var lastAlert: [String: Date] = [:]
    mutating func reset(_ id: String) { observations.removeValue(forKey: id); lastAlert.removeValue(forKey: id) }
    /// No initial availability alert, no alert across missing data or a gap, no duplicate old receipts.
    mutating func observe(id: String, available: Int?, at: Date?, now: Date = Date()) -> Bool {
        guard let at, (-5...120).contains(now.timeIntervalSince(at)), let count = available, count >= 0 else { observations.removeValue(forKey: id); return false }
        let previous = observations[id]
        if let previous, at <= previous.at { return false }
        observations[id] = (at, count)
        guard let previous, at.timeIntervalSince(previous.at) <= 180, previous.count == 0, count > 0,
              lastAlert[id].map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return false }
        lastAlert[id] = now; return true
    }
}
