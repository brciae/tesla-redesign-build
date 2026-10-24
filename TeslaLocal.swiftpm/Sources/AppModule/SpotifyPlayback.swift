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
    @Published private(set) var album = ""
    @Published private(set) var playing = false
    @Published private(set) var artwork: UIImage?
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0
    @Published private(set) var status = "연결 안 됨"
    @Published private(set) var connectionIssue = ""
    private var trackURI = ""
    private var artworkRequestAt = Date.distantPast
    private var connectionGeneration = UUID()
    private var commandGeneration = UUID()
    private var remote: SPTAppRemote?
    private var authentication: ASWebAuthenticationSession?
    private var request: UUID?
    private var exchanging = false
    private var wakeAfterAuthorization = false
    private var remoteAuthorizationPending = false
    private var authorizationGeneration = UUID()
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
        // Account authorization alone does not wake the Spotify app. An explicit
        // connect action must complete the SDK app-switch handshake as well.
        if authorized { openSpotifyAndConnect(); return }
        wakeAfterAuthorization = true
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
        guard !remoteAuthorizationPending else { return }
        if wakeAfterAuthorization, authorized, UIApplication.shared.applicationState == .active {
            openSpotifyAndConnect(); return
        }
        guard UIApplication.shared.applicationState == .active, !working, !connected,
              SpotifyPlaybackPolicy.validClientID(clientID), let refresh = token("refresh") else { return }
        if SpotifyPlaybackPolicy.remoteTokenUsable(expires: Double(token("remoteExpires") ?? "") ?? 0, now: Date().timeIntervalSince1970), let access = token("remoteAccess") {
            attach(access); return
        }
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
                if self.wakeAfterAuthorization {
                    if UIApplication.shared.applicationState == .active { self.openSpotifyAndConnect() }
                    else { self.status = "계정 인증 완료 · 앱 복귀 후 Spotify 연결" }
                } else { self.attach(access) }
            }
        }.resume()
    }
    private func configureRemote() {
        if remote == nil {
            remote = SPTAppRemote(configuration: SPTConfiguration(clientID: clientID, redirectURL: URL(string: SpotifyPlaybackPolicy.redirect)!), logLevel: .none)
            remote?.delegate = self
        }
    }
    private func openSpotifyAndConnect() {
        guard UIApplication.shared.applicationState == .active else { wakeAfterAuthorization = true; return }
        wakeAfterAuthorization = false
        connectionGeneration = UUID(); connectionIssue = ""
        remote?.delegate = nil; remote?.disconnect(); remote = nil
        configureRemote()
        remoteAuthorizationPending = true; working = true
        status = "Spotify에서 연결 승인 후 돌아오기"
        let generation = UUID(); authorizationGeneration = generation
        // Spotify's documented iOS handshake wakes its player and returns an SDK
        // token to onOpenURL. Empty URI resumes the current/last track.
        remote?.authorizeAndPlayURI("", completionHandler: { [weak self] opened in
            DispatchQueue.main.async {
                guard let self, self.authorizationGeneration == generation, self.remoteAuthorizationPending, !opened else { return }
                self.remoteAuthorizationPending = false; self.working = false
                self.status = "Spotify를 열지 못함 · 앱 설치 확인 필요"
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.authorizationGeneration == generation, self.remoteAuthorizationPending else { return }
            self.remoteAuthorizationPending = false; self.working = false
            self.status = "Spotify 연결 미완료 · 다시 연결"
        }
    }
    @discardableResult func receive(_ url: URL) -> Bool {
        guard SpotifyPlaybackPolicy.acceptsRemoteCallback(url, pending: remoteAuthorizationPending) else { return false }
        guard let parameters = remote?.authorizationParameters(from: url),
              let access = parameters[SPTAppRemoteAccessTokenKey], !access.isEmpty else {
            remoteAuthorizationPending = false; working = false
            status = "Spotify 연결 승인 실패 · 개발자 앱 설정 확인 필요"
            return true
        }
        remoteAuthorizationPending = false; working = false
        guard saveToken("remoteAccess", access), saveToken("remoteExpires", String(Date().timeIntervalSince1970 + 3600)) else {
            status = "Spotify 인증 저장 실패 · 앱 서명 확인 필요"; return true
        }
        status = "Spotify 승인 완료 · 플레이어 연결 중"
        attach(access) // If callback precedes activation, reconnect() uses the saved token.
        return true
    }
    private func attach(_ access: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        configureRemote()
        remote?.connectionParameters.accessToken = access
        status = "Spotify 연결 중"; working = true
        let generation = UUID(); connectionGeneration = generation
        remote?.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.connectionGeneration == generation, !self.connected, self.working else { return }
            self.remote?.disconnect(); self.working = false
            self.status = "Spotify 연결 시간 초과 · 음악 재생 후 다시 연결"
        }
    }
    func disconnect() {
        wakeAfterAuthorization = false; remoteAuthorizationPending = false; authorizationGeneration = UUID(); connectionGeneration = UUID()
        request = nil; authentication?.cancel(); authentication = nil; exchanging = false
        remote?.delegate = nil; remote?.disconnect(); remote = nil
        clearTokens(); connected = false; working = false; clearPlayback(); status = "연결 해제됨"
    }
    private func clearPlayback() { title = ""; artist = ""; album = ""; playing = false; artwork = nil; trackURI = ""; duration = 0; position = 0; artworkRequestAt = .distantPast }
    func refreshPlayback() {
        guard connected else { reconnect(); return }
        let generation = connectionGeneration
        remote?.playerAPI?.getPlayerState({ [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.connected, self.connectionGeneration == generation else { return }
                if let state = result as? SPTAppRemotePlayerState { self.playerStateDidChange(state) }
                else { self.status = error != nil ? "재생 정보 수신 실패 · 다시 새로고침" : "Spotify 연결됨 · 재생 정보 대기" }
            }
        })
    }
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.appRemoteDidEstablishConnection(appRemote) }; return }
        guard appRemote === remote else { return }
        connected = true; working = false; status = "Spotify 연결됨 · 재생 정보 대기"
        connectionIssue = ""
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if error != nil { DispatchQueue.main.async { self?.status = "재생 정보 구독 실패 · 새로고침 가능" } }
        })
        refreshPlayback()
        // Bounded initial recovery if the first state request races player startup.
        let generation = connectionGeneration
        for delay in [1.0, 3.0, 7.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.connectionGeneration == generation, self.connected, self.title.isEmpty else { return }
                self.refreshPlayback()
            }
        }
    }
    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.appRemote(appRemote, didFailConnectionAttemptWithError: error) }; return }
        guard appRemote === remote else { return }
        if let error = error as NSError? { connectionIssue = "\(error.domain) · \(error.code)" }
        connected = false; working = false; clearPlayback(); status = "Spotify에서 음악 재생 후 다시 연결"
    }
    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.appRemote(appRemote, didDisconnectWithError: error) }; return }
        guard appRemote === remote else { return }
        if let error = error as NSError? { connectionIssue = "\(error.domain) · \(error.code)" }
        connected = false; working = false; clearPlayback(); status = "Spotify 연결 대기"
    }
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.playerStateDidChange(playerState) }; return }
        guard connected else { return }
        status = "재생 정보 수신 중"
        title = playerState.track.name; artist = playerState.track.artist.name; album = playerState.track.album.name
        playing = !playerState.isPaused; duration = Double(playerState.track.duration) / 1000
        position = Double(playerState.playbackPosition) / 1000
        let uri = playerState.track.uri
        let changed = trackURI != uri
        guard changed || (artwork == nil && Date().timeIntervalSince(artworkRequestAt) >= 15) else { return }
        trackURI = uri; if changed { artwork = nil }
        artworkRequestAt = Date()
        remote?.imageAPI?.fetchImage(forItem: playerState.track, with: CGSize(width: 160, height: 160), callback: { [weak self] image, _ in
            DispatchQueue.main.async { if self?.connected == true, self?.trackURI == uri { self?.artwork = image as? UIImage } }
        })
    }
    func command(_ action: String) {
        guard connected, !working, let api = remote?.playerAPI else { return }
        working = true
        let generation = UUID(); commandGeneration = generation
        let connection = connectionGeneration
        let done: SPTAppRemoteCallback = { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.commandGeneration == generation, self.connectionGeneration == connection else { return }
                self.working = false; if error != nil { self.status = "Spotify 재생 제어 실패" }
                self.refreshPlayback()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.commandGeneration == generation, self.connectionGeneration == connection, self.working else { return }
            self.working = false; self.status = "재생 제어 응답 지연 · 다시 연결 가능"
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
    private func clearTokens() { for key in ["access", "refresh", "expires", "remoteAccess", "remoteExpires"] {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    } }
}

struct SpotifySettingsView: View {
    @ObservedObject private var spotify = SpotifyPlayback.shared
    @State private var clientID = ""
    var body: some View {
        Form {
            Section("현재 재생") {
                HStack(spacing: 12) {
                    Group {
                        if let art = spotify.artwork { Image(uiImage: art).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").resizable().scaledToFit().padding(16) }
                    }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spotify.title.isEmpty ? "재생 정보 없음" : spotify.title).font(.headline)
                        if !spotify.artist.isEmpty { Text(spotify.artist).font(.subheadline) }
                        if !spotify.album.isEmpty { Text(spotify.album).font(.caption).foregroundStyle(.secondary) }
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("spotify.nowPlaying")
                HStack {
                    Button { spotify.command("mediaPrev") } label: { Image(systemName: "backward.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("이전 곡")
                    Spacer()
                    Button { spotify.command("mediaToggle") } label: { Image(systemName: spotify.playing ? "pause.fill" : "play.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(spotify.playing ? "일시정지" : "재생")
                    Spacer()
                    Button { spotify.command("mediaNext") } label: { Image(systemName: "forward.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("다음 곡")
                }.buttonStyle(.borderless).disabled(!spotify.connected || spotify.working)
                Button("재생 정보 새로고침") { spotify.refreshPlayback() }.disabled(spotify.working)
            }
            Section("Spotify") {
                Text(spotify.status).accessibilityIdentifier("spotify.status")
                Button(spotify.connected ? "플레이어 다시 연결" : spotify.authorized ? "다시 연결" : "계정 연결") { spotify.saveClientID(clientID); spotify.connect() }
                    .disabled(spotify.working || !SpotifyPlaybackPolicy.validClientID(clientID))
                    .accessibilityIdentifier("spotify.connect")
                Link("Spotify 열기", destination: URL(string: "spotify:")!)
                if spotify.authorized { Button("연결 해제", role: .destructive) { spotify.disconnect() } }
                Text("블루투스 출력을 유지하며 곡·앨범아트·재생 제어를 연동함.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("계정 등록과 플레이어 연결은 별개임. 연결 시 Spotify가 열리며 현재 또는 마지막 곡이 재생될 수 있음.")
                    .font(.caption).foregroundStyle(.secondary)
                if !spotify.connectionIssue.isEmpty { LabeledContent("연결 오류", value: spotify.connectionIssue).font(.caption) }
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
        }.navigationTitle("Spotify 연결").onAppear { clientID = spotify.clientID; spotify.reconnect() }
    }
}
