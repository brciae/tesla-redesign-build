import SwiftUI

struct BrandLaunchArtwork: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Image("LaunchLogo").resizable().scaledToFit().frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityHidden(true)
                Text("YL Companion").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(.black)
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("YL Companion 시작")
            .accessibilityIdentifier("app.launch.brand")
    }
}

/// One cold-start transition per window. Background returns never replay it.
struct BrandLaunchContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showing = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            content()
            if showing { BrandLaunchArtwork().allowsHitTesting(false).transition(.opacity) }
        }
        .task {
            // Short, cancellable branding; never wait for Bluetooth, network or account readiness.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { showing = false; return }
            withAnimation(.easeOut(duration: reducedMotion ? 0.12 : 0.25)) { showing = false }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { showing = false } }
    }
}
