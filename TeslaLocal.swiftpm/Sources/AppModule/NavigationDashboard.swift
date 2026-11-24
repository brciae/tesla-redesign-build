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
    case cluster
    var id: String { rawValue }
    var title: String { "클러스터" }
    /// Camera for the vehicle view, nil when the layout shows no vehicle model.
    var carCamera: (yaw: Float, pitch: Float)? { nil }
    var carZoom: Float { 1.08 }
    var lookAhead: Float { 0 }
    var roadStyle: String { "asphalt" }
    var drawsRoadIn3D: Bool { false }
    var canvas: Color { NavInk.canvas }
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
    @AppStorage("navigation.focusMode") private var focusMode = false
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
        if focusMode { navigationLayout(m) } else { modelingLayout(m) }
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
                    ZStack { Rectangle().opacity(1 - shade); mapMask(rect: rect, m: m).opacity(shade) }
                }
                .position(x: rect.midX, y: rect.midY)
            // Scrim themes: continue the leading scrim into the camera-side gap so no hard edge appears.
            if m.wide, inset.leading > 0 {
                Color.black.opacity(shade)
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
        let mediaHeight: CGFloat = data.showsMedia && !focusMode ? 48 : 0
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
                if data.showsMedia && !focusMode {
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
        CGRect(x: 0, y: 0, width: m.w, height: m.h)
    }

    @ViewBuilder private func mapMask(rect: CGRect, m: NavMetrics) -> some View {
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
    }

    @ViewBuilder private func overlay(_ m: NavMetrics) -> some View {
        clusterLayer(m)
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
