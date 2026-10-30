import SwiftUI

@MainActor final class ChargingWatchStore: ObservableObject {
    static let shared = ChargingWatchStore()
    struct Favorite: Codable { var id: String; var name: String; var watching: Bool }
    @Published private(set) var favorites: [Favorite] = []
    private var policy = ChargingAvailabilityPolicy()
    private init() {
        if let data = UserDefaults.standard.data(forKey: "charging.favorites.v1"), data.count < 100_000 {
            favorites = Array(((try? JSONDecoder().decode([Favorite].self, from: data)) ?? []).prefix(100))
        }
    }
    func contains(_ id: String) -> Bool { favorites.contains { $0.id == id } }
    func watches(_ id: String) -> Bool { favorites.first { $0.id == id }?.watching == true }
    func toggleFavorite(_ site: NearbyChargingSite) {
        if contains(site.id) { favorites.removeAll { $0.id == site.id }; policy.reset(site.id) }
        else if favorites.count < 100 { favorites.append(.init(id: site.id, name: site.name, watching: false)) }
        save()
    }
    func toggleWatch(_ site: NearbyChargingSite) {
        if !contains(site.id), favorites.count < 100 { favorites.append(.init(id: site.id, name: site.name, watching: false)) }
        if let index = favorites.firstIndex(where: { $0.id == site.id }) { favorites[index].watching.toggle(); policy.reset(site.id) }
        save()
    }
    func observe(_ sites: [NearbyChargingSite], demo: Bool) {
        guard !demo else { return }
        let received = Set(sites.map(\.id))
        for favorite in favorites where favorite.watching && !received.contains(favorite.id) { policy.reset(favorite.id) }
        for site in sites where watches(site.id) {
            if policy.observe(id: site.id, available: site.available, at: site.fetchedAt) {
                ChargeNotificationManager.shared.notifyAvailability(id: site.id, name: site.name, available: site.available ?? 0, at: site.fetchedAt ?? Date())
            }
        }
    }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(favorites), forKey: "charging.favorites.v1") }
}
