import Foundation

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

struct FleetStreamingStatus {
    let keyPaired: Bool?
    let configured: Bool
    let synced: Bool
    let limitReached: Bool
    let hostname: String?
    init(payload: Any) {
        let object = payload as? [String: Any] ?? [:]
        let config = object["config"] as? [String: Any]
        keyPaired = object["key_paired"] as? Bool
        configured = config?.isEmpty == false
        synced = configured && (object["synced"] as? Bool == true)
        limitReached = object["limit_reached"] as? Bool == true
        hostname = config?["hostname"] as? String
    }
    var title: String {
        if keyPaired == false { return "차량 가상 키 등록 필요" }
        if !configured { return limitReached ? "차량의 스트리밍 연결 한도 도달" : "차량 수집 설정 필요" }
        return synced ? "차량에 수집 설정 적용됨" : "차량의 수집 설정 적용 대기"
    }
    var detail: String {
        if keyPaired == false { return "Tesla 앱에서 이 앱의 가상 키를 차량에 추가하세요." }
        if !configured { return limitReached ? "기존 연결을 확인하세요. 다른 앱의 설정을 자동 삭제하지 않습니다." : "서명 서버를 통해 NAS 수신 주소와 수집 항목을 차량에 등록해야 합니다." }
        return synced ? "NAS에 실제 기록이 도착했는지도 아래에서 확인하세요." : "차량이 온라인으로 연결되면 설정을 적용합니다. 반복해서 차량을 깨우지 않습니다."
    }
}

struct FleetSupplementCard: Identifiable {
    let id: String
    let title: String
    let rows: [FleetInsightRow]
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
