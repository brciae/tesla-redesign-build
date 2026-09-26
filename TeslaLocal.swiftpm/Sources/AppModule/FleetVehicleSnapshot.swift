import Foundation
import CoreFoundation

/// Read-only Fleet display data. Never promoted to BLE verification or automation evidence.
struct FleetVehicleSnapshot {
    let vin: String
    let receivedAt: Date
    let payload: [String: Any]

    func number(_ section: String, _ key: String) -> Double? {
        guard let value = (payload[section] as? [String: Any])?[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private func flag(_ section: String, _ key: String) -> Bool? {
        (payload[section] as? [String: Any])?[key] as? Bool
    }
    var soc: Double? { number("charge_state", "battery_level").flatMap { (0...100).contains($0) ? $0 : nil } }
    var rangeKm: Double? { number("charge_state", "battery_range").flatMap { $0 >= 0 ? $0 * 1.609344 : nil } }
    var insideC: Double? { number("climate_state", "inside_temp") }
    var outsideC: Double? { number("climate_state", "outside_temp") }
    var locked: Bool? { flag("vehicle_state", "locked") }
    var charging: Bool { (payload["charge_state"] as? [String: Any])?["charging_state"] as? String == "Charging" }
    var hasMeasurements: Bool { soc != nil || insideC != nil || locked != nil }
    func sectionIsRecent(_ section: String, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        guard age >= 0, age <= 120, let at = number(section, "timestamp") else { return false }
        let nowMS = now.timeIntervalSince1970 * 1000
        return at <= nowMS + 5000 && nowMS - at <= 120000
    }
    func isRecent(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(receivedAt)
        guard age >= 0 && age <= 120 else { return false }
        let stamps = ["charge_state", "climate_state", "vehicle_state"].compactMap { number($0, "timestamp") }
        return !stamps.isEmpty && stamps.allSatisfy { $0 <= now.timeIntervalSince1970 * 1000 + 5000 && now.timeIntervalSince1970 * 1000 - $0 <= 120000 }
    }
    func homeOverlay(now: Date = Date()) -> [String: Any] {
        let recent = isRecent(now: now)
        let meta: [String: Any] = ["mode": recent ? "recent" : "cached", "label": recent ? "Fleet 최근 조회" : "Fleet 마지막 수신", "at": receivedAt.timeIntervalSince1970 * 1000]
        var charge = meta, climate = meta
        charge["mode"] = sectionIsRecent("charge_state", now: now) ? "recent" : "cached"
        climate["mode"] = sectionIsRecent("climate_state", now: now) ? "recent" : "cached"
        charge["at"] = number("charge_state", "timestamp")
        climate["at"] = number("climate_state", "timestamp")
        charge["soc"] = soc; charge["rangeKm"] = rangeKm
        if let status = (payload["charge_state"] as? [String: Any])?["charging_state"] as? String,
           ["Charging", "Stopped", "Complete", "Disconnected", "NoPower", "Starting"].contains(status) { charge["charging"] = charging; charge["isCharging"] = charging }
        charge["chargerKW"] = number("charge_state", "charger_power")
        charge["limit"] = number("charge_state", "charge_limit_soc")
        charge["addedKWh"] = number("charge_state", "charge_energy_added")
        if let hours = number("charge_state", "time_to_full_charge") { charge["minutesToLimit"] = hours * 60 }
        climate["insideC"] = insideC; climate["outsideC"] = outsideC
        climate["isOn"] = flag("climate_state", "is_climate_on")
        climate["targetC"] = number("climate_state", "driver_temp_setting")
        var location = meta
        let lat = number("drive_state", "latitude"), lon = number("drive_state", "longitude")
        let coordinates = lat != nil && lon != nil && (-90...90).contains(lat!) && (-180...180).contains(lon!) && !(lat == 0 && lon == 0)
        location["hasCoordinates"] = coordinates
        if coordinates { location["latitude"] = lat; location["longitude"] = lon }
        location["gpsAt"] = number("drive_state", "timestamp")
        if let at = number("drive_state", "timestamp"), now.timeIntervalSince1970 * 1000 - at <= 120000, at <= now.timeIntervalSince1970 * 1000 + 5000 {
            location["mode"] = sectionIsRecent("drive_state", now: now) ? "recent" : "cached"
        } else { location["mode"] = coordinates ? "cached" : "missing" }
        return ["charge": charge, "climate": climate, "location": location, "drive": driveDisplay(now: now)]
    }

    func driveDisplay(now: Date = Date()) -> [String: Any] {
        var drive: [String: Any] = ["mode": sectionIsRecent("drive_state", now: now) ? "recent" : "cached", "receivedAt": receivedAt.timeIntervalSince1970 * 1000]
        drive["at"] = number("drive_state", "timestamp")
        if let odo = number("vehicle_state", "odometer"), odo >= 0 { drive["odometerKm"] = odo * 1.609344 }
        if let gear = (payload["drive_state"] as? [String: Any])?["shift_state"] as? String, ["P", "D", "R", "N"].contains(gear) { drive["gear"] = gear }
        if let speed = number("drive_state", "speed"), speed >= 0 { drive["speedKmh"] = speed * 1.609344 }
        let raw = payload["drive_state"] as? [String: Any] ?? [:]
        drive["destination"] = raw["active_route_destination"] as? String
        drive["destinationLat"] = number("drive_state", "active_route_latitude")
        drive["destinationLng"] = number("drive_state", "active_route_longitude")
        drive["arrivalMinutes"] = number("drive_state", "active_route_minutes_to_arrival")
        if let miles = number("drive_state", "active_route_miles_to_arrival"), miles >= 0 { drive["arrivalKm"] = miles * 1.609344 }
        return drive
    }

    /// Missing permissions/fields are not a route cancellation. Only explicit empty values qualify.
    func navigationEvent(now: Date = Date()) -> [String: Any] {
        guard sectionIsRecent("drive_state", now: now) else { return ["type": "wait"] }
        let d = driveDisplay(now: now), raw = payload["drive_state"] as? [String: Any] ?? [:]
        let name = (raw["active_route_destination"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = number("drive_state", "timestamp") ?? 0
        let receipt = receivedAt.timeIntervalSince1970 * 1000
        if let name, !name.isEmpty, let lat = number("drive_state", "active_route_latitude"), let lon = number("drive_state", "active_route_longitude"),
           (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) {
            let tokenData = try? JSONSerialization.data(withJSONObject: [name, lat, lon])
            return ["type": "route", "name": name, "latitude": lat, "longitude": lon, "at": stamp, "receivedAt": receipt,
                    "token": tokenData.flatMap { String(data: $0, encoding: .utf8) } ?? ""]
        }
        func explicitEmpty(_ key: String) -> Bool {
            guard let value = raw[key] else { return false }
            return value is NSNull || number("drive_state", key) == 0
        }
        let emptyName = raw["active_route_destination"] is NSNull || name == ""
        let parked = d["gear"] as? String == "P"
        if emptyName, explicitEmpty("active_route_minutes_to_arrival"), explicitEmpty("active_route_miles_to_arrival"),
           parked || (explicitEmpty("active_route_latitude") && explicitEmpty("active_route_longitude")) {
            return ["type": "absent", "at": stamp, "receivedAt": receipt, "parked": parked]
        }
        return ["type": "wait"]
    }

    /// Read-only translation. A missing Fleet shift_state is not proof of P.
    func parkingTelemetry(now: Date = Date()) -> [String: Any]? {
        guard sectionIsRecent("drive_state", now: now), let driveAt = number("drive_state", "timestamp"),
              driveAt <= now.timeIntervalSince1970 * 1000 + 5000,
              now.timeIntervalSince1970 * 1000 - driveAt <= 120000 else { return nil }
        let stamp = receivedAt.timeIntervalSince1970 * 1000
        var drive: [String: Any] = ["at": driveAt, "receivedAt": stamp]
        if let gear = (payload["drive_state"] as? [String: Any])?["shift_state"] as? String, ["P", "D", "R", "N"].contains(gear) { drive["gear"] = gear }
        if let speed = number("drive_state", "speed"), speed >= 0 { drive["speedKmh"] = speed * 1.609344 }
        if let odo = number("vehicle_state", "odometer") { drive["odometerKm"] = odo * 1.609344 }
        let overlay = homeOverlay(now: now)
        var closures: [String: Any] = ["at": number("vehicle_state", "timestamp") ?? 0]
        closures["locked"] = locked
        for (key, fleetKey) in [("driverFront", "df"), ("driverRear", "dr"), ("passengerFront", "pf"), ("passengerRear", "pr"), ("frunk", "ft"), ("trunk", "rt")] {
            if let value = number("vehicle_state", fleetKey), value >= 0 { closures[key] = value > 0 }
        }
        return ["drive": drive, "location": overlay["location"] ?? [:], "charge": overlay["charge"] ?? [:], "climate": overlay["climate"] ?? [:], "closures": closures]
    }
}


struct FleetInsightRow { let label: String; let value: String }
struct FleetInsightSection { let title: String; let source: String; let rows: [FleetInsightRow] }

extension FleetVehicleSnapshot {
    func insightSections() -> [FleetInsightSection] {
        func metric(_ section: String, _ key: String, _ label: String, _ unit: String, digits: Int = 1, scale: Double = 1) -> FleetInsightRow {
            let value = number(section, key).map { String(format: "%.*f", digits, $0 * scale) + unit } ?? "미수신"
            return FleetInsightRow(label: label, value: value)
        }
        func status(_ key: String, _ label: String) -> FleetInsightRow {
            FleetInsightRow(label: label, value: flag("vehicle_state", key).map { $0 ? "켜짐" : "꺼짐" } ?? "미수신")
        }
        var tires: [FleetInsightRow] = []
        for (key, label) in [("fl", "앞 왼쪽"), ("fr", "앞 오른쪽"), ("rl", "뒤 왼쪽"), ("rr", "뒤 오른쪽")] {
            tires.append(metric("vehicle_state", "tpms_pressure_" + key, label, " bar", digits: 2))
            tires.append(FleetInsightRow(label: label + " 경고", value: flag("vehicle_state", "tpms_hard_warning_" + key).map { $0 ? "차량 공기압 경고" : "차량 경고 없음" } ?? "미수신"))
        }
        var security = [FleetInsightRow(label: "잠금", value: locked.map { $0 ? "잠김" : "잠금 해제" } ?? "미수신"), status("sentry_mode", "감시 모드"), status("is_user_present", "차량 감지 탑승")]
        for (key, label) in [("fd_window", "앞 왼쪽 창문"), ("fp_window", "앞 오른쪽 창문"), ("rd_window", "뒤 왼쪽 창문"), ("rp_window", "뒤 오른쪽 창문"), ("df", "앞 왼쪽 문"), ("pf", "앞 오른쪽 문"), ("dr", "뒤 왼쪽 문"), ("pr", "뒤 오른쪽 문"), ("ft", "프렁크"), ("rt", "트렁크")] {
            security.append(FleetInsightRow(label: label, value: number("vehicle_state", key).map { $0 == 0 ? "닫힘" : "열림" } ?? "미수신"))
        }
        let vehicle = payload["vehicle_state"] as? [String: Any] ?? [:]
        let update = vehicle["software_update"] as? [String: Any] ?? [:]
        let firmware = [FleetInsightRow(label: "차량 소프트웨어", value: vehicle["car_version"] as? String ?? "미수신"), FleetInsightRow(label: "업데이트 상태", value: update["status"] as? String ?? "미수신"), FleetInsightRow(label: "업데이트 버전", value: update["version"] as? String ?? "미수신"), metric("vehicle_state", "odometer", "총 주행거리", " km", scale: 1.609344)]
        return [
            FleetInsightSection(title: "충전 진단", source: "charge_state", rows: [
                metric("charge_state", "charger_power", "충전 전력", " kW"), metric("charge_state", "charger_voltage", "입력 전압", " V", digits: 0),
                metric("charge_state", "charger_actual_current", "실제 전류", " A", digits: 0), metric("charge_state", "charge_current_request", "요청 전류", " A", digits: 0),
                metric("charge_state", "charge_current_request_max", "요청 가능 최대 전류", " A", digits: 0), metric("charge_state", "charge_energy_added", "이번 세션 충전량", " kWh"),
                metric("charge_state", "charge_rate", "표시 주행거리 증가 속도", " km/h", scale: 1.609344), metric("charge_state", "time_to_full_charge", "차량 예상 잔여 시간", " 분", digits: 0, scale: 60)]),
            FleetInsightSection(title: "타이어 상태", source: "vehicle_state", rows: tires),
            FleetInsightSection(title: "도착 전망", source: "drive_state", rows: [
                FleetInsightRow(label: "차량 목적지", value: (payload["drive_state"] as? [String: Any])?["active_route_destination"] as? String ?? "미수신"),
                metric("drive_state", "active_route_energy_at_arrival", "차량 예상 도착 배터리", " %"), metric("drive_state", "active_route_minutes_to_arrival", "남은 시간", " 분", digits: 0),
                metric("drive_state", "active_route_miles_to_arrival", "남은 거리", " km", scale: 1.609344), metric("drive_state", "active_route_traffic_minutes_delay", "교통 지연", " 분", digits: 0)]),
            FleetInsightSection(title: "주차·보안 확인", source: "vehicle_state", rows: security),
            FleetInsightSection(title: "소프트웨어·주행거리", source: "vehicle_state", rows: firmware)
        ]
    }

    func insightSummary() -> [String] {
        var lines: [String] = []
        if sectionIsRecent("vehicle_state") {
            let open = ["df", "pf", "dr", "pr", "ft", "rt"].compactMap { number("vehicle_state", $0) }.filter { $0 > 0 }.count
            if open > 0 { lines.append("문이나 트렁크가 \(open)곳 열려 있습니다. 출발 전에 확인하세요.") }
        }
        if sectionIsRecent("drive_state"), let arrival = number("drive_state", "active_route_energy_at_arrival"), (0...100).contains(arrival), arrival < 15 {
            lines.append(String(format: "도착 예상 잔량이 %.0f퍼센트로 적습니다. 경로에서 충전할 곳을 확인하세요.", arrival))
        }
        if lines.isEmpty, sectionIsRecent("vehicle_state"), flag("vehicle_state", "sentry_mode") == true {
            lines.append("감시 모드가 켜져 있습니다.")
        }
        return lines.isEmpty ? ["지금 읽어드릴 주요 변경 사항이 없습니다."] : lines
    }

    /// Recursively enumerate every returned field, including nested update data.
    func flattenedFields(section: String) -> [FleetInsightRow] {
        func flatten(_ value: Any, path: String) -> [FleetInsightRow] {
            if let dictionary = value as? [String: Any] {
                if dictionary.isEmpty { return [FleetInsightRow(label: path, value: "빈 객체")] }
                return dictionary.keys.sorted().flatMap { flatten(dictionary[$0]!, path: path.isEmpty ? $0 : path + "." + $0) }
            }
            if let array = value as? [Any] {
                if array.isEmpty { return [FleetInsightRow(label: path, value: "빈 목록")] }
                return array.enumerated().flatMap { flatten($0.element, path: path + "[\($0.offset)]") }
            }
            return [FleetInsightRow(label: path, value: value is NSNull ? "미수신 (null)" : String(describing: value))]
        }
        guard let value = payload[section] else { return [] }
        return flatten(value, path: section)
    }
}
