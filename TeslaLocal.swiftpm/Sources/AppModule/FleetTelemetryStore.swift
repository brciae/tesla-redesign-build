import Foundation
import CoreFoundation

@MainActor final class FleetTelemetryStore: ObservableObject {
    static let shared = FleetTelemetryStore()
    @Published private(set) var records: [FleetTelemetryReading] = []
    @Published private(set) var status = "Telemetry 이력 없음"
    private let file: URL
    private var writable = true
    private var persistence: FleetTelemetryJournal?
    private var appliedRevision: UInt64 = 0
    private var pendingIngestions = 0
    private var mainMotionSeen = Set<String>()
    private var mainMotionGear: [String: String] = [:]
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/fleet-telemetry.json")
        do {
            let restored = try FleetTelemetryJournal.restore(file)
            records = restored.records; persistence = FleetTelemetryJournal(file: file, restored: restored)
            if !records.isEmpty { status = "저장된 표본 \(records.count)개" }
        } catch { writable = false; status = "Telemetry 저장 자료를 읽지 못했습니다. 원본 파일은 보존됩니다." }
    }
    private func pendingKey(_ vin: String) -> String { "fleet.archive.history.pending." + vin }
    func pendingHistoryStart(vin: String) -> Date? {
        guard let stamp = UserDefaults.standard.object(forKey: pendingKey(vin)) as? Double else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }
    func historySaved(vin: String) { if pendingIngestions == 0 { UserDefaults.standard.removeObject(forKey: pendingKey(vin)) } }
    func requestHistoryRebuild(vin: String) {
        if let first = records.filter({ $0.vin == vin }).map(\.at).min() {
            UserDefaults.standard.set(first.timeIntervalSince1970, forKey: pendingKey(vin))
        }
    }
    @discardableResult func ingest(_ data: Data, vin: String) async throws -> Int {
        guard writable, let persistence else { throw FleetTelemetryData.failure("기존 저장 자료를 먼저 복구해야 합니다. 덮어쓰지 않습니다.") }
        let incoming = try FleetTelemetryData.decode(data, vin: vin)
        guard let first = incoming.map(\.at).min() else { return 0 }
        // Persist the analysis marker before durable delta append and before the NAS cursor advances.
        let pending = min(pendingHistoryStart(vin: vin) ?? first, first)
        UserDefaults.standard.set(pending.timeIntervalSince1970, forKey: pendingKey(vin))
        pendingIngestions += 1; defer { pendingIngestions -= 1 }
        let update = try await persistence.ingest(incoming)
        if update.revision > appliedRevision {
            appliedRevision = update.revision; records = update.records
            status = "\(incoming.count)개 확인 · 저장 표본 \(records.count)개" + (update.warning.map { " · " + $0 } ?? "")
        }
        return update.changed
    }
    func latest(vin: String) -> [String: FleetTelemetryReading] { FleetTelemetryData.latest(records, vin: vin) }
    @discardableResult func observeMainMotion(_ drive: [String: Any], vin: String) async throws -> Int {
        guard let data = FleetTelemetryData.mainMotionPayload(drive, vin: vin),
              let at = drive["at"] as? Double, let gear = drive["gear"] as? String else { return 0 }
        let key = vin + ":" + String(at) + ":" + gear
        guard mainMotionSeen.insert(key).inserted else { return 0 }
        if mainMotionSeen.count > 2000 { mainMotionSeen = [key] }
        guard mainMotionGear[vin] != gear else { return 0 }
        // Raw telemetry, including an explicit invalid value, is stronger than a display cache.
        guard !records.contains(where: { $0.vin == vin && $0.field == "Gear" && abs($0.at.timeIntervalSince1970 * 1000 - at) < 1 }) else { return 0 }
        do {
            let count = try await ingest(data, vin: vin)
            mainMotionGear[vin] = gear
            return count
        } catch {
            mainMotionSeen.remove(key)
            throw error
        }
    }
    func observe(_ snapshot: FleetVehicleSnapshot) {
        let payloads = snapshot.historyPayloads()
        guard !payloads.isEmpty else { return }
        Task { @MainActor in
            do { try await ingest(JSONSerialization.data(withJSONObject: payloads), vin: snapshot.vin) }
            catch { status = "Fleet 기록 저장 실패: " + error.localizedDescription }
        }
    }
}
