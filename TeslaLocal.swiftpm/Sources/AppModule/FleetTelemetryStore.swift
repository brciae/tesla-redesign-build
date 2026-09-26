import Foundation
import CoreFoundation

@MainActor final class FleetTelemetryStore: ObservableObject {
    static let shared = FleetTelemetryStore()
    @Published private(set) var records: [FleetTelemetryReading] = []
    @Published private(set) var status = "Telemetry 이력 없음"
    private let file: URL
    private var writable = true
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YLCompanion/fleet-telemetry.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { records = try JSONDecoder().decode([FleetTelemetryReading].self, from: Data(contentsOf: file)); status = "저장된 표본 \(records.count)개" }
            catch { writable = false; status = "Telemetry 저장 자료를 읽지 못했습니다. 원본 파일은 보존됩니다." }
        }
    }
    func ingest(_ data: Data, vin: String) throws {
        guard writable else { throw FleetTelemetryData.failure("기존 저장 자료를 먼저 복구해야 합니다. 덮어쓰지 않습니다.") }
        let incoming = try FleetTelemetryData.decode(data, vin: vin)
        let merged = FleetTelemetryData.merge(records, incoming)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(merged).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = merged; status = "\(incoming.count)개 확인 · 저장 표본 \(merged.count)개"
    }
    func latest(vin: String) -> [String: FleetTelemetryReading] { FleetTelemetryData.latest(records, vin: vin) }
    func observe(_ snapshot: FleetVehicleSnapshot) {
        let mappings: [(String, [(String, String)])] = [
            ("charge_state", [("battery_level", "BatteryLevel"), ("charging_state", "ChargeState"), ("charge_limit_soc", "ChargeLimitSoc"), ("charger_voltage", "ChargerVoltage"), ("charger_actual_current", "ChargeAmps")]),
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
        do { try ingest(JSONSerialization.data(withJSONObject: payloads), vin: snapshot.vin) }
        catch { status = "Fleet 기록 저장 실패: " + error.localizedDescription }
    }
}
