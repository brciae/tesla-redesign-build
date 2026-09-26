import SwiftUI

/// A single pressure presentation for BLE, Fleet snapshots and the NAS archive.
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("타이어 공기압", systemImage: "tirepressure").font(.headline)
            ZStack {
                Image("TeslaYLInterior").resizable().scaledToFit().frame(height: 270).accessibilityHidden(true)
                VStack {
                    HStack { wheel(0); Spacer(); wheel(1) }
                    Spacer()
                    HStack { wheel(2); Spacer(); wheel(3) }
                }.padding(.vertical, 18)
            }.frame(height: 270).accessibilityIdentifier("fleet.tires")
            Text("각 바퀴의 마지막 측정값 · 주행 직후에는 공기압이 높아질 수 있습니다.").font(.caption2).foregroundStyle(Theme.muted)
        }
    }
    private func wheel(_ index: Int) -> some View {
        let reading = sample(index)
        return VStack(spacing: 4) {
            Text(["앞 왼쪽", "앞 오른쪽", "뒤 왼쪽", "뒤 오른쪽"][index]).font(.caption2)
            Text(units.format(reading?.validBar, suffix: " bar")).font(.subheadline.bold()).monospacedDigit()
            if let at = reading?.at { Text(at.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.muted) }
        }.padding(9).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
