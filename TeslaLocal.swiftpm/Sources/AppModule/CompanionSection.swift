import SwiftUI

struct CompanionSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// Used by production screens and their interface test target.
func dateText(_ ms: Double?, time: Bool = true) -> String { guard let ms else { return "미수신" }; let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = time ? "M월 d일 HH:mm" : "yyyy.MM.dd"; return f.string(from: Date(timeIntervalSince1970: ms/1000)) }
