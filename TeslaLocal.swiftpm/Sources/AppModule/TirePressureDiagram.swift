import SwiftUI

/// A single pressure presentation for BLE, Fleet snapshots and the NAS archive.
///
/// v90: the 270pt interior photo and the four per-wheel timestamps are gone. A
/// tyre card is read at a glance — four numbers on a car outline — so the photo
/// was carrying no information the numbers did not already carry, and repeating
/// the same reception time four times pushed the values apart for nothing. The
/// newest of the four timestamps is now one caption on the title row.
struct TirePressureDiagram: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject private var telemetry = FleetTelemetryStore.shared
    private var vin: String { model.fleet.selectedVin.isEmpty ? model.settings.string("vin") : model.fleet.selectedVin }
    private func sample(_ index: Int) -> TirePressureSample? {
        var candidates: [TirePressureSample] = []
        if model.settings.string("vin") == vin {
            let group = model.groups.object("tire")
            let values = group["values"] as? [Any] ?? []
            if let at = group.number("at"), values.indices.contains(index) {
                candidates.append(TirePressureSample(bar: (values[index] as? NSNumber)?.doubleValue, at: Date(timeIntervalSince1970: at / 1000)))
            }
        }
        if let snapshot = model.fleet.vehicleSnapshot, snapshot.vin == vin,
           let at = snapshot.number("vehicle_state", "timestamp"),
           let section = snapshot.payload["vehicle_state"] as? Object,
           let raw = section["tpms_pressure_" + ["fl", "fr", "rl", "rr"][index]] {
            candidates.append(TirePressureSample(bar: (raw as? NSNumber)?.doubleValue, at: Date(timeIntervalSince1970: at / 1000)))
        }
        if let reading = telemetry.latest(vin: vin)[["TpmsPressureFl", "TpmsPressureFr", "TpmsPressureRl", "TpmsPressureRr"][index]] {
            candidates.append(TirePressureSample(bar: reading.invalid ? nil : reading.number, at: reading.at))
        }
        return TirePressureSample.newest(candidates)
    }

    /// The single time the card reports: the newest reading behind any wheel.
    private var receivedAt: Date? { (0..<4).compactMap { sample($0)?.at }.max() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("타이어 공기압").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(receivedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "미수신")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            HStack(spacing: 14) {
                VStack(spacing: 26) { wheel(0); wheel(2) }
                CarOutline().stroke(Color.white.opacity(0.28), lineWidth: 1.2).frame(width: 52, height: 104)
                VStack(spacing: 26) { wheel(1); wheel(3) }
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("fleet.tires")
            Text("주행 직후에는 공기압이 높게 나올 수 있음").font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    /// Value on top, corner label under it — the number is what the eye needs first.
    private func wheel(_ index: Int) -> some View {
        let reading = sample(index)
        let parts = units.displayParts(reading?.validBar, suffix: "bar")
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.0)
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(reading?.validBar == nil ? Theme.muted : .white)
                Text(parts.1.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Text(["앞 왼쪽", "앞 오른쪽", "뒤 왼쪽", "뒤 오른쪽"][index])
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(width: 72)
        .accessibilityElement(children: .combine)
    }
}

/// A top-down car silhouette: a body that narrows at the front, a windscreen and
/// rear screen, and a wheel outside each corner beside the number that belongs
/// to it.
///
/// v91: the first version was a plain rounded rectangle with two lines across it,
/// and the simulator screenshot showed exactly that — a pill, not a car. The
/// narrower nose gives it a front, and the four wheels sitting outside the body
/// are what make the corner mapping read without the labels carrying it alone.
private struct CarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let noseIn = w * 0.22, tailIn = w * 0.10
        let shoulder = h * 0.16, hip = h * 0.84
        var body = Path()
        body.move(to: CGPoint(x: rect.minX + noseIn, y: rect.minY))
        body.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + shoulder),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        body.addLine(to: CGPoint(x: rect.minX, y: rect.minY + hip))
        body.addQuadCurve(to: CGPoint(x: rect.minX + tailIn, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        body.addLine(to: CGPoint(x: rect.maxX - tailIn, y: rect.maxY))
        body.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + hip),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        body.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + shoulder))
        body.addQuadCurve(to: CGPoint(x: rect.maxX - noseIn, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        body.closeSubpath()

        var path = body
        let screenInset = w * 0.16
        for y in [rect.minY + h * 0.30, rect.maxY - h * 0.22] {
            path.move(to: CGPoint(x: rect.minX + screenInset, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - screenInset, y: y))
        }
        let wheelW = w * 0.13, wheelH = h * 0.14
        for y in [rect.minY + h * 0.19, rect.maxY - h * 0.19 - wheelH] {
            for x in [rect.minX - wheelW, rect.maxX] {
                path.addRoundedRect(in: CGRect(x: x, y: y, width: wheelW, height: wheelH),
                                    cornerSize: CGSize(width: wheelW * 0.4, height: wheelW * 0.4))
            }
        }
        return path
    }
}
