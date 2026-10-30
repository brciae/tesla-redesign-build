import XCTest
final class ProductionReviewTests: XCTestCase {
    func testLaunch() { review("launch") }
    func testHomeNavigation() { review("home") }
    func testHealth() { review("health") }
    func testTariffs() { review("tariffs") }
    func testMonthClosing() { review("month") }
    func testBatteryEvidence() { review("battery") }
    func testCoverage() { review("coverage") }
    func testImportPreview() { review("import") }
    func testInvalidImportBlocked() { review("importInvalid") }
    func testManualAutomationDraft() { review("automation") }
    func testNavigationSettings() { review("navigation") }
    func testDriving() { review("driving") }
    func testDrivingFocus() { review("focus") }
    private func review(_ screen: String) {
        continueAfterFailure = false
            let app = XCUIApplication()
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
            app.launchArguments = ["--ui-review-fixture", "--ui-review-screen", screen, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR", "-navigation.focusMode", screen == "focus" ? "YES" : "NO"]
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), screen)
            if ["navigation", "driving", "focus"].contains(screen) { allowLocationIfRequested() }
            else { XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists, "Unexpected permission on " + screen) }
            if screen == "home" {
                XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.descendants(matching: .any)["app.launch.brand"].exists)
                for tab in ["에너지", "운행", "메뉴", "홈"] { app.tabBars.buttons[tab].tap(); allowLocationIfRequested() }
                XCTAssertTrue(app.descendants(matching: .any)["home.readiness"].waitForExistence(timeout: 10))
                XCUIDevice.shared.press(.home); app.activate()
                XCTAssertFalse(app.descendants(matching: .any)["app.launch.brand"].exists)
            } else if screen == "import" {
                XCTAssertTrue(app.staticTexts["검증용 예시.csv"].waitForExistence(timeout: 10))
                let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); overview.name = "production-import-preview-overview"; overview.lifetime = .keepAlways; add(overview)
                let stored = app.staticTexts["저장량 열 · 20.00 kWh"]
                for _ in 0..<2 where !stored.exists || !stored.isHittable { app.swipeUp() }
                XCTAssertTrue(stored.waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["결제액 열 · 1200원"].exists)
                let apply = app.buttons["import.preview.apply"]
                for _ in 0..<2 where !apply.exists { app.swipeUp() }
                XCTAssertTrue(apply.waitForExistence(timeout: 5))
                XCTAssertFalse(apply.isEnabled)
            } else if screen == "importInvalid" {
                XCTAssertTrue(app.staticTexts["변환 가능한 기록, 0건"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["확인이 필요한 행, 1건"].exists)
                XCTAssertFalse(app.buttons["import.preview.apply"].isEnabled)
            } else if screen == "automation" {
                let create = app.buttons["automation.create"]
                XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
                let manual = app.buttons["직접 만들기"]
                XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
                let enabled = app.switches["이 규칙 활성화"]
                XCTAssertTrue(enabled.waitForExistence(timeout: 5))
                XCTAssertEqual(enabled.value as? String, "0")
                let draft = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); draft.name = "production-manual-automation-draft"; draft.lifetime = .keepAlways; add(draft)
                app.buttons["취소"].tap()
            } else if screen == "driving" || screen == "focus" {
                let setup = app.buttons["키 설정"]
                XCTAssertTrue(setup.waitForExistence(timeout: 10)); XCTAssertTrue(setup.isHittable)
                setup.tap()
                XCTAssertTrue(app.navigationBars["운전 화면 설정"].waitForExistence(timeout: 5))
                app.buttons["완료"].tap()
            } else if screen == "navigation" { XCTAssertTrue(app.switches["주행 집중 모드"].waitForExistence(timeout: 10)) }
            else if screen == "month" { XCTAssertTrue(app.navigationBars["월간 결산"].waitForExistence(timeout: 10)) }
            let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); portrait.name = "production-" + screen + "-portrait"; portrait.lifetime = .keepAlways; add(portrait)
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in let size = XCUIScreen.main.screenshot().image.size; return size.width > size.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 10), .completed, screen)
            let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); landscape.name = "production-" + screen + "-landscape"; landscape.lifetime = .keepAlways; add(landscape)
            XCUIDevice.shared.orientation = .portrait
            let reset = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in let size = XCUIScreen.main.screenshot().image.size; return size.height > size.width }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 10), .completed, screen)
    }
    private func allowLocationIfRequested() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        let labels = ["Allow While Using App", "앱을 사용하는 동안 허용", "Allow Once", "한 번 허용"]
        for title in labels where alert.buttons[title].exists { alert.buttons[title].tap(); return }
        XCTFail("Unexpected system alert during navigation setup")
    }

}
