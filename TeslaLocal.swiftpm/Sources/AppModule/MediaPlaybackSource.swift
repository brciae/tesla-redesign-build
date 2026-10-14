import Foundation

/// Vehicle-reported playback source. Bluetooth identifies the transport, not the phone app.
struct MediaPlaybackSource: Equatable {
    enum Icon: Equatable { case spotify, appleMusic, youtubeMusic, tidal, bluetooth, radio, music, browser }
    let name: String
    let icon: Icon

    static func resolve(code: Double?, sourceName: String) -> Self {
        // Tesla vehicle.proto MediaSourceType. Known codes take precedence over delayed detail packets.
        if let code, code.isFinite, code.rounded() == code {
            switch code {
            case 0: return .init(name: "재생 앱 정보 없음", icon: .music)
            case 1: return .init(name: "AM", icon: .radio)
            case 2: return .init(name: "FM", icon: .radio)
            case 3, 19: return .init(name: "SiriusXM", icon: .radio)
            case 5: return .init(name: "Slacker", icon: .music)
            case 6, 16: return .init(name: "USB", icon: .music)
            case 7: return .init(name: "iPod", icon: .music)
            case 8: return .init(name: "Bluetooth", icon: .bluetooth)
            case 9: return .init(name: "AUX", icon: .music)
            case 10: return .init(name: "DAB", icon: .radio)
            case 11: return .init(name: "Rdio", icon: .music)
            case 12: return .init(name: "Spotify", icon: .spotify)
            case 13, 14, 24, 25: return .init(name: "라디오", icon: .radio)
            case 17: return .init(name: "TuneIn", icon: .radio)
            case 18: return .init(name: "Stingray", icon: .music)
            case 20: return .init(name: "TIDAL", icon: .tidal)
            case 21, 22: return .init(name: "QQ Music", icon: .music)
            case 23: return .init(name: "Ximalaya", icon: .music)
            case 26: return .init(name: "NetEase Music", icon: .music)
            case 28: return .init(name: "브라우저", icon: .browser)
            default: break
            }
        }
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "spotify": return .init(name: "Spotify", icon: .spotify)
        case "applemusic", "애플뮤직": return .init(name: "Apple Music", icon: .appleMusic)
        case "youtubemusic", "유튜브뮤직": return .init(name: "YouTube Music", icon: .youtubeMusic)
        case "tidal": return .init(name: "TIDAL", icon: .tidal)
        case "bluetooth", "블루투스": return .init(name: "Bluetooth", icon: .bluetooth)
        case "fm", "am", "radio", "라디오": return .init(name: name, icon: .radio)
        default: return .init(name: name.isEmpty ? "재생 앱 정보 없음" : name, icon: .music)
        }
    }
}
