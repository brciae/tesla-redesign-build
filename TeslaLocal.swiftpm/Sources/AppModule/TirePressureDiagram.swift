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
                CarOutline().stroke(Color.white.opacity(0.22), lineWidth: 1.2).frame(width: 56, height: 108)
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

/// A plain top-down car silhouette: body, windscreen, rear screen. Enough to say
/// which number belongs to which corner without carrying a photograph.
private struct CarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.width * 0.34, height: rect.width * 0.34))
        let inset = rect.width * 0.17
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + rect.height * 0.26))
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - rect.height * 0.26))
        return path
    }
}
