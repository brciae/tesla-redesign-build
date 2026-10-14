import SwiftUI

struct ContextSpeechSettings: View {
    @AppStorage("automationSpeech.aiEnabled") private var enabled = false
    @AppStorage("automationSpeech.skipRoutine") private var skipRoutine = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("상황에 맞는 AI 멘트", isOn: $enabled).accessibilityIdentifier("automation.ai.speech")
            if enabled { Toggle("새 정보 없는 일상 인사 줄이기", isOn: $skipRoutine).accessibilityIdentifier("automation.ai.routine") }
            Text("자동화 만들기의 AI 연결 설정을 사용함. 켜면 안내 후보(사용자 멘트 포함)·발생 조건·시간대를 선택한 서비스로 전송함. 차량 식별값·좌표·원본 운행 기록은 전송하지 않음. API 이용료가 발생할 수 있음.")
                .font(.caption).foregroundStyle(.secondary)
            Text("수치·실행 결과는 앱에서 유지함. AI 오류·지연 시 기본 안내, 안전 경고와 방향 안내는 즉시 안내함.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
