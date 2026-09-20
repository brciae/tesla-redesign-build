import SwiftUI

struct DrivingWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var navigation: EmbeddedNavigation
    @ObservedObject var link: VehicleLink
    @ObservedObject private var appearance = VehicleAppearanceStore.shared
    @State private var settings = false
    @State private var carError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { navigation.stop() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("운전 화면 종료")
                Image(systemName: link.authentic ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash").foregroundStyle(link.authentic ? Color.green : .orange)
                Text(readout.inside).font(.caption).monospacedDigit()
                Spacer(minLength: 0)
                if !navigation.following {
                    // Kakao-style browse: the map stays where the user dragged it until this is tapped (or 15 s pass).
                    Button { navigation.recenter() } label: {
                        Label("현위치", systemImage: "location.fill").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Color.accentColor.opacity(0.9), in: Capsule())
                    }
                    .buttonStyle(.plain).frame(minHeight: 44)
                    .accessibilityIdentifier("map.recenter")
                    .transition(.opacity)
                }
                Menu {
                    Picker("내비 테마", selection: $navigation.theme) { ForEach(NavigationTheme.allCases) { Text($0.title).tag($0) } }
                } label: { Text(navigation.theme.title).font(.subheadline).frame(minHeight: 44) }.accessibilityLabel("내비 테마 선택")
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("운전 화면 설정")
            }.padding(.horizontal, 8)
            .animation(.easeInOut(duration: 0.2), value: navigation.following)
            if !navigation.directionNotice.isEmpty { Text(navigation.directionNotice).font(.caption).foregroundStyle(.orange) }
                        NavigationDashboard(theme: navigation.theme, data: readout) {
                if let controller = navigation.controller {
                    KakaoMapSurface(controller: controller, theme: navigation.theme, anchorX: navigation.theme == .cluster ? 0.52 : 0.58, anchorY: 0.72)
                } else { Color.black.overlay { Text(navigation.status).font(.caption).foregroundStyle(.secondary) } }
            } car: {
                ZStack {
                    if let camera = navigation.theme.carCamera {
                        RealityVehicleView(runtime: model.runtime, presentation: readout.scenePresentation(theme: navigation.theme),
                            command: VehicleCameraCommand(serial: NavigationTheme.allCases.firstIndex(of: navigation.theme) ?? 0, action: "angle", yaw: camera.yaw, pitch: camera.pitch, zoom: navigation.theme.carZoom),
                            reducedMotion: true, appearance: appearance.value(for: VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo)),
                            backgroundColor: .clear) { carError = $0 }
                        if carError != nil { Text("차량 모델 표시 불가").font(.caption).foregroundStyle(.orange) }
                    }
                }
            } onMedia: { action in
                switch action {
                case "mediaVolumeUp": link.mediaCommand("mediaVolume", delta: 1)
                case "mediaVolumeDown": link.mediaCommand("mediaVolume", delta: -1)
                default: link.mediaCommand(action)
                }
            }
            .animation(.smooth(duration: 0.28), value: readout.speed)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: readout.turnSymbol) car: {
                    ZStack {
                        if let camera = navigation.theme.carCamera {
                            RealityVehicleView(runtime: model.runtime, presentation: readout.scenePresentation(theme: navigation.theme),
                                command: VehicleCameraCommand(serial: NavigationTheme.allCases.firstIndex(of: navigation.theme) ?? 0, action: "angle", yaw: camera.yaw, pitch: camera.pitch, zoom: navigation.theme.carZoom),
                                reducedMotion: true, appearance: appearance.value(for: VehicleAppearanceStore.vehicleKey(vin: model.settings.string("vin"), demo: model.demo)),
                                backgroundColor: .clear) { carError = $0 }
                            if carError != nil { Text("차량 모델 표시 불가").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                } onMedia: { action in
                    switch action {
                    case "mediaVolumeUp": link.mediaCommand("mediaVolume", delta: 1)
                    case "mediaVolumeDown": link.mediaCommand("mediaVolume", delta: -1)
                    default: link.mediaCommand(action)
                    }
                }
            }
        }.background(navigation.theme.canvas)
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("내비 화면") {
                        Picker("테마", selection: $navigation.theme) { ForEach(NavigationTheme.allCases) { Text($0.title).tag($0) } }
                        DirectionPicker(navigation: navigation)
                    }
                    Section { NavigationLink("표시·음성 설정") { PreferencesView() } }
                }.navigationTitle("운전 화면 설정").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { settings = false } } }
            }
        }
        .onAppear { navigation.screenAppeared() }.onDisappear { navigation.screenDisappeared() }
    }
    private var readout: NavigationReadout {
        var r = NavigationReadout()
        let fresh = model.output.object("fresh"), d = model.groups.object("drive"), c = model.groups.object("charge"), t = model.groups.object("climate")
        r.speedUnit = units.speedLabel; r.connected = link.authentic
        r.clock = Date().formatted(date: .omitted, time: .shortened)
        r.vehicleName = model.settings.string("name", "Model Y")
        if fresh.flag("drive"), let speed = d.number("speedKmh"), speed.isFinite, speed >= 0 {
            r.speed = String(format: "%.0f", units.distanceValue(speed)); r.speedFraction = speed / 140
            r.speedKmh = speed
            r.gear = d.string("gear", "—")
            r.powerKW = d.number("powerKW")
            if let odo = d.number("odometerKm"), odo.isFinite { r.odometer = units.format(odo, suffix: " km") }
        } else if let gpsSpeed = navigation.telemetry["gpsSpeedKmh"] as? Double, gpsSpeed.isFinite, gpsSpeed >= 0 {
            // v29: BLE drive group stale → show the phone GPS speed from the Kakao engine instead of "—".
            r.speed = String(format: "%.0f", units.distanceValue(gpsSpeed)); r.speedFraction = gpsSpeed / 140; r.speedKmh = gpsSpeed
        }
        r.destination = d.string("destination")
        if fresh.flag("charge") { r.batterySOC = c.number("soc"); r.battery = units.format(c.number("soc"), suffix: "%"); r.range = units.format(c.number("rangeKm"), suffix: " km"); r.rangeKm = c.number("rangeKm") }
        if fresh.flag("drive"), let arrival = d.number("arrivalSOC"), arrival.isFinite, (0...100).contains(arrival) { r.arrivalSOC = arrival }
        // Head/tail lights after sunset (solar elevation at the car position, Seoul when unknown).
        let loc = model.groups.object("location")
        let lat = loc.number("latitude") ?? 37.5665
        let lng = loc.number("longitude") ?? 126.978
        r.night = SunClock.isDark(latitude: lat, longitude: lng)
        if fresh.flag("drive"), let power = d.number("powerKW"), power <= -15 { r.braking = true }
        if fresh.flag("drive"), let speed = d.number("speedKmh"), speed <= 1.5 || d.string("gear") == "P" {
            r.braking = true // Tesla Brake Hold (H) / Park: brake lights & ground reflection ON
        }
        readMedia(into: &r, fresh: fresh)
        if fresh.flag("climate") { r.inside = units.format(t.number("insideC"), suffix: "°C"); r.outside = units.format(t.number("outsideC"), suffix: "°C") }
        let n = navigation.telemetry
        guard let stamp = n["at"] as? Double, (0...10).contains(Date().timeIntervalSince1970 - stamp), n["valid"] as? Bool == true else { return r }
        func text(_ key: String, _ fallback: String = "") -> String { n[key] as? String ?? fallback }
        func distance(_ key: String) -> String {
            guard let metres = n[key] as? Double, metres.isFinite, metres >= 0 else { return "—" }
            if units.distance == "mi" { return units.format(metres / 1000, suffix: " km", digits: 1) }
            return metres >= 1000 ? String(format: "%.1f km", metres / 1000) : String(format: "%.0f m", metres)
        }
        if n["braking"] as? Bool == true { r.braking = true }
        if let through = n["laneThrough"] as? Int, through > 0 {
            r.currentRoadLanes = through
        } else if let lanes = n["roadLanes"] as? Int, lanes > 0 {
            r.currentRoadLanes = lanes
        }
        if let roadClass = n["roadClass"] as? String, !roadClass.isEmpty { r.currentRoadClass = roadClass }
        if let path = n["routePath"] as? [[NSNumber]] { r.routePath = path.flatMap { $0.prefix(2).map(\.doubleValue) } }
        r.road = text("road", "위치 확인 중"); r.turn = text("turn", "경로 확인 중"); r.turnSymbol = text("symbol", "location.north")
        r.exitClock = n["exitClock"] as? Int ?? 0
        r.nextExitClock = n["nextExitClock"] as? Int ?? 0
        if n["motionValid"] as? Bool == true, let bend = n["routeBend"] as? Double, bend.isFinite {
            r.routeBend = max(-1, min(1, bend)); r.motionValid = true
        }
        r.turnDistance = distance("turnMetres"); r.highway = text("highway")
        if !text("nextTurn").isEmpty { r.next = distance("nextMetres") + " · " + text("nextTurn"); r.nextSymbol = text("nextSymbol", "arrow.up") }
        r.remainingDistance = distance("remainMetres")
        r.gpsLive = n["gps"] as? Bool == true
        if let count = n["laneCount"] as? Int, count > 0 {
            r.laneCount = count
            r.laneSuggested = (n["laneSuggested"] as? [NSNumber] ?? []).map(\.intValue).filter { $0 >= 0 && $0 < count }
            if n["laneMetres"] != nil { r.laneDistance = distance("laneMetres") }
        }
        if let raw = n["laneRaw"] as? String { r.laneRaw = raw }
        if let limit = n["speedLimit"] as? Int, limit > 0 {
            r.speedLimit = limit
            if n["speedLimitMetres"] != nil { r.speedLimitDistance = distance("speedLimitMetres") }
        }
        if let remain = n["remainMetres"] as? Double, let total = n["routeTotalMetres"] as? Double, total > 0 {
            r.routeProgress = max(0, min(1, 1 - remain / total))
        }
        if let seconds = n["remainSeconds"] as? Double, seconds.isFinite, seconds >= 0 {
            r.remaining = "\(Int(ceil(seconds / 60)))분 남음"
            r.arrival = Date(timeIntervalSinceNow: seconds).formatted(date: .omitted, time: .shortened)
        }
        return r
    }

    private func readMedia(into r: inout NavigationReadout, fresh: Object) {
        r.mediaStatus = link.mediaStatus
        r.mediaBusy = link.mediaInFlight
        guard fresh.flag("media") else { return }
        let media = model.groups.object("media"), detail = model.groups.object("mediaDetail")
        r.mediaTitle = media.string("title"); r.mediaArtist = media.string("artist")
        r.mediaPlaying = media.flag("playing")
        r.mediaVolume = media.number("volume"); r.mediaVolumeMax = media.number("volumeMax")
        guard fresh.flag("mediaDetail") else { return }
        r.mediaSource = [detail.string("sourceName"), detail.string("station"), detail.string("device")].first { !$0.isEmpty } ?? ""
        if let duration = detail.number("duration"), duration > 0 {
            // The car reports milliseconds; tolerate seconds.
            let scale = duration > 36_000 ? 1000.0 : 1.0
            var elapsed = (detail.number("elapsed") ?? 0) / scale
            if r.mediaPlaying, let at = detail.number("at"), at > 0 { elapsed += max(0, min(3600, Date().timeIntervalSince1970 - at / 1000)) }
            r.mediaDuration = duration / scale
            r.mediaElapsed = min(duration / scale, elapsed)
        }
    }
}

/// Solar elevation (NOAA low-precision). Good to about a minute of sunset time — enough for lamp cues.
enum SunClock {
    static func isDark(at date: Date = Date(), latitude: Double, longitude: Double) -> Bool {
        elevation(at: date, latitude: latitude, longitude: longitude) < -0.833
    }
    static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let meanLong = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (meanLong + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let tilt = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(tilt) * sin(lambda), cos(lambda))
        let dec = asin(sin(tilt) * sin(lambda))
        let sidereal = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360)
        let hourAngle = (sidereal + longitude) * rad - ra
        let lat = latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)) / rad
    }
}
