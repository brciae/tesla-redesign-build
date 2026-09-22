import Foundation

@main struct FleetCommandTests {
    static func main() throws {
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
