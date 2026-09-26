import SwiftUI

/// Read-only, explicit playback: never dispatches a vehicle or automation command.
struct ScreenBriefingControls: View {
    @EnvironmentObject private var model: AppModel
    let scope: BriefingScope
    var compact = false
    var text: (() async -> String)? = nil
    @State private var pending: Task<Void, Never>?
    var body: some View {
        if scope.supportsSpeech {
        HStack(spacing: 8) {
            Button {
                pending?.cancel()
                pending = Task {
                    let result: String
                    if let text { result = await text() } else { result = model.screenBriefing(scope) }
                    guard !Task.isCancelled else { return }
                    model.speak(result)
                }
            } label: {
                if compact { Image(systemName: "waveform").frame(width: 44, height: 44) }
                else { Label("현재 상태 브리핑", systemImage: "waveform").frame(minHeight: 44) }
            }
            .accessibilityLabel("\(scope.rawValue) 현재 상태 브리핑")
            .accessibilityIdentifier("briefing.play.\(scope.rawValue)")
            Button { pending?.cancel(); model.stopSpeech() } label: {
                Image(systemName: "stop.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("브리핑 중지")
        }
        .buttonStyle(.borderless)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        .onDisappear { pending?.cancel() }
        }
    }
}
