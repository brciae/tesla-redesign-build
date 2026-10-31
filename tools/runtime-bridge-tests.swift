import Foundation
@main struct RuntimeBridgeTests {
    static func main() throws {
        let runtime = try LocalRuntime()
        var state = try runtime.call("export") as! Object
        let now = Date().timeIntervalSince1970 * 1000
        state["trips"] = (0..<100).map { i -> Object in
            ["id": "bridge-test-" + String(i), "start": now - Double(i + 2) * 100000, "end": now - Double(i + 1) * 100000, "distanceKm": 1.0, "startSOC": 80.0, "endSOC": 79.0,
             "points": (0..<20).map { j -> Object in ["at": now - Double(i + 2) * 100000 + Double(j) * 1000, "latitude": 37.0, "longitude": 127.0] }]
        }
        _ = try runtime.call("load", ["state": state])
        for _ in 0..<50 {
            let live = try runtime.call("ingestLive", ["groups": Object()]) as! Object
            precondition(live.flag("liveDelta"))
            precondition(live.object("history").object("trips").number("count") == 100)
            precondition(live.object("history").object("trips").rows("rows").first?["points"] == nil)
        }
        let restored = try JSONSerialization.jsonObject(with: runtime.exportData()) as! Object
        precondition(restored.rows("trips").count == 100)
        precondition(restored.rows("trips")[0].rows("points").count == 20, "Live presentation must not alter persisted history")
        let full = try runtime.call("view") as! Object
        precondition(full.object("state").rows("trips").count == 100 && !full.flag("liveDelta"))
        let tariffs = try runtime.call("chargeTariffCatalog") as! [Object]
        precondition(Set(tariffs.map { $0.string("operator") }).count == 6)
        let request: Object = ["at": 1792033200000.0, "chargeOperator": "플러그링크", "chargeType": "ac", "supplyKWh": 10]
        let nonmember = try runtime.call("chargeTariffQuote", request) as! Object
        precondition(nonmember.number("estimatedCost") == 3570 && !nonmember.flag("memberPricingApplied"))
        _ = try runtime.call("settings", ["chargeMemberOperators": ["플러그링크"]])
        let member = try runtime.call("chargeTariffQuote", request) as! Object
        precondition(member.number("estimatedCost") == 2920 && member.flag("memberPricingApplied"))
        let liveRestore = try runtime.call("loadLive", ["state": restored, "resume": true]) as! Object
        precondition(liveRestore.flag("liveDelta"), "Startup restore must not calculate period analysis on the UI thread")
        let before = try runtime.call("view") as! Object
        let worker = BackgroundAnalysis()
        var completed = false, ticks = 0
        var background: Object = [:]
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { _ in ticks += 1 }
        worker.calculate(try runtime.exportData()) { result in
            precondition(Thread.isMainThread)
            switch result { case .success(let value): background = value
            case .failure(let error): preconditionFailure(error.localizedDescription) }
            completed = true
        }
        let deadline = Date().addingTimeInterval(20)
        while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        heartbeat.invalidate()
        precondition(completed && ticks > 0, "Main run loop must remain responsive while analysis runs")
        precondition(background["state"] == nil && background["fresh"] == nil, "Analysis cannot overwrite live/authentication state")
        for key in ["health", "healthIndex", "totals"] {
            let a = try JSONSerialization.data(withJSONObject: before.object(key), options: [.sortedKeys])
            let b = try JSONSerialization.data(withJSONObject: background.object(key), options: [.sortedKeys])
            precondition(a == b, "Background analysis differs for \(key)")
        }
        _ = try runtime.call("deleteTripLive", ["id": "bridge-test-0"])
        let edited = try runtime.call("export") as! Object
        precondition(!edited.rows("trips").contains { $0.string("id") == "bridge-test-0" })
        print("PASS: background analysis equivalence, main-run-loop heartbeat \(ticks), live restore/edit and retained history")
    }
}
