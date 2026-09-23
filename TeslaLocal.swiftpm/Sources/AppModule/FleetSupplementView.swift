import SwiftUI

struct FleetSupplementView: View {
    @ObservedObject var fleet: TeslaFleetClient
    let kind: FleetSupplement
    @State private var result: FleetSupplementResult?
    @State private var error = ""
    @State private var busy = false
    @State private var search = ""
    private var cards: [FleetSupplementCard] {
        guard result?.vin == fleet.selectedVin else { return [] }
        return (result?.cards ?? []).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.rows.contains { $0.value.localizedCaseInsensitiveContains(search) } }
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
                    ForEach(cards) { card in
                        InfoCard {
                            Label(card.title, systemImage: kind == .nearbyCharging || kind == .chargingHistory ? "bolt.fill" : "car.fill").font(.headline)
                            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top) {
                                    Text(row.label).foregroundStyle(Theme.muted)
                                    Spacer(minLength: 16)
                                    Text(row.value).multilineTextAlignment(.trailing)
                                }.font(.subheadline)
                            }
                        }
                    }
                    if cards.isEmpty { ContentUnavailableView("표시할 기록 없음", systemImage: "tray", description: Text("조회한 범위에 표시할 기록이 없습니다.")) }
                } else { Caption("필요할 때 직접 조회합니다. 계정 권한이나 차량 지원에 따라 제공 범위가 다를 수 있습니다.") }
            }.padding(16)
        }.background(Theme.bg).navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
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
