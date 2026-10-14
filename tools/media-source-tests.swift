import Foundation

@main struct MediaSourceTests {
    static func main() {
        precondition(MediaPlaybackSource.resolve(code: 12, sourceName: "").name == "Spotify")
        precondition(MediaPlaybackSource.resolve(code: 8, sourceName: "Spotify").icon == .bluetooth, "Delayed detail must not turn Bluetooth into Spotify")
        precondition(MediaPlaybackSource.resolve(code: 20, sourceName: "Spotify").icon == .tidal)
        precondition(MediaPlaybackSource.resolve(code: nil, sourceName: " Apple Music \n").icon == .appleMusic)
        precondition(MediaPlaybackSource.resolve(code: 999, sourceName: "YouTube Music").icon == .youtubeMusic)
        precondition(MediaPlaybackSource.resolve(code: nil, sourceName: "").name == "재생 앱 정보 없음")
        precondition(MediaPlaybackSource.resolve(code: .nan, sourceName: "").icon == .music)
        precondition(MediaPlaybackSource.resolve(code: 12.5, sourceName: "기타 플레이어").name == "기타 플레이어")
        print("PASS: vehicle source identity, stale detail priority, unsupported/missing source and app name normalization")
    }
}
