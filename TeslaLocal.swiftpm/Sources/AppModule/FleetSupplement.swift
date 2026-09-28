import Foundation
import CoreFoundation

enum FleetSupplement: String, CaseIterable, Identifiable {
    case chargingHistory, nearbyCharging, alerts, service, releaseNotes, drivers, telemetryConfig, telemetryErrors
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chargingHistory: return "Tesla 충전 이력"
        case .nearbyCharging: return "주변 충전소"
        case .alerts: return "차량 경고 기록"
        case .service: return "서비스 상태"
        case .releaseNotes: return "차량 업데이트 안내"
        case .drivers: return "차량 접근 운전자"
        case .telemetryConfig: return "데이터 스트리밍 연결"
        case .telemetryErrors: return "데이터 수집 오류"
        }
    }
    var note: String {
        switch self {
        case .chargingHistory: return "Tesla 계정의 충전 이력 첫 페이지입니다. 다른 사업자 충전은 영수증 기록과 함께 확인하세요."
        case .nearbyCharging: return "차량 위치 기준입니다. 빈 충전기 수는 이동 중 달라질 수 있습니다."
        case .alerts: return "차량이 제공한 경고를 확인합니다. 수신되지 않은 경고까지 없다고 판단하지 않습니다."
        case .service: return "차량 서비스 상태입니다. 실제 예약·견적 승인은 Tesla 앱에서 진행하세요."
        case .releaseNotes: return "선택 차량의 소프트웨어 안내입니다. 지역·차량별 기능이 다를 수 있습니다."
        case .drivers: return "소유자 권한이 필요한 조회입니다. 이 화면에서는 접근 권한을 변경하지 않습니다."
        case .telemetryConfig: return "현재 차량에 적용된 수집 설정을 조회합니다. 서버를 새로 연결하거나 설정을 덮어쓰지 않습니다."
        case .telemetryErrors: return "차량이 보고한 스트리밍 연결 오류를 조회합니다."
        }
    }
    func path(vin: String) -> String {
        let suffix: String
        switch self {
        case .chargingHistory: return "/api/1/dx/charging/history"
        case .nearbyCharging: suffix = "nearby_charging_sites"
        case .alerts: suffix = "recent_alerts"
        case .service: suffix = "service_data"
        case .releaseNotes: suffix = "release_notes"
        case .drivers: suffix = "drivers"
        case .telemetryConfig: suffix = "fleet_telemetry_config"
        case .telemetryErrors: suffix = "fleet_telemetry_errors"
        }
        return "/api/1/vehicles/\(vin)/\(suffix)"
    }
    func query(vin: String) -> [URLQueryItem]? {
        self == .chargingHistory ? [URLQueryItem(name: "vin", value: vin)] : nil
    }
}

struct FleetSupplementResult {
    let vin: String
    let receivedAt: Date
    let payload: Any
    var rows: [FleetInsightRow] {
        FleetVehicleSnapshot(vin: vin, receivedAt: receivedAt, payload: ["자료": payload]).flattenedFields(section: "자료")
    }
}

struct NearbyChargingSite: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: String
    let available: Int?
    let total: Int?
    let powerKW: Double?
    var category: String {
        if kind == "슈퍼차저" { return "슈퍼차저" }
        if kind == "데스티네이션 충전" { return "완속" }
        if let powerKW { return powerKW >= 50 ? "급속" : "완속" }
        return "충전소"
    }
    var availability: String? {
        guard let available else { return nil }
        return total.map { "\(available)/\($0)" } ?? "\(available)"
    }

    static func parse(_ payload: Any) -> [NearbyChargingSite] {
        guard let root = payload as? [String: Any] else { return [] }
        let object = root["response"] as? [String: Any] ?? root
        var seen = Set<String>()
        return [("superchargers", "슈퍼차저"), ("destination_charging", "데스티네이션 충전")].flatMap { key, kind in
            (object[key] as? [[String: Any]] ?? []).compactMap { site -> NearbyChargingSite? in
                let location = site["location"] as? [String: Any] ?? site
                func number(_ value: Any?) -> Double? {
                    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
                    return n.doubleValue
                }
                guard let lat = number(location["lat"] ?? location["latitude"]),
                      let lon = number(location["long"] ?? location["lon"] ?? location["longitude"]),
                      (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) else { return nil }
                let name = site["name"] as? String ?? site["site_name"] as? String ?? kind
                let id = "\(lat),\(lon):\(name)"
                guard seen.insert(id).inserted else { return nil }
                func count(_ key: String) -> Int? {
                    guard let n = number(site[key]), n >= 0, n <= 10000, n.rounded() == n else { return nil }
                    return Int(n)
                }
                let total = count("total_stalls"), available = count("available_stalls")
                let power = number(site["power_kw"])
                return NearbyChargingSite(id: id, name: name, latitude: lat, longitude: lon, kind: kind,
                    available: available.flatMap { n in if let total, n > total { return nil }; return n }, total: total,
                    powerKW: power.flatMap { $0 > 0 ? $0 : nil })
            }
        }
    }
}

struct FleetStreamingStatus {
    let keyPaired: Bool?
    let configured: Bool
    let synced: Bool
    let limitReached: Bool
    let hostname: String?
    let locationConfigured: Bool
    init(payload: Any) {
        let object = payload as? [String: Any] ?? [:]
        let config = object["config"] as? [String: Any]
        keyPaired = object["key_paired"] as? Bool
        configured = config?.isEmpty == false
        synced = configured && (object["synced"] as? Bool == true)
        limitReached = object["limit_reached"] as? Bool == true
        hostname = config?["hostname"] as? String
        locationConfigured = (config?["fields"] as? [String: Any])?["Location"] != nil
    }
    var title: String {
        if keyPaired == false { return "차량 가상 키 등록 필요" }
        if !configured { return limitReached ? "차량의 스트리밍 연결 한도 도달" : "차량 수집 설정 필요" }
        if !locationConfigured { return "주차 좌표 수집 항목 누락" }
        return synced ? "차량에 수집 설정 적용됨" : "차량의 수집 설정 적용 대기"
    }
    var detail: String {
        if keyPaired == false { return "Tesla 앱에서 이 앱의 가상 키를 차량에 추가하세요." }
        if !configured { return limitReached ? "기존 연결을 확인하세요. 다른 앱의 설정을 자동 삭제하지 않습니다." : "서명 서버를 통해 NAS 수신 주소와 수집 항목을 차량에 등록해야 합니다." }
        if !locationConfigured { return "현재 차량 수집 설정에 위치가 빠져 있습니다. 아래에서 기존 NAS 주소를 유지한 채 주차 좌표 수집을 추가하세요." }
        return synced ? "NAS에 실제 기록이 도착했는지도 아래에서 확인하세요." : "차량이 온라인으로 연결되면 설정을 적용합니다. 반복해서 차량을 깨우지 않습니다."
    }
}

struct FleetSupplementCard: Identifiable {
    let id: String
    let title: String
    let rows: [FleetInsightRow]
}

enum FleetLocationRepair {
    /// Patch only missing location fields. Keep the existing destination, CA and other subscriptions.
    static func configuration(_ payload: Any, now: Date = Date()) throws -> [String: Any] {
        guard let object = payload as? [String: Any], object["key_paired"] as? Bool != false,
              var config = object["config"] as? [String: Any],
              let hostname = config["hostname"] as? String, !hostname.isEmpty,
              let port = config["port"] as? Int, (1...65535).contains(port),
              var fields = config["fields"] as? [String: Any], !fields.isEmpty else {
            throw NSError(domain: "FleetLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "기존 차량 수집 설정과 가상 키를 먼저 확인해 주세요."])
        }
        if let expiration = (config["exp"] as? NSNumber)?.doubleValue, expiration <= now.timeIntervalSince1970 {
            throw NSError(domain: "FleetLocation", code: 2, userInfo: [NSLocalizedDescriptionKey: "기존 수집 설정이 만료됐습니다. 서버 연결 등록을 갱신해 주세요."])
        }
        if fields["Location"] == nil { fields["Location"] = ["interval_seconds": 10] }
        if fields["GpsState"] == nil { fields["GpsState"] = ["interval_seconds": 10] }
        config["fields"] = fields
        return config
    }
}

extension FleetSupplementResult {
    /// Present known user-facing fields; IDs, raw schema paths and server internals stay out of the UI.
    var cards: [FleetSupplementCard] {
        let labels: [String: String] = [
            "site_name": "충전소", "name": "이름", "title": "제목", "description": "안내", "message": "안내",
            "start_time": "시작", "end_time": "종료", "charge_start_date_time": "충전 시작", "charge_stop_date_time": "충전 종료",
            "chargeStartDateTime": "충전 시작", "chargeStopDateTime": "충전 종료", "siteLocationName": "충전소",
            "energy_used": "충전량 (kWh)", "total_energy": "충전량 (kWh)", "energyDelivered": "충전량 (kWh)",
            "total_cost": "결제 금액", "totalCost": "결제 금액", "currency": "통화", "billingType": "결제 유형",
            "available_stalls": "사용 가능", "total_stalls": "전체 충전기", "power_kw": "최대 출력 (kW)",
            "address": "주소", "city": "도시", "status": "상태", "version": "버전", "release_notes": "업데이트 내용",
            "first_name": "이름", "last_name": "성", "email": "이메일", "service_status": "서비스 상태",
            "alert_name": "경고", "alert_body": "내용", "timestamp": "기록 시각", "date": "날짜"
        ]
        func visit(_ value: Any, path: String) -> [FleetSupplementCard] {
            if let list = value as? [Any] { return list.enumerated().flatMap { visit($0.element, path: path + "." + String($0.offset)) } }
            guard let object = value as? [String: Any] else { return [] }
            var items: [FleetInsightRow] = []
            for key in object.keys.sorted() {
                guard let label = labels[key], let raw = object[key], !(raw is NSNull), !(raw is [String: Any]), !(raw is [Any]) else { continue }
                var text = String(describing: raw)
                if key == "status" || key == "service_status" {
                    text = ["available": "이용 가능", "completed": "완료", "pending": "대기", "scheduled": "예약됨", "in_progress": "진행 중"][text] ?? text
                }
                items.append(FleetInsightRow(label: label, value: text))
            }
            let title = (object["site_name"] ?? object["siteLocationName"] ?? object["title"] ?? object["name"]) as? String ?? "차량 기록"
            var result = items.isEmpty ? [] : [FleetSupplementCard(id: path, title: title, rows: items)]
            for key in object.keys.sorted() where object[key] is [Any] || object[key] is [String: Any] {
                result += visit(object[key]!, path: path + "." + key)
            }
            return result
        }
        return visit(payload, path: "record")
    }
}
