import SwiftUI

struct FleetSupplementView: View {
    @ObservedObject var fleet: TeslaFleetClient
    let kind: FleetSupplement
    @State private var result: FleetSupplementResult?
    @State private var error = ""
    @State private var busy = false
    @State private var search = ""
    private var rows: [FleetInsightRow] {
        guard result?.vin == fleet.selectedVin else { return [] }
        return (result?.rows ?? []).filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Caption(kind.note)
                Button(busy ? "조회 중…" : "자료 조회") { Task { await refresh() } }.disabled(busy)
                if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.orange) }
                if let result, result.vin == fleet.selectedVin {
                    Text("조회 " + result.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.muted)
                    TextField("항목 또는 내용 검색", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(rows, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.label.replacingOccurrences(of: "자료.", with: "")).font(.caption.monospaced()).foregroundStyle(Theme.muted)
                            Text(row.value).font(.subheadline).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if rows.isEmpty { Caption("표시할 항목이 없습니다. 검색어와 응답 내용을 확인해 주세요.") }
                } else { Caption("필요할 때 직접 조회합니다. 계정 권한이나 차량 지원에 따라 제공 범위가 다를 수 있습니다.") }
            }.padding(16)
        }.background(Theme.bg).navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .onChange(of: fleet.selectedVin) { _, _ in result = nil; error = "" }
    }
    @MainActor private func refresh() async {
        guard !busy else { return }
        busy = true; error = ""; result = nil
        defer { busy = false }
        do { result = try await fleet.readSupplement(kind) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
