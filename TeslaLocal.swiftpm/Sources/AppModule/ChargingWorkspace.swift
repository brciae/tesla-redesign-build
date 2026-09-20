import SwiftUI
import Combine

/// A high-tech, dedicated full-screen charging dashboard that automatically appears
/// when the vehicle is actively charging or when tapped by the user.
struct ChargingWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @State private var targetLimit: Double = 80
    @State private var isStoppingCharge = false

    var body: some View {
        let p = homePresentation(model, link)
        let c = p.object("charge")
        let soc = c.number("soc") ?? 41
        let chargerKW = c.number("chargerKW") ?? 0
        let minutesToLimit = c.number("minutesToLimit")
        let addedKWh = c.number("addedKWh") ?? 0
        let rangeKm = c.number("rangeKm") ?? 0
        let isSupercharger = chargerKW > 45

        ZStack {
            // High-tech dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header Bar
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(isSupercharger ? Color.cyan : Color.green)
                            .font(.headline)
                        Text(isSupercharger ? "슈퍼차저 급속 충전" : "완속 충전 중")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.12))
                    )

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Big Glowing Battery Gauge
                ZStack {
                    // Pulsing ambient glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (isSupercharger ? Color.cyan : Color.green).opacity(pulseOpacity * 0.4),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 130
                            )
                        )
                        .scaleEffect(pulseScale)
                        .frame(width: 240, height: 240)

                    // Track Ring
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 14)
                        .frame(width: 200, height: 200)

                    // Progress Ring
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1.0, max(0.0, soc / 100.0))))
                        .stroke(
                            LinearGradient(
                                colors: isSupercharger ? [.cyan, .blue] : [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(.easeOut(duration: 0.8), value: soc)

                    // Center Info
                    VStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(isSupercharger ? Color.cyan : Color.green)

                        Text("\(Int(soc))")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            + Text("%").font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.7))

                        if let min = minutesToLimit, min > 0 {
                            Text("완충까지 약 \(min)분")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            Text("충전 완료")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.green)
                        }
                    }
                }
                .padding(.vertical, 10)

                // 4-Card Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(
                        title: "충전 전력",
                        value: "\(Int(chargerKW))",
                        unit: "kW",
                        icon: "bolt.circle.fill",
                        tint: isSupercharger ? .cyan : .green
                    )
                    MetricCard(
                        title: "충전된 전력량",
                        value: String(format: "%.1f", addedKWh),
                        unit: "kWh",
                        icon: "battery.100.bolt",
                        tint: .mint
                    )
                    MetricCard(
                        title: "주행 가능 거리",
                        value: "\(Int(rangeKm))",
                        unit: "km",
                        icon: "arrow.forward.circle.fill",
                        tint: .blue
                    )
                    MetricCard(
                        title: "충전 속도",
                        value: "\(Int(chargerKW * 5.2))",
                        unit: "km/h",
                        icon: "speedometer",
                        tint: .purple
                    )
                }
                .padding(.horizontal, 20)

                // Charge Curve Visualization Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("실시간 충전 추이", systemImage: "chart.xyaxis.line")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("실시간 반영 중")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Charge Curve Waveform
                    ChargeCurveWave(soc: soc, power: chargerKW)
                        .frame(height: 55)
                        .padding(.vertical, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                Spacer()

                // Tesla Official App Action Buttons
                HStack(spacing: 14) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isStoppingCharge.toggle()
                        let action = isStoppingCharge ? "chargeStart" : "chargeStop"
                        link.askControl(action, title: isStoppingCharge ? "충전 시작" : "충전 중지")
                    } label: {
                        HStack {
                            Image(systemName: isStoppingCharge ? "play.fill" : "pause.fill")
                            Text(isStoppingCharge ? "충전 시작" : "충전 중지")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isStoppingCharge ? Color.green : Color.red.opacity(0.85))
                        )
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        link.askControl("portOpen", title: "충전 포트 잠금 해제")
                    } label: {
                        HStack {
                            Image(systemName: "lock.open.fill")
                            Text("포트 잠금 해제")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if !reduced {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                    pulseOpacity = 0.9
                }
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct ChargeCurveWave: View {
    let soc: Double
    let power: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                path.move(to: CGPoint(x: 0, y: h * 0.85))
                path.addCurve(
                    to: CGPoint(x: w * 0.5, y: h * 0.35),
                    control1: CGPoint(x: w * 0.25, y: h * 0.75),
                    control2: CGPoint(x: w * 0.35, y: h * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.15),
                    control1: CGPoint(x: w * 0.65, y: h * 0.35),
                    control2: CGPoint(x: w * 0.85, y: h * 0.2)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [.green.opacity(0.4), .cyan, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            // Fill area under curve
            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h * 0.85))
                path.addCurve(
                    to: CGPoint(x: w * 0.5, y: h * 0.35),
                    control1: CGPoint(x: w * 0.25, y: h * 0.75),
                    control2: CGPoint(x: w * 0.35, y: h * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.15),
                    control1: CGPoint(x: w * 0.65, y: h * 0.35),
                    control2: CGPoint(x: w * 0.85, y: h * 0.2)
                )
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.18), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
