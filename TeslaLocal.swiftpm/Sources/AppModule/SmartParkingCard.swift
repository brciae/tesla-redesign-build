import SwiftUI
import CoreLocation

/// A sleek, high-density smart parking card synthesizing both vehicle telemetry and mobile sensor/vision data.
struct SmartParkingCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var manager = SmartParkingManager.shared
    @ObservedObject var link: VehicleLink
    @State private var showCamera = false
    @State private var showFullPhoto = false

    var body: some View {
        if model.fleet.isAuthenticated && !model.demo {
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.fleetParkingStatus).font(.subheadline)
                Button("현재 차량 위치를 주차 위치로 저장") { manager.saveCurrentFleetParking() }
                    .buttonStyle(.bordered)
                    .disabled(model.fleet.vehicleSnapshot?.parkingTelemetry() == nil)
                Caption("직접 저장한 시각을 기록함 · 실제 도착 시각은 차량에서 제공하지 않음")
            }.padding()
        }
        if let record = manager.latestRecord, record.vehicleID == nil || record.vehicleID == model.fleet.selectedVin {
            LocalBriefingControls(title: "주차 상태") {
                var lines = [record.displayTitle + ".", "\(formatTime(record.timestamp)) 위치 기록입니다."]
                if let warning = record.verification.securityWarning { lines.append(warning) }
                if let soc = record.vehicle.soc { lines.append("마지막 차량 수신 잔량 \(Int(soc))퍼센트입니다.") }
                return lines
            }
            VStack(alignment: .leading, spacing: 14) {
                // Header: Location Badge, Verification Status & Photo Thumbnail
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            // Location Type Badge
                            HStack(spacing: 5) {
                                Image(systemName: record.locationType.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                Text(record.locationType.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(badgeColor(for: record.locationType))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(badgeColor(for: record.locationType).opacity(0.18))
                            )

                            // Cross-Verification Badge
                            HStack(spacing: 4) {
                                Image(systemName: record.verification.isSecurityVerified ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(record.verification.isSecurityVerified ? "모바일+차량 종합검증" : "보안확인필요")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(record.verification.isSecurityVerified ? Color.green : Color.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule().fill((record.verification.isSecurityVerified ? Color.green : Color.orange).opacity(0.15))
                            )
                        }

                        // Main Title (OCR Floor & Pillar or Building Name)
                        Text(record.displayTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        // Subtitle (Address & Landmark)
                        Text(record.displaySubtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Photo Thumbnail (Tap to zoom)
                    if let photoName = record.mobile.photoFileName,
                       let image = loadLocalImage(named: photoName) {
                        Button {
                            showFullPhoto = true
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                        }
                    }
                }

                // Security Alert Banner (If vehicle unlocked or door open)
                if let warning = record.verification.securityWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13))
                        Text(warning)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.14))
                    )
                }

                LinearGradient(colors: [.clear, Color.white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)

                // 6-Tile Comprehensive Synthesis Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    // Tile 1: Elapsed Parking Time
                    tileView(
                        icon: "clock.fill",
                        iconColor: .cyan,
                        title: "위치 기록 경과",
                        value: elapsedTimeString(since: record.timestamp),
                        caption: formatTime(record.timestamp) + " 기록"
                    )

                    // Tile 2: Vehicle Heading & Orientation
                    tileView(
                        icon: "safari.fill",
                        iconColor: .indigo,
                        title: "차량 주차 방향",
                        value: record.vehicle.headingDescription ?? "방향 미기록",
                        caption: record.vehicle.heading != nil ? "차량 전면 방향" : "나침반 대기 중"
                    )

                    // Tile 3: Battery & Charging Status
                    let currentSOC = (link.telemetryGroups.object("charge").number("soc")) ?? record.vehicle.soc ?? 0
                    let startSOC = record.vehicle.soc ?? currentSOC
                    let delta = currentSOC - startSOC
                    let isCharging = (link.telemetryGroups.object("charge").number("charging") ?? 0) > 0 || record.vehicle.isCharging == true
                    let chargerKW = link.telemetryGroups.object("charge").number("chargerKW") ?? record.vehicle.chargerKW ?? 0

                    tileView(
                        icon: isCharging ? "bolt.car.fill" : "battery.100",
                        iconColor: isCharging ? .green : (delta < 0 ? .orange : .white.opacity(0.7)),
                        title: isCharging ? "충전 진행 중" : "배터리 소모량",
                        value: isCharging ? "\(Int(currentSOC))% (\(Int(chargerKW))kW)" : "\(Int(currentSOC))% (\(String(format: "%+.1f%%p", delta)))",
                        caption: isCharging ? "목표까지 충전 중" : "대기/센트리 소모"
                    )

                    // Tile 4: Vehicle Security & Closures
                    let isLocked = link.telemetryGroups.object("closures").flag("locked")
                    let areDoorsClosed = record.vehicle.areDoorsClosed ?? true
                    let isSecure = isLocked && areDoorsClosed

                    tileView(
                        icon: isSecure ? "lock.fill" : "lock.open.fill",
                        iconColor: isSecure ? .green : .orange,
                        title: "차량 보안 상태",
                        value: isSecure ? "잠김 · 도어 닫힘" : (isLocked ? "도어/트렁크 열림" : "차량 미잠금"),
                        caption: isSecure ? "보안 안전 확인됨" : "확인 및 원격 잠금 필요"
                    )

                    // Tile 5: Cabin & Exterior Temperatures
                    let inTemp = link.telemetryGroups.object("climate").number("insideC") ?? record.vehicle.insideTempC
                    let outTemp = link.telemetryGroups.object("climate").number("outsideC") ?? record.vehicle.outsideTempC
                    let tempText: String = {
                        if let i = inTemp, let o = outTemp {
                            return "\(Int(i))°C / \(Int(o))°C"
                        } else if let i = inTemp {
                            return "\(Int(i))°C"
                        }
                        return "온도 대기 중"
                    }()

                    tileView(
                        icon: "thermometer.medium",
                        iconColor: .teal,
                        title: "차량 실내/실외",
                        value: tempText,
                        caption: inTemp != nil ? "실내 / 실외 기온" : "공조 센서"
                    )

                    // Tile 6: Real-time Distance to Car
                    tileView(
                        icon: "figure.walk",
                        iconColor: .blue,
                        title: "차량과의 거리",
                        value: distanceToCarString(record: record),
                        caption: "현재 내 위치 기준"
                    )
                }

                // Action Buttons
                HStack(spacing: 10) {
                    if let lat = record.effectiveLatitude, let lng = record.effectiveLongitude, !(lat == 0 && lng == 0) {
                        Button {
                            openWalkingDirections(lat: lat, lng: lng)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.walk")
                                Text("내 차 찾기 (도보 길안내)")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.85))
                            )
                        }
                    }

                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                            Text("다시 촬영")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.12))
                        )
                    }

                    Button {
                        manager.clearRecord()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
            }
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.09, green: 0.11, blue: 0.16).opacity(0.92), Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.96)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.24), location: 0),
                                .init(color: .white.opacity(0.08), location: 0.3),
                                .init(color: .white.opacity(0.02), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in
                    if let image = UIImage(data: data) {
                        Task {
                            await manager.processParkingPhoto(
                                image: image,
                                vehicleTelemetry: manager.photoTelemetry(fallback: link.telemetryGroups)
                            )
                        }
                    }
                }
            }
            .sheet(isPresented: $showFullPhoto) {
                if let photoName = record.mobile.photoFileName,
                   let image = loadLocalImage(named: photoName) {
                    NavigationStack {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                        .navigationTitle(record.displayTitle)
                        .safeAreaInset(edge: .bottom) { LocalBriefingControls(title: "주차 사진") { [record.displayTitle] }.padding().background(.regularMaterial) }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기") { showFullPhoto = false }
                            }
                        }
                    }
                }
            }
        } else {
            // Prompt Card when no record exists or when parked
            Button {
                showCamera = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.cyan.opacity(0.18)).frame(width: 44, height: 44)
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(Color.cyan)
                            .font(.system(size: 20))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("주차 위치 촬영 및 자동 기록")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("기둥 번호 또는 야외 건물 촬영 시 차량+모바일 자동 검증")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in
                    if let image = UIImage(data: data) {
                        Task {
                            await manager.processParkingPhoto(
                                image: image,
                                vehicleTelemetry: manager.photoTelemetry(fallback: link.telemetryGroups)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func tileView(icon: String, iconColor: Color, title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
    }

    // MARK: - Helper Methods

    private func badgeColor(for type: ParkingLocationType) -> Color {
        switch type {
        case .underground: return Color.green
        case .tower: return Color.indigo
        case .outdoor: return Color.cyan
        case .evCharging: return Color.blue
        case .general: return Color.purple
        }
    }

    private func loadLocalImage(named: String) -> UIImage? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(named)
        return UIImage(contentsOfFile: url.path)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func elapsedTimeString(since: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(since) / 60)
        if minutes < 1 { return "방금 기록" }
        if minutes < 60 { return "\(minutes)분 경과" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        return "\(hours)시간 \(remMinutes)분 경과"
    }

    private func distanceToCarString(record: SmartParkingRecord) -> String {
        guard let phoneLoc = manager.currentPhoneLocation,
              let carLat = record.effectiveLatitude,
              let carLng = record.effectiveLongitude,
              !(carLat == 0 && carLng == 0) else {
            return "위치 보존됨"
        }

        let carLoc = CLLocation(latitude: carLat, longitude: carLng)
        let meters = phoneLoc.distance(from: carLoc)
        if meters < 10 {
            return "차량 바로 앞 (<10m)"
        } else if meters < 1000 {
            return "\(Int(meters))m (도보 \(max(1, Int(meters / 70)))분)"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }

    private func openWalkingDirections(lat: Double, lng: Double) {
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=w"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
