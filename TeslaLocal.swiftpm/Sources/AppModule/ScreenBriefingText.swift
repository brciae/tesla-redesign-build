import Foundation

extension AppModel {
    /// Connect adjacent measurements without mechanically joining advice or warnings.
    private func connectedFacts(_ facts: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < facts.count {
            let first = facts[index]
            if index + 1 < facts.count, first.hasSuffix("입니다."), facts[index + 1].hasSuffix("입니다."),
               first.count + facts[index + 1].count < 130, !first.contains("마지막 수신값"), !facts[index + 1].contains("마지막 수신값") {
                result.append(String(first.dropLast(4)) + "이며, " + facts[index + 1])
                index += 2
            } else { result.append(first); index += 1 }
        }
        return result
    }

    private func energyInterpretation(_ energy: Object) -> [String] {
        guard let driving = energy.number("drivingKmPerKWh"), driving.isFinite, driving > 0 else {
            return []
        }
        var result: [String] = []
        if let overall = energy.number("overallKmPerKWh"), overall.isFinite, overall > 0, overall <= driving {
            result.append(String(format: "주행 전비는 킬로와트시당 %.1f킬로미터, 주차 중 감소량까지 반영한 종합 전비는 %.1f킬로미터로 추정됩니다.", driving, overall))
            let gap = (1 - overall / driving) * 100
            if gap >= 5 {
                result.append(String(format: "같은 거리 기준으로 종합 전비가 약 %.0f퍼센트 낮아, 주행 외 소비가 효율 차이에 영향을 주고 있습니다.", gap))
                if let parking = energy.number("parkingKWh"), parking.isFinite, parking > 0 {
                    result.append(String(format: "주차 중 집계한 소비가 약 %.1f킬로와트시입니다. 주차 중 감시 모드와 공조 유지 시간을 줄이면 종합 전비 개선에 도움이 될 수 있습니다.", parking))
                }
            } else { result.append("두 전비의 차이가 작아, 현재 기록에서는 주행 외 소비의 영향이 크지 않습니다.") }
        } else { result.append(String(format: "주행 전비는 킬로와트시당 %.1f킬로미터입니다.", driving)) }
        if energy.flag("capacityAssumed") { result.append("배터리 용량을 가정해 계산한 값이므로 절대 수치보다 같은 조건에서의 추세를 비교해 주세요.") }
        return result
    }

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
            let energy = output.object("energyPeriods").object(String(days))
            let estimates = energy.isEmpty ? usage.object("energy") : energy
            let index = output.object("healthIndex")
            details = ["배터리와 충전 상태를 살펴보겠습니다."]
            if scope == .batteryAndCharging { details.append(battery) }
            details.append(days >= 36500 ? "전체 기록을 기준으로 분석했습니다." : "최근 \(days)일 기록을 기준으로 분석했습니다.")
            if let distance = usage.number("distanceKm") ?? estimates.number("totalDistanceKm"), distance.isFinite {
                details.append(String(format: "기록 거리는 %.1f킬로미터입니다.", distance))
            }
            details += energyInterpretation(estimates)
            if index.flag("estimated"), !index.flag("initial"), let degradation = index.number("degradationPercent"), degradation.isFinite, (0...100).contains(degradation) {
                var health = String(format: "초기 관측 용량과 비교한 상대 열화율은 %.1f퍼센트로 추정되며", degradation)
                if let uncertainty = index.number("uncertaintyPercent"), uncertainty.isFinite {
                    health += String(format: ", 관측 산포는 약 %.1f퍼센트포인트입니다.", uncertainty)
                } else { health += ", 신차 대비 공식 배터리 진단값은 아닙니다." }
                details.append(health)
            } else { details.append("배터리 열화는 비교 가능한 충전 자료가 부족해 아직 판단할 수 없습니다. 화면의 초기값 0퍼센트가 열화 없음을 뜻하지는 않습니다.") }
            if scope == .batteryAndCharging, charge.string("mode") == "recent", charge.flag("isCharging") {
                let power = charge.number("chargerKW"), minutes = charge.number("minutesToLimit")
                if let power, power.isFinite, let minutes, minutes.isFinite, minutes >= 0 {
                    details.append(String(format: "현재 %.1f킬로와트로 충전 중이며, 차량이 예상한 목표까지의 시간은 약 %.0f분입니다. 충전 후반에는 전력이 낮아져 완료 시각이 달라질 수 있습니다.", power, minutes))
                }
            }
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
        return scope.text(connectedFacts(details), demo: demo)
    }
}
