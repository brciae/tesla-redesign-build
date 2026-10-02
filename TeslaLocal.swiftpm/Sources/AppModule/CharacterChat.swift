import SwiftUI

/// v1.27: the running character as an in-app assistant. A floating avatar opens a chat;
/// answers use the vehicle's current state and are spoken with the selected Typecast voice.
struct CharacterChatMessage: Identifiable, Equatable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

@MainActor
final class CharacterChat: ObservableObject {
    @Published var presented = false
    @Published var messages: [CharacterChatMessage] = [CharacterChatMessage(fromUser: false, text: "안녕하세요! 차량 상태, 충전, 운행 기록 무엇이든 물어보세요.")]
    @Published var busy = false
    private var task: Task<Void, Never>?

    func send(_ raw: String, model: AppModel) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        messages.append(CharacterChatMessage(fromUser: true, text: text))
        busy = true
        CharacterReact.send("think")
        task = Task { [weak self] in
            let answer = await Self.answer(text, history: self?.messages ?? [], model: model)
            guard let self, !Task.isCancelled else { return }
            self.messages.append(CharacterChatMessage(fromUser: false, text: answer))
            self.busy = false
            CharacterReact.send("talk")
            model.voice.say(answer, key: "character.chat", category: "", priority: 3, ttl: 30, manual: true)
        }
    }
    func cancel() { task?.cancel(); busy = false }

    /// Vehicle facts handed to the model; the same text answers locally when no AI key is registered.
    private static func context(_ model: AppModel) -> String {
        [BriefingScope.home, .charging, .battery, .trips, .location]
            .map { model.screenBriefing($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func answer(_ question: String, history: [CharacterChatMessage], model: AppModel) async -> String {
        let facts = context(model)
        let provider = AutomationAPIProvider(rawValue: UserDefaults.standard.string(forKey: "automationAPI.provider") ?? "") ?? .openAI
        let modelID = UserDefaults.standard.string(forKey: "automationAPI.model." + provider.rawValue) ?? ""
        if AutomationAPI.key(provider) != nil, !modelID.isEmpty {
            let recent = history.suffix(8).map { ($0.fromUser ? "사용자: " : "도우미: ") + $0.text }.joined(separator: "\n")
            let prompt = """
            너는 테슬라 Model YL 차주의 앱 속 캐릭터 도우미다. 한국어 존댓말로 2~3문장, 음성으로 읽기 좋게 답한다.
            아래 차량 데이터에 있는 사실만 말하고, 모르면 모른다고 말한다. 숫자와 단위는 그대로 쓴다. 마크다운·이모지 금지.
            [차량 데이터]
            \(facts.isEmpty ? "수신된 데이터 없음" : facts)
            [대화]
            \(recent)
            """
            do {
                let reply = try await AutomationAPI.generate(provider: provider, model: modelID, prompt: prompt)
                let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return String(clean.prefix(600)) }
            } catch {
                return "AI 연결에 실패했어요. " + error.localizedDescription
            }
        }
        // No AI service registered: answer from the briefing that matches the question.
        let q = question
        let scope: BriefingScope =
            q.contains("충전") ? .charging :
            q.contains("배터리") || q.contains("잔량") ? .battery :
            q.contains("운행") || q.contains("주행") || q.contains("기록") ? .trips :
            q.contains("어디") || q.contains("위치") ? .location : .home
        let text = model.screenBriefing(scope)
        return text.isEmpty ? "아직 차량 데이터를 받지 못했어요. 차량 연결 후 다시 물어봐 주세요." : text
    }
}

/// v1.36: floating 3D character over the main tabs. Tap → chat, drag → move (position remembered).
/// It reacts to app events through CharacterReact (vehicle command result, charging, chat).
struct CharacterChatButton: View {
    @ObservedObject var chat: CharacterChat
    @AppStorage("characterChat.enabled") private var enabled = true
    @AppStorage("characterFloat.x") private var savedX = 0.0
    @AppStorage("characterFloat.y") private var savedY = 0.0
    @AppStorage("characterFloat.scale") private var scale = 1.0
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var bubble: String?
    @State private var bubbleToken = UUID()
    var body: some View {
        if enabled {
            Group {
                if CharacterRig.shared.available {
                    Character3DView(speedKmh: 0, clipOverride: "idle", interactive: false, yaw: 0.25, ambient: true)
                        .frame(width: 84 * liveScale, height: 132 * liveScale)
                        .background(Circle().fill(Color.white.opacity(0.0001)))
                } else {
                    ZStack {
                        Circle().fill(.white).shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.title2).foregroundStyle(.blue)
                    }.frame(width: 60, height: 60)
                }
            }
            .overlay(Rectangle().fill(Color.white.opacity(0.001))) // SwiftUI catches taps/drags above the 3D view
            .contentShape(Rectangle())
            .offset(x: savedX + drag.width, y: savedY + drag.height)
            .gesture(DragGesture(minimumDistance: 8)
                .updating($drag) { v, s, _ in s = v.translation }
                .onEnded { v in savedX += v.translation.width; savedY += v.translation.height })
            // v1.40: pinch to resize (also adjustable in 설정 → 캐릭터 크기).
            .simultaneousGesture(MagnificationGesture()
                .updating($pinch) { v, s, _ in s = v }
                .onEnded { v in scale = Self.clamp(scale * Double(v)) })
            .onTapGesture { CharacterReact.send("wave"); chat.presented = true }
            // v1.37: speech bubble above the character for whatever the app says out loud.
            .overlay(alignment: .topTrailing) {
                if let bubble {
                    Text(bubble)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .offset(x: savedX + drag.width - 20, y: savedY + drag.height - 12)
                        .alignmentGuide(.top) { d in d[.bottom] }
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                        .onTapGesture { withAnimation { self.bubble = nil } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CharacterReact.speech)) { n in
                guard let text = n.object as? String else { return }
                let token = UUID(); bubbleToken = token
                withAnimation(.spring(response: 0.3)) { bubble = text }
                CharacterReact.send("talk")
                let seconds = min(12, max(3.5, Double(text.count) * 0.12))
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { if bubbleToken == token { withAnimation { bubble = nil } } }
            }
            .accessibilityElement()
            .accessibilityLabel("캐릭터 도우미와 대화")
            .accessibilityAddTraits(.isButton)
        }
    }
    private var liveScale: CGFloat { CGFloat(Self.clamp(scale * Double(pinch))) }
    static func clamp(_ s: Double) -> Double { min(2.2, max(0.6, s.isFinite ? s : 1)) }
}

struct CharacterChatView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var chat: CharacterChat
    @State private var draft = ""
    @FocusState private var focused: Bool
    private let suggestions = ["지금 배터리 얼마야?", "충전 상태 알려줘", "최근 운행 요약해줘", "차 어디 있어?"]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            if CharacterRig.shared.available {
                                Character3DView(speedKmh: 0, clipOverride: "idle", yaw: 0)
                                    .frame(height: 240).padding(.top, 8)
                            } else if let img = CharacterAtlas.shared?.portrait {
                                Image(uiImage: img).resizable().scaledToFit().frame(height: 220)
                                    .padding(.top, 8)
                            }
                            ForEach(chat.messages) { m in bubble(m).id(m.id) }
                            if chat.busy {
                                HStack { ProgressView(); Text("생각 중…").font(.footnote).foregroundStyle(.secondary); Spacer() }
                                    .padding(.horizontal, 16).id("busy")
                            }
                        }.padding(.vertical, 8)
                    }
                    .onChange(of: chat.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { chat.send(s, model: model) }
                                .font(.footnote).buttonStyle(.bordered).disabled(chat.busy)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.vertical, 6)
                HStack(spacing: 8) {
                    TextField("메시지 입력", text: $draft, axis: .vertical)
                        .lineLimit(1...4).focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        chat.send(draft, model: model); draft = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
                    .accessibilityLabel("보내기")
                }
                .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 4)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("캐릭터 도우미")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { chat.cancel(); model.voice.stop(); chat.presented = false } }
            }
        }
    }
    private func bubble(_ m: CharacterChatMessage) -> some View {
        HStack {
            if m.fromUser { Spacer(minLength: 40) }
            Text(m.text)
                .font(.body)
                .foregroundStyle(m.fromUser ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(m.fromUser ? Color.blue : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .textSelection(.enabled)
            if !m.fromUser { Spacer(minLength: 40) }
        }.padding(.horizontal, 16)
    }
}
