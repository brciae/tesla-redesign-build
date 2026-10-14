import Foundation

/// Opt-in, bounded phrase selection. AI can select verified text, never vehicle commands or new facts.
final class AutomationContextSpeech {
    private var tasks: [String: Task<Void, Never>] = [:]
    private var tokens: [String: UUID] = [:]
    private var lastRequest = Date.distantPast
    private var recentRoutine: [String: Date] = [:]
    func cancelAll() { tasks.values.forEach { $0.cancel() }; tasks.removeAll(); tokens.removeAll() }
    func resolve(base: String, key: String, context: AutomationSpeechContext, completion: @escaping (String) -> Void) {
        tasks[key]?.cancel(); tasks[key] = nil; tokens[key] = nil
        let d = UserDefaults.standard
        let provider = AutomationAPIProvider.configured(defaults: d)
        let omit = (d.object(forKey: "automationSpeech.skipRoutine") as? Bool) ?? true
        let routine = omit && AutomationSpeechPolicy.canOmitRoutine(base: base, context: context)
        let routineKey = context.scope + ":" + context.trigger + ":" + base
        if routine {
            let now = Date()
            recentRoutine = recentRoutine.filter { now.timeIntervalSince($0.value) < 300 }
            if recentRoutine[routineKey] != nil { completion(""); return }
            recentRoutine[routineKey] = now
            if recentRoutine.count > 64 { recentRoutine.removeAll(); recentRoutine[routineKey] = now }
        }
        guard d.bool(forKey: "automationSpeech.aiEnabled"),
              AutomationAPI.key(provider) != nil,
              let model = d.string(forKey: "automationAPI.model." + provider.rawValue), !model.isEmpty,
              Date().timeIntervalSince(lastRequest) >= 15, tasks.count < 3, base.count <= 1200 else { completion(base); return }
        let options = AutomationSpeechPolicy.options(base: base, context: context, allowRoutineOmission: omit)
        if Set(options).count == 1 { completion(base); return }
        let token = UUID(); tokens[key] = token; lastRequest = Date()
        tasks[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            var text = base
            do {
                let prompt = try AutomationSpeechPolicy.prompt(options: options, context: context)
                let reply = try await AutomationAPI.generate(provider: provider, model: model, prompt: prompt, timeout: 4, maxTokens: 256, retryAllowed: false)
                text = AutomationSpeechPolicy.selected(reply, options: options) ?? base
            } catch { /* A failed selection uses the already verified local text. */ }
            guard !Task.isCancelled, self.tokens[key] == token else { return }
            self.tokens[key] = nil; self.tasks[key] = nil
            completion(text)
        }
    }
}
