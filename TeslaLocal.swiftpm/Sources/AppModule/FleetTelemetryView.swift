import SwiftUI
import Charts
import UniformTypeIdentifiers

struct FleetTelemetryView: View {
    let vin: String
    var connectionSettings = false
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = FleetTelemetryStore.shared
    @ObservedObject private var archive = FleetArchiveClient.shared
    @State private var serverAddress = ""
    @State private var serverToken = ""
    @State private var importing = false
    @State private var error = ""
    @State private var search = ""
    @State private var selectedField = "ModuleTempMax"
    @State private var serverExpanded = true
    @State private var streaming: FleetStreamingStatus?
    @State private var checking = false
    @State private var connectionError = ""
    private var latest: [String: FleetTelemetryReading] { store.latest(vin: vin) }
    private var trend: [FleetTelemetryReading] { Array(store.records.filter { $0.vin == vin && $0.field == selectedField && !$0.invalid && $0.number != nil }.suffix(240)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if connectionSettings {
                InfoCard {
                    Text("차량 → NAS → 앱").font(.headline)
                    Label(model.fleet.isAuthenticated ? "Tesla 계정 로그인됨" : "Tesla 계정 로그인 필요", systemImage: model.fleet.isAuthenticated ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    if let streaming {
                        Label(streaming.title, systemImage: streaming.synced ? "checkmark.circle.fill" : "wrench.and.screwdriver")
                        Caption(streaming.detail)
                        if let hostname = streaming.hostname { Text(hostname).font(.caption.monospaced()) }
                    }
                    Label(archive.connected ? "NAS 조회·키 인증 완료" : "NAS 연결 검사 필요", systemImage: archive.connected ? "checkmark.circle.fill" : "externaldrive.badge.questionmark")
                    if let count = archive.packetCount { LabeledContent("차량 수신 기록", value: "\(count)건") }
                    if let at = archive.lastVehicleReceivedAt { LabeledContent("NAS 마지막 수신", value: at.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                    Button(checking ? "차량 설정 확인 중…" : "차량 수집 상태 확인") {
                        checking = true; connectionError = ""
                        Task { @MainActor in
                            defer { checking = false }
                            do {
                                let result = try await model.fleet.readSupplement(.telemetryConfig)
                                guard result.vin == vin else { return }
                                streaming = FleetStreamingStatus(payload: result.payload)
                            } catch { connectionError = error.localizedDescription }
                        }
                    }.disabled(checking || vin.isEmpty || !model.fleet.isAuthenticated)
                    if let url = model.fleet.virtualKeyPairingURL {
                        Link("Tesla 앱에서 차량 가상 키 등록", destination: url)
                    }
                    if !connectionError.isEmpty { Caption(connectionError) }
                }
                DisclosureGroup("기록 가져오기·연결 상태") {
                    Text("배터리·차량 심층 분석").font(.headline)
                    Caption("수신된 배터리 온도·전기 상태와 변화 추이를 모아 봅니다. 차량 데이터 수집 서버를 연결하면 앱을 닫은 동안의 기록도 이어갈 수 있습니다.")
                    Text(store.status).font(.caption)
                    Button("Telemetry 기록 가져오기") { importing = true }.disabled(vin.isEmpty)
                    if !error.isEmpty { Caption(error) }
                }
                DisclosureGroup("NAS 차량 기록 서버 설정", isExpanded: $serverExpanded) {
                    Text("서버 주소").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    TextField("https://차량서버주소", text: $serverAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("archive.address")
                    Text("NAS 연결 키").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    SecureField("서버 전용 키 입력", text: $serverToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("archive.token")
                    Text("타입캐스트 키·Tesla 토큰·NAS 비밀번호와 다릅니다. 저장 후에는 다시 입력하지 않아도 됩니다.").font(.caption).foregroundStyle(Theme.muted)
                    Button(archive.busy ? "기록 가져오는 중…" : "연결 저장 · 기록 가져오기") {
                        do {
                            try archive.configure(address: serverAddress, token: serverToken)
                            serverToken = ""; error = ""
                            Task { await archive.sync(vin: vin) }
                        } catch { self.error = error.localizedDescription }
                    }.disabled(archive.busy || vin.isEmpty)
                    Caption(archive.status)
                    Caption("QuickConnect 관리 화면과 별도의 차량 기록 서버 주소를 사용합니다. 연결 키는 기기의 보안 저장소에 보관됩니다.")
                }
                } else {
                NavigationLink { FleetTelemetryView(vin: vin, connectionSettings: true) } label: { Label("기록 서버 연결 설정", systemImage: "externaldrive") }
                if ["ModuleTempMin", "ModuleTempMax", "PackVoltage", "PackCurrent", "EnergyRemaining", "NominalFullPackEnergyKwh"].contains(where: { latest[$0]?.number != nil && latest[$0]?.invalid == false }) { InfoCard {
                    Text("배터리 열관리·전기 상태").font(.headline)
                    measurement("최저 모듈 온도", field: "ModuleTempMin", unit: "°C")
                    measurement("최고 모듈 온도", field: "ModuleTempMax", unit: "°C")
                    difference("모듈 온도 편차", high: "ModuleTempMax", low: "ModuleTempMin", unit: "°C", scale: 1)
                    difference("셀 블록 전압 편차", high: "BrickVoltageMax", low: "BrickVoltageMin", unit: "mV", scale: 1000)
                    measurement("배터리 팩 전압", field: "PackVoltage", unit: "V")
                    measurement("배터리 팩 전류", field: "PackCurrent", unit: "A")
                    measurement("남은 에너지", field: "EnergyRemaining", unit: "kWh")
                    measurement("차량 보고 완충 에너지", field: "NominalFullPackEnergyKwh", unit: "kWh")
                    Caption("온도·전압 편차는 2초 이내 같은 시각의 유효한 값끼리 비교합니다. 이 값만으로 배터리 결함이나 열화를 판정하지 않습니다.")
                } }
                InfoCard {
                    Text("기록 추이").font(.headline)
                    Picker("추이 항목", selection: $selectedField) {
                        Text("최고 온도 °C").tag("ModuleTempMax")
                        Text("배터리 %").tag("Soc")
                        Text("충전 전력 kW").tag("DCChargingPower")
                    }.pickerStyle(.menu)
                    if trend.count > 1 {
                        Chart(trend) { point in
                            PointMark(x: .value("시각", point.at), y: .value("수신값", point.number!)).foregroundStyle(.mint)
                        }.frame(height: 180)
                        Caption("최근 유효 표본 최대 240개 · 미수신 구간은 연결하지 않습니다.")
                    } else { Caption("시계열 표본이 쌓이면 온도·잔량·충전 추이를 표시합니다.") }
                }
                }
                if connectionSettings { DisclosureGroup("연결 진단용 수신 신호") {
                    TextField("필드 이름 검색", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(latest.keys.sorted().filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { field in
                        if let value = latest[field] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field).font(.subheadline.bold())
                                Text(value.text).font(.caption.monospaced()).textSelection(.enabled)
                                Text(value.at.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if latest.isEmpty { Caption("수신 기록 없음") }
                } }
            }.padding(16)
        }.background(Theme.bg).navigationTitle(connectionSettings ? "NAS 연결·수집 설정" : "배터리 추이")
        .task(id: vin) {
            serverAddress = archive.address
            serverExpanded = archive.address.isEmpty
            await archive.sync(vin: vin)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 5_000_000 else { throw FleetTelemetryData.failure("최대 5 MB 파일을 가져올 수 있습니다.") }
                try store.ingest(Data(contentsOf: url), vin: vin); error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    @ViewBuilder private func measurement(_ title: String, field: String, unit: String) -> some View {
        if let value = latest[field], !value.invalid, let number = value.number {
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(title); Spacer(); Text(String(format: "%.1f %@", number, unit)) }.font(.subheadline)
                Text(value.at.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(Theme.muted)
            }
        }
    }
    @ViewBuilder private func difference(_ title: String, high: String, low: String, unit: String, scale: Double) -> some View {
        if let value = FleetTelemetryData.pairedDifference(latest[high], latest[low]) {
            HStack { Text(title); Spacer(); Text(String(format: "%.1f %@", value * scale, unit)) }.font(.subheadline)
        }
    }
}
