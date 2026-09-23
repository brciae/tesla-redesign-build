import Foundation

extension AppModel {
    func screenBriefing(_ scope: BriefingScope, days: Int = 30, rows: [Object]? = nil, address: String = "") -> String {
        let home = homePresentation(self, link)
        let charge = home.object("charge"), climate = home.object("climate")
        let fresh = output.object("fresh")
        let fleetDrive = !link.authentic && fleet.vehicleSnapshot?.vin == fleet.selectedVin ? fleet.vehicleSnapshot?.driveDisplay() ?? [:] : [:]
        let drive = fresh.flag("drive") ? groups.object("drive") : fleetDrive
        let driveFresh = fresh.flag("drive") || fleetDrive.string("mode") == "recent"
        func measurement(_ values: Object, key: String, label: String, unit: String) -> String {
            guard let value = values.number(key), value.isFinite else { return "" }
            let mode = values.string("mode")
            guard demo || mode == "recent" || mode == "cached" else { return "" }
            let age = mode == "cached" ? "마지막 수신값. " : ""
            return age + label + " \(Int(value.rounded()))" + unit + "입니다."
        }
        let connection = demo ? "예시 모드의 자료입니다." : (link.authentic ? "블루투스 연결됨." : "Fleet \(fleet.vehicleDisplayStatus)입니다.")
        let battery = measurement(charge, key: "soc", label: "배터리 잔량", unit: "퍼센트")
        let inside = measurement(climate, key: "insideC", label: "실내 온도", unit: "도")
        var details: [String] = []
        switch scope {
        case .automation:
            details = ["전체 \(automations.rules.count)개 중 \(automations.rules.filter(\.enabled).count)개 활성.", automations.presence, automations.status]
            if let last = automations.logs.first { details.append("최근 \(last.rule), \(last.status)입니다.") }
            else { details.append("아직 실행 기록이 없습니다.") }
        case .climate:
            details = [inside, measurement(climate, key: "outsideC", label: "외부 온도", unit: "도")]
            if climate.string("mode") == "recent", let on = climate["isOn"] as? Bool { details.insert(on ? "공조 작동 중입니다." : "공조 꺼짐.", at: 0) }
            details.append(measurement(climate, key: "targetC", label: "설정 온도", unit: "도"))
        case .charging:
            details = [battery, measurement(charge, key: "chargerKW", label: "충전 전력", unit: "킬로와트"), measurement(charge, key: "limit", label: "충전 한도", unit: "퍼센트")]
            if charge.string("mode") == "recent", let charging = charge["isCharging"] as? Bool { details.insert(charging ? "충전 중입니다." : "충전 중이 아닙니다.", at: 0) }
            if charge.flag("isCharging") { details.append(measurement(charge, key: "minutesToLimit", label: "목표까지 남은 시간", unit: "분")) }
        case .driving, .dashboard:
            if driveFresh {
                if drive.string("gear") == "P" { details.append("주차 중.") }
                if let speed = drive.number("speedKmh"), speed.isFinite {
                    details.append("시속 \(Int(speed.rounded()))킬로미터입니다.")
                } else { details.append("차량 속도 미확인.") }
                let destination = drive.string("destination")
                details.append(destination.isEmpty ? "차량 목적지 미설정입니다." : "차량 목적지 \(destination)입니다.")
            } else { details.append("차량 속도와 내비 목적지는 최신 수신값이 없습니다.") }
            if scope == .dashboard { details.append(navigation.guiding ? "앱 길안내 중." : "앱 길안내 대기.") }
        case .navigation:
            details = [navigation.guiding ? "길안내 진행 중입니다." : "길안내 대기 중입니다.", navigation.locationPermission, navigation.status]
        case .preferences:
            let defaults = UserDefaults.standard
            details = [defaults.bool(forKey: "voiceEnabled") ? "음성 안내 켜짐." : "음성 안내 꺼짐.", "하단 메뉴 불투명도 \(Int((defaults.object(forKey: "tabBarOpacity") as? Double ?? 1) * 100))퍼센트입니다."]
        case .home:
            details = [connection, battery, inside]
        case .controls, .security, .vehicle3D:
            details = scope == .security ? [connection] : []
        case .trips, .allTrips:
            let selected = rows ?? output.object("energyPeriods").object(String(days)).rows("trips")
            details = BriefingScope.tripSummary(selected.map { $0.number("distanceKm") })
            if scope == .trips {
                details.insert(days >= 36500 ? "전체 기간입니다." : "최근 \(days)일입니다.", at: 0)
                let estimates = output.object("energyPeriods").object(String(days))
                if let efficiency = estimates.number("drivingKmPerKWh"), efficiency.isFinite { details.append(String(format: "전비, 킬로와트시당 %.1f킬로미터입니다.", efficiency)) }
            }
        case .charges:
            let selected = rows ?? output.object("charging").rows("rows")
            details = [selected.isEmpty ? "충전 기록이 없습니다." : "충전 기록 \(selected.count)회입니다."]
            let costs = selected.compactMap { $0.number("cost") }.filter(\.isFinite)
            if !costs.isEmpty { details.append("금액 확인 \(costs.count)회 합계는 \(Int(costs.reduce(0, +).rounded()))원입니다.") }
        case .battery, .batteryAndCharging:
            let usage = output.object("battery").object(String(days))
            let index = output.object("healthIndex")
            details = [days >= 36500 ? "전체 기록 기준입니다." : "최근 \(days)일 기록 기준입니다."]
            if let distance = usage.number("distanceKm"), distance.isFinite { details.append(String(format: "기록 거리는 %.1f킬로미터입니다.", distance)) }
            if let efficiency = usage.object("energy").number("drivingKmPerKWh"), efficiency.isFinite { details.append(String(format: "전비, 킬로와트시당 %.1f킬로미터입니다.", efficiency)) }
            if index.flag("initial") { details.append("배터리 건강 지수 미측정.") }
            else if let soh = index.number("soh"), soh.isFinite { details.append(String(format: "추정 배터리 건강 지수 %.1f퍼센트입니다.", soh)) }
            if scope == .batteryAndCharging { details.append(battery) }
        case .location:
            let location = home.object("location")
            if location.flag("hasCoordinates"), let lat = location.number("latitude"), let lon = location.number("longitude"), lat.isFinite, lon.isFinite {
                details = [address.isEmpty ? String(format: "마지막 위치 위도 %.4f, 경도 %.4f입니다.", lat, lon) : "마지막 위치 \(address)입니다.", "수신 \(dateText(location.number("gpsAt")))입니다."]
            } else { details = ["차량 위치를 아직 수신하지 못했습니다."] }
        case .care:
            details = ["정비 기록 \(state.rows("maintenance").count)건입니다."]
            let pressures = (groups.object("tire")["values"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }.filter { $0.isFinite && $0 > 0 }
            if let low = pressures.min(), let high = pressures.max() { details.append(String(format: "마지막 타이어 공기압 %.2f에서 %.2f바입니다.", low, high)) }
        case .schedule:
            details = [(UserDefaults.standard.object(forKey: "backgroundBLERead") as? Bool ?? true) ? "앱 전환 후 블루투스 조회 유지가 켜져 있습니다." : "앱 전환 후 블루투스 조회 유지가 꺼져 있습니다.", "예약 알림 등록 여부 미확인."]
            if let temperature = state.object("weather").number("temperature_2m"), temperature.isFinite { details.append("마지막 조회 기온 \(Int(temperature.rounded()))도입니다.") }
        case .menu:
            details = ["등록 차량 \(settings.string("name", "미설정"))입니다.", connection, "자동화는 \(automations.rules.filter(\.enabled).count)개 활성 상태입니다."]
        case .daily:
            details = [output.string("briefing")]
        }
        if [BriefingScope.controls, .home, .security, .vehicle3D].contains(scope) {
            if let snapshot = fleet.vehicleSnapshot, snapshot.vin == fleet.selectedVin, snapshot.sectionIsRecent("vehicle_state"), let locked = snapshot.locked, !link.authentic {
                details.append(locked ? "차량 잠김." : "차량 잠금 해제됨.")
            } else if fresh.flag("closures"), let locked = groups.object("closures")["locked"] as? Bool {
                details.append(locked ? "차량 잠김." : "차량 잠금 해제됨.")
            } else { details.append("차량 잠금 미확인.") }
            if scope != .home, fresh.flag("closures") {
                let closures = groups.object("closures")
                let names = [("driverFront", "운전석 앞문"), ("driverRear", "운전석 뒷문"), ("passengerFront", "조수석 앞문"), ("passengerRear", "조수석 뒷문"), ("frunk", "프렁크"), ("trunk", "트렁크")]
                let open = names.filter { (closures[$0.0] as? Bool) == true }.map { $0.1 }
                if !open.isEmpty { details.insert(open.joined(separator: ", ") + " 열려 있습니다.", at: 0) }
            }
        }
        return scope.text(details, demo: demo)
    }
}
