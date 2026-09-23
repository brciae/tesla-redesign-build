import SwiftUI

/// Owns persisted rules and the at-most-once execution journal, not the BLE transport.
final class AutomationCoordinator: ObservableObject {
    @Published private(set) var rules: [AutomationRule] = []
    @Published private(set) var logs: [AutomationLog] = []
    @Published private(set) var status = "최신 차량 신호 대기"
    @Published private(set) var presence = "탑승 신호 미수신"
    private let file: URL
    private var policy = AutomationPolicy()
    private var sample: AutomationSample?
    private var physicalExpiresAt = 0.0
    private var climateExpiresAt = 0.0
    private var blocked = false
    var settingsDidChange: (() -> Void)?
    init(folder: URL) throws {
        file = folder.appendingPathComponent("automations.json")
        if FileManager.default.fileExists(atPath: file.path) {
            // Corrupt rules must not silently become active defaults.
            do {
                let data = try Data(contentsOf: file)
                guard data.count < 1_000_000 else { throw AutomationError.invalid }
                let document = try JSONDecoder().decode(AutomationDocument.self, from: data)
                guard document.schema == 1, document.rules.count <= 40, document.logs.count <= 80, document.lastFired.count <= 2000, document.lastFired.values.allSatisfy({ $0.isFinite }), Set(document.rules.map(\.id)).count == document.rules.count else { throw AutomationError.invalid }
                for rule in document.rules { try rule.validate() }
                policy.document = document
                for i in policy.document.logs.indices where policy.document.logs[i].status.contains("대기") || policy.document.logs[i].status.contains("준비") || policy.document.logs[i].status.contains("전송 중") {
                    policy.document.logs[i].status = "이전 실행 중단 · 결과 미확인 · 재실행 없음"
                }
            } catch { blocked = true; policy.document.rules = []; status = "자동화 저장자료 확인 필요 · 원본 보존·실행 중단" }
        } else {
            let d = UserDefaults.standard
            for i in policy.document.rules.indices {
                let t = policy.document.rules[i].trigger
                let key = [.departure, .arrival].contains(t) ? "voiceTrip" : [.chargeStart, .chargeEnd].contains(t) ? "voiceCharge" : t == .batteryLow ? "voiceBattery" : t == .destination ? "voiceDestination" : ""
                if !key.isEmpty, d.object(forKey: key) != nil { policy.document.rules[i].enabled = d.bool(forKey: key) }
            }
        }
        publish()
    }
    private func publish() { rules = policy.document.rules; logs = policy.document.logs }
    private func persist() throws {
        guard !blocked else { throw AutomationError.invalid }
        let data = try JSONEncoder().encode(policy.document)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
    func save(_ rule: AutomationRule) throws {
        try rule.validate()
        guard !blocked, policy.document.rules.count < 40 || policy.document.rules.contains(where: { $0.id == rule.id }) else { throw AutomationError.invalid }
        let old = policy.document
        if let index = policy.document.rules.firstIndex(where: { $0.id == rule.id }) { policy.document.rules[index] = rule }
        else { policy.document.rules.append(rule) }
        policy.settingsChanged(); sample = nil
        do { try persist(); publish(); settingsDidChange?() }
        catch { policy.document = old; throw error }
    }
    func enable(_ id: String, _ enabled: Bool) {
        guard var rule = rules.first(where: { $0.id == id }) else { return }
        rule.enabled = enabled
        do { try save(rule); status = enabled ? "설정 저장됨 · 다음 새 조건부터 적용" : "자동화 꺼짐" }
        catch { status = "설정 저장 실패 · 실행 설정 변경 안 됨" }
    }
    func remove(_ id: String) throws {
        let old = policy.document
        policy.document.rules.removeAll { $0.id == id }; policy.settingsChanged(); sample = nil
        do { try persist(); publish(); settingsDidChange?() }
        catch { policy.document = old; throw error }
    }
    func resetObservation() { sample = nil; physicalExpiresAt = 0; policy.reset(); presence = "탑승 신호 미수신" }
    private func report(_ id: String, _ message: String) {
        guard let i = policy.document.logs.firstIndex(where: { $0.id == id }) else { return }
        policy.document.logs[i].status = message
        do { try persist(); publish() } catch { blocked = true; status = "자동화 실행기록 저장 실패 · 추가 실행 중단" }
    }
    func observe(output: Object, previousTrips: Int, previousCharges: Int, link: VehicleLink, voice: VoiceCoordinator, demo: Bool) {
        guard !blocked else { return }
        let state = output.object("state"), groups = state.object("groups"), freshness = output.object("fresh")
        let now = Date().timeIntervalSince1970
        func fresh(_ key: String, maxAge: Double = 15) -> Bool {
            let g = groups.object(key)
            guard freshness.flag(key), let at = g.number("at"), let received = g.number("receivedAt") else { return false }
            return at / 1000 <= now && received / 1000 <= now && now - at / 1000 <= maxAge && now - received / 1000 <= maxAge
        }
        let d = groups.object("drive"), c = groups.object("closures"), charge = groups.object("charge"), tire = groups.object("tire")
        let units = VehicleUnits.saved
        var vin = state.object("settings").string("vin")
        if vin.isEmpty {
            vin = UserDefaults.standard.string(forKey: "vin") ?? ""
        }
        var s = AutomationSample(now: now, vehicle: vin)
        s.active = !demo && link.authentic
        // Do not consume the first boarding event while its enabled HVAC key is still authenticating.
        let needsHVAC = rules.contains { $0.enabled && $0.action != .speech && $0.vehicle == s.vehicle }
        s.boardingReady = !needsHVAC || !link.controlEnabled || link.controlsReady(category: "climate")
        s.driveFresh = fresh("drive"); s.closuresFresh = fresh("closures"); s.climateFresh = fresh("climate", maxAge: 30)
        s.chargeFresh = fresh("charge", maxAge: 30); s.tireFresh = fresh("tire", maxAge: 30)
        s.gear = d["gear"] as? String; s.speed = d.number("speedKmh")
        s.present = c["userPresent"] as? Bool; s.driverDoor = c["driverFront"] as? Bool
        s.closuresAt = c.number("receivedAt").map { $0 / 1000 }
        s.insideC = groups.object("climate").number("insideC"); s.soc = charge.number("soc")
        if let charging = charge.number("charging"), charging.isFinite, (0...100).contains(charging) { s.charging = Int(charging) }
        let rawTires = tire["values"] as? [Any] ?? [], seen = tire["seenAt"] as? [Any] ?? []
        s.tires = rawTires.enumerated().map { index, raw in
            guard index < seen.count, let at = seen[index] as? NSNumber, at.doubleValue.isFinite,
                  now - at.doubleValue / 1000 <= 120, at.doubleValue / 1000 <= now,
                  let value = raw as? NSNumber, value.doubleValue.isFinite, (0.1...10).contains(value.doubleValue) else { return nil }
            return value.doubleValue
        }
        s.tireWarnings = (tire["warnings"] as? [Bool] ?? []).contains(true)
        s.destination = String(d.string("destination").prefix(120))
        // Named destination is the stable identity; optional/jittering coordinates are not a new route.
        s.route = s.driveFresh ? s.destination.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        s.remainingMinutes = s.driveFresh ? d.number("arrivalMinutes") : nil
        s.hour = Calendar.current.component(.hour, from: Date())
        if state.rows("trips").count > previousTrips, let trip = state.rows("trips").last {
            s.endedTrip = trip.string("id")
            let delta = (trip.number("end") ?? 0) - (trip.number("start") ?? 0)
            let duration = delta.isFinite && (0...604800000).contains(delta) ? Int(delta / 60000) : 0
            s.tripSummary = "운행이 종료되었습니다. \(units.format(trip.number("distanceKm"), suffix: " km", digits: 1)), \(duration)분입니다." + (trip.flag("missing") ? " 일부 구간이 기록되지 않았습니다." : "")
        }
        if state.rows("charges").count > previousCharges { s.endedCharge = state.rows("charges").last?.string("id") }
        sample = s
        physicalExpiresAt = [d.number("at"), d.number("receivedAt"), c.number("at"), c.number("receivedAt")].map { ($0 ?? 0) / 1000 + 15 }.min() ?? 0
        climateExpiresAt = [groups.object("climate").number("at"), groups.object("climate").number("receivedAt")].map { ($0 ?? 0) / 1000 + 30 }.min() ?? 0
        presence = !s.closuresFresh || s.present == nil ? "탑승 신호 미수신 · 자동 공조 실행 안 함" : s.present == true ? "차량 탑승 신호 있음" : "차량 탑승 신호 없음"
        let before = policy.document
        let effects = policy.evaluate(s)
        guard policy.document != before else { return }
        do { try persist(); publish() } catch { blocked = true; status = "실행 전 기록 저장 실패 · 모든 동작 중단"; return }
        // Boarding and its optional battery summary share ONE persisted session event.
        // BLE reconnects and restored cached groups cannot create another announcement.
        if policy.didBoard {
            let defaults = UserDefaults.standard
            var texts = defaults.bool(forKey: "voiceAutomations") ? effects.filter { $0.rule.trigger == .boarding && $0.rule.speech }.map(\.text) : []
            if defaults.bool(forKey: "voiceConnection"), s.chargeFresh, let soc = s.soc, soc.isFinite, (0...100).contains(soc) {
                texts.append("배터리 \(Int(soc))퍼센트입니다.")
                if defaults.bool(forKey: "voiceBriefDetail"), let range = charge.number("rangeKm"), range.isFinite, (0...2000).contains(range) {
                    texts.append("표시 주행 가능 거리 \(units.format(range, suffix: " km"))입니다.")
                }
            }
            var seen = Set<String>()
            texts = texts.filter { seen.insert($0).inserted }
            if !texts.isEmpty { voice.say(texts.joined(separator: " "), key: "boarding:" + s.vehicle, category: defaults.bool(forKey: "voiceAutomations") ? "voiceAutomations" : "voiceConnection", ttl: 20, manual: false) }
        }
        for effect in effects {
            if effect.rule.speech && effect.rule.trigger != .boarding { voice.say(effect.text, key: "auto:" + effect.rule.id, category: "voiceAutomations", priority: [.batteryLow, .tireLow].contains(effect.rule.trigger) ? 3 : 1, ttl: 20, manual: false) }
            guard effect.rule.action != .speech else { report(effect.id, effect.rule.speech ? "음성 요청 · 음소거·조용시간·만료 적용" : "조건 감지 · 음성 꺼짐"); continue }
            let valid = { [weak self, weak link] in
                guard let self, let link, !self.blocked, let current = self.sample,
                      UIApplication.shared.applicationState == .active,
                      current.active, current.boarded, Date().timeIntervalSince1970 <= self.physicalExpiresAt,
                      Date().timeIntervalSince1970 - effect.at <= 8, current.vehicle == effect.rule.vehicle,
                      self.rules.contains(effect.rule), link.authentic else { return false }
                guard AutomationPolicy.allowsHour(effect.rule, hour: Calendar.current.component(.hour, from: Date())) else { return false }
                if effect.rule.cabinCondition != "always" {
                    guard Date().timeIntervalSince1970 <= self.climateExpiresAt, current.climateFresh,
                          let temperature = current.insideC, temperature.isFinite,
                          effect.rule.cabinCondition == "above" ? temperature >= effect.rule.cabinThresholdC : temperature <= effect.rule.cabinThresholdC else { return false }
                }
                return true
            }
            report(effect.id, "전송 준비 · 중복·자동 재전송 없음")
            guard !blocked else { continue }
            let reason = link.runAutomation(effect.rule.action.rawValue, title: effect.rule.name,
                args: effect.rule.action == .temperature ? ["value": effect.rule.targetC] : [:], authorized: valid) { [weak self] result in self?.report(effect.id, result) }
            if let reason { report(effect.id, "실행 건너뜀 · " + reason) }
        }
    }
}
