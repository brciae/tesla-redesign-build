import Foundation

// Minimal input adapters; the production ScreenBriefingText.swift runs unchanged.
typealias Object = [String: Any]
extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> Object { self[key] as? Object ?? [:] }
    func rows(_ key: String) -> [Object] { self[key] as? [Object] ?? [] }
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
}
struct Link { var authentic = false }
struct Fleet { var vehicleDisplayStatus = "FLEET_SENTINEL"; var selectedVin = "test"; var vehicleSnapshot: FleetVehicleSnapshot? }
struct Rule { var enabled = true }
struct Log { var rule = "AUTOMATION_SENTINEL"; var status = "실행됨" }
struct Automations { var rules = [Rule()]; var logs = [Log()]; var presence = "탑승 미확인"; var status = "자동화 대기" }
struct Navigation { var guiding = false; var locationPermission = "위치 사용 허용"; var status = "NAVIGATION_SENTINEL" }
class AppModel {
    var link = Link(); var fleet = Fleet(); var automations = Automations(); var navigation = Navigation()
    var demo = false; var output: Object = [:]; var groups: Object = [:]; var state: Object = [:]; var settings: Object = [:]; var home: Object = [:]
}
func homePresentation(_ model: AppModel, _ link: Link) -> Object { model.home }
func dateText(_ value: Double?) -> String { value == nil ? "미확인" : "기록 시각" }

@main struct ScreenBriefingTests {
    static func main() {
        let m = AppModel()
        precondition(BriefingScope.home.text(["주차 중.", "주차 중.", ""]) == "주차 중.")
        m.home = ["charge": ["mode": "recent", "soc": 67, "chargerKW": 7, "limit": 80], "climate": ["mode": "recent", "insideC": 23, "outsideC": 9], "location": ["hasCoordinates": true, "latitude": 37.5, "longitude": 127.1]]
        m.groups = ["drive": ["speedKmh": 42, "destination": "DESTINATION_SENTINEL"], "closures": ["locked": true]]
        m.output = ["fresh": ["drive": true, "closures": true], "briefing": "DAILY_SENTINEL", "energyPeriods": ["7": ["trips": [["distanceKm": 12.5]]], "30": ["trips": [["distanceKm": 100], ["distanceKm": 200]]]], "battery": ["7": ["distanceKm": 12.5], "30": ["distanceKm": 300]], "healthIndex": ["initial": true]]
        let fleetScopes: Set<BriefingScope> = [.home, .security, .menu]
        let batteryScopes: Set<BriefingScope> = [.home, .charging, .batteryAndCharging]
        let temperatureScopes: Set<BriefingScope> = [.home, .climate]
        for scope in BriefingScope.allCases {
            let text = m.screenBriefing(scope)
            precondition(!text.contains("요약입니다"), "Unnecessary screen introduction: \(scope)")
            precondition(text.contains("FLEET_SENTINEL") == fleetScopes.contains(scope), "Connection leaked into \(scope)")
            precondition(text.contains("배터리 잔량") == batteryScopes.contains(scope), "Battery leaked into \(scope)")
            precondition(text.contains("실내 온도") == temperatureScopes.contains(scope), "Climate leaked into \(scope)")
            precondition(text.contains("DAILY_SENTINEL") == (scope == .daily), "Global briefing leaked into \(scope)")
            precondition(text.contains("DESTINATION_SENTINEL") == ([BriefingScope.driving, .dashboard].contains(scope)), "Destination leaked into \(scope)")
            precondition(text.contains("AUTOMATION_SENTINEL") == (scope == .automation), "Automation leaked into \(scope)")
        }
        precondition(m.screenBriefing(.trips, days: 7).contains("12.5"))
        precondition(!m.screenBriefing(.trips, days: 7).contains("300.0"))
        precondition(m.screenBriefing(.trips, days: 30).contains("300.0"))
        precondition(m.screenBriefing(.allTrips, rows: [["distanceKm": 9]]).contains("9.0"))
        precondition(m.screenBriefing(.allTrips, rows: []).contains("운행 기록이 없습니다"))
        precondition(m.screenBriefing(.charges, rows: [["cost": 1234]]).contains("1234"))
        precondition(m.screenBriefing(.battery, days: 7).contains("12.5"))
        precondition(m.screenBriefing(.location, address: "ADDRESS_SENTINEL").contains("ADDRESS_SENTINEL"))
        m.output["energyPeriods"] = ["30": ["drivingKmPerKWh": 6.2, "overallKmPerKWh": 4.7, "parkingKWh": 3.2, "unclassifiedKWh": 0.8, "capacityAssumed": true]]
        let analysis = m.screenBriefing(.batteryAndCharging)
        precondition(analysis.contains("6.2") && analysis.contains("4.7") && analysis.contains("24퍼센트"))
        precondition(analysis.contains("주차 중 집계한 소비") && analysis.contains("가정"))
        precondition(!analysis.contains("분류되지 않은") && !analysis.contains("구분할 수 없습니다"))
        precondition(analysis.contains("초기 기준값"))
        m.home = [:]; m.groups = [:]; m.output = [:]
        for scope in BriefingScope.allCases {
            let text = m.screenBriefing(scope)
            precondition(!text.contains("67퍼센트") && !text.contains("23도"))
            precondition(!text.contains("nan") && !text.contains("inf"))
        }
        precondition(m.screenBriefing(.climate) == "요약할 자료가 아직 없습니다.")
        precondition(m.screenBriefing(.driving).contains("최신 수신값이 없습니다"))
        precondition(BriefingScope.tripSummary([nil, .nan, .infinity]).joined().contains("미확인"))
        print("Screen briefing: 21 scopes, cross-menu isolation, selected periods/rows, missing data PASS")
    }
}
