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
