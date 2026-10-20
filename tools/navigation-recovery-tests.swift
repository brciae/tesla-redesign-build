import Foundation
@main struct NavigationRecoveryTests {
    static func main() throws {
        var traffic = NavigationTrafficAnnouncement()
        precondition(traffic.consume("rerouting") == nil, "GPS wait must not announce submission")
        precondition(traffic.consume("trafficRequestStarted") == "경로를 재탐색합니다.")
        precondition(traffic.consume("trafficRequestStarted") == nil, "SDK callback must not duplicate speech")
        precondition(traffic.consume("trafficUpdated") == nil)
        precondition(traffic.consume("trafficRequestStarted") != nil, "A subsequent actual request speaks again")
        precondition(traffic.consume("trafficUpdated") == nil)
        precondition(traffic.consume("rerouting") == nil)
        precondition(traffic.consume("trafficUpdated") == nil, "GPS timeout must not announce a request")
        let now = Date()
        let state = NavigationRecoveryCheckpoint(vin: "TEST", name: "목적지", latitude: 37.5, longitude: 127,
                                                  manual: true, savedAt: now)
        let restored = try JSONDecoder().decode(NavigationRecoveryCheckpoint.self, from: JSONEncoder().encode(state))
        precondition(restored == state && restored.usable(vin: "TEST", now: now))
        let suite = "NavigationRecoveryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NavigationRecoveryStore(defaults: defaults)
        precondition(store.save(state))
        precondition(NavigationRecoveryStore(defaults: UserDefaults(suiteName: suite)!).load() == state)
        store.clear()
        precondition(NavigationRecoveryStore(defaults: UserDefaults(suiteName: suite)!).load() == nil, "Explicit stop must survive a fresh store instance")
        precondition(!restored.usable(vin: "OTHER", now: now))
        precondition(!restored.usable(vin: "TEST", now: now.addingTimeInterval(21601)))
        precondition(!restored.usable(vin: "TEST", now: now.addingTimeInterval(-6)))
        for point in [(Double.nan,127.0),(91.0,127.0),(37.5,181.0),(0.0,0.0)] {
            var bad = state; bad.latitude = point.0; bad.longitude = point.1
            precondition(!bad.usable(vin: "TEST", now: now))
        }
        var blank = state; blank.name = ""; precondition(!blank.usable(vin: "TEST", now: now))
        print("PASS: route checkpoint roundtrip, vehicle identity, expiry, future date and invalid coordinate rejection")
    }
}
