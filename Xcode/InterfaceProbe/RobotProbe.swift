import SwiftUI

struct RobotProbe: View {
    @State private var speed = 0.0
    @AppStorage("character.id") private var selected = "r4d5c4915"
    var body: some View {
        VStack {
            Picker("로봇", selection: $selected) {
                ForEach(CharacterOption.all.filter(\.robot)) { item in Text(item.name).tag(item.id) }
            }
            Character3DView(speedKmh: speed, ambient: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("robot.scene")
            Text(CharacterRig.rig(selected).loadError ?? "로봇 모델 로드됨")
            Button(speed == 0 ? "비행" : "대기") { speed = speed == 0 ? 70 : 0 }
        }.padding().onAppear { selected = "r4d5c4915" }
    }
}
