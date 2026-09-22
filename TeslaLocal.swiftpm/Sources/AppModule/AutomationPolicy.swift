import Foundation

enum AutomationTrigger: String, Codable, CaseIterable, Identifiable {
    case boarding, departure, arrival, chargeStart, chargeEnd, batteryLow, tireLow, rest, remaining, delay, destination
    var id: String { rawValue }
    var title: String {
        switch self {
        case .boarding: return "탑승 인사"
        case .departure: return "출발 안내"
        case .arrival: return "운행 종료"
        case .chargeStart: return "충전 시작"
        case .chargeEnd: return "충전 종료"
        case .batteryLow: return "배터리 잔량 주의"
        case .tireLow: return "타이어 저압 경고"
        case .rest: return "휴식 안내"
        case .remaining: return "남은 시간 안내"
        case .delay: return "도착 예정 지연"
        case .destination: return "목적지 변경"
        }
    }
    var detail: String {
        switch self {
        case .boarding: return "차량의 탑승 신호·운전석 문 닫힘·P가 연속 확인될 때 한 번"
        case .departure: return "D/R에서 실제 움직임이 시작될 때 한 번"
        case .arrival: return "주행 후 P가 유지되어 운행 기록이 종료될 때"
        case .chargeStart: return "새 상태에서 충전 시작으로 바뀔 때"
        case .chargeEnd: return "충전 종료 기록이 저장될 때"
        case .batteryLow: return "주행 중 설정한 잔량 이하일 때"
        case .tireLow: return "차량 저압 경고 또는 직접 정한 공기압 기준 사용"
        case .rest: return "연속 수신한 운전 시간이 기준을 넘을 때 · 단절 구간은 제외"
        case .remaining: return "차량 내비의 남은 시간이 기준을 통과할 때"
        case .delay: return "같은 목적지의 최초 도착 예상보다 설정 시간 이상 늦어질 때"
        case .destination: return "차량 내비 목적지가 다른 곳으로 변경될 때"
        }
    }
}
enum AutomationAction: String, Codable, CaseIterable, Identifiable {
    case speech, climateOn, climateOff, temperature
    var id: String { rawValue }
    var title: String {
        switch self { case .speech: return "음성 안내만"; case .climateOn: return "공조 켜기"; case .climateOff: return "공조 끄기"; case .temperature: return "공조 목표 온도 설정" }
    }
}
struct AutomationRule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var trigger: AutomationTrigger
    var enabled = true
    var action = AutomationAction.speech
    var speech = true
    var message = ""
    var timeGreeting = false
    var hoursEnabled = false
    var startHour = 0
    var endHour = 24
    var cooldownMinutes = 10
    var threshold = 20.0
    var customTireThreshold = false
    var targetC = 22.0
    var cabinCondition = "always"
    var cabinThresholdC = 26.0
    var vehicle = ""
    static var defaults: [AutomationRule] {
        AutomationTrigger.allCases.map { trigger in
            var rule = AutomationRule(name: trigger.title, trigger: trigger)
            rule.id = "builtin." + trigger.rawValue
            rule.timeGreeting = trigger == .boarding
            rule.cooldownMinutes = [.batteryLow, .tireLow].contains(trigger) ? 30 : 1
            if trigger == .rest { rule.threshold = 120 }
            if trigger == .remaining { rule.threshold = 10 }
            if trigger == .tireLow { rule.threshold = 2.4 }
            return rule
        }
    }
    func validate() throws {
        guard !id.isEmpty, id.count <= 80, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 60, message.count <= 400,
              (0...23).contains(startHour), (0...24).contains(endHour), (1...1440).contains(cooldownMinutes),
              threshold.isFinite, (0...300).contains(threshold), targetC.isFinite, (16...28).contains(targetC), targetC * 2 == (targetC * 2).rounded(),
              cabinThresholdC.isFinite, (-20...60).contains(cabinThresholdC), ["always", "above", "below"].contains(cabinCondition),
              action == .speech || (trigger == .boarding && vehicle.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil) else { throw AutomationError.invalid }
        if [.rest, .remaining, .delay].contains(trigger), !(1...300).contains(threshold) { throw AutomationError.invalid }
        if trigger == .batteryLow, !(1...100).contains(threshold) { throw AutomationError.invalid }
        if trigger == .tireLow, !(1...4).contains(threshold) { throw AutomationError.invalid }
    }
}
enum AutomationError: Error, LocalizedError {
    case invalid
    var errorDescription: String? { "규칙 형식·조건·값을 확인해야 함. 지원하지 않는 조건·동작은 저장하지 않음." }
}
struct AutomationLog: Codable, Identifiable, Equatable {
    var id: String
    var at: Double
    var rule: String
    var message: String
    var status: String
}
struct AutomationDocument: Codable, Equatable {
    var schema = 1
    var rules = AutomationRule.defaults
    var logs: [AutomationLog] = []
    var lastFired: [String: Double] = [:]
    var vehicle = ""
    var boardingLatched = false
    var motionLatched = false
}
struct AutomationSample {
    var now: Double
    var vehicle: String
    var active = true
    var driveFresh = false
    var closuresFresh = false
    var climateFresh = false
    var chargeFresh = false
    var tireFresh = false
    var gear: String?
    var speed: Double?
    var present: Bool?
    var driverDoor: Bool?
    var insideC: Double?
    var soc: Double?
    var charging: Int?
    var tires: [Double?] = []
    var tireWarnings = false
    var destination = ""
    var route = ""
    var remainingMinutes: Double?
    var endedTrip: String?
    var endedCharge: String?
    var tripSummary = ""
    var hour = 12
    var boardingReady = true
    var closuresAt: Double?
    var moving: Bool { driveFresh && ["D", "R"].contains(gear ?? "") && (speed ?? -1) >= 1 }
    var parked: Bool { driveFresh && gear == "P" && (speed == nil || ((speed ?? -1) >= 0 && (speed ?? 1) <= 0.5)) }
    var boarded: Bool { parked && closuresFresh && present == true && driverDoor == false }
}
/// Two new authenticated reads are required for each automatic write. Single use, no replay.
struct AutomationWriteGate {
    private let expires: Double
    private var remaining = ["closures", "drive"]
    private var awaiting: String?
    private var consumed = false
    init(now: Double) { expires = now + 8 }
    mutating func issueNext(now: Double) -> String? {
        guard !consumed, now.isFinite, now <= expires, awaiting == nil, !remaining.isEmpty else { return nil }
        awaiting = remaining.removeFirst(); return awaiting
    }
    mutating func receive(groups: Set<String>, now: Double) {
        guard !consumed, now.isFinite, now <= expires, let group = awaiting, groups.contains(group) else { return }
        awaiting = nil
    }
    mutating func consume(now: Double, authorized: Bool, domainReady: Bool) -> Bool {
        guard !consumed, awaiting == nil, remaining.isEmpty, now.isFinite, now <= expires, authorized, domainReady else { return false }
        consumed = true; return true
    }
}
struct AutomationEffect {
    var id: String
    var rule: AutomationRule
    var text: String
    var at: Double
}

/// Pure, deterministic policy. It never sends a vehicle command. The caller must atomically
/// persist document before consuming any effect. Interrupted/expired effects are never replayed.
struct AutomationPolicy {
    var document = AutomationDocument()
    private(set) var didBoard = false
    private var previous: AutomationSample?
    private var lastPresenceAt: Double?
    private var occupancySince: Double?
    private var absentSince: Double?
    private var exitDoorAt: Double?
    private var driveSeconds = 0.0
    private var parkSince: Double?
    private var routeBaseline: Double?
    private var milestones: Set<String> = []
    mutating func reset() {
        previous = nil; lastPresenceAt = nil; occupancySince = nil; absentSince = nil; exitDoorAt = nil; driveSeconds = 0
        parkSince = nil; routeBaseline = nil; milestones = []
    }
    mutating func settingsChanged() { reset(); document.boardingLatched = true }
    static func renderedText(for rule: AutomationRule, sample: AutomationSample, delayMinutes: Double = 0) -> String {
        var text: String
        switch rule.trigger {
        case .boarding: text = "탑승을 환영합니다."
        case .departure: text = "출발했습니다. 안전한 운행 되세요."
        case .arrival: text = sample.tripSummary
        case .chargeStart: text = "충전이 시작되었습니다."
        case .chargeEnd: text = "충전이 종료되어 기록을 저장했습니다."
        case .batteryLow: text = "배터리 잔량이 \(Int(sample.soc ?? 0))퍼센트입니다. 충전 계획을 확인하세요."
        case .tireLow: text = "타이어 공기압 주의 신호가 있습니다. 안전한 곳에서 타이어 상태를 확인하세요."
        case .rest: text = "앱에서 관측한 연속 운전 시간이 \(Int(rule.threshold))분을 넘었습니다. 안전한 곳에서 잠시 쉬어 가세요."
        case .remaining: text = "목적지까지 약 \(Int(sample.remainingMinutes ?? 0))분 남았습니다."
        case .delay: text = "차량 내비의 도착 예상이 처음보다 약 \(Int(max(0, delayMinutes)))분 늦어졌습니다."
        case .destination: text = "목적지가 \(sample.destination)으로 변경되었습니다."
        }
            if !rule.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = rule.message }
            text = text.replacingOccurrences(of: "{인사}", with: Self.greeting(hour: sample.hour))
                .replacingOccurrences(of: "{배터리}", with: sample.chargeFresh && sample.soc != nil ? "\(Int(sample.soc ?? 0))퍼센트" : "미확인")
                .replacingOccurrences(of: "{목적지}", with: sample.driveFresh && !sample.destination.isEmpty ? sample.destination : "미설정")
            if rule.timeGreeting && !rule.message.contains("{인사}") {
                text = rule.trigger == .boarding && rule.message.isEmpty ? Self.greeting(hour: sample.hour) : Self.greeting(hour: sample.hour) + " " + text
            }
        return text
    }
    static func previewText(for rule: AutomationRule, hour: Int) -> String {
        var sample = AutomationSample(now: 0, vehicle: "preview")
        sample.hour = hour
        sample.chargeFresh = true
        sample.driveFresh = true
        sample.soc = rule.trigger == .batteryLow ? rule.threshold : 82
        sample.destination = "예시 목적지"
        sample.remainingMinutes = rule.threshold
        sample.tripSummary = "예시 운행이 종료되었습니다. 30분 동안 20킬로미터 이동했습니다."
        return renderedText(for: rule, sample: sample, delayMinutes: rule.threshold)
    }

    static func greeting(hour: Int) -> String {
        switch hour { case 5..<12: return "좋은 아침입니다."; case 12..<18: return "좋은 오후입니다."; case 18..<22: return "좋은 저녁입니다."; default: return "늦은 시간입니다. 편안하고 안전하게 이동하세요." }
    }
    static func allowsHour(_ rule: AutomationRule, hour: Int) -> Bool {
        guard rule.hoursEnabled else { return true }
        if rule.startHour == rule.endHour { return true }
        return rule.startHour < rule.endHour ? hour >= rule.startHour && hour < rule.endHour : hour >= rule.startHour || hour < rule.endHour
    }
    mutating func evaluate(_ input: AutomationSample) -> [AutomationEffect] {
        didBoard = false
        var sample = input
        // Reject nonfinite/implausible telemetry before comparisons, interpolation or Int conversion.
        func bounded(_ n: Double?, _ range: ClosedRange<Double>) -> Double? { guard let n, n.isFinite, range.contains(n) else { return nil }; return n }
        sample.speed = bounded(sample.speed, 0...400)
        if input.speed != nil && sample.speed == nil { sample.driveFresh = false }
        sample.soc = bounded(sample.soc, 0...100)
        sample.insideC = bounded(sample.insideC, -50...100)
        sample.remainingMinutes = bounded(sample.remainingMinutes, 0...10080)
        sample.tires = sample.tires.map { bounded($0, 0.1...10) }
        guard sample.active, !sample.vehicle.isEmpty, sample.now.isFinite else { reset(); return [] }
        if document.vehicle != sample.vehicle {
            let firstVehicle = document.vehicle.isEmpty
            document.vehicle = sample.vehicle
            if !firstVehicle { document.boardingLatched = true; document.motionLatched = false }
            reset()
        }
        if let old = previous, sample.now < old.now || sample.now - old.now > 35 { reset() }
        let old = previous
        defer { previous = sample }
        // Only a new closures receipt advances presence debounce; charge/drive polling
        // must not turn one cached false signal into a confirmed exit.
        let presenceAt = sample.closuresAt ?? sample.now
        if sample.closuresFresh && sample.driveFresh && presenceAt.isFinite && presenceAt <= sample.now && sample.now - presenceAt <= 15 {
            if lastPresenceAt == nil || presenceAt > lastPresenceAt! {
                if let last = lastPresenceAt, presenceAt - last > 15 { occupancySince = nil; absentSince = nil; exitDoorAt = nil }
                lastPresenceAt = presenceAt
                if sample.parked && sample.driverDoor == true { exitDoorAt = presenceAt }
                if let at = exitDoorAt, presenceAt - at > 120 { exitDoorAt = nil }
                if sample.boarded {
                    absentSince = nil
                    if occupancySince == nil { occupancySince = presenceAt }
                    // Occupancy may stay true briefly after the person closes the door.
                    // Keep that recent door cycle until presence is stable for eight seconds.
                    if presenceAt - (occupancySince ?? presenceAt) >= 8 { exitDoorAt = nil }
                    if sample.boardingReady && presenceAt - (occupancySince ?? presenceAt) >= 2 && !document.boardingLatched {
                        document.boardingLatched = true; didBoard = true
                    }
                } else {
                    occupancySince = nil
                    if sample.parked && sample.present == false {
                        if absentSince == nil { absentSince = presenceAt }
                        // Rearm only after a real door-open/close cycle and sustained absence.
                        if exitDoorAt != nil && sample.driverDoor == false && presenceAt - (absentSince ?? presenceAt) >= 8 {
                            document.boardingLatched = false; exitDoorAt = nil
                        }
                    } else { absentSince = nil }
                }
            }
        } else { occupancySince = nil; absentSince = nil; exitDoorAt = nil; lastPresenceAt = nil }
        let boarding = didBoard
        if sample.moving && old?.moving == true { driveSeconds += max(0, min(15, sample.now - (old?.now ?? sample.now))) }
        if sample.parked {
            if parkSince == nil { parkSince = sample.now }
            if sample.now - (parkSince ?? sample.now) >= 45 || sample.endedTrip != nil { document.motionLatched = false }
            if sample.now - (parkSince ?? sample.now) >= 600 { driveSeconds = 0; milestones = milestones.filter { !$0.hasPrefix("rest:") } }
        } else { parkSince = nil }
        if boarding { document.motionLatched = false }
        let departure = sample.moving && old?.driveFresh == true && old?.moving == false && !document.motionLatched
        if sample.moving { document.motionLatched = true }
        if sample.route != old?.route { routeBaseline = nil; milestones = milestones.filter { !$0.hasPrefix("route:") } }
        if sample.moving, !sample.route.isEmpty, let minutes = sample.remainingMinutes, routeBaseline == nil { routeBaseline = sample.now + minutes * 60 }
        var effects: [AutomationEffect] = []
        for rule in document.rules where rule.enabled {
            guard (try? rule.validate()) != nil, Self.allowsHour(rule, hour: sample.hour) else { continue }
            if rule.action != .speech && (rule.vehicle != sample.vehicle || !sample.boarded) { continue }
            if rule.cabinCondition != "always" {
                guard sample.climateFresh, let c = sample.insideC,
                      rule.cabinCondition == "above" ? c >= rule.cabinThresholdC : c <= rule.cabinThresholdC else { continue }
            }
            let key = sample.vehicle + ":" + rule.id
            if let fired = document.lastFired[key] {
                if fired > sample.now { document.lastFired[key] = sample.now; continue }
                if sample.now - fired < Double(rule.cooldownMinutes * 60) { continue }
            }
            var fire = false, text = "", milestone: String?
            switch rule.trigger {
            case .boarding: fire = boarding; text = "탑승을 환영합니다."
            case .departure: fire = departure; text = "출발했습니다. 안전한 운행 되세요."
            case .arrival: fire = sample.endedTrip != nil; text = sample.tripSummary
            case .chargeStart: fire = sample.chargeFresh && old?.chargeFresh == true && old?.charging != nil && old?.charging != 5 && sample.charging == 5; text = "충전이 시작되었습니다."
            case .chargeEnd: fire = sample.endedCharge != nil; text = "충전이 종료되어 기록을 저장했습니다."
            case .batteryLow: fire = sample.moving && sample.chargeFresh && sample.soc != nil && (sample.soc ?? 101) <= rule.threshold; text = "배터리 잔량이 \(Int(sample.soc ?? 0))퍼센트입니다. 충전 계획을 확인하세요."
            case .tireLow:
                let low = sample.tires.compactMap { $0 }.filter { $0 > 0 && $0 < rule.threshold }
                fire = sample.moving && sample.tireFresh && (sample.tireWarnings || (rule.customTireThreshold && !low.isEmpty))
                text = "타이어 공기압 주의 신호가 있습니다. 안전한 곳에서 타이어 상태를 확인하세요."
            case .rest:
                let stage = Int(driveSeconds / max(60, rule.threshold * 60)); milestone = "rest:\(rule.id):\(stage)"
                fire = sample.moving && stage > 0; text = "앱에서 관측한 연속 운전 시간이 \(Int(rule.threshold))분을 넘었습니다. 안전한 곳에서 잠시 쉬어 가세요."
            case .remaining:
                milestone = "route:\(rule.id):remaining"
                fire = sample.moving && !sample.route.isEmpty && sample.remainingMinutes != nil && sample.route == old?.route && (old?.remainingMinutes ?? -1) > rule.threshold && (sample.remainingMinutes ?? 1e9) <= rule.threshold
                text = "목적지까지 약 \(Int(sample.remainingMinutes ?? 0))분 남았습니다."
            case .delay:
                let delay = sample.now + (sample.remainingMinutes ?? 0) * 60 - (routeBaseline ?? sample.now)
                let stage = Int(max(0, delay) / max(60, rule.threshold * 60)); milestone = "route:\(rule.id):delay:\(stage)"
                fire = sample.moving && !sample.route.isEmpty && sample.remainingMinutes != nil && routeBaseline != nil && stage > 0
                text = "차량 내비의 도착 예상이 처음보다 약 \(Int(max(0, delay) / 60))분 늦어졌습니다."
            case .destination:
                fire = sample.driveFresh && old?.driveFresh == true && !sample.route.isEmpty && !(old?.route.isEmpty ?? true) && sample.route != old?.route
                text = "목적지가 \(sample.destination)으로 변경되었습니다."
            }
            guard fire else { continue }
            if let milestone { guard !milestones.contains(milestone) else { continue }; milestones.insert(milestone) }
            text = Self.renderedText(for: rule, sample: sample, delayMinutes: max(0, sample.now + (sample.remainingMinutes ?? 0) * 60 - (routeBaseline ?? sample.now)) / 60)
            let eventID = UUID().uuidString
            document.lastFired[key] = sample.now
            document.logs.insert(AutomationLog(id: eventID, at: sample.now, rule: rule.name, message: text, status: rule.action == .speech ? "음성 처리 대기" : "동작 준비 · 재실행 안 함"), at: 0)
            effects.append(AutomationEffect(id: eventID, rule: rule, text: text, at: sample.now))
        }
        document.logs = Array(document.logs.prefix(80))
        if document.lastFired.count > 200 { document.lastFired = document.lastFired.filter { sample.now - $0.value < 86400 * 7 } }
        return effects
    }
}
