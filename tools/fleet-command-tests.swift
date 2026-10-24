import Foundation

@main struct FleetCommandTests {
    static func main() throws {
        let rearLeft = try FleetCommandPolicy.seatHeaterParameters(position: 7, level: 3)
        precondition(rearLeft == ["seat_position": 7, "level": 3])
        let coolerOff = try FleetCommandPolicy.seatCoolerParameters(position: 0, level: 0)
        let coolerHigh = try FleetCommandPolicy.seatCoolerParameters(position: 1, level: 3)
        precondition(coolerOff == ["seat_position": 1, "seat_cooler_level": 1])
        precondition(coolerHigh == ["seat_position": 2, "seat_cooler_level": 4])
        do { _ = try FleetCommandPolicy.seatCoolerParameters(position: 7, level: 1); preconditionFailure("Unsupported rear cooling accepted") } catch {}
        for invalid in ["", "http://example.com", "https://user:password@example.com", "https://example.com?token=secret", "https://example.com#fragment"] {
            do { _ = try FleetCommandPolicy.proxyURL(invalid); preconditionFailure("Invalid proxy accepted") } catch {}
        }
        let validURL = try FleetCommandPolicy.proxyURL("https://example.com/proxy")
        precondition(validURL.host == "example.com")
        for response in ["{\"response\":{\"result\":1}}", "{}", "{\"response\":{}}", "{\"response\":{\"result\":false}}", "{\"response\":{\"result\":false,\"reason\":\"vehicle unavailable\"}}"] {
            do { _ = try FleetCommandPolicy.accepted(Data(response.utf8)); preconditionFailure("Unconfirmed command accepted") } catch {}
        }
        let accepted = try FleetCommandPolicy.accepted(Data("{\"response\":{\"result\":true}}".utf8))
        precondition(accepted)
        print("PASS: Fleet commands require HTTPS trusted endpoint and explicit vehicle approval; missing/false responses never succeed")
    }
}
