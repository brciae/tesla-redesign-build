import SwiftUI

struct ContextSpeechSettings: View {
    @AppStorage("automationSpeech.aiEnabled") private var enabled = false
    @AppStorage("automationSpeech.skipRoutine") private var skipRoutine = true
    var body: some View {
        Group {
            Toggle("상황에 맞는 AI 멘트", isOn: $enabled).accessibilityIdentifier("automation.ai.speech")
            if enabled { Toggle("새 정보 없는 일상 인사 줄이기", isOn: $skipRoutine).accessibilityIdentifier("automation.ai.routine") }
            Text("AI를 켜면 멘트·조건·시간대를 연결한 서비스로 전송함. 좌표·차량 식별값·원본 운행 기록은 제외함. API 비용 별도임.")
                .font(.caption).foregroundStyle(.secondary)
            Caption("AI 응답이 늦으면 기본 안내를 사용함. 안전 경고·방향 안내와 실제 수치는 AI가 변경하지 않음.")
        }
    }
}
