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
            Button { model.aiRules.draft = nil; model.aiRules.presented = true } label: {
                Image(systemName: "plus.circle.fill").font(.title).accessibilityLabel("자동화 만들기")
            }
        } }
        .sheet(item: $editor) { r in AutomationRuleEditor(store: store, initial: r) { editor = nil } }
        .onChange(of: voiceEnabled) { _, value in if !value { model.voice.stopAutomatic() } }
    }
    /// v34: counts first, history one tap away — no log dump on the page.
    private var summary: some View {
        let active = store.rules.filter(\.enabled).count
        return InfoCard {
            CardTitle(title: "자동화 상태", systemImage: "bolt.circle.fill",
                      info: "앱이 켜져 있고 차량 상태를 받는 동안 실행함. 탑승 인사는 BLE 또는 Fleet의 새 탑승·문 상태로 확인하며, Fleet 조회 간격만큼 늦을 수 있음. 자동 공조는 별도 BLE 인증이 필요함. 앱 종료 중에는 탑승 인사를 실행하지 않음.")
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
                if rules.isEmpty { Caption("＋에서 원하는 자동화를 입력하면 앱 안에서 규칙을 생성합니다.") }
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
                    if [.boarding, .chargingLocked].contains(rule.trigger) { Picker("동작", selection: $rule.action) { ForEach(AutomationAction.allCases.filter { rule.trigger == .chargingLocked ? [.speech, .sentryOn].contains($0) : $0 != .sentryOn }) { Text($0.title).tag($0) } } }
                    else { Text("음성 안내") }
                    if rule.action == .temperature { Stepper("목표 \(valueText(rule.targetC, digits: 1))°C", value: $rule.targetC, in: 16...28, step: 0.5) }
                    if rule.action != .speech {
                        Caption(rule.action == .climateOn ? "차량에 설정된 목표 온도로 공조를 켬. 목표 온도 변경을 함께 전송하지 않음." : "이 규칙에 지정한 명령 한 개만 전송함.")
                        Caption(rule.trigger == .chargingLocked ? "충전·잠금 최신 상태 확인 후 감시 모드를 한 번 요청합니다. 앱이 열려 있고 Fleet 명령 연결이 필요합니다." : "활성화 후 다음 탑승에 공조 명령 한 개를 요청합니다. 차량 신호·인증이 없으면 실행하지 않습니다.")
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
                        if rule.action != .speech { rule.vehicle = model.fleet.selectedVin.isEmpty ? model.settings.string("vin") : model.fleet.selectedVin }
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

/// Generation only creates an inactive draft; saving and enabling stay explicit.
final class AutomationAI: ObservableObject {
    @Published var presented = false
    @Published var draft: AutomationRule?
    @Published var status = ""
    @Published var busy = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false; status = "생성 취소됨" }
    func receive(_ url: URL, vehicle: String) { status = "외부 AI 연결은 API 등록 방식으로 변경되었습니다." }
    func generate(provider: AutomationAPIProvider, model: String, request: String, vehicle: String) {
        guard !busy else { return }
        let token = UUID(); generation = token
        busy = true; status = "규칙 생성 중…"
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.busy = false } }
            do {
                let prompt = try AutomationTransfer.prompt(request)
                let result = try await AutomationAPI.generate(provider: provider, model: model, prompt: prompt)
                try Task.checkCancellation()
                guard vehicle == TeslaFleetClient.shared.selectedVin || (TeslaFleetClient.shared.selectedVin.isEmpty && vehicle == (UserDefaults.standard.string(forKey: "vin") ?? "")) else { throw AutomationAPI.failure("차량이 변경되었습니다. 다시 생성해 주세요.") }
                self.draft = try AutomationTransfer.decode(result, vehicle: vehicle)
                self.status = "생성 완료 · 조건과 동작을 검토한 후 저장하세요."
            } catch is CancellationError { if self.generation == token { self.status = "생성 취소됨" } }
            catch { if self.generation == token { self.status = error.localizedDescription } }
        }
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
    @AppStorage("automationAPI.provider") private var provider = AutomationAPIProvider.openAI.rawValue
    @State private var request = "충전 중 차량이 잠기면 감시 모드를 켜 줘."
    @State private var modelID = ""
    @State private var apiKey = ""
    @State private var registered = false
    @State private var connectionExpanded = false
    private var selected: AutomationAPIProvider { AutomationAPIProvider(rawValue: provider) ?? .openAI }
    var body: some View {
        if let draft = ai.draft {
            AutomationRuleEditor(store: store, initial: draft) { ai.draft = nil; ai.presented = false }
        } else {
            NavigationStack {
                Form {
                    LocalBriefingControls(title: "자동화 만들기") { ["\(provider) API로 규칙을 생성합니다.", ai.status] }
                    Section("원하는 자동화") {
                        TextField("언제, 어떤 동작을 할까요?", text: $request, axis: .vertical).lineLimit(4...8)
                        Button("충전 중 잠기면 감시 모드 켜기") { request = "충전 중 차량이 잠기면 감시 모드를 켜 줘." }
                        Button("탑승하면 공조 켜기") { request = "탑승하면 공조를 켜 줘." }
                        Caption("조건과 동작을 문장으로 입력하세요. 지원하지 않는 요청은 이유를 표시합니다.")
                    }
                    Section("AI 연결") {
                        Picker("API 서비스", selection: $provider) { ForEach(AutomationAPIProvider.allCases) { Text($0.rawValue).tag($0.rawValue) } }.disabled(ai.busy)
                        DisclosureGroup(registered ? "API 등록됨 · 연결 설정" : "API 등록", isExpanded: $connectionExpanded) {
                            TextField("모델 ID (예: \(selected.exampleModel))", text: $modelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField(registered ? "새 API 키로 변경" : "API 키", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("연결 설정 저장") {
                                do {
                                    guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AutomationAPI.failure("모델 ID를 입력해 주세요.") }
                                    if !apiKey.isEmpty { try AutomationAPI.saveKey(apiKey, provider: selected) }
                                    guard AutomationAPI.key(selected) != nil else { throw AutomationAPI.failure("API 키를 입력해 주세요.") }
                                    UserDefaults.standard.set(modelID, forKey: "automationAPI.model." + provider)
                                    apiKey = ""; registered = true; connectionExpanded = false; ai.status = "API 등록 완료"
                                } catch { ai.status = error.localizedDescription }
                            }.disabled(ai.busy)
                            if registered { Button("등록한 API 키 삭제", role: .destructive) { AutomationAPI.removeKey(selected); registered = false; ai.status = "API 키 삭제됨" }.disabled(ai.busy) }
                        }
                        Caption("API 키는 기기에 보안 저장됩니다. 직접 입력한 요청만 선택한 서비스로 전송하며 차량 키·위치·운행 기록은 첨부하지 않습니다. API 사용료는 해당 서비스에서 별도로 부과됩니다.")
                    }
                    Section {
                        Button {
                            model.stopSpeech()
                            let vin = model.fleet.selectedVin.isEmpty ? model.settings.string("vin") : model.fleet.selectedVin
                            ai.generate(provider: selected, model: modelID, request: request, vehicle: vin)
                        } label: { Label(ai.busy ? "생성 중…" : "앱에서 자동화 생성", systemImage: "sparkles") }
                        .disabled(ai.busy || !registered || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.count > 1200 || modelID.isEmpty)
                        if ai.busy { ProgressView(); Button("생성 취소") { ai.cancel() } }
                        if !ai.status.isEmpty { Text(ai.status).font(.callout) }
                        Caption("생성된 규칙은 검토 화면에서 조건·동작을 확인한 뒤 저장합니다.")
                    }
                }
                .navigationTitle("자동화 만들기")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { ai.cancel(); dismiss() } } }
            }.onAppear { load() }.onChange(of: provider) { _, _ in load() }.onDisappear { if ai.draft == nil { ai.cancel() } }
        }
    }
    private func load() {
        apiKey = ""; modelID = UserDefaults.standard.string(forKey: "automationAPI.model." + provider) ?? selected.exampleModel
        registered = AutomationAPI.key(selected) != nil; connectionExpanded = !registered
    }
}
