import AudioToolbox
import SwiftUI
import UIKit

// v30 navigation dashboard.
// Six layouts traced from the supplied references. v30: larger type (no "…" truncation), translucent scrims so the
// map stays visible, a car-media card (BLE media state + controls) and one 3D road for every car view so the
// car and road always share the same scale (the touring ratio is the reference).
// The map child is mounted exactly once; only its frame changes between themes and orientations.

// MARK: - Palette

enum NavInk {
    static let blue = Color(red: 0.039, green: 0.518, blue: 1.0)            // iOS systemBlue (dark) #0A84FF
    static let blueDeep = Color(red: 0.137, green: 0.318, blue: 0.918)      // #2351EA
    static let arc = Color(red: 0.039, green: 0.518, blue: 1.0)             // #0A84FF
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345)         // iOS systemGreen (dark) #30D158
    static let red = Color(red: 1.0, green: 0.271, blue: 0.227)             // iOS systemRed (dark) #FF453A
    static let amber = Color(red: 1.0, green: 0.624, blue: 0.039)           // iOS systemOrange (dark) #FF9F0A
    static let canvas = Color(red: 0.043, green: 0.047, blue: 0.055)        // #0B0C0E
    static let mapBase = Color(red: 0.165, green: 0.173, blue: 0.192)       // #2A2C31
    static let card = Color(red: 0.110, green: 0.110, blue: 0.118)          // secondarySystemBackground #1C1C1E
    static let cardHi = Color(red: 0.173, green: 0.173, blue: 0.180)        // tertiarySystemBackground #2C2C2E
    static let slate = Color(red: 0.118, green: 0.125, blue: 0.145)         // #1E2025
    static let pill = Color(red: 0.039, green: 0.043, blue: 0.051)          // #0A0B0D
    static let muted = Color(red: 0.596, green: 0.596, blue: 0.624)         // secondaryLabel (dark) #98989F
    static let gearOff = Color(red: 0.420, green: 0.439, blue: 0.471)
    static let neon = Color(red: 0.231, green: 0.576, blue: 1.0)            // #3B93FF
    static let navy = Color(red: 0.035, green: 0.071, blue: 0.200)          // #091233
    static let navyHi = Color(red: 0.078, green: 0.169, blue: 0.451)        // #142B73
}

// MARK: - Public model

enum NavigationTheme: String, CaseIterable, Identifiable {
    case cluster, touring, minimal, panorama, focus, fleet, running
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cluster: return "클러스터"
        case .touring: return "투어링"
        case .minimal: return "미니멀"
        case .panorama: return "파노라마"
        case .focus: return "포커스"
        case .fleet: return "관제"
        case .running: return "러닝"
        }
    }
    /// Camera for the vehicle view, nil when the layout shows no vehicle model.
    var carCamera: (yaw: Float, pitch: Float)? {
        switch self {
        case .touring: return (-0.72, 0.42)          // Tesla-app front three-quarter
        case .minimal, .panorama: return (.pi, 0.30) // chase view over the neon road
        case .focus: return (.pi, 0.62)              // driving visualisation, high behind
        case .cluster, .fleet, .running: return nil
        }
    }
    /// Camera distance multiplier. Road and car live in the same 3D scene, so scale always matches.
    var carZoom: Float {
        switch self {
        case .touring: return 1.35
        case .minimal, .panorama: return 2.25
        case .focus: return 2.3
        default: return 1.08
        }
    }
    /// Metres the camera looks ahead of the car (shows the curve ahead instead of the bumper).
    var lookAhead: Float {
        switch self {
        case .minimal, .panorama: return 7
        case .focus: return 4
        default: return 0
        }
    }
    var roadStyle: String { self == .minimal || self == .panorama ? "neon" : "asphalt" }
    var drawsRoadIn3D: Bool { carCamera != nil }
    var canvas: Color {
        switch self {
        case .minimal, .focus: return .black
        case .panorama: return NavInk.navy
        case .running: return Color(white: 0.97)
        default: return NavInk.canvas
        }
    }
}

/// Display-only model. Never substitutes a remembered speed, limit, lane or turn for missing data.
struct NavigationReadout {
    var junctionImage: UIImage?
    var junctionMetres: Double = -1
    var speed = "—", speedUnit = "km/h", gear = "—", battery = "—", range = "—"
    var inside = "—", outside = "—", road = "위치 확인 중", turn = "경로 확인 중"
    var turnDistance = "—", turnSymbol = "location.north", next = "", nextSymbol = "arrow.up"
    var exitClock = 0, nextExitClock = 0
    var batterySOC: Double? = nil
    var remaining = "—", remainingDistance = "—", arrival = "—", highway = ""
    var connected = false
    var speedFraction: Double = 0
    var speedKmh: Double = 0
    var routeBend: Double = 0
    var motionValid = false
    var powerKW: Double?
    var destination = ""
    var speedLimit: Int? = nil
    /// v1.31: 0 none · 1 over the limit · 2 ≥10 km/h over · 3 ≥20 km/h over.
    var overspeedLevel: Int {
        guard let limit = speedLimit, limit > 0, speedKmh.isFinite else { return 0 }
        // v1.42: only warn inside the distance chosen in 설정 (300 / 500 / 1000 m) before the camera.
        if let m = speedLimitMetres, m.isFinite {
            let range = UserDefaults.standard.object(forKey: "overspeed.distance") as? Double ?? 500
            if m > range { return 0 }
        }
        let over = speedKmh - Double(limit)
        return over >= 20 ? 3 : over >= 10 ? 2 : over > 0.5 ? 1 : 0
    }
    var speedLimitDistance = ""
    var speedLimitMetres: Double? = nil
    var odometer = "—"
    var clock = ""
    var gpsLive = false
    var positionEstimated = false
    var routeProgress: Double? = nil
    var rangeKm: Double? = nil
    var arrivalSOC: Double? = nil
    var energyPrediction: TripEnergyEstimate?
    var vehicleName = "Model Y"
    /// Kakao lane guidance at the next lane-info point (not the car's measured lane).
    var laneCount = 0
    var laneSuggested: [Int] = []
    var laneDistance = ""
    var laneRaw = ""
    /// Lane count of the road the car is on (last Kakao lane info on this road, else a road-class estimate).
    var currentRoadLanes = 0
    /// urban / highway / narrow — decides the centre-line painting.
    var currentRoadClass = "urban"
    /// Route shape ahead in metres, flattened [left, forward, left, forward, …].
    var routePath: [Double] = []
    var braking = false
    var night = false
    // Car media (BLE media state)
    var mediaTitle = "", mediaArtist = "", mediaSource = ""
    var mediaSourceCode: Double? = nil
    var mediaApp: MediaPlaybackSource { .resolve(code: mediaSourceCode, sourceName: mediaSource) }
    var mediaPlaying = false
    var mediaElapsed: Double? = nil
    var mediaDuration: Double? = nil
    var mediaVolume: Double? = nil
    var mediaVolumeMax: Double? = nil
    var mediaStatus = ""
    var mediaBusy = false
    var phoneSpotify = false
    var mediaArtwork: UIImage? = nil
    var mediaControllable: Bool { (connected || phoneSpotify) && !mediaBusy }

    var hasMedia: Bool { !mediaTitle.isEmpty || !mediaSource.isEmpty || (mediaSourceCode ?? 0) > 0 }
    var showsMedia: Bool { hasMedia }
    var roadLanes: Int {
        if currentRoadLanes >= 1 { return min(6, currentRoadLanes) }
        if laneCount >= 1 { return min(6, laneCount) }
        return currentRoadClass == "narrow" ? 1 : 2
    }
    /// Recommended lane centre (fractional, from the left) or nil when no guidance.
    var suggestedLane: Double? { laneSuggested.isEmpty ? nil : Double(laneSuggested.reduce(0, +)) / Double(laneSuggested.count) }

    /// RealityKit presentation for the car view of `theme`.
    func scenePresentation(theme: NavigationTheme) -> Object {
        // Decorative road only. Recommended lanes do not locate the vehicle within a lane.
        let p: Object = ["states": Object(), "allowInteraction": false, "animate": false,
                         "wheelSpeedKmh": speedKmh, "steer": 0,
                         "roadLanes": theme.drawsRoadIn3D ? 1 : 0, "roadLane": -1,
                         "roadStyle": theme.roadStyle, "roadClass": currentRoadClass, "lookAhead": Double(theme.lookAhead),
                         "brake": braking, "headlights": night]
        return p
    }
}

// MARK: - Metrics

private struct NavMetrics {
    let size: CGSize
    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var wide: Bool { size.width >= size.height * 1.35 }
    /// v30: ~12% larger than v29 at the 844 × 346 reference box; portrait floor 0.82.
    var u: CGFloat { wide ? min(h / 300, w / 760) : max(0.82, min(1.15, w / 390)) }
    var pad: CGFloat { 12 * u }
}

// MARK: - Dashboard

struct NavigationDashboard<MapContent: View, CarContent: View>: View {
    @AppStorage("navigation.dashboardShade") private var shadeAmount = 0.45
    private var shade: Double { shadeAmount.isFinite ? min(1, max(0, shadeAmount)) : 0.45 }
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    let theme: NavigationTheme
    let data: NavigationReadout
    @ViewBuilder var map: () -> MapContent
    @ViewBuilder var car: () -> CarContent
    /// mediaToggle, mediaNext, mediaPrev, mediaVolumeUp, mediaVolumeDown
    var onMedia: (String) -> Void = { _ in }

    @Environment(\.dashboardSafeArea) private var safeArea
    @Environment(\.dashboardChromeClearance) private var chromeClearance
    var body: some View {
        GeometryReader { geo in
            layout(NavMetrics(size: geo.size))
        }
        .overlay { OverspeedAlert(level: data.overspeedLevel) }
    }

    @ViewBuilder
    private func layout(_ m: NavMetrics) -> some View {
        // Keep all six original theme compositions; navigation data updates never select a different layout.
        modelingLayout(m)
    }

    private func modelingLayout(_ m: NavMetrics) -> some View {
        let rect = mapRect(m)
        let inset = overlayInset(m)
        return ZStack(alignment: .topLeading) {
            theme.canvas.frame(width: m.w, height: m.h)
            map()
                .frame(width: rect.width, height: rect.height)
                .background(NavInk.mapBase)
                .mask {
                    if theme == .cluster || theme == .panorama {
                        ZStack { Rectangle().opacity(1 - shade); mapMask(rect: rect, m: m).opacity(shade) }
                    } else { mapMask(rect: rect, m: m) }
                }
                .position(x: rect.midX, y: rect.midY)
                .opacity(theme == .minimal ? 0 : 1)
                .allowsHitTesting(theme != .minimal)
                .accessibilityHidden(theme == .minimal)
            // Scrim themes: continue the leading scrim into the camera-side gap so no hard edge appears.
            if m.wide, inset.leading > 0, theme == .cluster || theme == .fleet {
                Color.black.opacity((theme == .cluster ? 1 : 0.4) * shade)
                    .frame(width: inset.leading + 1, height: m.h)
                    .allowsHitTesting(false)
            }
            overlay(NavMetrics(size: CGSize(width: max(1, m.w - inset.leading - inset.trailing), height: max(1, m.h - inset.top - inset.bottom))))
                .frame(width: max(1, m.w - inset.leading - inset.trailing), height: max(1, m.h - inset.top - inset.bottom))
                .offset(x: inset.leading, y: inset.top)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("navigation.foreground")
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // Own container so the root identifier does not overwrite the safe-area foreground identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation.modeling")
    }

    /// Only nudge content clear of the camera island: landscape takes a partial side inset,
    /// portrait only the top. Bottom (home indicator) and the far side stay full-bleed.
    private func overlayInset(_ m: NavMetrics) -> EdgeInsets {
        if m.w > m.h {
            // Sides keep the full cutout inset (UI tests require clearance on both camera orientations);
            // The map stays full-bleed; foreground clearance keeps the route stop off media controls.
            return EdgeInsets(top: chromeClearance, leading: safeArea.leading, bottom: 0, trailing: safeArea.trailing)
        }
        return EdgeInsets(top: max(safeArea.top, chromeClearance), leading: 0, bottom: 0, trailing: 0)
    }

    private func navigationLayout(_ m: NavMetrics) -> some View {
        let mediaHeight: CGFloat = data.showsMedia ? 48 : 0
        let footerHeight: CGFloat = 54 + mediaHeight
        let headerHeight: CGFloat = m.wide ? 0 : (data.laneCount > 0 ? 164 : 124)
        let sidebar: CGFloat = m.wide ? min(280, m.w * 0.30) : 0
        let rect = CGRect(x: sidebar, y: headerHeight, width: m.w - sidebar, height: max(1, m.h - headerHeight - footerHeight))
        let canvasColor = theme.canvas
        let textColor = Color.white
        return ZStack(alignment: .topLeading) {
            canvasColor.frame(width: m.w, height: m.h)
            map()
                .frame(width: rect.width, height: rect.height)
                .background(NavInk.mapBase)
                .clipped()
                .position(x: rect.midX, y: rect.midY)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("navigation.map")
            navigationPriorityHeader(m, wide: m.wide)
                .frame(width: m.wide ? sidebar : m.w, height: m.wide ? m.h - footerHeight : headerHeight)
                .accessibilityIdentifier("navigation.guidance")
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.destination.isEmpty ? "경로 미수신" : data.destination).font(.caption).lineLimit(1).minimumScaleFactor(0.5)
                        Text("\(data.arrival) 도착 · \(data.remaining) · \(data.remainingDistance)").font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    Spacer(minLength: 0)
                    Text(data.battery + " · " + data.range).font(.caption).lineLimit(1).minimumScaleFactor(0.5)
                }.padding(.horizontal, 12).frame(height: 54).background(theme.canvas)
                if data.showsMedia {
                    NavigationMediaHeader(data: data, action: onMedia)
                        .frame(height: mediaHeight).accessibilityIdentifier("navigation.mediaDock")
                }
            }.frame(width: m.w, height: footerHeight).offset(y: m.h - footerHeight)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
        .clipped()
        .foregroundStyle(textColor)
        .environment(\.colorScheme, .dark)
    }

    private func navigationPriorityHeader(_ m: NavMetrics, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.turnDistance).font(.system(size: 28, weight: .bold)).monospacedDigit()
                    GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.8)
                }
                if !wide { Spacer(minLength: 0); Text(data.speed).overspeed(data.overspeedLevel).font(.title.bold()).monospacedDigit(); Text(data.speedUnit).font(.caption2) }
            }
            if wide {
                HStack(alignment: .firstTextBaseline) {
                    Text(data.speed).overspeed(data.overspeedLevel).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    Text(data.speedUnit).font(.caption)
                    Spacer()
                    if let limit = data.speedLimit { LimitSign(limit: limit, distance: data.speedLimitDistance, size: 40) }
                }
            }
            if !data.next.isEmpty { GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock).font(.caption).lineLimit(1).minimumScaleFactor(0.5) }
            if data.laneCount > 0 { LaneStrip(data: data, u: min(1, m.u)).frame(maxHeight: 40) }
            if wide { Spacer(minLength: 0) }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(TeslaGuidanceSurface(radius: 16))
    }

    private func mapRect(_ m: NavMetrics) -> CGRect {
        switch theme {
        case .cluster, .fleet, .minimal:
            // Minimal keeps the map mounted full-size but transparent (a 1 pt Kakao map view is not safe).
            return CGRect(x: 0, y: 0, width: m.w, height: m.h)
        case .touring:
            let cardH = min(m.h * 0.38, 270 * m.u)
            return m.wide
                ? CGRect(x: m.w * 0.40, y: m.pad, width: m.w * 0.60 - m.pad, height: m.h - m.pad * 2)
                : CGRect(x: m.pad, y: cardH + m.pad * 1.5, width: m.w - m.pad * 2, height: m.h - cardH - m.pad * 2.5)
        case .panorama:
            return m.wide
                ? CGRect(x: 0, y: 0, width: m.w * 0.38, height: m.h)
                : CGRect(x: 0, y: m.h * 0.56, width: m.w, height: m.h * 0.44)
        case .focus:
            return m.wide
                ? CGRect(x: m.w - m.w * 0.25 - m.pad, y: m.pad, width: m.w * 0.25, height: m.h * 0.48)
                : CGRect(x: m.pad, y: m.h * 0.56, width: m.w - m.pad * 2, height: m.h * 0.22)
        case .running:
            return runningRects(m).map
        }
    }

    @ViewBuilder private func mapMask(rect: CGRect, m: NavMetrics) -> some View {
        switch theme {
        case .touring, .focus, .running:
            RoundedRectangle(cornerRadius: 24 * m.u, style: .continuous)
        case .panorama:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                           startPoint: m.wide ? .leading : .bottom, endPoint: m.wide ? .trailing : .top)
        case .cluster:
            // Portrait fades the map out under the bottom panel. Landscape must
            // not: there the cluster sits on the left and its own scrim does the
            // blending horizontally, so a top-to-bottom mask would cut the map
            // across the wrong axis.
            if m.wide {
                Rectangle()
            } else {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.55), location: 0.88),
                    .init(color: .clear, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
            }
        default:
            Rectangle()
        }
    }

    @ViewBuilder private func overlay(_ m: NavMetrics) -> some View {
        switch theme {
        case .cluster: clusterLayer(m)
        case .touring: touringLayer(m)
        case .minimal: minimalLayer(m)
        case .panorama: panoramaLayer(m)
        case .focus: focusLayer(m)
        case .fleet: fleetLayer(m)
        case .running: runningLayer(m)
        }
    }

    private func routeNotice(_ m: NavMetrics, y: CGFloat) -> some View {
        Text("경로 미수신")
            .font(.system(size: 13 * m.u, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: m.w, alignment: .center)
            .offset(y: y)
    }

    private func media(_ style: MediaCard.Style, _ m: NavMetrics) -> MediaCard {
        MediaCard(data: data, u: m.u, style: style, action: onMedia)
    }

    private func island(_ m: NavMetrics) -> MediaIsland {
        MediaIsland(data: data, u: m.u, action: onMedia)
    }

    /// 3D car on its own road; the view never takes touches.
    private func carStage(_ label: String) -> some View {
        car().allowsHitTesting(false).accessibilityLabel(label)
    }

    // MARK: Cluster (ref 1) — map-first; translucent gauge scrim so the map reads through

    private func clusterLayer(_ m: NavMetrics) -> some View {
        let ring = m.wide ? min(m.h * 0.62, m.w * 0.25) : min(m.w * 0.46, m.h * 0.26)
        let panelW = m.wide ? ring * 1.34 : m.w
        let panelH = m.wide ? m.h : ring * 1.25
        let panelY = m.wide ? 0 : m.h - panelH
        let center = m.wide ? CGPoint(x: panelW * 0.48, y: m.h * 0.54) : CGPoint(x: m.w * 0.29, y: panelY + panelH * 0.52)
        let cardW = m.wide ? min(m.w * 0.34, 330 * m.u) : m.w - m.pad * 2
        let pillH = 46 * m.u
        let bottomX = m.wide ? panelW : ring * 1.16
        let bottomW = m.w - bottomX - m.pad
        return ZStack(alignment: .topLeading) {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.92), location: 0.40),
                .init(color: .black.opacity(0.65), location: 0.70),
                .init(color: .black.opacity(0.20), location: 0.90),
                .init(color: .clear, location: 1.0)
            ], startPoint: m.wide ? .leading : .bottom, endPoint: m.wide ? .trailing : .top)
                .opacity(shade)
                .frame(width: m.wide ? panelW * CGFloat(0.65 + shade * 0.65) : m.w, height: m.wide ? m.h : panelH * CGFloat(0.65 + shade * 0.70))
                .offset(y: m.wide ? 0 : m.h - panelH * CGFloat(0.65 + shade * 0.70))
                .allowsHitTesting(false)
            NavBadge(u: m.u).offset(x: m.pad, y: m.pad)
            SpeedRing(data: data, size: ring)
                .position(x: center.x, y: center.y)
            if let limit = data.speedLimit {
                LimitSign(limit: limit, distance: data.speedLimitDistance, size: 50 * m.u)
                    .offset(x: m.wide ? panelW + 20 * m.u : m.w - 72 * m.u, y: m.wide ? m.pad : panelY - 84 * m.u)
            }
            VStack(spacing: 6 * m.u) {
                if data.showsMedia { NavigationMediaHeader(data: data, action: onMedia) }
                ManeuverStack(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                if data.laneCount > 0 { LaneStrip(data: data, u: m.u) }
            }
            .frame(width: cardW)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: m.w - cardW - m.pad, y: m.pad)
            if m.wide {
                TripPill(data: data, u: m.u)
                    .frame(width: min(bottomW, 470 * m.u), height: pillH)
                    .frame(width: bottomW, alignment: .trailing)
                    .offset(x: bottomX, y: m.h - pillH - m.pad * 0.7)
            } else {
                TripPill(data: data, u: m.u, stacked: true)
                    .frame(width: bottomW, height: pillH * 1.5)
                    .offset(x: bottomX, y: m.h - pillH * 1.5 - m.pad)
            }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Touring (ref 3) — vehicle card left, map card right with destination + media

    private func touringLayer(_ m: NavMetrics) -> some View {
        let rect = mapRect(m)
        let card = m.wide
            ? CGRect(x: m.pad, y: m.pad, width: m.w * 0.40 - m.pad * 2, height: m.h - m.pad * 2)
            : CGRect(x: m.pad, y: m.pad, width: m.w - m.pad * 2, height: min(m.h * 0.38, 270 * m.u))
        let inner = rect.width - 24 * m.u
        return ZStack(alignment: .topLeading) {
            VehicleCard(data: data, u: m.u, reduced: reducedMotion, car: car)
                .frame(width: card.width, height: card.height)
                .offset(x: card.minX, y: card.minY)
            HStack(alignment: .top, spacing: 8 * m.u) {
                TurnBanner(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let limit = data.speedLimit {
                    LimitSign(limit: limit, distance: data.speedLimitDistance, size: 46 * m.u)
                }
            }
            .frame(width: inner)
            .offset(x: rect.minX + 12 * m.u, y: rect.minY + 12 * m.u)
            Group {
                if m.wide {
                    HStack(alignment: .bottom, spacing: 8 * m.u) {
                        DestinationCard(data: data, u: m.u, compact: data.showsMedia)
                            .frame(width: data.showsMedia ? inner * 0.54 - 8 * m.u : inner)
                        if data.showsMedia { media(.card, m).frame(width: inner * 0.46) }
                    }
                } else {
                    VStack(spacing: 8 * m.u) {
                        if data.showsMedia { media(.mini, m) }
                        DestinationCard(data: data, u: m.u)
                    }
                }
            }
            .frame(width: inner)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: inner, height: rect.height - 24 * m.u, alignment: .bottom)
            .offset(x: rect.minX + 12 * m.u, y: rect.minY + 12 * m.u)
            if !data.motionValid && data.destination.isEmpty { routeNotice(m, y: card.maxY - 22 * m.u) }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Minimal (ref 4) — black horizon, big speed, chase view on the neon 3D road

    private func minimalLayer(_ m: NavMetrics) -> some View {
        let stage = m.wide
            ? CGRect(x: m.w * 0.12, y: m.h * 0.20, width: m.w * 0.76, height: m.h * 0.80)
            : CGRect(x: 0, y: m.h * 0.22, width: m.w, height: m.h * 0.78)
        let side = m.wide ? m.w * 0.24 : m.w * 0.44
        return ZStack(alignment: .topLeading) {
            carStage("내 차량 · 뒤에서 보기")
                .frame(width: stage.width, height: stage.height)
                .offset(x: stage.minX, y: stage.minY)
            VStack(spacing: 2 * m.u) {
                // Tesla Autopilot Light Status Icons (matching Tesla screen)
                HStack(spacing: 8 * m.u) {
                    Image(systemName: "headlight.low.beam.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 13 * m.u))
                    ZStack {
                        Image(systemName: "headlight.high.beam.fill")
                            .foregroundStyle(Color.white.opacity(0.85))
                            .font(.system(size: 13 * m.u))
                        Text("A")
                            .font(.system(size: 6.5 * m.u, weight: .black))
                            .foregroundStyle(Color.black)
                            .offset(x: 1.5 * m.u)
                    }
                    Image(systemName: "light.beacon.max.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12 * m.u))
                }
                .padding(.bottom, 2 * m.u)

                // Speed & Speed Limit Sign side-by-side (Tesla FSD authentic cluster)
                HStack(alignment: .center, spacing: 12 * m.u) {
                    HStack(alignment: .firstTextBaseline, spacing: 4 * m.u) {
                        Text(data.speed).overspeed(data.overspeedLevel)
                            .font(.system(size: (m.wide ? 68 : 72) * m.u, weight: .light))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.smooth(duration: 0.25), value: data.speed)
                        Text(data.speedUnit.uppercased())
                            .font(.system(size: 13 * m.u, weight: .semibold)).tracking(1.5 * m.u)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    LimitSign(limit: data.speedLimit ?? 30, distance: data.speedLimitDistance, size: 40 * m.u)
                }

                GearRow(gear: data.gear, u: m.u * 0.85, style: .quiet).padding(.top, 4 * m.u)
            }
            .frame(width: m.wide ? m.w * 0.40 : m.w)
            .offset(x: m.wide ? m.w * 0.30 : 0, y: m.pad)

            if m.wide {
                TurnColumn(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                    .frame(width: side, alignment: .leading)
                    .offset(x: m.pad * 1.5, y: m.h * 0.24)
                RangeTag(data: data, u: m.u)
                    .offset(x: m.pad * 1.5, y: m.pad)
                ArrivalColumn(data: data, u: m.u)
                    .frame(width: side, alignment: .trailing)
                    .offset(x: m.w - side - m.pad * 1.5, y: m.h * 0.24)
                ClimateTag(data: data, u: m.u)
                    .frame(width: side, alignment: .trailing)
                    .offset(x: m.w - side - m.pad * 1.5, y: m.pad)
            } else {
                HStack {
                    RangeTag(data: data, u: m.u)
                    Spacer()
                    ClimateTag(data: data, u: m.u)
                }
                .frame(width: m.w - m.pad * 3)
                .offset(x: m.pad * 1.5, y: m.h * 0.16)

                HStack(alignment: .top) {
                    TurnColumn(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                    Spacer()
                    ArrivalColumn(data: data, u: m.u)
                }
                .frame(width: m.w - m.pad * 3)
                .offset(x: m.pad * 1.5, y: m.h * 0.21)
            }

            if data.showsMedia {
                island(m)
                    .frame(width: m.w - m.pad * 3, height: m.h - m.pad, alignment: .bottomLeading)
                    .offset(x: m.pad * 1.5, y: 0)
            }
            if !data.motionValid && data.destination.isEmpty { routeNotice(m, y: stage.minY + stage.height * 0.12) }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Panorama (ref 5) — map | speed + chase view | trip + media

    private func panoramaLayer(_ m: NavMetrics) -> some View {
        // The forecast adds a second guidance row in portrait. Reserve its height
        // above the instruments instead of drawing it over the gear selector.
        let portraitInstrumentTop: CGFloat = data.energyPrediction == nil ? 0.19 : 0.28
        let center = m.wide
            ? CGRect(x: m.w * 0.31, y: 0, width: m.w * 0.39, height: m.h)
            : CGRect(x: 0, y: m.h * portraitInstrumentTop, width: m.w, height: m.h * (0.56 - portraitInstrumentTop))
        let right = m.wide ? CGRect(x: m.w * 0.71, y: 0, width: m.w * 0.29, height: m.h) : .zero
        let carH = center.height * (m.wide ? 0.64 : 0.70)
        return ZStack(alignment: .topLeading) {
            RadialGradient(colors: [NavInk.navyHi.opacity(0.85), .clear], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: center.width * 0.75)
                .opacity(shade)
                .frame(width: center.width, height: center.height)
                .offset(x: center.minX, y: center.minY)
                .allowsHitTesting(false)
            carStage("내 차량 · 뒤에서 보기")
                .frame(width: center.width, height: carH)
                .offset(x: center.minX, y: center.maxY - carH)
            VStack(spacing: 2 * m.u) {
                GearRow(gear: data.gear, u: m.u * 0.85, style: .letters)
                    .accessibilityIdentifier("navigation.panorama.gear")
                HStack(alignment: .center, spacing: 10 * m.u) {
                    VStack(spacing: 0) {
                        Text(data.speed).overspeed(data.overspeedLevel)
                            .font(.system(size: 60 * m.u, weight: .heavy)).italic()
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Text(data.speedUnit).font(.system(size: 13 * m.u, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    }
                    if let limit = data.speedLimit {
                        LimitSign(limit: limit, distance: data.speedLimitDistance, size: 42 * m.u)
                    }
                }
            }
            .frame(width: center.width)
            .offset(x: center.minX, y: center.minY + 8 * m.u)
            RangeMeter(data: data, u: m.u)
                .frame(width: min(center.width * 0.84, 300 * m.u))
                .position(x: center.midX, y: center.maxY - 20 * m.u)
            VStack(alignment: .leading, spacing: 4 * m.u) {
                HStack(spacing: 10 * m.u) {
                    ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 36 * m.u)
                    Text(data.turnDistance).font(.system(size: 34 * m.u, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                }
                GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock).font(.system(size: 16 * m.u, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
                if !data.next.isEmpty {
                    GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock).font(.system(size: 13 * m.u)).foregroundStyle(.black.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .padding(12 * m.u)
            .modifier(TeslaGuidanceSurface(radius: 14 * m.u))
            .modifier(JunctionGuidance(data: data))
            .frame(width: m.wide ? m.w * 0.29 : m.w - m.pad * 2, alignment: .leading)
            .offset(x: m.pad, y: m.pad)
            if m.wide {
                VStack(alignment: .leading, spacing: 10 * m.u) {
                    HStack(spacing: 10 * m.u) {
                        Label(data.outside, systemImage: "cloud.fill").font(.system(size: 16 * m.u, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(data.clock).font(.system(size: 16 * m.u, weight: .semibold)).monospacedDigit()
                    }
                    .lineLimit(1).minimumScaleFactor(0.5)
                    DestinationCard(data: data, u: m.u, compact: true)
                    Spacer(minLength: 0)
                    if data.showsMedia { media(.card, m) }
                }
                .padding(m.pad)
                .frame(width: right.width, height: right.height)
                .offset(x: right.minX, y: right.minY)
            } else {
                VStack(spacing: 8 * m.u) {
                    if data.showsMedia { media(.mini, m) }
                    DestinationCard(data: data, u: m.u, compact: true)
                }
                .frame(width: m.w - m.pad * 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: m.w - m.pad * 2, height: m.h - m.pad * 2, alignment: .bottom)
                .offset(x: m.pad, y: m.pad)
            }
            if !data.motionValid && data.destination.isEmpty { routeNotice(m, y: center.maxY - carH * 0.5) }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Focus (ref 6) — driving visualisation: 3D car on the lane road, glass side columns

    private func focusLayer(_ m: NavMetrics) -> some View {
        let rect = mapRect(m)
        let colW = m.wide ? m.w * 0.25 : m.w - m.pad * 2
        let stage = m.wide
            ? CGRect(x: colW + m.pad * 2, y: 0, width: m.w - (colW + m.pad * 2) * 2, height: m.h)
            : CGRect(x: 0, y: m.h * 0.20, width: m.w, height: m.h * 0.35)
        return ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Color(white: 0.16), .black], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 4, endRadius: stage.width * 0.7)
                .opacity(shade)
                .frame(width: stage.width, height: stage.height)
                .offset(x: stage.minX, y: stage.minY)
                .allowsHitTesting(false)
            carStage("내 차량 · 주행 시각화")
                .frame(width: stage.width, height: stage.height)
                .offset(x: stage.minX, y: stage.minY)
            FocusTurnPill(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                .frame(maxWidth: stage.width - m.pad * 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: stage.width)
                .offset(x: stage.minX, y: stage.minY + m.pad)
            FocusSpeedColumn(data: data, u: m.u, media: m.wide && data.showsMedia ? media(.mini, m) : nil)
                .frame(width: colW, height: m.wide ? m.h - m.pad * 2 : m.h * 0.20 - m.pad * 1.5)
                .offset(x: m.pad, y: m.pad)
            if data.laneCount > 0 {
                LaneStrip(data: data, u: m.u)
                    .frame(width: rect.width)
                    .offset(x: rect.minX, y: m.wide ? rect.maxY + 8 * m.u : rect.maxY - 46 * m.u)
            }
            if !m.wide && data.showsMedia {
                media(.mini, m)
                    .frame(width: rect.width)
                    .offset(x: rect.minX, y: rect.maxY + 8 * m.u)
            }
            FocusArrival(data: data, u: m.u)
                .frame(width: rect.width)
                .offset(x: rect.minX, y: m.wide ? rect.maxY + 8 * m.u : rect.maxY + (!m.wide && data.showsMedia ? 58 * m.u : 8 * m.u))
            EnergyLine(powerKW: data.powerKW, u: m.u)
                .frame(width: stage.width * 0.8, height: 20 * m.u)
                .offset(x: stage.minX + stage.width * 0.1, y: stage.maxY - 26 * m.u)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Running — the character runs in place facing the viewer, paced by the car's speed

    /// v1.30: one source of truth for every running-theme rect, so the map never overlaps the cards.
    /// Portrait: character top 58 %, turn card, then info | map side by side.
    /// Landscape: character left half; right column = turn card, map, info.
    private func runningRects(_ m: NavMetrics) -> (stage: CGRect, turn: CGRect, map: CGRect, info: CGRect) {
        let gap = m.pad
        if m.wide {
            let colX = m.w * 0.50, colW = m.w * 0.50 - gap
            let turn = CGRect(x: colX, y: gap, width: colW, height: 66 * m.u)
            let rest = m.h - turn.maxY - gap * 3
            let map = CGRect(x: colX, y: turn.maxY + gap, width: colW, height: max(0, rest * 0.56))
            let info = CGRect(x: colX, y: map.maxY + gap, width: colW, height: max(0, m.h - map.maxY - gap * 2))
            return (CGRect(x: 0, y: 0, width: m.w * 0.48, height: m.h), turn, map, info)
        }
        let stageH = m.h * 0.58
        let turn = CGRect(x: gap, y: stageH, width: m.w - gap * 2, height: 76 * m.u)
        let lowerY = turn.maxY + gap, lowerH = max(0, m.h - lowerY - gap)
        let infoW = (m.w - gap * 3) * 0.48
        let info = CGRect(x: gap, y: lowerY, width: infoW, height: lowerH)
        let map = CGRect(x: info.maxX + gap, y: lowerY, width: m.w - info.maxX - gap * 2, height: lowerH)
        return (CGRect(x: 0, y: 0, width: m.w, height: stageH), turn, map, info)
    }

    private func runningLayer(_ m: NavMetrics) -> some View {
        let r = runningRects(m)
        let stage = r.stage, turn = r.turn, info = r.info
        return ZStack(alignment: .topLeading) {
            CharacterRunnerView(speedKmh: data.speedKmh)
                .frame(width: stage.width, height: stage.height * 0.94)
                .offset(x: stage.minX, y: stage.minY + stage.height * 0.04)
                .allowsHitTesting(true) // v1.37: drag to orbit in portrait and landscape
            RunningTurnCard(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                .frame(width: turn.width, height: turn.height)
                .offset(x: turn.minX, y: turn.minY)
            RunningInfoPanel(data: data, u: m.u)
                .frame(width: info.width, height: max(0, info.height))
                .offset(x: info.minX, y: info.minY)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    // MARK: Fleet (ref 7) — map-first operations console

    private func fleetLayer(_ m: NavMetrics) -> some View {
        let panelW = m.wide ? min(m.w * 0.36, 320 * m.u) : m.w - m.pad * 2
        let panelH = m.wide ? m.h - m.pad * 2 : m.h * 0.48
        let panelY = m.wide ? m.pad : m.h - panelH - m.pad
        // Portrait stacks the panel below, so the maneuver column uses the full width.
        let rightW = m.wide ? min(300 * m.u, m.w - panelW - m.pad * 3) : m.w - m.pad * 2
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                .opacity(shade)
                .frame(width: panelW + m.pad * 4, height: m.h)
                .allowsHitTesting(false)
            FleetPanel(data: data, u: m.u)
                .frame(width: panelW, height: panelH)
                .offset(x: m.pad, y: panelY)
            HStack(spacing: 6 * m.u) {
                Chip(text: data.clock.isEmpty ? "—" : data.clock, icon: "clock", u: m.u)
                Chip(text: data.outside, icon: "thermometer.medium", u: m.u)
                Chip(text: data.connected ? "차량 연결" : "신호 없음", icon: "antenna.radiowaves.left.and.right", u: m.u, tint: data.connected ? NavInk.green : .orange)
            }
            .frame(width: m.w - m.pad * 2, alignment: .trailing)
            .offset(x: m.pad, y: m.pad)
            VStack(alignment: .trailing, spacing: 8 * m.u) {
                if data.showsMedia { NavigationMediaHeader(data: data, action: onMedia).frame(width: rightW) }
                TurnBanner(data: data, u: m.u).modifier(JunctionGuidance(data: data))
                    .frame(width: rightW, alignment: .leading)
                if data.laneCount > 0 { LaneStrip(data: data, u: m.u).frame(width: rightW) }
                if !m.wide, let limit = data.speedLimit {
                    LimitSign(limit: limit, distance: data.speedLimitDistance, size: 46 * m.u)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: m.w - rightW - m.pad, y: m.pad + 44 * m.u)
            if m.wide, let limit = data.speedLimit {
                LimitSign(limit: limit, distance: data.speedLimitDistance, size: 46 * m.u)
                    .offset(x: m.w - rightW - m.pad - 58 * m.u, y: m.pad + 44 * m.u)
            }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }
}

private struct HorizonGlow: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - Shared components

private struct NavBadge: View {
    let u: CGFloat
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 15 * u, weight: .bold))
            .frame(width: 34 * u, height: 34 * u)
            .background(NavInk.blue, in: RoundedRectangle(cornerRadius: 8 * u, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct SpeedRing: View {
    let data: NavigationReadout
    let size: CGFloat
    private var fraction: Double { min(1, max(0, data.speedFraction.isFinite ? data.speedFraction : 0)) }
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: max(3, size * 0.03), lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * fraction)
                .stroke(NavInk.green, style: StrokeStyle(lineWidth: max(3, size * 0.03), lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.45), value: fraction)
            VStack(spacing: 0) {
                Text(data.speed).overspeed(data.overspeedLevel)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .monospacedDigit().tracking(-size * 0.012)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth(duration: 0.25), value: data.speed)
                Text(data.speedUnit)
                    .font(.system(size: size * 0.075, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                GearRow(gear: data.gear, u: size / 230, style: .letters)
                    .padding(.top, size * 0.07)
            }
            .frame(width: size * 0.84)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
    }
}

private enum GearStyle { case letters, quiet }

private struct GearRow: View {
    let gear: String
    let u: CGFloat
    let style: GearStyle
    var body: some View {
        HStack(spacing: 12 * u) {
            ForEach(["P", "R", "N", "D"], id: \.self) { item in
                let on = gear == item
                Text(item)
                    .font(.system(size: 17 * u, weight: .bold))
                    .foregroundStyle(on ? .white : NavInk.gearOff)
                    .frame(width: 26 * u, height: 26 * u)
                    .background(RoundedRectangle(cornerRadius: 6 * u, style: .continuous)
                        .fill(on ? (style == .letters ? NavInk.blue : Color.white.opacity(0.14)) : .clear))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("기어 \(gear)")
    }
}

private struct LimitSign: View {
    let limit: Int
    let distance: String
    let size: CGFloat
    var body: some View {
        VStack(spacing: 2) {
            Text("\(limit)")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
                .overlay(Circle().stroke(NavInk.red, lineWidth: size * 0.11))
            if !distance.isEmpty {
                Text(distance)
                    .font(.system(size: size * 0.24, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(NavInk.red, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("제한 속도 \(limit)")
    }
}

/// Ref 1: blue maneuver card, dark follow-up row.
private struct ManeuverStack: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14 * u) {
                ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 50 * u)
                VStack(alignment: .leading, spacing: 2 * u) {
                    Text(data.turnDistance)
                        .font(.system(size: 34 * u, weight: .bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock)
                        .font(.system(size: 15 * u, weight: .semibold))
                        .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14 * u)
            .background(Color.clear)
            if !data.next.isEmpty {
                HStack(spacing: 10 * u) {
                    GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock)
                        .font(.system(size: 14 * u, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 4 * u)
                    ManeuverGlyph(symbol: data.nextSymbol, exitClock: data.nextExitClock, size: 22 * u)
                        .padding(3 * u)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5 * u))
                }
                .padding(.horizontal, 14 * u)
                .frame(height: 38 * u)
                .background(Color.black.opacity(0.04))
            }
        }
        .modifier(TeslaGuidanceSurface(radius: 12 * u))
        .clipShape(RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10 * u, y: 6 * u)
        .accessibilityElement(children: .contain)
    }
}

/// Ref 3: compact blue banner inside the map card.
private struct TurnBanner: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 4 * u) {
            HStack(spacing: 10 * u) {
                ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 28 * u)
                if !data.turnDistance.isEmpty && data.turnDistance != "—" {
                    Text(data.turnDistance)
                        .font(.system(size: 26 * u, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.25), value: data.turnDistance)
                }
            }
            GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock)
                .font(.system(size: 15 * u, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(0.8)
            if !data.next.isEmpty {
                GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock)
                    .font(.system(size: 13 * u, weight: .medium))
                    .foregroundStyle(.black.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 16 * u).padding(.vertical, 12 * u)
        .modifier(TeslaGuidanceSurface(radius: 16 * u))
        .shadow(color: .black.opacity(0.12), radius: 10 * u, y: 4 * u)
        .accessibilityElement(children: .contain)
    }
}

private struct TurnColumn: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 4 * u) {
            HStack(spacing: 8 * u) {
                ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 28 * u)
                Text(data.turnDistance)
                    .font(.system(size: 34 * u, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock)
                .font(.system(size: 18 * u, weight: .medium))
                .foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            if !data.next.isEmpty {
                GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock)
                    .font(.system(size: 16 * u)).foregroundStyle(.black.opacity(0.65))
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10 * u)
        .modifier(TeslaGuidanceSurface(radius: 16 * u))
        .accessibilityElement(children: .contain)
    }
}

private struct ArrivalColumn: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(alignment: .trailing, spacing: 4 * u) {
            Text(data.arrival).font(.system(size: 26 * u, weight: .semibold)).monospacedDigit()
            Text("\(data.remaining) · \(data.remainingDistance)")
                .font(.system(size: 16 * u)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.5)
            if !data.destination.isEmpty {
                Text(data.destination).font(.system(size: 16 * u)).foregroundStyle(NavInk.muted).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RangeTag: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        HStack(spacing: 8 * u) {
            BatteryGauge(level: data.batterySOC, width: 26 * u).font(.system(size: 15 * u))
            Text(data.range).font(.system(size: 15 * u, weight: .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ClimateTag: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        HStack(spacing: 6 * u) {
            Image(systemName: "thermometer.medium").font(.system(size: 14 * u))
            Text(data.outside).font(.system(size: 15 * u, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }
}

private struct TripPill: View {
    let data: NavigationReadout
    let u: CGFloat
    var stacked = false
    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 4 * u) {
                    HStack(spacing: 10 * u) { arrival; distance }
                    HStack(spacing: 10 * u) { remaining; Spacer(minLength: 0); battery }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14 * u) { arrival; distance; remaining; Spacer(minLength: 4 * u); signal; battery }
                    HStack(spacing: 10 * u) { arrival; distance; Spacer(minLength: 4 * u); battery }
                    HStack(spacing: 8 * u) { arrival; Spacer(minLength: 2 * u); distance }
                }
            }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        .padding(.horizontal, 14 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { GlassFill(radius: 12 * u) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("도착 \(data.arrival), 남은 거리 \(data.remainingDistance), \(data.remaining), 배터리 \(data.battery)")
    }
    private var arrival: some View { Text(data.arrival).font(.system(size: 18 * u, weight: .bold)) }
    private var distance: some View { Text(data.remainingDistance).font(.system(size: 17 * u, weight: .semibold)) }
    private var remaining: some View { Text(data.remaining).font(.system(size: 15 * u)).foregroundStyle(.white.opacity(0.8)).layoutPriority(1) }
    @ViewBuilder private var signal: some View {
        if !data.connected { Text("신호 없음").font(.system(size: 14 * u, weight: .medium)).foregroundStyle(.orange) }
    }
    private var battery: some View {
        HStack(spacing: 6 * u) {
            BatteryGauge(level: data.batterySOC, width: 28 * u).font(.system(size: 14 * u))
            Text(stacked ? data.battery : "\(data.battery) · \(data.range)").font(.system(size: 16 * u, weight: .semibold))
        }.fixedSize().layoutPriority(2) // v1.31: never "3…" — the battery % always shows in full
    }
}

/// Translucent dark glass: the map stays readable underneath.
private struct GlassFill: View {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        // iOS Maps-style sheet: system material only, no gradient rim.
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(colorScheme == .dark ? .regularMaterial : .thickMaterial)
    }
}

/// v33: a borderless panel — soft blurred scrim with no stroke, faded at the edges so the card
/// blends into the map and its neighbours instead of sitting in a drawn box.
private struct SoftPanel: View {
    let radius: CGFloat
    var strength: CGFloat = 0.5
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(.regularMaterial)
            shape.fill(NavInk.card.opacity(0.55))
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}

/// Ref 3 bottom card: destination, progress, distance · time, arrival.
private struct DestinationCard: View {
    let data: NavigationReadout
    let u: CGFloat
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            HStack(spacing: 10 * u) {
                Image(systemName: data.destination.isEmpty ? "location.circle.fill" : "flag.checkered")
                    .font(.system(size: 15 * u, weight: .semibold))
                    .foregroundStyle(data.destination.isEmpty ? Color.cyan : Color.white)
                    .frame(width: 32 * u, height: 32 * u)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
                Text(data.destination.isEmpty ? "자유 주행 모드" : data.destination)
                    .font(.system(size: 16 * u, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let soc = data.arrivalSOC, soc.isFinite {
                    Label("\(finiteInt(soc.rounded()))%", systemImage: "bolt.fill")
                        .font(.system(size: 14 * u, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5).layoutPriority(1)
                        .foregroundStyle(soc < 15 ? NavInk.amber : NavInk.green)
                        .accessibilityLabel("도착 시 배터리 \(finiteInt(soc.rounded()))%")
                }
            }
            if !data.destination.isEmpty {
                ProgressTrack(value: data.routeProgress, u: u)
                HStack(alignment: .firstTextBaseline, spacing: 6 * u) {
                    Text(data.remainingDistance).font(.system(size: 18 * u, weight: .semibold))
                    Text("·").foregroundStyle(NavInk.muted)
                    Text(data.remaining).font(.system(size: 16 * u, weight: .semibold)).foregroundStyle(NavInk.neon)
                    Spacer(minLength: 4 * u)
                    if !compact { Text("도착").font(.system(size: 14 * u)).foregroundStyle(NavInk.muted) }
                    Text(data.arrival).font(.system(size: 16 * u, weight: .semibold))
                }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            } else {
                HStack(spacing: 6 * u) {
                    Text("실시간 차량 속도 및 지도 연동 활성")
                        .font(.system(size: 13 * u, weight: .medium))
                        .foregroundStyle(NavInk.muted)
                    Spacer()
                    Text(data.clock)
                        .font(.system(size: 14 * u, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(14 * u)
        .background { GlassFill(radius: 14 * u) }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressTrack: View {
    let value: Double?
    let u: CGFloat
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                if let value, value.isFinite {
                    Capsule().fill(NavInk.blue).frame(width: g.size.width * CGFloat(min(1, max(0, value))))
                }
            }
        }
        .frame(height: 5 * u)
        .accessibilityHidden(true)
    }
}

/// Ref 3 left card: 3/4-view car driving on a lane road, speed, climate/gear tiles, range ticks.
private struct VehicleCard<CarContent: View>: View {
    let data: NavigationReadout
    let u: CGFloat
    let reduced: Bool
    @ViewBuilder var car: () -> CarContent
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dynamicU = min(u, max(0.72, h / 290))
            let stageH = min(h * 0.42, w * 0.45)
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RadialGradient(colors: [NavInk.neon.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.75),
                                   startRadius: 2, endRadius: w * 0.6)
                    // The 3D view draws the car on its own lane road (same camera, so road and car always agree).
                    car()
                        .allowsHitTesting(false)
                        .frame(width: w, height: stageH)
                        .accessibilityLabel("내 차량 · 대각선 위에서 보기")
                }
                .frame(width: w, height: stageH)
                .clipped()
                HStack(alignment: .firstTextBaseline, spacing: 6 * dynamicU) {
                    Text(data.speed).overspeed(data.overspeedLevel)
                        .font(.system(size: min(42 * dynamicU, h * 0.15), weight: .regular)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(data.speedUnit).font(.system(size: 14 * dynamicU)).foregroundStyle(NavInk.muted)
                    Spacer(minLength: 0)
                    GearRow(gear: data.gear, u: dynamicU * 0.72, style: .letters)
                }
                .padding(.horizontal, 14 * dynamicU)
                HStack(spacing: 8 * dynamicU) {
                    Tile(icon: "fanblades.fill", title: "실내", value: data.inside, u: dynamicU)
                    Tile(icon: "thermometer.sun.fill", title: "외기", value: data.outside, u: dynamicU)
                }
                .padding(.horizontal, 12 * dynamicU).padding(.top, 4 * dynamicU)
                Spacer(minLength: 2 * dynamicU)
                HStack {
                    Text("주행 가능").font(.system(size: 14 * dynamicU)).foregroundStyle(NavInk.muted)
                    Spacer()
                    Text(data.range).font(.system(size: 13 * dynamicU, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 14 * dynamicU)
                TickBar(value: data.batterySOC.map { $0 / 100 }, u: dynamicU)
                    .frame(height: 14 * dynamicU)
                    .padding(.horizontal, 14 * dynamicU).padding(.top, 2 * dynamicU).padding(.bottom, 10 * dynamicU)
            }
            .frame(width: w, height: h)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 26 * u, style: .continuous).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 26 * u, style: .continuous).fill(NavInk.card.opacity(0.6))
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 16 * u, y: 8 * u)
        }
    }
}

private struct Tile: View {
    let icon: String
    let title: String
    let value: String
    let u: CGFloat
    var body: some View {
        HStack(spacing: 8 * u) {
            Image(systemName: icon)
                .font(.system(size: 14 * u, weight: .semibold))
                .frame(width: 26 * u, height: 26 * u)
                .background(NavInk.blue, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 13 * u)).foregroundStyle(NavInk.muted)
                Text(value).font(.system(size: 14 * u, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
        .padding(10 * u)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16 * u, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct TickBar: View {
    let value: Double?
    let u: CGFloat
    var body: some View {
        GeometryReader { g in
            let count = max(10, finiteInt(Double(g.size.width / max(0.01, 5 * u)), 10))
            let on = finiteInt(Double(count) * min(1, max(0, value ?? 0)))
            HStack(spacing: 2 * u) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i < on ? NavInk.blue : Color.white.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: i == on - 1 ? g.size.height : g.size.height * 0.7)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Ref 5: range meter with min/max estimate.
private struct RangeMeter: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(spacing: 4 * u) {
            Text(data.range).font(.system(size: 14 * u, weight: .semibold)).monospacedDigit()
            HStack(spacing: 8 * u) {
                Text(data.battery).font(.system(size: 13 * u)).foregroundStyle(NavInk.muted)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(NavInk.green)
                            .frame(width: g.size.width * CGFloat(min(1, max(0, (data.batterySOC ?? 0) / 100))))
                    }
                }
                .frame(height: 4 * u)
                Image(systemName: "bolt.fill").font(.system(size: 12 * u)).foregroundStyle(NavInk.green)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ref 6 bottom line: regen (blue) ← 0 → power (green→red); marker shows live motor power.
private struct EnergyLine: View {
    let powerKW: Double?
    let u: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let p = powerKW ?? 0
            let zero = w * 0.3
            let x = zero + (p >= 0 ? CGFloat(min(1, p / 200)) * (w - zero) : CGFloat(max(-1, p / 80)) * zero)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(width: w, height: 3 * u).offset(y: 8 * u)
                Capsule()
                    .fill(LinearGradient(colors: p >= 0 ? [NavInk.green, .yellow, NavInk.red] : [NavInk.neon, NavInk.neon.opacity(0.6)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: abs(x - zero), height: 3 * u)
                    .offset(x: min(x, zero), y: 8 * u)
                    .animation(.easeOut(duration: 0.4), value: p)
                Rectangle().fill(.white.opacity(0.6)).frame(width: 1, height: 9 * u).offset(x: zero, y: 5 * u)
                Text("회생").font(.system(size: 11 * u, weight: .medium)).foregroundStyle(NavInk.muted).offset(y: -4 * u)
                Text("출력").font(.system(size: 11 * u, weight: .medium)).foregroundStyle(NavInk.muted)
                    .frame(width: w, alignment: .trailing).offset(y: -4 * u)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(powerKW.map { "모터 출력 \(Int($0)) 킬로와트" } ?? "모터 출력 미수신")
    }
}

/// Kakao lane guidance (left → right). Recommended lanes are blue; this is guidance, not the car's measured lane.
private struct LaneStrip: View {
    let data: NavigationReadout
    let u: CGFloat

    private func laneSymbol(at index: Int) -> String {
        let parts = data.laneRaw.split(separator: ",")
        if index < parts.count {
            let segs = parts[index].split(separator: "/")
            if let first = segs.first, let code = Int(first) {
                switch code {
                case 2: return "arrow.turn.up.left"
                case 3: return "arrow.turn.up.right"
                case 4: return "arrow.uturn.down"
                case 5: return "arrow.up.left"
                case 6: return "arrow.up.right"
                case 7: return "arrow.turn.up.left"
                case 8: return "arrow.up.left"
                case 9: return "arrow.up.right"
                default: return "arrow.up"
                }
            }
        }
        return "arrow.up"
    }

    var body: some View {
        HStack(spacing: 6 * u) {
            HStack(spacing: 3 * u) {
                ForEach(0..<max(1, data.laneCount), id: \.self) { i in
                    let on = data.laneSuggested.contains(i)
                    Image(systemName: laneSymbol(at: i))
                        .font(.system(size: 14 * u, weight: .bold))
                        .foregroundStyle(on ? .white : .white.opacity(0.35))
                        .frame(width: 22 * u, height: 26 * u)
                        .background(on ? NavInk.blue : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4 * u))
                }
            }
            Spacer(minLength: 0)
            if !data.laneDistance.isEmpty {
                Text(data.laneDistance).font(.system(size: 14 * u, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(6 * u)
        .background { GlassFill(radius: 8 * u) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("차로 안내 \(data.laneCount)차로 중 \(data.laneSuggested.map { "\($0 + 1)" }.joined(separator: ", "))차로 권장")
    }
}

private struct FocusTurnPill: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        HStack(spacing: 10 * u) {
            ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 26 * u)
            Text(data.turnDistance).font(.system(size: 22 * u, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Rectangle().fill(.black.opacity(0.15)).frame(width: 1, height: 18 * u)
            GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock).font(.system(size: 15 * u, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16 * u).padding(.vertical, 8 * u).frame(minHeight: 50 * u)
        .modifier(TeslaGuidanceSurface(radius: 25 * u))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
    }
}

private struct FocusSpeedColumn: View {
    let data: NavigationReadout
    let u: CGFloat
    var media: MediaCard? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10 * u) {
            HStack(spacing: 10 * u) {
                ForEach(["P", "R", "N", "D"], id: \.self) { g in
                    Text(g).font(.system(size: 15 * u, weight: .bold))
                        .foregroundStyle(data.gear == g ? .white : NavInk.gearOff)
                }
                Spacer(minLength: 0)
                if let limit = data.speedLimit { LimitSign(limit: limit, distance: "", size: 32 * u) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(data.speed).overspeed(data.overspeedLevel).font(.system(size: 64 * u, weight: .light)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(data.speedUnit.uppercased()).font(.system(size: 13 * u, weight: .semibold)).tracking(1.5 * u)
                    .foregroundStyle(NavInk.muted)
            }
            Spacer(minLength: 0)
            if let media { media }
            VStack(alignment: .leading, spacing: 6 * u) {
                HStack {
                    Image(systemName: "bolt.fill").font(.system(size: 12 * u)).foregroundStyle(NavInk.green)
                    Text(data.battery).font(.system(size: 15 * u, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(data.range).font(.system(size: 15 * u, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [NavInk.green.opacity(0.7), NavInk.green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * CGFloat(min(1, max(0, (data.batterySOC ?? 0) / 100))))
                    }
                }
                .frame(height: 5 * u)
            }
        }
        .padding(16 * u)
        .background { SoftPanel(radius: 26 * u, strength: 0.5) }
        .accessibilityElement(children: .contain)
    }
}

private struct FocusArrival: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            HStack(alignment: .firstTextBaseline) {
                Text(data.arrival).font(.system(size: 20 * u, weight: .semibold))
                Text("도착").font(.system(size: 13 * u)).foregroundStyle(NavInk.muted)
                Spacer(minLength: 0)
                Text("\(data.remaining) · \(data.remainingDistance)").font(.system(size: 14 * u)).foregroundStyle(.white.opacity(0.75))
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            ProgressTrack(value: data.routeProgress, u: u)
            if !data.next.isEmpty {
                HStack(spacing: 6 * u) {
                    ManeuverGlyph(symbol: data.nextSymbol, exitClock: data.nextExitClock, size: 16 * u)
                    GuidanceCardLabel(text: data.next, symbol: data.nextSymbol, exitClock: data.nextExitClock).font(.system(size: 13 * u)).foregroundStyle(NavInk.muted).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
        }
        .padding(14 * u)
        .background { SoftPanel(radius: 22 * u, strength: 0.5) }
        .accessibilityElement(children: .contain)
    }
}

/// Ref 7 left panel: header, route timeline, stat grid, battery.
private struct FleetPanel: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        // Compact variant drops the timeline and footer when the panel is short (landscape phones).
        ViewThatFits(in: .vertical) {
            content(full: true)
            content(full: false)
        }
        .padding(14 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18 * u, style: .continuous))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 16 * u, y: 8 * u)
        .accessibilityElement(children: .contain)
    }
    private func content(full: Bool) -> some View {
        VStack(alignment: .leading, spacing: (full ? 12 : 8) * u) {
            HStack(spacing: 8 * u) {
                VStack(alignment: .leading, spacing: 1 * u) {
                    Text(data.vehicleName).font(.system(size: 16 * u, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 5 * u) {
                        Circle().fill(data.connected ? NavInk.green : .orange).frame(width: 7 * u, height: 7 * u)
                        Text(data.connected ? "주행 중" : "차량 신호 없음").font(.system(size: 14 * u, weight: .semibold))
                            .foregroundStyle(data.connected ? NavInk.green : .orange)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3 * u) {
                    Text(data.speed).overspeed(data.overspeedLevel).font(.system(size: 30 * u, weight: .semibold)).monospacedDigit()
                    Text(data.speedUnit).font(.system(size: 13 * u)).foregroundStyle(NavInk.muted)
                }
                Text(data.gear).font(.system(size: 15 * u, weight: .bold))
                    .frame(width: 26 * u, height: 26 * u)
                    .background(NavInk.blue, in: RoundedRectangle(cornerRadius: 7 * u))
            }
            if full {
            HStack(alignment: .top, spacing: 10 * u) {
                VStack(spacing: 0) {
                    Circle().stroke(NavInk.neon, lineWidth: 2 * u).frame(width: 10 * u, height: 10 * u)
                    Rectangle().fill(LinearGradient(colors: [NavInk.neon, NavInk.green], startPoint: .top, endPoint: .bottom))
                        .frame(width: 2 * u).frame(maxHeight: .infinity)
                    Circle().fill(NavInk.green).frame(width: 10 * u, height: 10 * u)
                }
                .frame(height: 84 * u)
                VStack(alignment: .leading, spacing: 0) {
                    Text("현재 도로").font(.system(size: 12 * u)).foregroundStyle(NavInk.muted)
                    Text(data.road).font(.system(size: 15 * u, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.75)
                    Spacer(minLength: 4 * u)
                    Text("목적지").font(.system(size: 12 * u)).foregroundStyle(NavInk.muted)
                    Text(data.destination.isEmpty ? "—" : data.destination).font(.system(size: 15 * u, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.75)
                }
                .frame(height: 84 * u)
            }
            }
            VStack(alignment: .leading, spacing: 5 * u) {
                HStack {
                    Text("경로 진행").font(.system(size: 13 * u, weight: .semibold)).foregroundStyle(NavInk.muted)
                    Spacer()
                    Text(data.routeProgress.map { "\(finiteInt(($0 * 100).rounded()))%" } ?? "—")
                        .font(.system(size: 13 * u, weight: .semibold)).monospacedDigit()
                }
                ProgressTrack(value: data.routeProgress, u: u * 1.4)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6 * u), GridItem(.flexible(), spacing: 6 * u)], spacing: 6 * u) {
                stat("남은 거리", data.remainingDistance)
                stat("남은 시간", data.remaining.replacingOccurrences(of: " 남음", with: ""))
                stat("도착", data.arrival)
                stat("주행 가능", data.range)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5 * u) {
                HStack {
                    Text("배터리").font(.system(size: 13 * u, weight: .semibold)).foregroundStyle(NavInk.muted)
                    Spacer()
                    Text(data.battery).font(.system(size: 14 * u, weight: .semibold)).monospacedDigit()
                }
                SegmentBar(value: data.batterySOC.map { $0 / 100 }, u: u).frame(height: 14 * u)
            }
            if full {
            HStack(spacing: 8 * u) {
                Label(data.outside, systemImage: "thermometer.medium")
                Spacer(minLength: 0)
                Label(data.odometer, systemImage: "road.lanes")
            }
            .font(.system(size: 13 * u)).foregroundStyle(NavInk.muted).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2 * u) {
            Text(label).font(.system(size: 12 * u)).foregroundStyle(NavInk.muted)
            Text(value).font(.system(size: 15 * u, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * u)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16 * u, style: .continuous))
    }
}

private struct SegmentBar: View {
    let value: Double?
    let u: CGFloat
    var body: some View {
        GeometryReader { g in
            let count = max(12, finiteInt(Double(g.size.width / max(0.01, 6 * u)), 12))
            let on = finiteInt(Double(count) * min(1, max(0, value ?? 0)))
            HStack(spacing: 2 * u) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(i < on ? NavInk.green : Color.white.opacity(0.12))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Chip: View {
    let text: String
    var icon: String? = nil
    let u: CGFloat
    var tint: Color = .white
    var body: some View {
        HStack(spacing: 5 * u) {
            if let icon { Image(systemName: icon).font(.system(size: 13 * u, weight: .semibold)) }
            Text(text).font(.system(size: 15 * u, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11 * u).frame(height: 30 * u)
        .background(.regularMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .lineLimit(1).minimumScaleFactor(0.5)
    }
}

// MARK: - Car media

/// Now-playing card for the car's media (BLE media state) with play/pause, track and volume controls.
/// Commands go through VehicleLink.mediaCommand; buttons are disabled without an authenticated link.
private struct MediaCard: View {
    enum Style { case mini, card }
    let data: NavigationReadout
    let u: CGFloat
    let style: Style
    let action: (String) -> Void

    var body: some View {
        Group {
            if style == .mini { mini } else { card }
        }
        .padding(style == .mini ? 8 * u : 12 * u)
        .background { GlassFill(radius: (style == .mini ? 14 : 18) * u) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation.media")
    }

    private var enabled: Bool { data.mediaControllable }
    private var title: String {
        if !data.mediaTitle.isEmpty { return data.mediaTitle }
        return data.hasMedia ? data.mediaApp.name : "재생 정보 없음"
    }
    private var subtitle: String {
        if !data.mediaStatus.isEmpty { return data.mediaStatus }
        let parts = [data.mediaArtist, data.mediaTitle.isEmpty ? "" : data.mediaApp.name].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return data.connected ? "차량 미디어" : "차량 연결 필요"
    }
    private var icon: String {
        let s = data.mediaSource.lowercased()
        if s.contains("bluetooth") || s.contains("블루투스") { return "headphones" }
        if s.contains("radio") || s.contains("라디오") || s.contains("fm") { return "radio" }
        if s.contains("podcast") || s.contains("팟캐스트") { return "mic.fill" }
        return "music.note"
    }
    private var progress: Double? {
        guard let e = data.mediaElapsed, let d = data.mediaDuration, d > 0, e.isFinite else { return nil }
        return min(1, max(0, e / d))
    }

    private func art(_ side: CGFloat) -> some View {
        PlaybackArtwork(data: data, side: side)
    }

    private func control(_ name: String, _ symbol: String, _ label: String, size: CGFloat) -> some View {
        Button { action(name) } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: max(44, size * 2), height: max(44, size * 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityIdentifier("media." + name)
    }

    private var toggleSymbol: String { data.mediaPlaying ? "pause.fill" : "play.fill" }
    private var toggleLabel: String { data.mediaPlaying ? "일시정지" : "재생" }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2 * u) {
            Text(title).font(.system(size: 16 * u, weight: .semibold))
                .lineLimit(style == .mini ? 1 : 2).minimumScaleFactor(0.7)
                .accessibilityIdentifier("navigation.media.title")
            Text(subtitle).font(.system(size: 13 * u))
                .foregroundStyle(data.mediaStatus.isEmpty ? NavInk.muted : NavInk.amber)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mini: some View {
        HStack(spacing: 8 * u) {
            art(40 * u)
            texts
            control("mediaToggle", toggleSymbol, toggleLabel, size: 18 * u)
            control("mediaNext", "forward.fill", "다음 곡", size: 16 * u)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            HStack(spacing: 10 * u) {
                art(46 * u)
                texts
            }
            if let progress {
                HStack(spacing: 8 * u) {
                    Text(clock(data.mediaElapsed))
                    ProgressTrack(value: progress, u: u)
                    Text(clock(data.mediaDuration))
                }
                .font(.system(size: 12 * u)).monospacedDigit().foregroundStyle(NavInk.muted)
            }
            // Narrow cards keep the transport controls and drop the volume pair.
            ViewThatFits(in: .horizontal) {
                transport(volume: true)
                transport(volume: false)
            }
            .frame(height: 40 * u)
        }
    }

    private func transport(volume: Bool) -> some View {
        HStack(spacing: 0) {
            control("mediaPrev", "backward.fill", "이전 곡", size: 16 * u)
            Spacer(minLength: 0)
            control("mediaToggle", toggleSymbol, toggleLabel, size: 22 * u)
            Spacer(minLength: 0)
            control("mediaNext", "forward.fill", "다음 곡", size: 16 * u)
            if volume && data.connected {
                Spacer(minLength: 0)
                control("mediaVolumeDown", "speaker.minus.fill", "볼륨 낮추기", size: 14 * u)
                control("mediaVolumeUp", "speaker.plus.fill", "볼륨 높이기", size: 14 * u)
            }
        }
    }

    private func clock(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Minimal now-playing capsule (Dynamic Island style). Tap to expand for track controls; collapses after 5 s.
/// One compact row above maneuver guidance; never floats over the route or expands into it.
struct ParkedNavigationActions: View {
    let stop: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Label("길안내 중", systemImage: "location.fill")
                .font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 8)
            NavigationEndButton(stop: stop)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .foregroundStyle(.white).background(Color.black)
    }
}

struct NavigationEndButton: View {
    let stop: () -> Void
    var body: some View {
        Button(action: stop) {
            Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("안내 종료")
        .accessibilityIdentifier("navigation.parked.stop")
    }
}

/// Small vector source marks stay legible in every media layout without network artwork requests.
private struct PlaybackSourceIcon: View {
    let source: MediaPlaybackSource
    let side: CGFloat
    var body: some View {
        Canvas { context, size in
            let s = size.width
            let bounds = CGRect(origin: .zero, size: size)
            switch source.icon {
            case .spotify:
                context.fill(Path(ellipseIn: bounds), with: .color(Color(red: 0.12, green: 0.84, blue: 0.38)))
                for i in 0..<3 {
                    let inset = (0.21 + Double(i) * 0.035) * s
                    let y = (0.34 + Double(i) * 0.16) * s
                    var wave = Path(); wave.move(to: CGPoint(x: inset, y: y))
                    wave.addQuadCurve(to: CGPoint(x: s - inset, y: y + 0.035 * s), control: CGPoint(x: 0.5 * s, y: y - 0.13 * s))
                    context.stroke(wave, with: .color(.black), style: StrokeStyle(lineWidth: s * (0.075 - Double(i) * 0.012), lineCap: .round))
                }
            case .youtubeMusic:
                context.fill(Path(ellipseIn: bounds), with: .color(.red))
                context.stroke(Path(ellipseIn: bounds.insetBy(dx: s * 0.16, dy: s * 0.16)), with: .color(.white), lineWidth: s * 0.035)
                var play = Path(); play.move(to: CGPoint(x: s * 0.42, y: s * 0.32))
                play.addLine(to: CGPoint(x: s * 0.69, y: s * 0.5)); play.addLine(to: CGPoint(x: s * 0.42, y: s * 0.68)); play.closeSubpath()
                context.fill(play, with: .color(.white))
            case .tidal:
                context.fill(Path(roundedRect: bounds, cornerRadius: s * 0.2), with: .color(.black))
                for point in [(0.25, 0.36), (0.5, 0.36), (0.75, 0.36), (0.5, 0.61)] {
                    let x = point.0 * s, y = point.1 * s, r = s * 0.12
                    var diamond = Path(); diamond.move(to: CGPoint(x: x, y: y - r))
                    diamond.addLine(to: CGPoint(x: x + r, y: y)); diamond.addLine(to: CGPoint(x: x, y: y + r)); diamond.addLine(to: CGPoint(x: x - r, y: y)); diamond.closeSubpath()
                    context.fill(diamond, with: .color(.white))
                }
            case .netflix:
                context.fill(Path(roundedRect: bounds, cornerRadius: s * 0.2), with: .color(.black))
                context.draw(Text("N").font(.system(size: s * 0.82, weight: .black)).foregroundStyle(.red), at: CGPoint(x: s / 2, y: s / 2))
            default:
                let color: Color
                switch source.icon {
                case .appleMusic: color = Color(red: 0.97, green: 0.22, blue: 0.36)
                case .youtube: color = .red
                case .video, .game: color = .purple
                case .usb, .aux: color = .gray
                default: color = .blue
                }
                context.fill(Path(roundedRect: bounds, cornerRadius: s * 0.22), with: .color(color))
                if source.icon == .bluetooth {
                    var rune = Path(); rune.move(to: CGPoint(x: s * 0.5, y: s * 0.14))
                    rune.addLine(to: CGPoint(x: s * 0.5, y: s * 0.86)); rune.addLine(to: CGPoint(x: s * 0.76, y: s * 0.66)); rune.addLine(to: CGPoint(x: s * 0.25, y: s * 0.29))
                    rune.move(to: CGPoint(x: s * 0.25, y: s * 0.71)); rune.addLine(to: CGPoint(x: s * 0.76, y: s * 0.34)); rune.addLine(to: CGPoint(x: s * 0.5, y: s * 0.14))
                    context.stroke(rune, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round, lineJoin: .round))
                } else {
                    let symbol: String
                    switch source.icon {
                    case .radio: symbol = "radio.fill"
                    case .browser: symbol = "globe"
                    case .usb: symbol = "externaldrive.fill"
                    case .aux: symbol = "cable.connector"
                    case .video, .youtube: symbol = "play.rectangle.fill"
                    case .game: symbol = "gamecontroller.fill"
                    default: symbol = "music.note"
                    }
                    context.draw(Text(Image(systemName: symbol)).font(.system(size: s * 0.58)).foregroundStyle(.white), at: CGPoint(x: s / 2, y: s / 2))
                }
            }
        }
        .foregroundStyle(.white).frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("재생 소스: \(source.name)")
        .accessibilityIdentifier("navigation.media.source")
    }
}

private struct PlaybackArtwork: View {
    let data: NavigationReadout
    let side: CGFloat
    var body: some View {
        if let art = data.mediaArtwork {
            Image(uiImage: art).resizable().scaledToFill().frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.15))
                .overlay(alignment: .bottomTrailing) { PlaybackSourceIcon(source: data.mediaApp, side: max(12, side * 0.38)) }
        } else { PlaybackSourceIcon(source: data.mediaApp, side: side) }
    }
}
private struct NavigationMediaHeader: View {
    let data: NavigationReadout
    let action: (String) -> Void
    var body: some View {
        HStack(spacing: 8) {
            PlaybackArtwork(data: data, side: 26)
            VStack(alignment: .leading, spacing: 1) {
              Text(data.mediaTitle.isEmpty ? data.mediaApp.name : data.mediaTitle)
                .font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("navigation.media.title")
              if !data.mediaArtist.isEmpty { Text(data.mediaArtist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { action("mediaToggle") } label: {
                Image(systemName: data.mediaPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!data.mediaControllable)
            .accessibilityLabel(data.mediaPlaying ? "일시정지" : "재생")
        }
        .padding(.leading, 12).frame(height: 44)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct MediaIsland: View {
    let data: NavigationReadout
    let u: CGFloat
    let action: (String) -> Void
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 8 * u) {
            PlaybackArtwork(data: data, side: 26 * u)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 15 * u, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityIdentifier("navigation.media.title")
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12 * u)).foregroundStyle(NavInk.muted).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: (expanded ? 240 : 160) * u, alignment: .leading)
            if expanded { button("mediaPrev", "backward.fill", "이전 곡") }
            button("mediaToggle", data.mediaPlaying ? "pause.fill" : "play.fill", data.mediaPlaying ? "일시정지" : "재생")
            if expanded { button("mediaNext", "forward.fill", "다음 곡") }
        }
        .padding(.leading, 14 * u).padding(.trailing, 4 * u)
        .frame(height: (expanded ? 52 : 38) * u)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 8 * u, y: 3 * u)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { expanded.toggle() } }
        .task(id: expanded) {
            guard expanded else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { expanded = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation.media.island")
    }

    private var title: String { data.mediaTitle.isEmpty ? data.mediaApp.name : data.mediaTitle }
    private var subtitle: String {
        if !data.mediaStatus.isEmpty { return data.mediaStatus }
        return [data.mediaArtist, data.mediaTitle.isEmpty ? "" : data.mediaApp.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var enabled: Bool { data.mediaControllable }

    private func button(_ name: String, _ symbol: String, _ label: String) -> some View {
        Button { action(name) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15 * u, weight: .semibold))
                .frame(width: 34 * u, height: 34 * u)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityIdentifier("media.island." + name)
    }
}

/// Small animated level bars for the island (still when paused or with Reduce Motion).
private struct IslandBars: View {
    let active: Bool
    let u: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let moving = active && !reduced
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2 * u) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(NavInk.neon)
                        .frame(width: 3 * u, height: 14 * u * barLevel(i, t, moving))
                }
            }
            .frame(height: 14 * u)
        }
        .accessibilityHidden(true)
    }
    private func barLevel(_ i: Int, _ t: TimeInterval, _ moving: Bool) -> CGFloat {
        guard moving else { return 0.35 }
        let phase = t * (3.1 + Double(i) * 0.9) + Double(i)
        return CGFloat(0.3 + 0.7 * abs(sin(phase)))
    }
}

private struct DashboardSafeAreaKey: EnvironmentKey { static let defaultValue = EdgeInsets() }
private struct DashboardChromeClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct NavigationEndActionKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
private struct NavigationChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
extension EnvironmentValues {
    var navigationEndAction: (() -> Void)? {
        get { self[NavigationEndActionKey.self] }
        set { self[NavigationEndActionKey.self] = newValue }
    }
    var dashboardChromeClearance: CGFloat {
        get { self[DashboardChromeClearanceKey.self] }
        set { self[DashboardChromeClearanceKey.self] = newValue }
    }
    var dashboardSafeArea: EdgeInsets {
        get { self[DashboardSafeAreaKey.self] }
        set { self[DashboardSafeAreaKey.self] = newValue }
    }
}
// Shared by every theme. Keep the map full-bleed and route controls clear of the foreground.
struct NavigationWorkspaceChrome<Content: View, Controls: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var expanded = false
    @State private var activity = 0
    @State private var chromeHeight: CGFloat = 0
    var endGuidance: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls
    var body: some View {
        GeometryReader { geometry in
        content()
            .environment(\.dashboardSafeArea, geometry.safeAreaInsets)
            .environment(\.navigationEndAction, endGuidance)
            .environment(\.dashboardChromeClearance, expanded ? chromeHeight : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    if expanded {
                        HStack(spacing: 4) {
                            VStack(spacing: 4) {
                                controls()
                            }.frame(maxWidth: .infinity)
                            Button { setExpanded(false) } label: {
                                Image(systemName: "chevron.up").frame(width: 44, height: 44)
                            }.accessibilityLabel("상단 조작 닫기")
                                .accessibilityIdentifier("navigation.chrome.close")
                        }
                        .padding(.horizontal, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("navigation.chrome.panel")
                        .simultaneousGesture(TapGesture().onEnded { activity += 1 })
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        ZStack(alignment: .top) {
                        Button { setExpanded(true) } label: {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 36, height: 4)
                                .padding(8).background(.black.opacity(0.45), in: Capsule())
                                .frame(width: 100, height: 44, alignment: .top)
                                .contentShape(Rectangle())
                        }.accessibilityLabel("상단 조작 열기")
                            .accessibilityIdentifier("navigation.chrome.open")
                        }
                    }
                }.foregroundStyle(.white).padding(.horizontal, 8)
                    .padding(.leading, geometry.safeAreaInsets.leading)
                    .padding(.trailing, geometry.safeAreaInsets.trailing)
                    .padding(.top, geometry.size.width > geometry.size.height ? 6 : 48)
                    .background(GeometryReader { size in Color.clear.preference(key: NavigationChromeHeightKey.self, value: size.size.height + 8) })
                    // v1.24: pin the panel to the screen's top edge in every orientation.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
            .onPreferenceChange(NavigationChromeHeightKey.self) { chromeHeight = $0 }
            .task(id: activity) {
                guard expanded, !voiceOver else { return }
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                guard !Task.isCancelled else { return }
                setExpanded(false)
            }
        }
    }
    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded = value }
        activity += 1
    }
}


struct NavigationTrafficRefreshButton: View {
    let enabled: Bool
    let refreshing: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
              Group {
                if refreshing { ProgressView().tint(.cyan) }
                else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14)) }
              }.frame(width: 44, height: 44)
              Text(refreshing ? "교통 반영 재탐색 중" : "교통 반영 재탐색").font(.caption)
              Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.disabled(!enabled || refreshing)
            .accessibilityLabel("교통 반영 재탐색")
            .accessibilityIdentifier("navigation.traffic.refresh")
    }
}

private struct TeslaGuidanceSurface: ViewModifier {
    @Environment(\.navigationEndAction) private var endGuidance
    let radius: CGFloat
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content.frame(maxWidth: .infinity)
            if let endGuidance { NavigationEndButton(stop: endGuidance).padding(.trailing, 2) }
        }.foregroundStyle(.black)
            .environment(\.guidanceDarkInk, true)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .light)
                shape.fill(Color.white.opacity(0.65))
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityElement(children: .contain).accessibilityIdentifier("navigation.maneuver.surface")
    }
}

struct DashboardShadeControl: View {
    @AppStorage("navigation.dashboardShade") private var value = 0.45
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("계기판 그라데이션")
                Spacer()
                Text("\(Int(((value.isFinite ? min(1, max(0, value)) : 0.45) * 100).rounded()))%")
                    .monospacedDigit().accessibilityIdentifier("navigation.shade.percent")
            }
            Slider(value: $value, in: 0...1, step: 0.05)
                .accessibilityLabel("계기판 그라데이션").accessibilityIdentifier("navigation.shade.slider")
            Text("낮출수록 검정 가림 범위와 농도가 줄어 지도가 더 넓게 보임.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct JunctionGuidance: ViewModifier {
    let data: NavigationReadout
    @Environment(\.navigationEndAction) private var endGuidance
    func body(content: Content) -> some View {
        let visible = data.junctionImage != nil && data.junctionMetres.isFinite && data.junctionMetres > 0
        VStack(spacing: 5) {
        content.opacity(visible ? 0 : 1)
            .environment(\.navigationEndAction, visible ? nil : endGuidance)
            .allowsHitTesting(!visible).accessibilityHidden(visible)
            .overlay {
                if visible, let image = data.junctionImage {
                    NavigationJunctionCard(image: image, metres: data.junctionMetres)
                        .accessibilityHidden(false)
                }
            }
        if let prediction = data.energyPrediction { TripEnergyPredictionRow(estimate: prediction) }
        }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("navigation.junction.region")
    }
}

struct NavigationJunctionCard: View {
    let image: UIImage
    let metres: Double
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: max(1, geometry.size.height - 22))
                    .accessibilityLabel("교차로 상세 안내 이미지")
                HStack {
                    Text("진출로 안내").font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 2)
                    Text("\(finiteInt(metres)) m").font(.system(size: 12, weight: .bold)).monospacedDigit()
                }.padding(.horizontal, 6).frame(height: 22)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.black).modifier(TeslaGuidanceSurface(radius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("navigation.junction")
    }
}

/// Int(x) traps on NaN/±infinity (zero-size layout during theme or rotation changes). Clamp instead.
func finiteInt(_ x: Double, _ fallback: Int = 0) -> Int {
    guard x.isFinite else { return fallback }
    return Int(max(-1_000_000, min(1_000_000, x)))
}

/// Light cards for the running theme (white canvas).
private struct RunningTurnCard: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        HStack(spacing: 12 * u) {
            ManeuverGlyph(symbol: data.turnSymbol, exitClock: data.exitClock, size: 36 * u)
                .frame(width: 44 * u)
            VStack(alignment: .leading, spacing: 2 * u) {
                Text(data.turnDistance).font(.system(size: 24 * u, weight: .bold)).monospacedDigit()
                GuidanceCardLabel(text: data.turn, symbol: data.turnSymbol, exitClock: data.exitClock).font(.system(size: 15 * u, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            if let limit = data.speedLimit {
                Text("\(limit)").font(.system(size: 18 * u, weight: .heavy)).monospacedDigit().foregroundStyle(.black)
                    .frame(width: 44 * u, height: 44 * u)
                    .background(Circle().fill(.white)).overlay(Circle().stroke(Color.red, lineWidth: 5 * u))
            }
        }
        .foregroundStyle(Color.black)
        .padding(12 * u)
        .modifier(TeslaGuidanceSurface(radius: 20 * u))
        .shadow(color: .black.opacity(0.08), radius: 10 * u, y: 3 * u)
    }
}

private struct RunningInfoPanel: View {
    let data: NavigationReadout
    let u: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * u) {
                Text(data.speed).overspeed(data.overspeedLevel).font(.system(size: 46 * u, weight: .bold)).monospacedDigit()
                Text(data.speedUnit).font(.system(size: 14 * u, weight: .semibold)).foregroundStyle(Color.black.opacity(0.5))
                Spacer(minLength: 0)
                Text(data.gear).font(.system(size: 18 * u, weight: .bold)).foregroundStyle(Color.black.opacity(0.55))
            }
            Divider()
            row("도착", data.arrival)
            row("남은 거리", data.remainingDistance)
            row("배터리", data.battery)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.black)
        .lineLimit(1).minimumScaleFactor(0.5)
        .padding(12 * u)
        .background(.white, in: RoundedRectangle(cornerRadius: 20 * u, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8 * u, y: 2 * u)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13 * u)).foregroundStyle(Color.black.opacity(0.5))
            Spacer(minLength: 4)
            Text(value).font(.system(size: 15 * u, weight: .semibold)).monospacedDigit()
        }
    }
}


// MARK: - v1.31 overspeed warning

private struct OverspeedTint: ViewModifier {
    let level: Int
    func body(content: Content) -> some View {
        if level > 0 { content.foregroundStyle(Color.red) } else { content }
    }
}
extension Text {
    /// Red speed digits whenever the car is above the posted / camera limit.
    func overspeed(_ level: Int) -> some View { modifier(OverspeedTint(level: level)) }
}

/// Edge-red pulse (≥10 km/h over) and a chime whose rate rises with the excess (≥10: every 2 s, ≥20: every 0.8 s).
private struct OverspeedAlert: View {
    let level: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastBeep = Date.distantPast
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: level < 2)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let rate = level >= 3 ? 2.6 : 1.3
            let pulse = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(t * rate * 2 * .pi)
            ZStack {
                if level >= 2 {
                    RadialGradient(colors: [.clear, .clear, Color.red.opacity(level >= 3 ? 0.55 : 0.38)],
                                   center: .center, startRadius: 0, endRadius: 520)
                        .opacity(pulse)
                }
            }
            .onChange(of: Int(t * 10)) { _, _ in beepIfDue(ctx.date) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func beepIfDue(_ now: Date) {
        guard level >= 2 else { return }
        let interval = level >= 3 ? 0.8 : 2.0
        guard now.timeIntervalSince(lastBeep) >= interval else { return }
        lastBeep = now
        OverspeedChime.shared.play()
    }
}
