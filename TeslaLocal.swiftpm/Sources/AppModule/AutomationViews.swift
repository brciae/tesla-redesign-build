import SwiftUI
import UniformTypeIdentifiers

struct AutomationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View { AutomationDashboard(store: model.automations) }
}
private struct AutomationDashboard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.selectAppTab) private var selectTab
    @AppStorage("voiceAutomations") private var voiceEnabled = true
    @ObservedObject var store: AutomationCoordinator
    @State private var editor: AutomationRule?
    @State private var importing = false
    var body: some View {
        PageBody(title: "자동화", briefing: .automation) {
            summary
            rulesSection("내가 만든 룰", rules: store.rules.filter { !$0.id.hasPrefix("builtin.") })
            rulesSection("기본 안내", rules: store.rules.filter { $0.id.hasPrefix("builtin.") })
            InfoCard {
                CardTitle(title: "자동화 설정", systemImage: "gearshape",
                          info: "한 번 탑승 시 한 규칙의 명령 한 개만 전송함. 중복 제어는 건너뛰며 수신 불가·앱 종료·백그라운드에서는 실행하지 않음. 공조는 활성 규칙만 탑승당 1회 실행하고, 카메라·과속 안내는 카카오 내비 설정에서 변경함.")
                Toggle("자동화 규칙의 음성 안내", isOn: $voiceEnabled)
                NavigationLink("안내 음성 설정", value: Page.preferences)
                NavigationLink("알림 설정", value: Page.notifications)
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("룰 추가", systemImage: "square.and.pencil") { editor = AutomationRule(name: "새 자동화", trigger: .boarding, enabled: false) }
                Button("AI로 만들기", systemImage: "sparkles") { model.aiRules.presented = true }
                Button("가져오기", systemImage: "square.and.arrow.down") { importing = true }
            } label: { Image(systemName: "plus.circle.fill").font(.title).accessibilityLabel("자동화 추가") }
        } }
        .sheet(item: $editor) { r in AutomationRuleEditor(store: store, initial: r) { editor = nil } }
        .sheet(isPresented: $importing) { AutomationImportView(store: store) }
        .onChange(of: voiceEnabled) { _, value in if !value { model.voice.stopAutomatic() } }
    }
    /// v34: counts first, history one tap away — no log dump on the page.
    private var summary: some View {
        let active = store.rules.filter(\.enabled).count
        return InfoCard {
            CardTitle(title: "자동화 상태", systemImage: "bolt.circle.fill",
                      info: "규칙은 앱이 켜져 있고 차량과 연결된 동안에만 실행됨. 상태 문구는 블루투스 연결·탑승 감지 결과이며, 실행 내역에서 각 규칙이 언제 동작했는지 확인할 수 있음.")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(active)").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text("/ \(store.rules.count)개 규칙 활성").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            Caption(store.presence + " · " + store.status)
            NavigationLink { AutomationHistory(store: store) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("실행 내역").font(.subheadline.weight(.semibold))
                        Text(store.logs.first?.status ?? "아직 실행된 규칙 없음").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
        }
    }

    private func rulesSection(_ title: String, rules: [AutomationRule]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(title) (\(rules.count))").font(.headline).foregroundStyle(Theme.muted)
            InfoCard {
                if rules.isEmpty { Caption("＋에서 조건·동작을 정하거나 AI로 규칙을 만들 수 있음.") }
                ForEach(rules) { r in
                    HStack(spacing: 12) {
                        Button {
                            model.voice.preview(AutomationPolicy.previewText(for: r, hour: Calendar.current.component(.hour, from: Date())))
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .frame(width: 32, height: 32)
                                .background(Color.cyan.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(r.name) 음성 테스트")

                        Button { editor = r } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(r.name).font(.headline)
                                Text(r.trigger.detail).font(.caption).foregroundStyle(Theme.muted)
                                if r.action != .speech { Text(r.action.title).font(.caption).foregroundStyle(.cyan) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Toggle(r.name, isOn: Binding(get: { r.enabled }, set: { store.enable(r.id, $0) }))
                            .labelsHidden()
                            .tint(.cyan)

                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted).accessibilityHidden(true)
                    }
                    .padding(.vertical, 6)
                    if r.id != rules.last?.id { Divider() }
                }
            }
        }
    }
}
struct AutomationRuleEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: AutomationCoordinator
    @State private var rule: AutomationRule
    @State private var error = ""
    @State private var deleting = false
    let done: () -> Void
    init(store: AutomationCoordinator, initial: AutomationRule, done: @escaping () -> Void) { self.store = store; _rule = State(initialValue: initial); self.done = done }
    var body: some View {
        NavigationStack {
            Form {
                LocalBriefingControls(title: "자동화 편집") {
                    var lines = ["\(rule.name). \(rule.enabled ? "활성" : "비활성") 설정입니다.", "조건은 \(rule.trigger.title), 동작은 \(rule.action.title)입니다."]
                    if rule.trigger == .batteryLow { lines.append("잔량 \(Int(rule.threshold))퍼센트 이하입니다.") }
                    if [.rest, .remaining, .delay].contains(rule.trigger) { lines.append("기준 \(Int(rule.threshold))분입니다.") }
                    if rule.trigger == .tireLow && rule.customTireThreshold { lines.append("공기압 \(rule.threshold)바 미만입니다.") }
                    if rule.cabinCondition != "always" { lines.append("실내 \(rule.cabinThresholdC)도 \(rule.cabinCondition == "above" ? "이상" : "이하") 조건입니다.") }
                    if rule.action == .temperature { lines.append("목표 온도 \(rule.targetC)도입니다.") }
                    if rule.hoursEnabled { lines.append("\(rule.startHour)시부터 \(rule.endHour)시까지 적용됩니다.") }
                    lines.append("최소 반복 간격 \(rule.cooldownMinutes)분. 저장 전 편집 내용입니다.")
                    return lines
                }
                if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                Section("이름·조건") {
                    TextField("규칙 이름", text: $rule.name)
                    Toggle("이 규칙 활성화", isOn: $rule.enabled)
                    Picker("언제", selection: $rule.trigger) { ForEach(AutomationTrigger.allCases) { Text($0.title).tag($0) } }
                    Caption(rule.trigger.detail)
                    if rule.trigger == .batteryLow { Stepper("잔량 \(Int(rule.threshold))% 이하", value: $rule.threshold, in: 1...100, step: 1) }
                    if [.rest, .remaining, .delay].contains(rule.trigger) { Stepper("기준 \(Int(rule.threshold))분", value: $rule.threshold, in: 1...300, step: 1) }
                    if rule.trigger == .tireLow {
                        Toggle("직접 정한 압력 기준도 사용", isOn: $rule.customTireThreshold)
                        if rule.customTireThreshold { Stepper("\(valueText(rule.threshold, digits: 2)) bar 미만", value: $rule.threshold, in: 1...4, step: 0.05); Caption("차량 권장 냉간 압력을 참고해 직접 설정함. 표시는 다른 단위로 바꿔도 이 기준의 원단위는 bar임.") }
                    }
                }
                Section("실행할 동작") {
                    if rule.trigger == .boarding { Picker("동작", selection: $rule.action) { ForEach(AutomationAction.allCases) { Text($0.title).tag($0) } } }
                    else { Text("음성 안내") }
                    if rule.action == .temperature { Stepper("목표 \(valueText(rule.targetC, digits: 1))°C", value: $rule.targetC, in: 16...28, step: 0.5) }
                    if rule.action != .speech {
                        Caption(rule.action == .climateOn ? "차량에 설정된 목표 온도로 공조를 켬. 목표 온도 변경을 함께 전송하지 않음." : "이 규칙에 지정한 명령 한 개만 전송함.")
                        Caption("활성화하면 다음 새 탑승 확인 시 현재 등록 차량에 자동 요청함. 신호·인증이 없으면 건너뛰며 이후 재연결 때 재전송하지 않음. 차 문·트렁크·잠금 자동 제어는 지원하지 않음.")
                    }
                    Picker("실내 온도 조건", selection: $rule.cabinCondition) { Text("제한 없음").tag("always"); Text("이상일 때").tag("above"); Text("이하일 때").tag("below") }
                    if rule.cabinCondition != "always" { Stepper("실내 \(valueText(rule.cabinThresholdC, digits: 1))°C", value: $rule.cabinThresholdC, in: -20...60, step: 0.5) }
                }
                Section("안내 음성") {
                    Toggle("음성 안내", isOn: $rule.speech)
                    Toggle("시간대에 맞는 인사 추가", isOn: $rule.timeGreeting)
                    TextField("비워두면 기본 안내", text: $rule.message, axis: .vertical).lineLimit(3...6)
                    Caption("변수: {인사} · {배터리} · {목적지}. 알 수 없는 값은 미확인으로 안내함.")
                    VoicePreviewControls(previewTitle: "음성만 미리 듣기", preview: {
                        model.voice.preview(AutomationPolicy.previewText(for: rule, hour: Calendar.current.component(.hour, from: Date())))
                    }, stop: { model.stopSpeech() })
                    VoiceStatus(voice: model.voice)
                    Caption("예시 데이터로 음성만 재생 · 차량 명령 없음.")
                }
                Section("시간·반복") {
                    Toggle("시간대 제한", isOn: $rule.hoursEnabled)
                    if rule.hoursEnabled {
                        Picker("시작", selection: $rule.startHour) { ForEach(0..<24, id: \.self) { Text("\($0)시").tag($0) } }
                        Picker("종료", selection: $rule.endHour) { ForEach(0..<25, id: \.self) { Text("\($0)시").tag($0) } }
                        Caption("22시~7시처럼 자정을 넘는 조건 가능. 시작·종료가 같으면 제한 없음.")
                    }
                    Stepper("최소 반복 간격 \(rule.cooldownMinutes)분", value: $rule.cooldownMinutes, in: 1...1440)
                    Caption("간격이 지나도 새 이벤트 조건이 맞아야 실행함. 탑승 규칙은 문 열림·비탑승·새 탑승이 다시 관측되어야 함.")
                }
                Section {
                    ShareLink("규칙 JSON 공유", item: (try? AutomationTransfer.encode(rule)) ?? "")
                    if store.rules.contains(where: { $0.id == rule.id }), !rule.id.hasPrefix("builtin.") { Button("이 규칙 삭제", role: .destructive) { deleting = true } }
                }
            }.navigationTitle("자동화 편집").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소", action: done) }
                    ToolbarItem(placement: .confirmationAction) { Button("저장") {
                        if rule.action != .speech { rule.vehicle = model.settings.string("vin") }
                        do { try store.save(rule); done() } catch { self.error = error.localizedDescription }
                    } }
                }
                .onChange(of: rule.trigger) { _, value in
                    rule.action = .speech
                    if let preset = AutomationRule.defaults.first(where: { $0.trigger == value }) { rule.threshold = preset.threshold }
                }
                .confirmationDialog("이 규칙을 삭제할지 확인", isPresented: $deleting) { Button("삭제", role: .destructive) { do { try store.remove(rule.id); done() } catch { self.error = error.localizedDescription } } }
        }
    }
}
private struct AutomationHistory: View {
    @ObservedObject var store: AutomationCoordinator
    var body: some View {
        List {
            LocalBriefingControls(title: "자동화 실행 내역") {
                Array(store.logs.prefix(3)).map { "\($0.rule): \($0.status). \($0.message)" }
            }
            if store.logs.isEmpty { Text("아직 실행된 규칙 없음") }
            ForEach(store.logs) { log in VStack(alignment: .leading, spacing: 7) { Text(log.rule).font(.headline); Text(log.message); Text(log.status).foregroundStyle(Theme.muted); Text(Date(timeIntervalSince1970: log.at), style: .date).font(.caption); Text(Date(timeIntervalSince1970: log.at), style: .time).font(.caption) } }
        }.navigationTitle("실행 내역 · 최근 80건")
    }
}
private struct AutomationImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AutomationCoordinator
    @State private var text = ""
    @State private var error = ""
    @State private var draft: AutomationRule?
    @State private var picker = false
    var body: some View {
        NavigationStack { Form {
            LocalBriefingControls(title: "규칙 가져오기") { [text.isEmpty ? "가져올 내용 미입력." : "입력 내용 검토 전입니다.", error.isEmpty ? "" : "검사 오류: \(error)"] }
            Caption("YL 자동화 JSON 한 개를 가져옴. 테파일럿 원본 가져오기는 형식이 확인되지 않아 지원하지 않음. 가져온 규칙은 꺼진 상태이며 검토·저장 후 직접 켜야 함.")
            TextEditor(text: $text).frame(minHeight: 180).font(.system(.caption, design: .monospaced))
            PasteButton(payloadType: String.self) { values in text = String((values.first ?? "").prefix(32768)) }
            Button("JSON 파일 선택") { picker = true }
            Button("내용 검토") { do { draft = try AutomationTransfer.decode(text, vehicle: model.settings.string("vin")) } catch { self.error = error.localizedDescription } }
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
        }.navigationTitle("규칙 가져오기").toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.json, .plainText]) { result in
                do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 32768 else { throw AutomationError.invalid }
                    text = try String(contentsOf: url, encoding: .utf8)
                } catch { self.error = error.localizedDescription }
            }.sheet(item: $draft) { r in AutomationRuleEditor(store: store, initial: r) { draft = nil; dismiss() } }
    }
}

/// Subscription apps execute on the iPhone via a user-configured system Shortcut.
/// The URL callback is one-use, expires, and can only produce an inactive review draft.
final class AutomationAI: ObservableObject {
    @Published var presented = false
    @Published var draft: AutomationRule?
    @Published var status = ""
    func start(provider: String, request: String, vehicle: String) {
        do {
            let prompt = try AutomationTransfer.prompt(request)
            let name = UserDefaults.standard.string(forKey: "automationShortcut." + provider) ?? "YL 자동화 " + provider
            let request = AutomationCallback(nonce: UUID().uuidString, expires: Date().timeIntervalSince1970 + 1200)
            guard let url = request.shortcutURL(name: name, prompt: prompt) else { throw AutomationError.invalid }
            let d = UserDefaults.standard
            d.set(request.nonce, forKey: "automationAI.nonce"); d.set(request.expires, forKey: "automationAI.expires"); d.set(vehicle, forKey: "automationAI.vehicle")
            status = "단축어 응답 대기 · 취소·실패 시 차량 동작 없음"
            UIApplication.shared.open(url) { [weak self] ok in if !ok { DispatchQueue.main.async { self?.clear(); self?.status = "단축어 앱을 열지 못함 · 연결 설정 확인 필요" } } }
        } catch { status = error.localizedDescription }
    }
    private func clear() { for key in ["nonce", "expires", "vehicle"] { UserDefaults.standard.removeObject(forKey: "automationAI." + key) } }
    func receive(_ url: URL, vehicle: String) {
        let d = UserDefaults.standard
        guard let nonce = d.string(forKey: "automationAI.nonce"), let result = AutomationCallback(nonce: nonce, expires: d.double(forKey: "automationAI.expires")).accept(url, now: Date().timeIntervalSince1970) else { return }
        let sameVehicle = d.string(forKey: "automationAI.vehicle") == vehicle
        clear(); presented = true
        guard sameVehicle else { status = "요청 중 차량 프로필 변경 · 결과 적용 안 함"; return }
        guard result.status == "success" else { status = result.status == "cancel" ? "AI 생성 취소됨" : "단축어 실행 실패 · 이름·AI 로그인·입력/출력 연결 확인 필요"; return }
        do { draft = try AutomationTransfer.decode(result.text, vehicle: vehicle); status = "AI 응답 수신 · 검토 후 저장 필요" }
        catch { status = "AI 결과가 지원 규칙 형식과 다름 · 자동 실행·저장 없음" }
    }
}
struct AutomationAIHost: ViewModifier {
    @ObservedObject var ai: AutomationAI
    let store: AutomationCoordinator
    func body(content: Content) -> some View { content.sheet(isPresented: $ai.presented) { AutomationAIView(ai: ai, store: store) } }
}
private struct AutomationAIView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ai: AutomationAI
    let store: AutomationCoordinator
    @AppStorage("automationAI.provider") private var provider = "Claude"
    @State private var request = "아침 6시부터 10시 사이에 탑승하면 시간대 인사와 함께 공조 켜기를 요청해 줘."
    @State private var shortcut = ""
    @State private var installed = false
    var body: some View {
        if let draft = ai.draft {
            AutomationRuleEditor(store: store, initial: draft) { ai.draft = nil; ai.presented = false }
        } else {
            NavigationStack { Form {
                LocalBriefingControls(title: "AI로 자동화 만들기") { ["선택 AI는 \(provider)입니다.", installed && !shortcut.isEmpty ? "단축어 설정 확인됨." : "단축어 준비 확인 필요.", ai.status] }
                Section("AI 선택") {
                    Picker("생성에 사용할 AI", selection: $provider) { Text("Claude").tag("Claude"); Text("ChatGPT").tag("ChatGPT"); Text("Gemini").tag("Gemini") }
                    Caption("PC·API 키·별도 유료 API 없이 iPhone의 AI 앱·단축어를 사용함. 선택한 AI에 직접 쓴 요청과 공개 규칙 형식만 전달함. 차량 키·VIN·운행 기록은 보내지 않음. 구독 한도가 적용되며 AI 앱의 추가 과금 옵션은 사용하지 않아야 함.")
                }
                Section("만들고 싶은 자동화") {
                    TextField("조건과 원하는 동작", text: $request, axis: .vertical).lineLimit(4...8)
                    Caption("AI가 조건을 잘못 해석할 수 있으므로 결과를 확인해야 함. 저장 이후 규칙 실행에는 AI나 PC가 필요하지 않음.")
                }
                Section("최초 연결 · 아이폰에서 한 번 설정") {
                    if provider == "Claude" {
                        Text("1. Claude 앱에 구독 계정으로 로그인\n2. 단축어 앱에서 새 단축어 생성\n3. ‘Ask Claude’의 메시지에 ‘단축어 입력’ 변수 지정\n4. 마지막 동작 ‘중단 및 출력’에 Claude 응답 지정\n5. 아래 이름으로 저장")
                        Caption("공식 iOS 18 이상 App Intent 사용. Claude 앱 기본 모델을 사용하며 구독 사용량에 포함됨. iOS 권한 확인 화면이 표시될 수 있음.")
                    } else if provider == "ChatGPT" {
                        Text("단축어에 ChatGPT 앱의 질문 동작이 있으면 입력을 ‘단축어 입력’으로 연결하고 결과를 ‘중단 및 출력’으로 전달함. 지원 기기에서는 Apple Intelligence의 ‘모델 사용 → 확장 모델 ChatGPT’ 경로도 가능함.")
                        Caption("Apple Intelligence의 ChatGPT 계정 연결 또는 ChatGPT 앱 로그인이 필요함. 이 기기에 노출되는 단축어 동작·응답 반환을 먼저 확인해야 함. Codex PC 중계를 사용하지 않음.")
                    } else {
                        Caption("Gemini 구독 앱의 요청·응답 단축어 연결은 아직 확인되지 않음. 지금은 프롬프트 복사 후 Gemini에서 만든 JSON을 ‘가져오기’로 전달하는 방식만 제공함. API 무료 할당량을 유료 구독 연동으로 표시하지 않음.")
                    }
                    if provider != "Gemini" {
                        TextField("단축어 이름", text: $shortcut)
                        Toggle("위 단축어를 설정했음", isOn: $installed)
                        Button("선택한 AI로 생성") {
                            UserDefaults.standard.set(shortcut, forKey: "automationShortcut." + provider)
                            model.stopSpeech(); ai.start(provider: provider, request: request, vehicle: model.settings.string("vin"))
                        }.disabled(!installed || shortcut.isEmpty || request.isEmpty || request.count > 1200)
                    }
                    Button("요청 프롬프트 복사") { do { UIPasteboard.general.string = try AutomationTransfer.prompt(request); ai.status = "프롬프트 복사됨 · 직접 입력한 요청과 형식만 포함" } catch { ai.status = error.localizedDescription } }
                    Link("선택한 AI 열기", destination: URL(string: provider == "Claude" ? "https://claude.ai/new" : provider == "ChatGPT" ? "https://chatgpt.com/" : "https://gemini.google.com/app")!)
                    if !ai.status.isEmpty { Text(ai.status).font(.caption).foregroundStyle(.orange) }
                }
            }.navigationTitle("AI로 자동화 만들기").toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .onAppear { loadProvider() }.onChange(of: provider) { _, _ in loadProvider() }
                .onChange(of: installed) { _, value in UserDefaults.standard.set(value, forKey: "automationShortcutReady." + provider) }
            }
        }
    }
    private func loadProvider() { shortcut = UserDefaults.standard.string(forKey: "automationShortcut." + provider) ?? "YL 자동화 " + provider; installed = UserDefaults.standard.bool(forKey: "automationShortcutReady." + provider) }
}
