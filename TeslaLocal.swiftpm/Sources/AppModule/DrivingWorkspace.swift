import SwiftUI
import CoreLocation
import MapKit

struct DrivingWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.vehicleUnits) private var units
    @ObservedObject var navigation: EmbeddedNavigation
    @ObservedObject var link: VehicleLink
    @ObservedObject private var appearance = VehicleAppearanceStore.shared
    @AppStorage("preferredMapEngine") private var preferredMapEngine = "kakao"
    @State private var settings = false
    @State private var carError: String?
    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if !isLandscape {
                        topBar(compact: false)
                    }
                    NavigationDashboard(theme: navigation.theme, data: readout) {
                        if preferredMapEngine == "kakao", let controller = navigation.controller {
                            KakaoMapSurface(controller: controller, theme: navigation.theme, anchorX: navigation.theme == .cluster ? 0.52 : 0.58, anchorY: 0.72)
                        } else {
                            LiveStandbyMapView(navigation: navigation, readout: readout) {
                                settings = true
                            }
                        }
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
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: readout.turnSymbol)
                }

                if isLandscape {
                    topBar(compact: true)
                        .padding(.top, 6)
                }
            }
            .background(navigation.theme.canvas)
        }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("지도 엔진") {
                        Picker("기본 지도", selection: $preferredMapEngine) {
                            Text("카카오 지도 (KNSDK)").tag("kakao")
                            Text("애플 지도 (Apple Map)").tag("apple")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: preferredMapEngine) { newEngine in
                            if newEngine == "kakao" && navigation.controller == nil {
                                navigation.startStandbyKakaoMap()
                            }
                        }
                    }
                    Section("내비 화면") {
                        Picker("테마", selection: $navigation.theme) { ForEach(NavigationTheme.allCases) { Text($0.title).tag($0) } }
                        DirectionPicker(navigation: navigation)
                    }
                    Section { NavigationLink("표시·음성 설정") { PreferencesView() } }
                }.navigationTitle("운전 화면 설정").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { settings = false } } }
            }
        }
        .onAppear {
            navigation.screenAppeared()
            model.voice.announceDashboardStart(destination: readout.destination)
            if preferredMapEngine == "kakao" && navigation.controller == nil {
                navigation.startStandbyKakaoMap()
            }
        }
        .onDisappear { navigation.screenDisappeared() }
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { navigation.dismissWorkspace() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
            }
            .accessibilityLabel("운전 화면 닫기")

            Image(systemName: link.authentic ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(link.authentic ? Color.green : Color.white.opacity(0.45))

            if !compact {
                Text(readout.inside)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            if !navigation.following {
                Button { navigation.recenter() } label: {
                    Label("현위치", systemImage: "location.fill")
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .padding(.horizontal, compact ? 10 : 12)
                        .frame(minHeight: compact ? 30 : 36)
                        .background(Color.accentColor.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.recenter")
                .transition(.opacity)
            }

            Button {
                preferredMapEngine = (preferredMapEngine == "kakao" ? "apple" : "kakao")
                if preferredMapEngine == "kakao" && navigation.controller == nil {
                    navigation.startStandbyKakaoMap()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: preferredMapEngine == "kakao" ? "map.fill" : "apple.logo")
                        .font(.system(size: compact ? 10 : 11))
                    Text(preferredMapEngine == "kakao" ? "카카오" : "애플")
                        .font(.system(size: compact ? 11 : 12, weight: .bold))
                }
                .padding(.horizontal, compact ? 7 : 9)
                .frame(minHeight: compact ? 30 : 36)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("지도 엔진 전환")

            Menu {
                Picker("내비 테마", selection: $navigation.theme) { ForEach(NavigationTheme.allCases) { Text($0.title).tag($0) } }
            } label: {
                Text(navigation.theme.title)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(minHeight: compact ? 30 : 44)
                    .background(compact ? Color.white.opacity(0.12) : Color.clear, in: Capsule())
            }
            .accessibilityLabel("내비 테마 선택")

            Menu {
                Button { model.openInTMap() } label: { Label("티맵으로 안내", systemImage: "arrow.turn.up.right") }
                Button { model.openInKakaoNavi() } label: { Label("카카오내비로 안내", systemImage: "map") }
                Button { model.openInNaverMap() } label: { Label("네이버 지도로 안내", systemImage: "paperplane") }
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.circle")
                    .font(.system(size: compact ? 15 : 17))
                    .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
            }

            Button { settings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: compact ? 14 : 16))
                    .frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
            }
            .accessibilityLabel("운전 화면 설정")
        }
        .padding(.horizontal, compact ? 10 : 8)
        .padding(.vertical, compact ? 4 : 0)
        .background(compact ? AnyView(Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))) : AnyView(EmptyView()))
        .animation(.easeInOut(duration: 0.2), value: navigation.following)
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
            r.gear = d.string("gear", "P")
            r.powerKW = d.number("powerKW")
            if let odo = d.number("odometerKm"), odo.isFinite { r.odometer = units.format(odo, suffix: " km") }
        } else if let gpsSpeed = navigation.telemetry["gpsSpeedKmh"] as? Double, gpsSpeed.isFinite, gpsSpeed >= 0 {
            // Live phone GPS speed when moving
            r.speed = String(format: "%.0f", units.distanceValue(gpsSpeed)); r.speedFraction = gpsSpeed / 140; r.speedKmh = gpsSpeed
            r.gear = gpsSpeed > 1.5 ? "D" : "P"
        } else {
            // Graceful parked / standby state
            r.speed = "0"
            r.speedFraction = 0
            r.speedKmh = 0
            r.gear = "P"
        }

        if let odo = model.groups.object("drive").number("odometerKm"), odo.isFinite {
            r.odometer = units.format(odo, suffix: " km")
        }

        let dest = d.string("destination")
        r.destination = dest
        if !dest.isEmpty {
            r.turn = dest
            r.turnSymbol = "arrow.triangle.turn.up.right.diamond.fill"
            if let arrMin = d.number("arrivalMinutes"), arrMin.isFinite, arrMin > 0 {
                r.remaining = "\(Int(round(arrMin)))분 남음"
                r.arrival = Date().addingTimeInterval(arrMin * 60).formatted(date: .omitted, time: .shortened)
            }
            if let arrKm = d.number("arrivalKm"), arrKm.isFinite, arrKm > 0 {
                r.remainingDistance = String(format: "%.1f km", arrKm)
                r.turnDistance = String(format: "%.1f km", arrKm)
            }
        } else {
            let isMoving = (r.gear == "D" || r.speedKmh > 2)
            r.turn = isMoving ? "자유 주행 모드" : "안내 대기"
            r.turnSymbol = "location.north.circle.fill"
            r.turnDistance = ""
            r.remaining = "실시간 주행"
            r.remainingDistance = "목적지 미설정"
            r.arrival = "—"
        }
        r.road = "실시간 주행"

        if fresh.flag("charge"), let soc = c.number("soc") {
            r.batterySOC = soc
            r.battery = units.format(soc, suffix: "%")
            r.range = units.format(c.number("rangeKm"), suffix: " km")
            r.rangeKm = c.number("rangeKm")
        } else {
            let cachedSoc = model.groups.object("charge").number("soc") ?? 80.0
            let cachedRange = model.groups.object("charge").number("rangeKm") ?? 340.0
            r.batterySOC = cachedSoc
            r.battery = units.format(cachedSoc, suffix: "%")
            r.range = units.format(cachedRange, suffix: " km")
            r.rangeKm = cachedRange
        }

        if fresh.flag("drive"), let arrival = d.number("arrivalSOC"), arrival.isFinite, (0...100).contains(arrival) { r.arrivalSOC = arrival }

        // Head/tail lights after sunset (solar elevation at the car position, Seoul when unknown).
        let loc = model.groups.object("location")
        let lat = loc.number("latitude") ?? 37.5665
        let lng = loc.number("longitude") ?? 126.978
        r.night = SunClock.isDark(latitude: lat, longitude: lng)
        if fresh.flag("drive"), let power = d.number("powerKW"), power <= -15 { r.braking = true }
        if fresh.flag("drive"), d.string("gear") == "D", let speed = d.number("speedKmh"), speed <= 0.8 {
            r.braking = true // Tesla Brake Hold (H) in D: brake lights ON
        }
        readMedia(into: &r, fresh: fresh)

        if fresh.flag("climate"), let inside = t.number("insideC") {
            r.inside = units.format(inside, suffix: "°C")
            r.outside = units.format(t.number("outsideC"), suffix: "°C")
        } else {
            let cachedInside = model.groups.object("climate").number("insideC") ?? 21.5
            let cachedOutside = model.groups.object("climate").number("outsideC") ?? 20.0
            r.inside = units.format(cachedInside, suffix: "°C")
            r.outside = units.format(cachedOutside, suffix: "°C")
        }
        let n = navigation.telemetry
        if let stamp = n["at"] as? Double, (0...10).contains(Date().timeIntervalSince1970 - stamp), n["valid"] as? Bool == true {
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
            if !text("road").isEmpty { r.road = text("road") }
            if !text("turn").isEmpty { r.turn = text("turn") }
            if !text("symbol").isEmpty { r.turnSymbol = text("symbol") }
            r.exitClock = n["exitClock"] as? Int ?? 0
            r.nextExitClock = n["nextExitClock"] as? Int ?? 0
            if n["motionValid"] as? Bool == true, let bend = n["routeBend"] as? Double, bend.isFinite {
                r.routeBend = max(-1, min(1, bend)); r.motionValid = true
            }
            if n["turnMetres"] != nil { r.turnDistance = distance("turnMetres") }
            r.highway = text("highway")
            if !text("nextTurn").isEmpty { r.next = distance("nextMetres") + " · " + text("nextTurn"); r.nextSymbol = text("nextSymbol", "arrow.up") }
            if n["remainMetres"] != nil { r.remainingDistance = distance("remainMetres") }
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

struct LiveStandbyMapView: View {
    @ObservedObject var navigation: EmbeddedNavigation
    let readout: NavigationReadout
    var onSettings: () -> Void = {}

    var body: some View {
        ZStack {
            StandbyMKMapView()

            VStack {
                Spacer()
                statusPill
                    .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 8) {
            if !navigation.hasKey {
                Image(systemName: "key.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text("카카오 Native App Key 필요")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Button("키 설정") {
                    onSettings()
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue, in: Capsule())
                .foregroundStyle(.white)
            } else if !navigation.consent || !navigation.enabled {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
                Text("카카오 GPS 전달 동의 필요")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Button("1-터치 활성화") {
                    navigation.activateWorkspace()
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue, in: Capsule())
                .foregroundStyle(.white)
            } else if navigation.busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("카카오 경로 탐색 중…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                    .font(.system(size: 13))
                Text(readout.destination.isEmpty ? "실시간 지도 주행 중 · 테슬라 내비 연동 대기" : "\(readout.destination) 길안내 준비")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if !readout.destination.isEmpty {
                    Button("길안내 시작") {
                        navigation.retry()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue, in: Capsule())
                    .foregroundStyle(.white)
                } else if navigation.hasKey && navigation.consent {
                    Button("카카오 지도로 전환") {
                        UserDefaults.standard.set("kakao", forKey: "preferredMapEngine")
                        navigation.startStandbyKakaoMap()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.98, green: 0.85, blue: 0.0), in: Capsule())
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.1, opacity: 0.85), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }
}

struct StandbyMKMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = true
        map.userTrackingMode = .followWithHeading
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = true
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.userTrackingMode != .followWithHeading && uiView.userTrackingMode != .follow {
            uiView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }
}

