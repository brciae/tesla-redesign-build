import Foundation

@main struct VehicleRouteSyncTests {
    static func main() {
        let now = 1_800_000_000_000.0
        var policy = VehicleRouteAuthority()
        precondition(policy.observe(latitude: 37.5, longitude: 127, at: now, receivedAt: now, now: now) == .vehicle)
        policy.beginManual(at: now + 1000)
        precondition(policy.observe(latitude: 37.5, longitude: 127, at: now + 2000, receivedAt: now + 2000, now: now + 2000) == .ignore, "Old car destination must not undo a phone selection")
        precondition(policy.observe(latitude: 37.6, longitude: 127.1, at: now + 3000, receivedAt: now + 3000, now: now + 3000) == .replaceManual, "A new vehicle destination replaces the phone route")
        precondition(policy.observe(latitude: 37.5, longitude: 127, at: now + 2000, receivedAt: now + 4000, now: now + 4000) == .ignore, "Delayed earlier car route cannot roll back the new destination")
        precondition(policy.observe(latitude: 37.6, longitude: 127.1, at: now + 4000, receivedAt: now + 4000, now: now + 4000) == .vehicle)
        var restored = VehicleRouteAuthority()
        restored.beginManual(at: now - 3600000)
        precondition(restored.observe(latitude: 37.7, longitude: 127.2, at: now, receivedAt: now, now: now) == .replaceManual, "Restored old phone route yields when boarding")
        var offline = VehicleRouteAuthority()
        offline.beginManual(at: now)
        precondition(offline.observe(latitude: 37.7, longitude: 127.2, at: now - 60000, receivedAt: now, now: now) == .ignore)
        precondition(offline.observe(latitude: .nan, longitude: 127, at: now, receivedAt: now, now: now) == .ignore)
        precondition(offline.observe(latitude: 37.7, longitude: 127.2, at: now + 60000, receivedAt: now, now: now) == .ignore)
        precondition(offline.observe(latitude: 37.7, longitude: 127.2, at: now + 1000, receivedAt: now + 1000, now: now + 1000) == .replaceManual)
        policy.beginManual(at: now + 5000)
        policy.endManual()
        precondition(policy.observe(latitude: 37.6, longitude: 127.1, at: now + 6000, receivedAt: now + 6000, now: now + 6000) == .vehicle, "Explicit end clears manual suppression; route gate still owns cancellation blocking")
        let active = NavigationAnnouncementContext(guiding: true, destination: "앱 경로", routeKey: "A", at: 1000, seconds: 610, arrivalSOC: 12, now: 1001)
        precondition(active.destination == "앱 경로" && active.routeKey == "A" && active.remainingMinutes == 610.0 / 60 && active.arrivalSOC == 12)
        for (guiding, at) in [(false, 1000.0), (true, 980.0)] {
            let stopped = NavigationAnnouncementContext(guiding: guiding, destination: "이전 경로", routeKey: "A", at: at, seconds: 610, arrivalSOC: 12, now: 1001)
            precondition(stopped.destination.isEmpty && stopped.routeKey.isEmpty && stopped.remainingMinutes == nil && stopped.arrivalSOC == nil)
        }
        print("PASS: manual/vehicle destination precedence, restored route takeover, stale/out-of-order guards, coherent active route announcement context and explicit-end suppression")
    }
}
