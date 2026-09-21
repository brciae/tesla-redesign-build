import SwiftUI
import RealityKit
import UIKit
import simd

private let closureLabels: [(String, String)] = [("driverFront", "운전석 앞문"), ("driverRear", "운전석 뒷문"), ("passengerFront", "조수석 앞문"), ("passengerRear", "조수석 뒷문"), ("frunk", "프렁크"), ("trunk", "트렁크")]

@MainActor
struct Vehicle3DPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var link: VehicleLink
    @ObservedObject private var appearanceStore = VehicleAppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    var compact = false
    var chargingMode = false
    @State private var preview = false
    @State private var confirmPreview = false
    @State private var overrides: [String: Bool] = [:]
    @State private var camera = VehicleCameraCommand()
    @State private var sceneError: String?
    @State private var sceneVisible = false
    private var presentation: Object {
        var base = (try? model.runtime.call("vehicle3D", ["connected": link.connected, "authenticated": link.authentic && link.closuresSupported, "sessionStartedAt": link.sessionStartedAt, "demo": model.demo, "preview": preview, "overrides": overrides, "reduceMotion": reduced])) as? Object ?? ["states": [:], "restricted": true, "note": "3D 상태 처리 오류"]
        if chargingMode {
            base["chargingDecor"] = true
        }
        return base
    }
    var body: some View {
        let p = presentation, states = p.object("states"), example = p.string("mode") == "preview"
        VStack(alignment: .leading, spacing: compact ? 8 : 18) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(compact ? HomeVisualStyle.vehicleAspect : 16.0/9.0, contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            if sceneVisible {
                                RealityVehicleView(runtime: model.runtime, presentation: p, command: camera, reducedMotion: reduced, appearance: appearanceStore.value(for: VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo))) { sceneError = $0 }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .accessibilityLabel("회전 가능한 참고용 3D 차량. 부품 상태는 아래 목록에서 확인 가능함.")
                if !compact {
                    Text(example ? "3D 체험 · 실제 조작 아님" : p.string("mode") == "live" ? "수신 상태 · 미확인 \(Int(p.number("unknownCount") ?? 6))개" : "3D 모델 · 실차 상태 미확인")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(example ? .orange : Theme.muted)
                        .padding(8).background(Theme.bg.opacity(0.92), in: Capsule()).padding(.top, 6)
                }
                if let sceneError { Text("3D 장면을 열지 못함\n\(sceneError)").font(.caption).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg) }
                // Jijijik-style floating circular refresh button on the right side of the vehicle
                if compact {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                link.refreshNow(retryUnavailable: true)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(white: 0.16).opacity(0.88))
                                        .frame(width: 42, height: 42)
                                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(link.refreshing || link.busy ? Color.cyan : .white)
                                        .rotationEffect(.degrees(link.refreshing || link.busy ? 360 : 0))
                                        .animation(link.refreshing || link.busy ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: link.refreshing || link.busy)
                                }
                            }
                            .buttonStyle(MotionButtonStyle())
                            .accessibilityLabel("차량 정보 최신화")
                            .padding(.trailing, 10)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }.clipped()
            if !compact {
                NavigationLink(value: Page.appearance) { Label("차꾸미기", systemImage: "paintpalette") }.buttonStyle(.bordered)
                if p.flag("restricted") { Caption("정차 P 상태 확인 전에는 회전·개폐 체험을 제한함. 상태 변화는 애니메이션 없이 표시함.") }
                else { Caption("좌우 드래그로 360° 회전 · 두 손가락으로 확대") }
                HStack(spacing: 16) {
                    cameraButton("앞", yaw: 0); cameraButton("옆", yaw: -.pi/2); cameraButton("뒤", yaw: .pi)
                    Spacer()
                    Button { camera.serial += 1; camera.action = "reset" } label: { Label("시점 초기화", systemImage: "arrow.counterclockwise") }
                }.font(.system(size: 14)).disabled(p.flag("restricted"))
                HStack { Button("확대") { camera.serial += 1; camera.action = "in" }; Spacer(); Button("축소") { camera.serial += 1; camera.action = "out" } }.disabled(p.flag("restricted"))
                Caption(p.string("note"))
                if !model.demo {
                    Button(preview ? "체험 종료 · 실차 상태로" : "정차 상태에서 개폐 체험") {
                        if preview { preview = false; overrides = [:] } else { confirmPreview = true }
                    }.buttonStyle(.bordered).disabled(p.flag("restricted") && !preview)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(closureLabels, id: \.0) { key, label in
                        let state = states.string(key, "unknown")
                        Button {
                            guard example, !p.flag("restricted") else { return }
                            overrides[key] = state != "open"
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(label).font(.system(size: 14, weight: .medium))
                                HStack { Text(state == "open" ? "열림" : state == "closed" ? "닫힘" : "미확인"); Spacer(); if example { Image(systemName: "hand.tap") } }
                                    .font(.system(size: 12)).foregroundStyle(state == "unknown" ? Theme.muted : state == "open" ? .orange : Theme.green)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(MotionButtonStyle()).disabled(!example || p.flag("restricted"))
                            .accessibilityLabel("\(label), \(state == "open" ? "열림" : state == "closed" ? "닫힘" : "미확인")\(example ? ", 화면에서만 전환" : "")")
                    }
                }
                if example { HStack { Button("화면에서 모두 열기") { overrides = Dictionary(uniqueKeysWithValues: closureLabels.map { ($0.0, true) }) }; Spacer(); Button("모두 닫기") { overrides = [:] } }.font(.system(size: 14)).disabled(p.flag("restricted")) }
                Caption("실차에서는 문·트렁크가 열린 정도나 움직이는 방향을 추정하지 않음. 수신된 열림/닫힘을 정해진 예시 각도로 표현함. 미확인 상태는 배지와 목록으로 구분하며 원래 재질과 마지막 자세 또는 기본 자세를 유지함.")
                Caption("BloxBloger의 2025 Tesla Model Y를 개인 비상업용으로 수정함. Y L 비율을 참고한 모델이며 정식 Tesla 자산이 아님. 휠·창문·램프·실내와 개폐 구조는 실차와 다를 수 있음. 차량 제어 명령 없음.")
                HStack {
                    Link("모델 원작자·출처", destination: URL(string: "https://sketchfab.com/3d-models/2025-tesla-model-y-619601e7800d418da5922c4fa7833f74")!)
                    Spacer()
                    Link("CC BY-NC 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-nc/4.0/")!)
                }.font(.caption)
                if !example { Caption("차량 기준 시각 \(dateText(p.number("sourceAt"))) · 응답 수신 \(dateText(p.number("receivedAt")))") }
            }
        }
        .confirmationDialog("정차 중에 화면 모형만 조작함. 실제 차량에 문·트렁크 명령은 보내지 않음.", isPresented: $confirmPreview) { Button("정차 중임 · 화면 체험 시작") { preview = true; overrides = [:] } }
        .onChange(of: p.flag("restricted")) { _, restricted in if restricted { preview = false; overrides = [:] } }
        .onChange(of: model.demo) { _, _ in preview = false; overrides = [:] }
        .onAppear {
            sceneError = nil
            if chargingMode {
                camera = VehicleCameraCommand(serial: 100, action: "angle", yaw: 2.38, pitch: 0.32, zoom: 1.15)
            }
            sceneVisible = true
        }
        .onDisappear { sceneVisible = false }
    }
    private func cameraButton(_ title: String, yaw: Float) -> some View { Button(title) { camera.serial += 1; camera.action = "angle"; camera.yaw = yaw } }
}
