import XCTest
final class ProductionReviewTests: XCTestCase {
    func testProductionScreensAndHomeNavigation() {
        continueAfterFailure = false
        for screen in ["home", "health", "tariffs", "month", "battery", "navigation"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-review-fixture", "--ui-review-screen", screen, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), screen)
            if screen == "home" {
                XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
                for tab in ["에너지", "운행", "메뉴", "홈"] { app.tabBars.buttons[tab].tap() }
                XCTAssertTrue(app.otherElements["home.readiness"].exists || app.buttons["home.readiness"].exists)
            } else if screen == "navigation" { XCTAssertTrue(app.switches["주행 집중 모드"].waitForExistence(timeout: 10)) }
            else if screen == "month" { XCTAssertTrue(app.navigationBars["월간 결산"].waitForExistence(timeout: 10)) }
            let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "production-" + screen + "-portrait"; portrait.lifetime = .keepAlways; add(portrait)
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTAttachment(screenshot: app.screenshot()); landscape.name = "production-" + screen + "-landscape"; landscape.lifetime = .keepAlways; add(landscape)
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
    }
}
