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
        print("PASS: native JS object bridge, bounded live callbacks, full history retention and checkpoint roundtrip")
    }
}
