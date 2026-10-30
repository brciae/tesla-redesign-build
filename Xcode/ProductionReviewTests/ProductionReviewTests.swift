import XCTest
final class ProductionReviewTests: XCTestCase {
    func testProductionScreensAndHomeNavigation() {
        continueAfterFailure = false
        for screen in ["launch", "home", "health", "tariffs", "month", "battery", "coverage", "automation", "navigation"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-review-fixture", "--ui-review-screen", screen, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), screen)
            if screen == "home" {
                XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.descendants(matching: .any)["app.launch.brand"].exists)
                for tab in ["에너지", "운행", "메뉴", "홈"] { app.tabBars.buttons[tab].tap() }
                XCTAssertTrue(app.descendants(matching: .any)["home.readiness"].waitForExistence(timeout: 10))
            } else if screen == "automation" {
                let create = app.buttons["자동화 만들기"]
                XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
                let manual = app.buttons["직접 만들기"]
                XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
                let enabled = app.switches["이 규칙 활성화"]
                XCTAssertTrue(enabled.waitForExistence(timeout: 5))
                XCTAssertEqual(enabled.value as? String, "0")
                let draft = XCTAttachment(screenshot: app.screenshot()); draft.name = "production-manual-automation-draft"; draft.lifetime = .keepAlways; add(draft)
                app.buttons["취소"].tap()
            } else if screen == "navigation" { XCTAssertTrue(app.switches["주행 집중 모드"].waitForExistence(timeout: 10)) }
            else if screen == "month" { XCTAssertTrue(app.navigationBars["월간 결산"].waitForExistence(timeout: 10)) }
            let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "production-" + screen + "-portrait"; portrait.lifetime = .keepAlways; add(portrait)
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 10), .completed, screen)
            let landscape = XCTAttachment(screenshot: app.screenshot()); landscape.name = "production-" + screen + "-landscape"; landscape.lifetime = .keepAlways; add(landscape)
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
    }
}
