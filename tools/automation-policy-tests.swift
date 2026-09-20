import Foundation

@main struct AutomationPolicyTests {
    static func main() throws {
        let vin = "7SAYGDEE0PF000001"
        func sample(_ now: Double) -> AutomationSample {
            var s = AutomationSample(now: now, vehicle: vin)
            s.driveFresh = true; s.closuresFresh = true; s.gear = "P"; s.speed = 0
            s.present = true; s.driverDoor = false; return s
        }
        func only(_ trigger: AutomationTrigger) -> AutomationPolicy {
            var p = AutomationPolicy(); p.document.rules = AutomationRule.defaults.filter { $0.trigger == trigger }; return p
        }
        var p = only(.boarding)
        precondition(p.evaluate(sample(1000)).isEmpty)
        precondition(p.evaluate(sample(1001)).isEmpty)
        precondition(p.evaluate(sample(1003)).count == 1)
        let saved = try JSONEncoder().encode(p.document)
        p = only(.boarding); p.document = try JSONDecoder().decode(AutomationDocument.self, from: saved)
        precondition(p.evaluate(sample(1100)).isEmpty && p.evaluate(sample(1103)).isEmpty)
        var absent = sample(1110); absent.present = false
        _ = p.evaluate(absent); absent.now += 3; _ = p.evaluate(absent)
        precondition(p.evaluate(sample(1120)).isEmpty && p.evaluate(sample(1123)).isEmpty, "presence glitch without door must not rearm")
        var opened = sample(1140); opened.driverDoor = true; _ = p.evaluate(opened)
        _ = p.evaluate(sample(1141)); absent = sample(1145); absent.present = false
        _ = p.evaluate(absent); absent.now += 3; _ = p.evaluate(absent)
        precondition(p.evaluate(sample(1150)).isEmpty && p.evaluate(sample(1153)).isEmpty, "past door opening must not rearm a later presence glitch")
        absent.now = 1200; absent.driverDoor = true; _ = p.evaluate(absent); absent.now += 3; _ = p.evaluate(absent)
        precondition(p.document.boardingLatched, "open door and brief absence do not rearm")
        absent.now = 1209; absent.driverDoor = false; _ = p.evaluate(absent)
        precondition(!p.document.boardingLatched, "door cycle plus sustained absence confirms exit")
        precondition(p.evaluate(sample(1211)).isEmpty && p.evaluate(sample(1214)).count == 1)
        // Reconnects, background/resume and process restore preserve the boarding latch.
        for time in [1220.0, 1280, 1400] {
            p.reset(); precondition(p.evaluate(sample(time)).isEmpty && p.evaluate(sample(time + 3)).isEmpty)
        }
        var staleExit = sample(1500); staleExit.present = false; staleExit.driverDoor = true; staleExit.closuresAt = 1500
        _ = p.evaluate(staleExit)
        staleExit.now = 1503; staleExit.driverDoor = false; staleExit.closuresAt = 1503; _ = p.evaluate(staleExit)
        staleExit.now = 1512; _ = p.evaluate(staleExit)
        precondition(p.document.boardingLatched, "cached closures must not accumulate exit time")
        precondition(p.evaluate(sample(1513)).isEmpty && p.evaluate(sample(1516)).isEmpty)
        p = only(.boarding)
        var cachedBoarding = sample(1600); cachedBoarding.closuresAt = 1600; _ = p.evaluate(cachedBoarding)
        cachedBoarding.now = 1604; precondition(p.evaluate(cachedBoarding).isEmpty)
        cachedBoarding.closuresAt = 1604; precondition(p.evaluate(cachedBoarding).count == 1)
        precondition(p.evaluate(sample(1665)).isEmpty, "cooldown expiry alone must never repeat boarding")
        var lateExit = sample(1700); lateExit.driverDoor = true; _ = p.evaluate(lateExit)
        lateExit.now = 1701; lateExit.driverDoor = false; _ = p.evaluate(lateExit)
        lateExit.now = 1702; lateExit.present = false; _ = p.evaluate(lateExit)
        lateExit.now = 1710; _ = p.evaluate(lateExit)
        precondition(!p.document.boardingLatched, "presence may turn false after the door has already closed")
        precondition(p.evaluate(sample(1712)).isEmpty && p.evaluate(sample(1715)).count == 1)
        p.settingsChanged(); precondition(p.evaluate(sample(1300)).isEmpty && p.evaluate(sample(1303)).isEmpty)
        var initialEdit = only(.boarding); initialEdit.settingsChanged()
        precondition(initialEdit.evaluate(sample(1)).isEmpty && initialEdit.evaluate(sample(4)).isEmpty)
        var unknown = sample(1400); unknown.present = nil; p = only(.boarding)
        _ = p.evaluate(unknown); unknown.now += 3; precondition(p.evaluate(unknown).isEmpty)
        p = only(.departure); var s = sample(1000); _ = p.evaluate(s); s.gear = "D"; s.now += 1
        precondition(p.evaluate(s).isEmpty); s.now += 1; s.speed = 2; precondition(p.evaluate(s).count == 1)
        s.now += 70; s.speed = 0; _ = p.evaluate(s); s.now += 1; s.speed = 2
        precondition(p.evaluate(s).isEmpty, "red-light stop must not repeat departure greeting")
        p = only(.delay); s = sample(1000); s.route = "집"; s.remainingMinutes = 30
        _ = p.evaluate(s); s.now = 1600; s.gear = "D"; s.speed = 30; precondition(p.evaluate(s).isEmpty, "do not count time parked as traffic delay")
        for bad in [Double.nan, Double.infinity, -Double.infinity] { s.now += 1; s.remainingMinutes = bad; precondition(p.evaluate(s).isEmpty) }
        p = only(.batteryLow); s = sample(1000); s.gear = "D"; s.speed = 30; s.chargeFresh = true
        for bad in [Double.nan, Double.infinity, -1, 101] { s.soc = bad; s.now += 1; precondition(p.evaluate(s).isEmpty) }
        s.soc = 10; s.now += 1; precondition(p.evaluate(s).count == 1)
        p = only(.remaining); s.remainingMinutes = 11; s.route = "집"; _ = p.evaluate(s); s.remainingMinutes = 9; s.now += 2
        precondition(p.evaluate(s).count == 1); s.now += 90; precondition(p.evaluate(s).isEmpty)
        p = only(.boarding); var physical = AutomationRule(name: "공조", trigger: .boarding, action: .climateOn, vehicle: vin)
        try physical.validate(); p.document.rules = [physical]; _ = p.evaluate(sample(1)); precondition(p.evaluate(sample(4)).count == 1)
        p = only(.boarding); p.document.rules = [physical]; var waiting = sample(1); waiting.boardingReady = false
        _ = p.evaluate(waiting); waiting.now = 4; precondition(p.evaluate(waiting).isEmpty && !p.document.boardingLatched)
        waiting.now = 5; waiting.boardingReady = true; precondition(p.evaluate(waiting).count == 1)
        waiting.now = 8; precondition(p.evaluate(waiting).isEmpty, "authentication readiness must consume boarding once")
        var gate = AutomationWriteGate(now: 100)
        gate.receive(groups: ["closures", "drive"], now: 100)
        precondition(!gate.consume(now: 100, authorized: true, domainReady: true), "old/unrequested data cannot authorize a write")
        precondition(gate.issueNext(now: 101) == "closures")
        gate.receive(groups: ["closures"], now: 102)
        precondition(gate.issueNext(now: 102) == "drive")
        gate.receive(groups: ["drive"], now: 103)
        precondition(!gate.consume(now: 103, authorized: false, domainReady: true), "changed presence must block wireCommand")
        precondition(!gate.consume(now: 103, authorized: true, domainReady: false), "changed authentication must block wireCommand")
        precondition(gate.consume(now: 103, authorized: true, domainReady: true))
        precondition(!gate.consume(now: 104, authorized: true, domainReady: true), "never replay")
        gate = AutomationWriteGate(now: 100); precondition(gate.issueNext(now: 101) == "closures")
        gate.receive(groups: ["closures"], now: 109)
        precondition(gate.issueNext(now: 109) == nil && !gate.consume(now: 109, authorized: true, domainReady: true), "expired intent cannot retry")
        physical.enabled = false; p = only(.boarding); p.document.rules = [physical]; _ = p.evaluate(sample(1)); precondition(p.evaluate(sample(4)).isEmpty)
        physical.enabled = true; physical.trigger = .departure
        precondition((try? physical.validate()) == nil, "non-boarding control prohibited")
        let encoded = try AutomationTransfer.encode(AutomationRule(name: "환영", trigger: .boarding))
        let decoded = try AutomationTransfer.decode(encoded, vehicle: vin)
        precondition(!decoded.enabled && !decoded.id.hasPrefix("builtin."))
        precondition(!encoded.contains(vin) && !encoded.contains("enabled") && !encoded.contains("vehicle"))
        func rejected(_ text: String) { precondition((try? AutomationTransfer.decode(text, vehicle: vin)) == nil) }
        rejected(encoded.replacingOccurrences(of: "\"boarding\"", with: "\"unlock\""))
        rejected(encoded.replacingOccurrences(of: "\"speech\" : true", with: "\"speech\" : true, \"enabled\" : true"))
        rejected("{\"kind\":\"YLAutomationRule\",\"schema\":true,\"rule\":{\"name\":\"x\",\"trigger\":\"boarding\",\"action\":\"speech\"}}")
        rejected(String(repeating: "x", count: 32769))
        let cb = AutomationCallback(nonce: "test-nonce", expires: 2200)
        let url = cb.shortcutURL(name: "YL 자동화 Claude", prompt: "기호 + & ? 한글")!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first { $0.name == "text" }?.value == "기호 + & ? 한글")
        var success = URLComponents(string: query.first { $0.name == "x-success" }!.value!)!
        success.queryItems!.append(URLQueryItem(name: "result", value: encoded))
        precondition(cb.accept(success.url!, now: 1200)?.text == encoded)
        precondition(cb.accept(success.url!, now: 2300) == nil)
        precondition(AutomationCallback(nonce: "other", expires: 2200).accept(success.url!, now: 1200) == nil)
        precondition(AutomationPolicy.greeting(hour: 8).contains("아침"))
        print("PASS: boarding once across reconnect/restart, fresh closure receipts, sustained exit door cycle, motion, invalid telemetry, disabled control, strict JSON, and nonce callback")
    }
}
