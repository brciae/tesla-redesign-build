import XCTest

final class InteractionTests: XCTestCase {
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
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Roundabout exit nine"; shot.lifetime = .keepAlways; add(shot)
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
    func testAppearanceProductionScreens() {
        let app = XCUIApplication(); app.launch()
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
}
