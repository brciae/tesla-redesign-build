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
    func observe(_ snapshot: FleetVehicleSnapshot) {
        let mappings: [(String, [(String, String)])] = [
            ("charge_state", [("battery_level", "BatteryLevel"), ("charging_state", "ChargeState"), ("charge_limit_soc", "ChargeLimitSoc"), ("charger_voltage", "ChargerVoltage"), ("charger_actual_current", "ChargeAmps"), ("time_to_full_charge", "TimeToFullCharge"), ("charger_power", "ChargePower"), ("charge_energy_added", "ChargeEnergyAdded")]),
            ("drive_state", [("shift_state", "Gear"), ("speed", "VehicleSpeed")]),
            ("climate_state", [("inside_temp", "InsideTemp"), ("outside_temp", "OutsideTemp"), ("is_climate_on", "HvacPower")]),
            ("vehicle_state", [("odometer", "Odometer"), ("sentry_mode", "SentryMode"), ("locked", "Locked"), ("tpms_pressure_fl", "TpmsPressureFl"), ("tpms_pressure_fr", "TpmsPressureFr"), ("tpms_pressure_rl", "TpmsPressureRl"), ("tpms_pressure_rr", "TpmsPressureRr")])
        ]
        var payloads: [[String: Any]] = []
        for (section, pairs) in mappings where snapshot.sectionIsRecent(section) {
            guard let source = snapshot.payload[section] as? [String: Any], let at = snapshot.number(section, "timestamp") else { continue }
            var fields: [[String: Any]] = []
            for (key, field) in pairs {
                guard let raw = source[key] else { continue }
                let value: [String: Any]
                if raw is NSNull { value = ["invalid": true] }
                else if let number = raw as? NSNumber {
                    if CFGetTypeID(number) == CFBooleanGetTypeID() { value = ["booleanValue": number.boolValue] }
                    else { value = ["doubleValue": number.doubleValue] }
                } else if let text = raw as? String { value = ["stringValue": text] }
                else { continue }
                fields.append(["key": field, "value": value])
            }
            if !fields.isEmpty { payloads.append(["vin": snapshot.vin, "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: at / 1000)), "data": fields]) }
        }
        guard !payloads.isEmpty else { return }
        Task { @MainActor in
            do { try await ingest(JSONSerialization.data(withJSONObject: payloads), vin: snapshot.vin) }
            catch { status = "Fleet 기록 저장 실패: " + error.localizedDescription }
        }
    }
}
