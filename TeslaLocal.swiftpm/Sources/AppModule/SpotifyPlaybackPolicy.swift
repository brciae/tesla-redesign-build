import Foundation
import CryptoKit

/// Only an explicitly authorized, local Spotify player can identify phone playback.
enum SpotifyPlaybackPolicy {
    static let defaultClientID = "e2ad541a9a4f46daa4acc776cdc5d97e" // Public OAuth client identifier, not a secret.
    static let redirect = "ylcompanion://spotify/callback"
    static func validClientID(_ value: String) -> Bool {
        value.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil
    }
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func callbackCode(_ url: URL, state: String) -> String? {
        guard url.scheme == "ylcompanion", url.host == "spotify", url.path == "/callback",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }
    static func usePhonePlayer(connected: Bool, playing: Bool, phoneTitle: String, carSource: Double?, carTitle: String) -> Bool {
        guard connected, !phoneTitle.isEmpty else { return false }
        // A local player does not prove it is the selected source on the car.
        if let source = carSource, source > 0, source != 8 { return false }
        if playing { return true }
        return carSource == 8 && !carTitle.isEmpty && phoneTitle.caseInsensitiveCompare(carTitle) == .orderedSame
    }
}
