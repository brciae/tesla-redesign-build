import SwiftUI

struct OfflineMapSettings: View {
    @ObservedObject var navigation: EmbeddedNavigation
    @State private var confirmDownload = false
    @State private var requested = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            let downloaded = navigation.controller?.offlineMapDownloaded == true
            Text(downloaded ? "전체 지도 다운로드 완료" : requested ? "다운로드 요청됨 · 완료 확인 중" : "전체 지도 미다운로드")
            Text(navigation.controller?.offlineMapInUse == true ? "현재 저장 지도 사용 중" : "현재 실시간 지도 사용 중")
                .font(.caption).foregroundStyle(.secondary)
            Button(downloaded ? "전체 지도 업데이트" : "전체 지도 다운로드") { confirmDownload = true }
                .disabled(navigation.controller == nil)
            if requested && !downloaded {
                Button("다운로드 일시 중지") { navigation.controller?.pauseOfflineMapDownload(); requested = false }
            }
            Button("다운로드한 지도 사용") { navigation.controller?.useOfflineMap(true) }
                .disabled(!downloaded || navigation.guiding)
            Button("실시간 지도 사용") { navigation.controller?.useOfflineMap(false) }
                .disabled(navigation.controller == nil || navigation.guiding)
            Text("지도 표시용 저장 기능임. 새 경로 탐색·재탐색과 교통정보에는 통신이 필요할 수 있음. 진행 중인 경로는 통신 소실만으로 종료하지 않음.")
                .font(.caption).foregroundStyle(.secondary)
            if navigation.controller == nil { Text("카카오 지도를 먼저 열어 준비해야 함").font(.caption) }
        }
        .alert("전체 지도 다운로드", isPresented: $confirmDownload) {
            Button("다운로드 시작") { navigation.controller?.downloadOfflineMap(); requested = true }
            Button("취소", role: .cancel) { }
        } message: { Text("대용량 데이터와 저장 공간을 사용할 수 있음. Wi-Fi 연결을 확인한 뒤 시작 필요함.") }
    }
}
