import SwiftUI

/// InfoNote renders EmptyView to keep all cards clean and free from developer disclaimers.
struct InfoNote: View {
    let title: String
    let text: String

    init(_ title: String = "설명", _ text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        EmptyView()
    }
}

/// Card header: icon and title in clean modern iOS design.
struct CardTitle: View {
    let title: String
    var systemImage: String? = nil
    var info: String? = nil
    var infoTitle: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
        }
    }
}

/// Charts draw in with a left-to-right wipe and a soft fade the first time they appear.
struct ChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
            }
            .opacity(0.35 + 0.65 * Double(progress))
            .onAppear {
                guard progress < 1 else { return }
                if reduceMotion { progress = 1 } else { withAnimation(.smooth(duration: 1.1).delay(0.08)) { progress = 1 } }
            }
    }
}
extension View { func chartReveal() -> some View { modifier(ChartReveal()) } }
