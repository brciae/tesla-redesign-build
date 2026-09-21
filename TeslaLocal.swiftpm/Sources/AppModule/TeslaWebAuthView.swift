import SwiftUI
import WebKit
import CryptoKit

/// Tesla official web OAuth authentication sheet.
/// Uses standard PKCE Authorization Code flow on `auth.tesla.com`.
/// Intercepts the callback without showing the void 404 page, exchanges the authorization code
/// for Bearer access and refresh tokens, and securely stores them in the iOS Keychain.
struct TeslaWebAuthView: View {
    @ObservedObject var fleet: TeslaFleetClient
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var codeVerifier = ""

    var onLoginSuccess: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                if let authURL = makeAuthURL() {
                    TeslaOAuthWebView(
                        url: authURL,
                        codeVerifier: codeVerifier,
                        fleet: fleet,
                        isLoading: $isLoading,
                        errorMessage: $errorMessage,
                        onSuccess: {
                            onLoginSuccess?()
                            dismiss()
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("테슬라 공식 로그인 화면 불러오는 중…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground).opacity(0.85))
                }

                if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("로그인 처리 실패")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("다시 시도") {
                            self.errorMessage = nil
                            self.isLoading = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle("테슬라 공식 계정 로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }

    private func makeAuthURL() -> URL? {
        if codeVerifier.isEmpty {
            codeVerifier = Self.randomString(length: 64)
        }
        let challenge = Self.codeChallenge(from: codeVerifier)
        let state = Self.randomString(length: 16)
        var components = URLComponents(string: "https://auth.tesla.com/oauth2/v3/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: "ownerapi"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: "https://auth.tesla.com/void/callback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email offline_access vehicle_device_data vehicle_cmds"),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    static func randomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

struct TeslaOAuthWebView: UIViewRepresentable {
    let url: URL
    let codeVerifier: String
    @ObservedObject var fleet: TeslaFleetClient
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TeslaOAuthWebView

        init(_ parent: TeslaOAuthWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.absoluteString.starts(with: "https://auth.tesla.com/void/callback") {
                decisionHandler(.cancel)
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    exchangeCode(code)
                } else {
                    DispatchQueue.main.async {
                        self.parent.errorMessage = "인가 코드를 찾을 수 없습니다."
                    }
                }
                return
            }
            decisionHandler(.allow)
        }

        private func exchangeCode(_ code: String) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }

            let tokenURL = URL(string: "https://auth.tesla.com/oauth2/v3/token")!
            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let params: [String: String] = [
                "grant_type": "authorization_code",
                "client_id": "ownerapi",
                "code": code,
                "code_verifier": parent.codeVerifier,
                "redirect_uri": "https://auth.tesla.com/void/callback"
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: params)
            } catch {
                DispatchQueue.main.async {
                    self.parent.errorMessage = "요청 생성 실패: \(error.localizedDescription)"
                    self.parent.isLoading = false
                }
                return
            }

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async {
                        self.parent.errorMessage = "토큰 요청 네트워크 오류: \(error.localizedDescription)"
                        self.parent.isLoading = false
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async {
                        self.parent.errorMessage = "토큰 응답 파싱 실패"
                        self.parent.isLoading = false
                    }
                    return
                }

                if let err = json["error"] as? String {
                    let desc = json["error_description"] as? String ?? err
                    DispatchQueue.main.async {
                        self.parent.errorMessage = "테슬라 인증 실패: \(desc)"
                        self.parent.isLoading = false
                    }
                    return
                }

                guard let accessToken = json["access_token"] as? String else {
                    DispatchQueue.main.async {
                        self.parent.errorMessage = "토큰 정보가 응답에 없습니다."
                        self.parent.isLoading = false
                    }
                    return
                }

                let refreshToken = json["refresh_token"] as? String
                DispatchQueue.main.async {
                    self.parent.fleet.saveToken(accessToken: accessToken, refreshToken: refreshToken)
                    Task {
                        _ = try? await self.parent.fleet.fetchVehicles()
                    }
                    self.parent.isLoading = false
                    self.parent.onSuccess()
                }
            }.resume()
        }
    }
}
