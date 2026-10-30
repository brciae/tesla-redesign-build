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
