import SwiftUI

/// Continuous battery fill, independent of text formatting and SF Symbol step sizes.
struct BatteryGauge: View {
    let level: Double?
    var width: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var valid: Double? { guard let level, level.isFinite, (0...100).contains(level) else { return nil }; return level }
    private var tint: Color { guard let value = valid else { return .gray }; return value <= 20 ? .red : value <= 50 ? .yellow : .green }
    var body: some View {
        HStack(spacing: width * 0.04) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: width * 0.09).strokeBorder(tint.opacity(0.8), lineWidth: width * 0.055)
                RoundedRectangle(cornerRadius: width * 0.035)
                    .fill(tint)
                    .frame(width: max(0, (width * 0.84 - width * 0.16) * CGFloat((valid ?? 0) / 100)), height: width * 0.30)
                    .padding(.leading, width * 0.08)
                if valid == nil { Text("?").font(.system(size: width * 0.28, weight: .bold)).foregroundStyle(.gray).frame(maxWidth: .infinity) }
            }.frame(width: width * 0.84, height: width * 0.46)
            RoundedRectangle(cornerRadius: width * 0.035).fill(tint.opacity(0.8)).frame(width: width * 0.07, height: width * 0.20)
        }.frame(width: width, height: width * 0.50)
            .animation(reduced ? nil : .easeOut(duration: 0.3), value: valid)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(valid.map { "배터리 \(Int($0))퍼센트" } ?? "배터리 미수신")
    }
}
