import SwiftUI

/// Sheet/editor summaries must read their local draft or filtered rows, never global vehicle data.
struct LocalBriefingControls: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let summary: () -> [String]
    var body: some View {
        HStack(spacing: 8) {
            Button {
                let lines = summary().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                model.speak(lines.isEmpty ? "요약할 자료가 아직 없습니다." : lines.joined(separator: " "))
            } label: { Label("현재 내용 요약", systemImage: "waveform").frame(minHeight: 44) }
                .accessibilityLabel("\(title) 요약 듣기").accessibilityIdentifier("briefing.play.\(title)")
            Button { model.stopSpeech() } label: { Image(systemName: "stop.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("브리핑 중지")
        }.buttonStyle(.borderless).font(.subheadline.weight(.semibold)).lineLimit(1)
    }
}
