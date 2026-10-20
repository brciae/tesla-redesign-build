import Foundation
@main struct SpotifyPolicyTests {
    static func main() {
        let remoteURL = URL(string: "ylcompanion://spotify/callback#access_token=fixture")!
        precondition(SpotifyPlaybackPolicy.acceptsRemoteCallback(remoteURL, pending: true))
        precondition(!SpotifyPlaybackPolicy.acceptsRemoteCallback(remoteURL, pending: false))
        for value in ["other://spotify/callback", "ylcompanion://activity", "ylcompanion://spotify/wrong"] {
            precondition(!SpotifyPlaybackPolicy.acceptsRemoteCallback(URL(string: value)!, pending: true))
        }
        precondition(SpotifyPlaybackPolicy.remoteTokenUsable(expires: 200, now: 100))
        precondition(!SpotifyPlaybackPolicy.remoteTokenUsable(expires: 160, now: 100))
        precondition(!SpotifyPlaybackPolicy.remoteTokenUsable(expires: .nan, now: 100))
        precondition(SpotifyPlaybackPolicy.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        precondition(SpotifyPlaybackPolicy.validClientID(String(repeating: "a", count: 32)))
        for bad in ["someone@example.com", "spotify-user", "", String(repeating: "z", count: 32)] { precondition(!SpotifyPlaybackPolicy.validClientID(bad)) }
        precondition(SpotifyPlaybackPolicy.callbackCode(URL(string: "ylcompanion://spotify/callback?state=S&code=C")!, state: "S") == "C")
        for raw in ["ylcompanion://spotify/callback?state=X&code=C", "ylcompanion://activity?state=S&code=C", "ylcompanion://spotify/callback?state=S&state=S&code=C", "ylcompanion://spotify/callback?state=S&code=C&error=denied"] {
            precondition(SpotifyPlaybackPolicy.callbackCode(URL(string: raw)!, state: "S") == nil)
        }
        precondition(SpotifyPlaybackPolicy.usePhonePlayer(connected: true, playing: true, phoneTitle: "Song", carSource: 8, carTitle: "Song"))
        precondition(SpotifyPlaybackPolicy.usePhonePlayer(connected: true, playing: true, phoneTitle: "Song", carSource: nil, carTitle: ""))
        for code in [2.0,6,12,20,29] { precondition(!SpotifyPlaybackPolicy.usePhonePlayer(connected: true, playing: true, phoneTitle: "Song", carSource: code, carTitle: "Other")) }
        precondition(!SpotifyPlaybackPolicy.usePhonePlayer(connected: false, playing: true, phoneTitle: "Song", carSource: 8, carTitle: "Song"))
        precondition(!SpotifyPlaybackPolicy.usePhonePlayer(connected: true, playing: false, phoneTitle: "Old", carSource: 8, carTitle: "Other"))
        print("PASS: Spotify PKCE RFC vector, Client ID validation, callback state/route/duplicate rejection, exact local phone source selection")
    }
}
