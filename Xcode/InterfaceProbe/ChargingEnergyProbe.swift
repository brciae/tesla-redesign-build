import SwiftUI

/// Production vehicle renderer and battery card, with explicit synthetic telemetry.
struct ChargingEnergyProbe: View {
    @StateObject private var model = AppModel()
    @AppStorage("energy.saving") private var saving = true
    @State private var tab = 0
    @State private var updates = 0
    @State private var builds = 0
    @State private var error = ""
    @State private var days = 30
    @State private var stale = false
    private var presentation: Object {
        ["allowInteraction": false, "animate": false, "isCharging": !stale, "chargingPlugged": true,
         "soc": 22 + Double(updates % 79), "chargerKW": 6 + Double(updates % 3),
         "states": Dictionary(uniqueKeysWithValues: ["driverFront","driverRear","passengerFront","passengerRear","frunk","trunk"].map { ($0, "closed") })]
    }
    var body: some View {
        VStack {
            Picker("검사 화면", selection: $tab) { Text("차량 모델").tag(0); Text("배터리").tag(1) }.pickerStyle(.segmented)
            if tab == 0 {
                Toggle("절전모드", isOn: $saving)
                RealityVehicleView(runtime: model.runtime, presentation: presentation,
                    command: VehicleCameraCommand(serial: 100, action: "angle", yaw: 2.38, pitch: 0.32, zoom: 0.95), reducedMotion: saving,
                    onSceneReady: { builds += 1 }) { error = $0 ?? "" }
                    .frame(height: 360).accessibilityIdentifier("charging.energy.scene")
                Text("씬 생성 \(builds)회 · 갱신 \(updates)회").accessibilityIdentifier("charging.energy.count")
                if !error.isEmpty { Text(error).accessibilityIdentifier("charging.energy.error") }
                Button("충전 값 100회 갱신") {
                    Task { @MainActor in
                        for _ in 0..<100 {
                            updates += 1
                            try? await Task.sleep(nanoseconds: 30_000_000)
                        }
                    }
                }.disabled(updates > 0 && updates < 100)
                Button("수신 상태 전환") { stale.toggle() }
                Text("합성 데이터 · 실제 충전 제어 없음").font(.caption)
            } else {
                ScrollView {
                    BatteryOverview(index: ["initial": true,"sampleCount": 0,"provisional": true,
                        "fullChargeRange": ["count": 2,"latestKm": 480.0,"initialKm": 500.0,"changePercent": -4.0],
                        "statusReason": "완충 표시거리 관측 예시"],
                        usage: ["parking": ["count": 1,"excludedCount": 0,"medianPerDay": 8.0,
                            "rows": [["start": Date().addingTimeInterval(-10800).timeIntervalSince1970 * 1000,
                                "end": Date().timeIntervalSince1970 * 1000,"hours": 3.0,"startSOC": 80.0,"endSOC": 79.0,
                                "evidence": "P 상태 관측 기반","exclusionReason": ""]]]], days: $days)
                }
            }
            Spacer(minLength: 0)
        }.padding()
    }
}
