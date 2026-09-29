import SwiftUI

struct PublicChargingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var region: String
    @State private var key = ""
    @State private var message = ""
    private var registered: Bool { PublicChargingKey.read() != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section("한국환경공단 충전소") {
                    SecureField(registered ? "인증키 변경" : "공공데이터포털 인증키", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    NavigationLink(region.isEmpty ? "조회 지역 · 자동(차량 위치+인접)" : "조회 지역 · " + PublicChargingRegions.summary(region)) { PublicChargingRegionPicker(region: $region) }
                    Text("인증키는 이 기기에 보안 저장됩니다.").font(.caption).foregroundStyle(.secondary)
                }
                if !message.isEmpty { Text(message).foregroundStyle(.orange) }
                Button("저장하고 조회") {
                    do {
                        if !key.isEmpty { try PublicChargingKey.save(key) }
                        guard registered else { message = "인증키를 입력하세요."; return }
                        key = ""; dismiss()
                    } catch { message = error.localizedDescription }
                }.accessibilityIdentifier("charging.api.save")
                Link("공공데이터포털 인증키 확인", destination: URL(string: "https://www.data.go.kr/iim/main/mypageMain.do")!)
            }.navigationTitle("충전소 데이터 연결").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { key = ""; dismiss() } } }
        }
    }
}

struct PublicChargingRegionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var region: String
    @State private var query = ""
    var body: some View {
        List {
            Button { region = "" } label: {
                HStack { Text("자동 · 차량 위치와 인접 지역"); Spacer(); if region.isEmpty { Image(systemName: "checkmark") } }
            }
            if !region.isEmpty { Text("여러 지역을 선택할 수 있습니다 (최대 8곳)").font(.caption).foregroundStyle(.secondary) }
            ForEach(PublicChargingRegions.names.keys.sorted().filter { query.isEmpty || (PublicChargingRegions.names[$0] ?? "").contains(query) }, id: \.self) { code in
            Button {
                var set = region.split(separator: ",").map(String.init)
                if let i = set.firstIndex(of: code) { set.remove(at: i) } else if set.count < 8 { set.append(code) }
                region = set.joined(separator: ",")
            } label: {
                HStack { Text(PublicChargingRegions.names[code] ?? code); Spacer(); if region.split(separator: ",").contains(Substring(code)) { Image(systemName: "checkmark") } }
            }
            }
        }.searchable(text: $query, prompt: "시·군·구 검색").navigationTitle("조회 지역")
    }
}
