import SwiftUI
import AuthenticationServices
import Security
import SpotifyiOS

/// Spotify owns the audio session and Bluetooth output. This object controls metadata only.
final class SpotifyPlayback: NSObject, ObservableObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyPlayback()
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var playing = false
    @Published private(set) var artwork: UIImage?
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0
    @Published private(set) var status = "연결 안 됨"
    private var trackURI = ""
    private var remote: SPTAppRemote?
    private var authentication: ASWebAuthenticationSession?
    private var request: UUID?
    private var exchanging = false
    private var observers: [NSObjectProtocol] = []
    private let service = "local.ylcompanion.spotify"
    var clientID: String { UserDefaults.standard.string(forKey: "spotify.clientID") ?? SpotifyPlaybackPolicy.defaultClientID }
    var authorized: Bool { token("refresh") != nil }

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.reconnect() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.remote?.playerAPI?.delegate = nil
            self?.remote?.disconnect(); self?.connected = false; self?.clearPlayback()
            if self?.authentication == nil && self?.exchanging != true { self?.working = false }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func saveClientID(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != clientID else { return }
        disconnect()
        UserDefaults.standard.set(clean, forKey: "spotify.clientID")
        status = SpotifyPlaybackPolicy.validClientID(clean) ? "계정 연결 필요" : "32자리 Client ID 확인 필요"
    }
    func connect() {
        guard !working else { return }
        guard SpotifyPlaybackPolicy.validClientID(clientID) else { status = "Spotify 개발자 앱의 Client ID 필요"; return }
        guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else { status = "Spotify 앱 설치 필요"; return }
        if authorized { reconnect(); return }
        let verifier = UUID().uuidString + UUID().uuidString
        let state = UUID().uuidString
        let id = UUID(); request = id; working = true
        let cid = clientID
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [URLQueryItem(name: "client_id", value: cid), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyPlaybackPolicy.redirect), .init(name: "scope", value: "app-remote-control"),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: SpotifyPlaybackPolicy.challenge(verifier)),
            .init(name: "state", value: state)]
        authentication = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "ylcompanion") { [weak self] callback, _ in
            DispatchQueue.main.async {
                guard let self, self.request == id else { return }
                self.authentication = nil
                guard let callback, let code = SpotifyPlaybackPolicy.callbackCode(callback, state: state) else {
                    self.working = false; self.status = "연결 취소 또는 인증 응답 확인 필요"; return
                }
                self.exchange(["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
                               "redirect_uri": SpotifyPlaybackPolicy.redirect, "client_id": cid], request: id)
            }
        }
        authentication?.presentationContextProvider = self
        if authentication?.start() != true { authentication = nil; working = false; status = "로그인 창을 열지 못함" }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func reconnect() {
        guard UIApplication.shared.applicationState == .active, !working, !connected,
              SpotifyPlaybackPolicy.validClientID(clientID), let refresh = token("refresh") else { return }
        let expires = Double(token("expires") ?? "") ?? 0
        if expires > Date().timeIntervalSince1970 + 60, let access = token("access") { attach(access); return }
        working = true
        let id = UUID(); request = id
        exchange(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID], request: id)
    }
    private func exchange(_ values: [String: String], request id: UUID) {
        exchanging = true
        var body = URLComponents(); body.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.request == id else { return }
                self.exchanging = false
                self.working = false
                let code = (response as? HTTPURLResponse)?.statusCode
                guard error == nil, code == 200, let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = object["access_token"] as? String, !access.isEmpty,
                      let seconds = object["expires_in"] as? Double, (1...86400).contains(seconds) else {
                    self.status = code == 400 ? "계정 연결을 다시 진행해 주세요" : "인증 서버 연결 대기"
                    if code == 400 { self.clearTokens() }
                    return
                }
                let refresh = object["refresh_token"] as? String ?? self.token("refresh")
                guard let refresh, !refresh.isEmpty,
                      self.saveToken("refresh", refresh), self.saveToken("access", access),
                      self.saveToken("expires", String(Date().timeIntervalSince1970 + seconds)) else {
                    self.clearTokens(); self.status = "인증 저장 실패 · 앱 서명 확인 필요"; return
                }
                self.attach(access)
            }
        }.resume()
    }
    private func attach(_ access: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        if remote == nil {
            remote = SPTAppRemote(configuration: SPTConfiguration(clientID: clientID, redirectURL: URL(string: SpotifyPlaybackPolicy.redirect)!), logLevel: .none)
            remote?.delegate = self
        }
        remote?.connectionParameters.accessToken = access
        status = "Spotify 연결 중"; working = true
        remote?.connect()
    }
    func disconnect() {
        request = nil; authentication?.cancel(); authentication = nil; exchanging = false
        remote?.delegate = nil; remote?.disconnect(); remote = nil
        clearTokens(); connected = false; working = false; clearPlayback(); status = "연결 해제됨"
    }
    private func clearPlayback() { title = ""; artist = ""; playing = false; artwork = nil; trackURI = ""; duration = 0; position = 0 }
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        guard appRemote === remote else { return }
        connected = true; working = false; status = "이 iPhone의 Spotify와 연결됨"
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if error != nil { DispatchQueue.main.async { self?.status = "재생 정보 구독 실패"; self?.connected = false; self?.clearPlayback() } }
        })
        appRemote.playerAPI?.getPlayerState({ [weak self] result, _ in
            if let state = result as? SPTAppRemotePlayerState { self?.playerStateDidChange(state) }
        })
    }
    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        guard appRemote === remote else { return }
        connected = false; working = false; clearPlayback(); status = "Spotify에서 음악 재생 후 다시 연결"
    }
    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        guard appRemote === remote else { return }
        connected = false; working = false; clearPlayback(); status = "Spotify 연결 대기"
    }
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        guard connected else { return }
        title = playerState.track.name; artist = playerState.track.artist.name
        playing = !playerState.isPaused; duration = Double(playerState.track.duration) / 1000
        position = Double(playerState.playbackPosition) / 1000
        let uri = playerState.track.uri
        guard trackURI != uri else { return }
        trackURI = uri; artwork = nil
        remote?.imageAPI?.fetchImage(forItem: playerState.track, with: CGSize(width: 160, height: 160), callback: { [weak self] image, _ in
            DispatchQueue.main.async { if self?.connected == true, self?.trackURI == uri { self?.artwork = image as? UIImage } }
        })
    }
    func command(_ action: String) {
        guard connected, !working, let api = remote?.playerAPI else { return }
        working = true
        let done: SPTAppRemoteCallback = { [weak self] _, error in
            DispatchQueue.main.async { self?.working = false; if error != nil { self?.status = "Spotify 재생 제어 실패" } }
        }
        switch action {
        case "mediaToggle": if playing { api.pause(done) } else { api.resume(done) }
        case "mediaNext": api.skip(toNext: done)
        case "mediaPrev": api.skip(toPrevious: done)
        default: working = false
        }
    }
    private func token(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func saveToken(_ key: String, _ value: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let data = Data(value.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = query; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    private func clearTokens() { for key in ["access", "refresh", "expires"] {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    } }
}

struct SpotifySettingsView: View {
    @ObservedObject private var spotify = SpotifyPlayback.shared
    @State private var clientID = ""
    var body: some View {
        Form {
            Section("Spotify") {
                Text(spotify.status).accessibilityIdentifier("spotify.status")
                Button(spotify.connected ? "연결됨" : spotify.authorized ? "다시 연결" : "계정 연결") { spotify.saveClientID(clientID); spotify.connect() }
                    .disabled(spotify.working || spotify.connected || !SpotifyPlaybackPolicy.validClientID(clientID))
                    .accessibilityIdentifier("spotify.connect")
                Link("Spotify 열기", destination: URL(string: "spotify:")!)
                if spotify.authorized { Button("연결 해제", role: .destructive) { spotify.disconnect() } }
                Text("블루투스 출력을 유지하며 곡·앨범아트·재생 제어를 연동함.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
              DisclosureGroup("연동 설정") {
                TextField("Client ID · 32자리", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("spotify.clientID")
                Text("계정 이메일·사용자 ID가 아닌 개발자 앱의 Client ID 필요. 비밀번호와 Client Secret은 입력하지 않음.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Spotify 개발자 대시보드", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                LabeledContent("Redirect URI") { Text(SpotifyPlaybackPolicy.redirect).font(.caption).textSelection(.enabled) }
                LabeledContent("Bundle ID") { Text(Bundle.main.bundleIdentifier ?? "확인 필요").font(.caption).textSelection(.enabled) }
                Text("개발자 앱에 iOS SDK·Bundle ID 등록 필요. 첫 연결에는 인터넷 필요.")
                    .font(.caption).foregroundStyle(.secondary)
              }
            }
            if !spotify.title.isEmpty { Section("현재 재생") {
                HStack { if let art = spotify.artwork { Image(uiImage: art).resizable().scaledToFit().frame(width: 64, height: 64) }
                    VStack(alignment: .leading) { Text(spotify.title); Text(spotify.artist).font(.caption) }
                }
            } }
        }.navigationTitle("Spotify 연결").onAppear { clientID = spotify.clientID; spotify.reconnect() }
    }
}
