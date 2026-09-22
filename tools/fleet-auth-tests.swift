import Foundation

@main struct FleetAuthTests {
    static func main() throws {
        precondition(FleetAuthPolicy.tokenURL.host == "fleet-auth.prd.vn.cloud.tesla.com")
        precondition(FleetAuthPolicy.asiaPacificURL == "https://fleet-api.prd.na.vn.cloud.tesla.com")
        let payload = Data(#"{"exp":1000}"#.utf8).base64EncodedString()
        precondition(FleetAuthPolicy.needsRefresh("header.\(payload).signature", now: Date(timeIntervalSince1970: 950)))
        precondition(!FleetAuthPolicy.needsRefresh("header.\(payload).signature", now: Date(timeIntervalSince1970: 900)))
        precondition(!FleetAuthPolicy.needsRefresh("opaque-token"))
        // Rechecking the existing OAuth token must retain its renewal credentials.
        precondition(FleetAuthPolicy.preservesRefreshToken(storedAccess: "same-token", incomingAccess: " same-token\n"))
        precondition(!FleetAuthPolicy.preservesRefreshToken(storedAccess: "old-token", incomingAccess: "another-account-token"))
        precondition(!FleetAuthPolicy.preservesRefreshToken(storedAccess: nil, incomingAccess: "new-token"))
        let redirect = "https://example.com/callback"
        let code = try FleetAuthPolicy.callbackCode("https://example.com/callback/?state=fresh&code=a%2Bb%26c%3Dd", redirect: redirect, state: "fresh")
        precondition(code == "a+b&c=d")
        precondition(String(data: FleetAuthPolicy.formBody(["code": code]), encoding: .utf8) == "code=a%2Bb%26c%3Dd")
        for invalid in ["old-code", "https://evil.example/callback?state=fresh&code=x", "https://example.com/callback?state=old&code=x", "https://example.com/callback?state=fresh&code=x&code=y", "https://example.com/callback?state=fresh&error=access_denied"] {
            do { _ = try FleetAuthPolicy.callbackCode(invalid, redirect: redirect, state: "fresh"); fatalError("Invalid callback accepted") }
            catch { precondition((error as NSError).domain == "TeslaOAuth") }
        }
        print("PASS: Tesla Fleet endpoint, Korea region, callback state/origin, duplicate code rejection and form encoding")
    }
}
