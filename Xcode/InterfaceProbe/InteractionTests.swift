import XCTest

final class InteractionTests: XCTestCase {
    func testRestoredClimateAndFleetCards() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["climate-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["목표 실내 온도"].waitForExistence(timeout: 10))
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Restored climate top and cabin"; top.lifetime = .keepAlways; add(top)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["반려동물"].waitForExistence(timeout: 5))
        let lower = XCTAttachment(screenshot: app.screenshot()); lower.name = "Restored climate seats and modes"; lower.lifetime = .keepAlways; add(lower)
        app.terminate(); app.launchArguments = ["fleet-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["충전 진단"].waitForExistence(timeout: 10))
        let fleet = XCTAttachment(screenshot: app.screenshot()); fleet.name = "Fleet detail cards"; fleet.lifetime = .keepAlways; add(fleet)
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
        XCTAssertTrue(app.staticTexts["초기 가정 · 관측 추정 전"].waitForExistence(timeout: 8))
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
                if ["클러스터", "관제"].contains(theme) {
                    let media = app.staticTexts["navigation.media.title"]
                    XCTAssertTrue(media.exists, "media header missing")
                    XCTAssertLessThanOrEqual(media.frame.maxY, app.staticTexts["1.5 km"].firstMatch.frame.minY, "media must stay above directions")
                }
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
        XCTAssertEqual(app.staticTexts["cache.files"].label, "0")
    }
}
