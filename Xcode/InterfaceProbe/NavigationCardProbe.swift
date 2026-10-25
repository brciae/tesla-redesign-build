import SwiftUI
import AVFoundation

struct NavigationCardProbe: View {
    @State private var kind = 0
    @State private var stale = false
    @State private var ended = false
    @State private var audioStatus = "혼합 검사 대기"
    @ObservedObject private var pip = NavigationPictureInPicture.shared
    @State private var state = VehicleActivityAttributes.ContentState(connected: false, guiding: true,
        destination: "회사", instruction: "포곡로132번길 비보호 좌회전", remainingMinutes: 5, batteryPercent: nil,
        observedAt: Date(), turnSymbol: "arrow.turn.up.left", turnMetres: 150, arrivalAt: Date().addingTimeInterval(300),
        nextInstruction: "우회전", nextTurnSymbol: "arrow.turn.up.right", nextTurnMetres: 295,
        remainingMetres: 1300, routeProgress: 0.35, laneCount: 3, laneSuggested: [1,2], speedLimit: 30, speedLimitMetres: 181)
    var body: some View {
        VStack(spacing: 14) {
            Picker("카드", selection: $kind) { Text("잠금화면").tag(0); Text("플로팅").tag(1) }.pickerStyle(.segmented)
            if kind == 0 {
                if !ended { VehicleNavigationCard(state: state, stale: stale).background(.white, in: RoundedRectangle(cornerRadius: 20)) }
                else { Text("안내 종료됨") }
            } else {
                NavigationPipSource(manager: pip).frame(width: 360, height: 210).accessibilityIdentifier("navigation.pip.source")
                Text(pip.status).accessibilityIdentifier("navigation.pip.status")
                Text("프레임 전달 \(pip.renderedFrames)").accessibilityIdentifier("navigation.pip.frames")
                Button("플로팅 안내 시작") { pip.start() }
            }
            Button("다음 안내 수신") {
                stale = false; state.observedAt = Date(); state.turnMetres = 611; state.turnSymbol = "arrow.turn.up.right"
                state.instruction = "용인시청 우회전"; state.nextTurnMetres = 517; state.nextTurnSymbol = "arrow.turn.up.left"
                state.remainingMinutes = 4; state.remainingMetres = 1400; publish()
            }
            Button("수신 중단") { stale = true; state.observedAt = Date().addingTimeInterval(-60); publish() }
            Button("안내 종료") { ended = true; state.guiding = false; publish() }
            Button("음성·음악 혼합 확인") {
                do {
                    try VoiceAudioRouting.activateFloatingGuidance(force: true)
                    let defaults = UserDefaults(suiteName: "YLProbe.AudioLease")!
                    defaults.set("auto", forKey: "voiceOutput"); defaults.set(true, forKey: "voiceDuck")
                    try VoiceAudioRouting.activate(defaults, owner: "probeSpeech")
                    VoiceAudioRouting.release(owner: "probeSpeech")
                    let session = AVAudioSession.sharedInstance()
                    audioStatus = session.category == .playback && session.categoryOptions.contains(.mixWithOthers) && !session.categoryOptions.contains(.duckOthers) ? "음성 종료 후 음악 혼합 유지" : "음성 혼합 상태 확인 필요"
                    if !pip.active { VoiceAudioRouting.release(owner: "navigation.pip") }
                    defaults.removePersistentDomain(forName: "YLProbe.AudioLease")
                } catch { audioStatus = "혼합 검사 실패" }
            }
            Text(audioStatus).font(.caption).accessibilityIdentifier("navigation.pip.audio")
            Spacer()
        }.padding().background(Color.gray.opacity(0.15))
            .onAppear { publish() }.onChange(of: kind) { _, _ in publish() }
            .onDisappear { state.guiding = false; publish() }
    }
    private func publish() { pip.update(state, enabled: true) }
}
