import Foundation

/// Waiting for GPS is not an SDK request. Speak once only after submission;
/// duplicate SDK callbacks must not repeat the announcement.
struct NavigationTrafficAnnouncement {
    private var announced = false
    mutating func consume(_ event: String) -> String? {
        if event == "trafficUpdated" { announced = false; return nil }
        guard event == "trafficRequestStarted", !announced else { return nil }
        announced = true
        return "경로를 재탐색합니다."
    }
}

/// Route announcements use the same active SDK route as the navigation screen.
struct NavigationAnnouncementContext {
    var active = false
    var destination = ""
    var routeKey = ""
    var remainingMinutes: Double?
    var arrivalSOC: Double?
    var arrivalLowSOC: Double?
    var reserveSOC = 20.0
    init(guiding: Bool, destination: String, routeKey: String, at: Double?, seconds: Double?, arrivalSOC: Double?, now: Double,
         arrivalLowSOC: Double? = nil, reserveSOC: Double = 20) {
        active = guiding && !routeKey.isEmpty
        guard guiding, !routeKey.isEmpty, let at, at.isFinite, (-5...10).contains(now - at) else { return }
        self.destination = String(destination.prefix(120)); self.routeKey = routeKey
        if let seconds, seconds.isFinite, (0...604800).contains(seconds) { remainingMinutes = seconds / 60 }
        if let arrivalSOC, arrivalSOC.isFinite, (0...100).contains(arrivalSOC) { self.arrivalSOC = arrivalSOC }
        if let low = arrivalLowSOC, low.isFinite, (0...100).contains(low) { self.arrivalLowSOC = low }
        self.reserveSOC = reserveSOC.isFinite ? min(100, max(0, reserveSOC)) : 20
    }
}

enum ArrivalEnergyWarningPolicy {
    /// Both the screen and speech compare the forecast's lower bound with the user's reserve.
    /// The central estimate only determines escalation; it never overrides the configured reserve.
    static func level(arrival: Double?, low: Double?, reserve: Double) -> Int {
        guard let arrival, arrival.isFinite, (0...100).contains(arrival), reserve.isFinite, (0...100).contains(reserve) else { return 0 }
        let bound = low.flatMap { $0.isFinite && (0...arrival).contains($0) ? $0 : nil } ?? arrival
        guard bound < reserve else { return 0 }
        return arrival < min(10, reserve) ? 2 : 1
    }
}

/// The current vehicle destination may replace a phone/manual route. Repeated old
/// vehicle snapshots must not undo a newer selection made on the phone.
struct VehicleRouteAuthority {
    enum Decision { case ignore, vehicle, replaceManual }
    private struct Spot: Equatable { let lat: Float; let lng: Float }
    private var lastSpot: Spot?
    private var lastAt: Double = 0
    private var lastReceipt: Double = 0
    private var manualAt: Double?
    private var manualBaseline: Spot?
    mutating func beginManual(at: Double) { manualAt = at; manualBaseline = lastSpot }
    mutating func endManual() { manualAt = nil; manualBaseline = nil }
    func acceptsVehicleEnd(at: Double?, receivedAt: Double?, now: Double) -> Bool {
        guard let at, let receivedAt, at.isFinite, receivedAt.isFinite,
              (-5000...30000).contains(now - at), (-5000...30000).contains(now - receivedAt),
              at >= lastAt, receivedAt >= lastReceipt else { return false }
        return manualAt.map { at >= $0 } ?? true
    }
    mutating func observe(latitude: Double, longitude: Double, at: Double, receivedAt: Double, now: Double) -> Decision {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180,
              !(latitude == 0 && longitude == 0), at.isFinite, receivedAt.isFinite,
              at <= now + 5000, receivedAt <= now + 5000,
              now - at <= 30000, now - receivedAt <= 30000,
              at >= lastAt, receivedAt >= lastReceipt else { return .ignore }
        let spot = Spot(lat: Float(latitude), lng: Float(longitude))
        lastSpot = spot; lastAt = at; lastReceipt = receivedAt
        guard let manualAt else { return .vehicle }
        guard at >= manualAt, spot != manualBaseline else { return .ignore }
        self.manualAt = nil; manualBaseline = nil
        return .replaceManual
    }
}

struct NavigationRecoveryStore {
    let defaults: UserDefaults
    private let key = "navigation.activeRecovery.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func save(_ checkpoint: NavigationRecoveryCheckpoint) -> Bool {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
    func load() -> NavigationRecoveryCheckpoint? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NavigationRecoveryCheckpoint.self, from: data)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

/// Only an active destination is retained; never reuse an old phone position as a new origin.
struct NavigationRecoveryCheckpoint: Codable, Equatable {
    var vin: String
    var name: String
    var latitude: Double
    var longitude: Double
    var manual: Bool
    var savedAt: Date
    func usable(vin selectedVIN: String, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return vin == selectedVIN && !name.isEmpty && latitude.isFinite && longitude.isFinite &&
            abs(latitude) <= 90 && abs(longitude) <= 180 && !(latitude == 0 && longitude == 0) && age >= -5 && age <= 21600
    }
}
