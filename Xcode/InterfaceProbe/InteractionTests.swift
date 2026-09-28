import XCTest

final class InteractionTests: XCTestCase {
    func testChargingMapDestinationAndRejectedVehicleSend() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["charging-map-probe"]; app.launch()
        XCTAssertTrue(app.buttons["charging.destination"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["3/8대 가능"].exists)
        let mapShot = XCTAttachment(screenshot: app.screenshot()); mapShot.name = "Nearby charging map and selected station"; mapShot.lifetime = .keepAlways; add(mapShot)
        app.buttons["charging.destination"].tap()
        XCTAssertTrue(app.buttons["destination.send"].waitForExistence(timeout: 5))
        app.buttons["destination.send"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "차량 전송을 확인하지 못했습니다")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["destination.appOnly"].exists)
        let failureShot = XCTAttachment(screenshot: app.screenshot()); failureShot.name = "Vehicle destination rejection offers app only guidance"; failureShot.lifetime = .keepAlways; add(failureShot)
        app.buttons["destination.appOnly"].tap()
        XCTAssertTrue(app.buttons["charging.destination"].waitForExistence(timeout: 5))
    }
    func testFullscreenChromeAcrossThemesAndRotation() {
        let app = XCUIApplication(); app.launchArguments = ["fullscreen-navigation-probe"]; app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            for title in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
                let open = app.buttons["navigation.chrome.open"]
                XCTAssertTrue(open.waitForExistence(timeout: 5))
                let canvas = app.staticTexts["navigation.canvas.size"]
                XCTAssertTrue(canvas.waitForExistence(timeout: 3))
                let before = canvas.label
                let size = before.split(separator: "/").compactMap { Double($0) }
                XCTAssertEqual(size.count, 2)
                guard size.count == 2 else { return }
                XCTAssertGreaterThan(size[0], app.frame.width - 3)
                XCTAssertGreaterThan(size[1], app.frame.height - 3)
                let foreground = app.otherElements["navigation.foreground"]
                XCTAssertTrue(foreground.exists)
                if orientation != .portrait {
                    XCTAssertGreaterThan(foreground.frame.minX, app.frame.minX + 20, "Dashboard must avoid either camera cutout orientation")
                    XCTAssertLessThan(foreground.frame.maxX, app.frame.maxX - 20)
                }
                open.tap()
                XCTAssertTrue(app.buttons["navigation.chrome.close"].waitForExistence(timeout: 3))
                app.buttons[title].tap()
                XCTAssertEqual(canvas.label, before, "Opening controls and changing theme must preserve canvas geometry")
                app.buttons["navigation.chrome.close"].tap()
                XCTAssertTrue(open.waitForExistence(timeout: 3))
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "Fullscreen \(title) \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        app.buttons["navigation.chrome.open"].tap()
        let stop = app.buttons["navigation.parked.stop"]
        XCTAssertTrue(stop.isHittable); XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
        stop.tap()
        XCTAssertTrue(app.staticTexts["fullscreen.stopped"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Fullscreen controls overlay"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.buttons["navigation.chrome.open"].waitForExistence(timeout: 9))
    }

    func testOverlappingSafetySpeechFinishesWithoutWarningLoop() {
        let app = XCUIApplication(); app.launchArguments = ["voice-playback-probe", "voice-overlap-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["중첩 안내 2개 완주 · 주의 반복 차단"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["voice.probe.count"].label, "재생 시작 2 / 완료 2")
    }

    func testSpeakerOutputForAllVoiceCategories() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["voice-playback-probe", "voice-output-probe"]; app.launch()
        app.buttons["voice.output"].tap()
        app.buttons["iPhone 스피커"].tap()
        for (index, title) in ["수동 미리듣기", "화면 브리핑", "제어 응답", "연결 알림", "운행 알림", "충전 알림", "자동화", "길안내", "안전 안내"].enumerated() {
            app.buttons[title].tap()
            XCTAssertTrue(app.staticTexts["재생 시작 \(index + 1) / 완료 \(index + 1)"].waitForExistence(timeout: 12))
            XCTAssertTrue(app.staticTexts["voice.output.last"].label.contains("iPhone 스피커"))
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Phone speaker output across nine voice categories"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["voice.output"].tap()
        app.buttons["시스템·Bluetooth"].tap()
        app.buttons["수동 미리듣기"].tap()
        XCTAssertTrue(app.staticTexts["재생 시작 10 / 완료 10"].waitForExistence(timeout: 12))
    }

    func testNavigationLandingLayoutAndActions() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["landing-probe"]; app.launch()
        XCTAssertTrue(app.buttons["landing.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["장소 또는 주소 검색"].exists)
        app.buttons["landing.search"].tap()
        XCTAssertEqual(app.staticTexts["landing.result"].label, "검색 열림")
        app.buttons["운전 대시보드"].tap()
        XCTAssertEqual(app.staticTexts["landing.result"].label, "대시보드 열림")
        app.buttons["주변 충전소"].tap()
        XCTAssertEqual(app.staticTexts["landing.result"].label, "충전소 열림")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Navigation landing search recent places and compact actions"; shot.lifetime = .keepAlways; add(shot)
    }

    func testChargeCostsAutomaticallyUseRegisteredRates() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["charge-cost-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["예상 충전금액 2000원"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["예상 충전금액 7000원"].exists)
        XCTAssertTrue(app.staticTexts["총 충전량"].exists)
        XCTAssertTrue(app.staticTexts["총 충전비"].exists)
        XCTAssertFalse(app.staticTexts["미입력분 예상액"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Automatic home and Supercharger estimated cost"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["단가 설정 열기"].tap()
        XCTAssertTrue(app.navigationBars["충전 단가 자동 적용"].waitForExistence(timeout: 10))
    }

    func testAudioSettingsInterruptionsPreemptionAndRecovery() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["voice-lifecycle-probe"]; app.launch()
        let result = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "음성 상태 17/17 검증 완료", "실패 ·")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 90))
        XCTAssertEqual(result.label, "음성 상태 17/17 검증 완료")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Voice settings interruption expiry preemption recovery and Typecast preview"; shot.lifetime = .keepAlways; add(shot)
    }
    func testAllAutomationEventsReachPlayback() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["voice-events-probe"]; app.launch()
        let result = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "자동화 24/24 재생 완료", "실패 ·")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 120))
        XCTAssertEqual(result.label, "자동화 24/24 재생 완료")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "All twelve automation triggers and Fleet speech events complete playback"; shot.lifetime = .keepAlways; add(shot)
    }
    func testAllVoiceCategoriesActuallyStartAndFinishPlayback() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["voice-playback-probe"]; app.launch()
        for (index, title) in ["수동 미리듣기", "화면 브리핑", "제어 응답", "연결 알림", "운행 알림", "충전 알림", "자동화", "길안내", "안전 안내"].enumerated() {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10)); app.buttons[title].tap()
            let completed = app.staticTexts["재생 시작 \(index + 1) / 완료 \(index + 1)"]
            XCTAssertTrue(completed.waitForExistence(timeout: 12), "Must actually complete AVAudioPlayer output: \(title)")
        }
        app.buttons["탑승 자동화 검증"].tap()
        XCTAssertTrue(app.staticTexts["탑승 조건 충족 · 실제 자동화 음성 요청"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["재생 시작 10 / 완료 10"].waitForExistence(timeout: 12))
        app.buttons["Fleet 탑승 자동화 검증"].tap()
        XCTAssertTrue(app.staticTexts["Fleet 탑승 조건 충족 · 실제 자동화 음성 요청"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["재생 시작 11 / 완료 11"].waitForExistence(timeout: 12))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Eleven voice paths including BLE and Fleet boarding playback completion"; shot.lifetime = .keepAlways; add(shot)
    }
    func testChargeCalendarQuarantinesRepeatedCompletion() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["charge-audit-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["중복 의심 기록 제외"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["충전"].tap()
        XCTAssertTrue(app.staticTexts["40.36"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["1452.96"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Charge duplicate quarantine calendar"; shot.lifetime = .keepAlways; add(shot)
    }
    func testNASConnectionFieldsVisible() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["archive-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["차량 → NAS → 앱"].waitForExistence(timeout: 10))
        for _ in 0..<3 where !app.secureTextFields["archive.token"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.textFields["archive.address"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["archive.token"].isHittable)
        XCTAssertTrue(app.staticTexts["NAS 연결 키"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "NAS labeled connection fields"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<3 where !app.buttons["NAS 전체 다시 받기"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["NAS 전체 다시 받기"].isHittable)
        XCTAssertTrue(app.buttons["신규·누락 기록 가져오기"].exists)
        XCTAssertFalse(app.buttons["NAS 전체 다시 받기"].isEnabled, "No NAS credentials must never start a recovery")
        let recovery = XCTAttachment(screenshot: app.screenshot()); recovery.name = "NAS history recovery controls"; recovery.lifetime = .keepAlways; add(recovery)
    }
    func testDestinationSearchEntry() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["search-probe"]; app.launch()
        XCTAssertTrue(app.textFields["destination.query"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["검색"].isEnabled)
        XCTAssertTrue(app.buttons["집"].isHittable)
        XCTAssertTrue(app.buttons["회사"].isHittable)
        let field = app.textFields["destination.query"]
        field.tap(); field.typeText("고등기술연구원")
        XCTAssertTrue(app.buttons["검색"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Destination search entry"; shot.lifetime = .keepAlways; add(shot)
    }
    func testRestoredClimateAndFleetCards() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["climate-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["목표 실내 온도"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["climate.power"].exists)
        XCTAssertTrue(app.buttons["climate.defrost"].exists)
        XCTAssertTrue(app.buttons["climate.steering"].exists)
        XCTAssertFalse(app.buttons["전원 켜기"].exists)
        XCTAssertFalse(app.buttons["전원 끄기"].exists)
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Restored climate top and cabin"; top.lifetime = .keepAlways; add(top)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["반려동물"].waitForExistence(timeout: 5))
        let lower = XCTAttachment(screenshot: app.screenshot()); lower.name = "Restored climate seats and modes"; lower.lifetime = .keepAlways; add(lower)
        app.terminate(); app.launchArguments = ["fleet-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["내 차량"].waitForExistence(timeout: 10))
        let fleet = XCTAttachment(screenshot: app.screenshot()); fleet.name = "Fleet detail cards"; fleet.lifetime = .keepAlways; add(fleet)
    }

    func testVisualFleetOverviewAndWarranty() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["fleet-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["내 차량"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["최근 충전"].exists)
        XCTAssertTrue(app.buttons["타이어·정비"].exists)
        var shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fleet visual charge overview"; shot.lifetime = .keepAlways; add(shot)
        shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fleet consolidated menu"; shot.lifetime = .keepAlways; add(shot)
        let warranty = app.buttons["보증·관리"]
        if !warranty.isHittable { app.swipeUp() }
        XCTAssertTrue(warranty.waitForExistence(timeout: 5)); warranty.tap()
        XCTAssertTrue(app.staticTexts["남은 거리"].firstMatch.waitForExistence(timeout: 5))
        shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Warranty remaining bars"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.buttons.firstMatch.tap()
        let tires = app.buttons["타이어·정비"]
        XCTAssertTrue(tires.waitForExistence(timeout: 5)); tires.tap()
        for label in ["앞 왼쪽", "앞 오른쪽", "뒤 왼쪽", "뒤 오른쪽"] { XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5)) }
        shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Unified tire readings"; shot.lifetime = .keepAlways; add(shot)

    }

    func testTabBarOpacityAndContentSeparation() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["tabbar-probe"]; app.launch()
        let full = app.buttons["opacity.full"]
        XCTAssertTrue(full.waitForExistence(timeout: 8))
        full.tap()
        XCTAssertTrue(app.staticTexts["불투명도 100%"].exists)
        for title in ["홈", "컨트롤", "에너지", "운행", "메뉴"] {
            app.tabBars.buttons[title].tap()
            let bottom = app.buttons["content.bottom"]
            XCTAssertTrue(bottom.isHittable)
            XCTAssertLessThanOrEqual(bottom.frame.maxY, app.tabBars.firstMatch.frame.minY)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Opaque tab bar"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["opacity.half"].tap()
        XCTAssertTrue(app.staticTexts["불투명도 50%"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["불투명도 50%"].waitForExistence(timeout: 8))
        app.buttons["opacity.full"].tap()
    }
    func testBatteryGaugeThresholds() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["battery-gauge-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["배터리 잔량 표시"].waitForExistence(timeout: 8))
        for label in ["0%", "20%", "21%", "50%", "51%", "100%", "미수신"] { XCTAssertTrue(app.staticTexts[label].exists) }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Battery gauge thresholds"; shot.lifetime = .keepAlways; add(shot)
    }
    func testRoundaboutSymbol() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "roundabout-probe"]; app.launch()
        XCTAssertTrue(app.otherElements["회전교차로 9시 방향 출구"].waitForExistence(timeout: 8) || app.staticTexts["회전교차로"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Roundabout exit nine"; shot.lifetime = .keepAlways; add(shot)
        XCUIDevice.shared.orientation = .portrait
    }
    func testBatteryBaselineAndPeriods() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["battery-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["충전 자료가 쌓이면 추정값 표시"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["현재 지수 100%"].exists)
        for period in ["7일", "30일", "90일"] {
            app.segmentedControls.buttons[period].tap()
            XCTAssertTrue(app.segmentedControls.buttons[period].isSelected)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Battery baseline"; shot.lifetime = .keepAlways; add(shot)
    }
    func testRouteMotionDirections() {
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "motion-probe"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let minimal = app.segmentedControls.buttons["미니멀"]
        XCTAssertTrue(minimal.waitForExistence(timeout: 8))
        minimal.tap()
        for direction in ["left", "right"] {
            let btn = app.buttons["motion." + direction]
            XCTAssertTrue(btn.waitForExistence(timeout: 8))
            btn.tap()
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Motion " + direction; shot.lifetime = .keepAlways; add(shot)
        }
        let toggle = app.buttons["motion.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        toggle.tap()
        for frame in 0..<3 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Motion flowing \(frame)"; shot.lifetime = .keepAlways; add(shot)
        }
        toggle.tap()
        let empty = app.buttons["navigation.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
        empty.tap()
        XCTAssertTrue(app.staticTexts["경로 미수신"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }
    func testNavigationThemesAndRotation() {
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe"]; app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.0)
            for theme in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
                let button = app.segmentedControls.buttons[theme]
                XCTAssertTrue(button.waitForExistence(timeout: 8)); button.tap()
                XCTAssertTrue(app.staticTexts["34"].waitForExistence(timeout: 8), "speed missing: \(theme) \(orientation.rawValue)")
                XCTAssertTrue(app.staticTexts["1.5 km"].exists, "turn distance missing: \(theme) \(orientation.rawValue)")
                XCTAssertTrue(app.staticTexts["1.5 km"].firstMatch.isHittable, "turn distance covered: \(theme) \(orientation.rawValue)")
                let media = app.staticTexts["navigation.media.title"]
                XCTAssertTrue(media.exists, "media dock missing: \(theme)")
                XCTAssertTrue(app.otherElements["navigation.modeling"].exists, "theme composition must be preserved")
                XCTAssertTrue(button.isSelected, "selected theme must match the visible composition")
                if theme == "투어링" { XCTAssertTrue(app.staticTexts["실내"].exists && app.staticTexts["외기"].exists) }
                if theme == "관제" { XCTAssertTrue(app.staticTexts["경로 진행"].exists && app.staticTexts["남은 거리"].exists) }
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "Navigation \(theme) \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        app.buttons["navigation.empty"].tap()
        let emptySpeed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["34"])
        let emptyTurn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["1.5 km"])
        XCTAssertEqual(XCTWaiter.wait(for: [emptySpeed, emptyTurn], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["경로 확인 중"].exists)
        XCUIDevice.shared.orientation = .portrait
    }
    func testParkedRouteStopButton() {
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "parked-route-probe"]; app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let stop = app.buttons["navigation.parked.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            XCTAssertTrue(stop.isHittable)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Parked route stop \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["navigation.parked.stop"].tap()
        XCTAssertTrue(app.staticTexts["navigation.stopped"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["navigation.parked.stop"].exists)
        XCUIDevice.shared.orientation = .portrait
    }
    func testAppearanceProductionScreens() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["reset-appearance-fixture"]; app.launch()
        app.buttons["home.appearance"].tap()
        let white = app.buttons["펄 화이트 프로"]
        XCTAssertTrue(white.waitForExistence(timeout: 15)); white.tap()
        for tab in ["색상", "틴팅", "번호판", "랩핑"] {
            app.segmentedControls.buttons[tab].tap()
            if tab == "번호판" {
                let plate = app.textFields["appearance.plate"]
                XCTAssertTrue(plate.waitForExistence(timeout: 5))
                plate.tap()
                plate.typeText("123가 4567\n")
                XCTAssertEqual(plate.value as? String, "123가 4567")
            }
            if tab == "랩핑" {
                app.segmentedControls.buttons["색상"].tap(); app.buttons["울트라 레드"].tap()
                app.segmentedControls.buttons["랩핑"].tap(); app.segmentedControls.buttons["스트라이프"].tap()
            }
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Appearance " + tab; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(app.buttons["appearance.save"].exists)
        app.buttons["appearance.save"].tap()
        XCTAssertTrue(app.buttons["home.appearance"].waitForExistence(timeout: 3))
        app.buttons["home.appearance"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["번호판"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["번호판"].tap()
        let savedPlate = app.textFields["appearance.plate"]
        XCTAssertTrue(savedPlate.waitForExistence(timeout: 5))
        XCTAssertEqual(savedPlate.value as? String, "123가 4567")
    }
    private func expectCounts(_ app: XCUIApplication, _ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: app.staticTexts["voice.counts"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 3), .completed)
    }
    func testPreviewAndStopAreIndependentFormActions() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["설정"].tap()
        let preview = app.buttons["voice.preview"], stop = app.buttons["voice.stop"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        expectCounts(app, "1,0") // Preview must not also invoke Stop.
        preview.tap()
        expectCounts(app, "2,0")
        stop.tap()
        expectCounts(app, "2,1") // Stop must not invoke Preview.
        app.buttons["voice.profile"].tap()
        XCTAssertFalse(app.buttons["서연 · 여성"].exists)
        XCTAssertFalse(app.buttons["한국어 · iPhone 기본"].exists)
        let eunkyung = app.buttons.matching(NSPredicate(format: "label CONTAINS '은경'")).firstMatch
        if eunkyung.waitForExistence(timeout: 3) {
            eunkyung.tap()
        }
        app.buttons["voice.style"].tap()
        app.buttons["차분하게"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Voice named style"; shot.lifetime = .keepAlways; add(shot)
    }
    func testAutomationAndSettingsHaveSeparateRoots() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["자동화"].tap()
        XCTAssertTrue(app.staticTexts["automation.root"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["voice.preview"].exists)
        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.buttons["voice.preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["automation.root"].exists)
        app.tabBars.buttons["차량"].tap()
        app.buttons["home.automation"].tap()
        XCTAssertTrue(app.staticTexts["automation.detail"].waitForExistence(timeout: 5))
    }

    func testVoiceChangesCannotDeleteCache() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["cache-probe"]; app.launch()
        XCTAssertTrue(app.buttons["음성 변경"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["PASS voice isolation and disk reuse"].waitForExistence(timeout: 10))
        app.buttons["음성 변경"].tap()
        XCTAssertEqual(app.staticTexts["cache.voice"].label, "은경")
        XCTAssertEqual(app.staticTexts["cache.files"].label, "24")
        app.buttons["미리 듣기"].tap()
        XCTAssertEqual(app.staticTexts["cache.files"].label, "24")
        XCTAssertFalse(app.buttons["모든 음성 캐시 삭제"].exists)
        app.buttons["voice.cache.delete"].tap()
        XCTAssertTrue(app.buttons["취소"].waitForExistence(timeout: 3))
        app.buttons["취소"].tap()
        XCTAssertEqual(app.staticTexts["cache.files"].label, "24")
        app.buttons["voice.cache.delete"].tap()
        app.buttons["모든 음성 캐시 삭제"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '0'"), object: app.staticTexts["cache.files"])
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed)
        XCTAssertEqual(app.staticTexts["cache.files"].label, "0")
    }
}
