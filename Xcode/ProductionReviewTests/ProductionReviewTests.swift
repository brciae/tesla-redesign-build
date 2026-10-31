import XCTest
final class ProductionReviewTests: XCTestCase {
    func testLaunch() { review("launch") }
    func testHomeNavigation() { review("home") }
    func testHomeDark() { review("home", appearance: "dark") }
    func testClimateHelp() { review("climate") }
    func testParkingSummary() { review("parking") }
    func testBatterySummary() { review("batterySummary") }
    func testMenuHierarchy() { review("menu") }
    func testHealth() { review("health") }
    func testTariffs() { review("tariffs") }
    func testMonthClosing() { review("month") }
    func testBatteryEvidence() { review("battery") }
    func testCoverage() { review("coverage") }
    func testImportPreview() { review("import") }
    func testInvalidImportBlocked() { review("importInvalid") }
    func testManualAutomationDraft() { review("automation") }
    func testNavigationSettings() { review("navigation") }
    func testUnifiedAutomationVoiceSettings() { review("voice") }
    func testDriving() { review("driving") }
    func testDrivingFocus() { review("focus") }
    private func review(_ screen: String, appearance: String = "light") {
        continueAfterFailure = false
            let app = XCUIApplication()
            defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
            app.launchArguments = ["--ui-review-fixture", "--ui-review-screen", screen, "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR", "-appearance", appearance, "-navigation.focusMode", screen == "focus" ? "YES" : "NO"]
            XCUIDevice.shared.orientation = .portrait
            let launched = Date()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), screen)
            if ["navigation", "driving", "focus"].contains(screen) { allowLocationIfRequested() }
            else { XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists, "Unexpected permission on " + screen) }
            if screen == "home" {
                XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.descendants(matching: .any)["app.launch.brand"].waitForNonExistence(timeout: 5))
                let scene = app.descendants(matching: .any).matching(identifier: "vehicle.scene").firstMatch
                XCTAssertTrue(scene.waitForExistence(timeout: 20))
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (scene.value as? String)?.hasPrefix("yaw") == true }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
                print("PERF home scene ready seconds: \(Date().timeIntervalSince(launched))")
                let beforeRotation = scene.value as? String
                scene.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 0.1, thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
                XCTAssertNotEqual(scene.value as? String, beforeRotation, "Home car must respond to horizontal rotation")
                for tab in ["에너지", "운행", "메뉴", "홈"] {
                    app.tabBars.buttons[tab].tap(); allowLocationIfRequested()
                    if tab == "에너지" && appearance == "light" {
                        app.segmentedControls.buttons["TeslaMate"].tap()
                        app.buttons["배터리"].tap()
                        let capacity = app.buttons["battery.capacity.detail"]
                        for _ in 0..<4 where !capacity.exists || !capacity.isHittable { app.swipeUp() }
                        XCTAssertTrue(capacity.waitForExistence(timeout: 10)); capacity.tap()
                        XCTAssertTrue(app.staticTexts["battery.health.ratio"].waitForExistence(timeout: 10))
                        let integrated = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); integrated.name = "production-main-battery-health"; integrated.lifetime = .keepAlways; add(integrated)
                        app.navigationBars["배터리 용량"].buttons.element(boundBy: 0).tap()
                    }
                    if tab == "메뉴" && appearance == "light" {
                        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); menu.name = "production-main-menu-portrait"; menu.lifetime = .keepAlways; add(menu)
                        app.buttons["주행·안내"].tap()
                        app.buttons["음성·내비 안내"].tap()
                        XCTAssertTrue(app.navigationBars["음성·내비 안내"].waitForExistence(timeout: 5))
                        app.navigationBars["음성·내비 안내"].buttons.element(boundBy: 0).tap()
                        app.navigationBars["주행·안내"].buttons.element(boundBy: 0).tap()
                    }
                }
                XCTAssertTrue(app.buttons["home.chat"].exists)
                XCTAssertTrue(app.descendants(matching: .any)["home.readiness"].waitForExistence(timeout: 10))
                XCUIDevice.shared.press(.home); app.activate()
                XCTAssertTrue(app.descendants(matching: .any)["app.launch.brand"].waitForNonExistence(timeout: 5))
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
            } else if screen == "voice" {
                let navigationVoice = app.buttons["preferences.navigationVoice"]
                for _ in 0..<5 where !navigationVoice.exists || !navigationVoice.isHittable { app.swipeUp() }
                XCTAssertTrue(navigationVoice.waitForExistence(timeout: 5)); navigationVoice.tap()
                XCTAssertTrue(app.switches["길안내 음성"].waitForExistence(timeout: 5))
                let voiceDetail = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); voiceDetail.name = "production-navigation-voice-detail"; voiceDetail.lifetime = .keepAlways; add(voiceDetail)
                app.navigationBars["길안내·안전 경고"].buttons.element(boundBy: 0).tap()
                for _ in 0..<5 { app.swipeDown() }
                let link = app.buttons["preferences.automationVoice"]
                for _ in 0..<5 where !link.exists || !link.isHittable { app.swipeUp() }
                XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
                let master = app.switches["automation.voice.enabled"]
                XCTAssertTrue(master.waitForExistence(timeout: 5))
                let original = master.value as? String
                master.switches.firstMatch.tap()
                let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in master.value as? String != original }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
                let changed = master.value as? String
                app.navigationBars["자동화 음성 설정"].buttons.element(boundBy: 0).tap()
                XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
                XCTAssertEqual(master.value as? String, changed)
                master.switches.firstMatch.tap()
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in master.value as? String == original }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
                XCTAssertEqual(app.switches.matching(identifier: "automation.ai.speech").count, 1)
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
                let voiceSettings = app.buttons["automation.voice.settings"]
                for _ in 0..<6 where !voiceSettings.exists || !voiceSettings.isHittable { app.swipeUp() }
                XCTAssertTrue(voiceSettings.waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["automation.voice.summary"].exists)
                XCTAssertFalse(app.switches["automation.voice.enabled"].exists)
                XCTAssertFalse(app.switches["automation.ai.speech"].exists)
                voiceSettings.tap()
                XCTAssertTrue(app.switches["automation.voice.enabled"].waitForExistence(timeout: 5))
                app.navigationBars["자동화 음성 설정"].buttons.element(boundBy: 0).tap()
            } else if screen == "driving" || screen == "focus" {
                let setup = app.buttons["키 설정"]
                XCTAssertTrue(setup.waitForExistence(timeout: 10)); XCTAssertTrue(setup.isHittable)
                setup.tap()
                XCTAssertTrue(app.navigationBars["운전 화면 설정"].waitForExistence(timeout: 5))
                app.buttons["완료"].tap()
            } else if screen == "navigation" {
                let display = app.buttons["navigation.display.settings"]
                XCTAssertTrue(display.waitForExistence(timeout: 10))
                XCTAssertFalse(app.switches["주행 집중 모드"].exists)
                let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); overview.name = "production-navigation-overview"; overview.lifetime = .keepAlways; add(overview)
                display.tap()
                let focus = app.switches["주행 집중 모드"]
                for _ in 0..<3 where !focus.exists || !focus.isHittable { app.swipeUp() }
                XCTAssertTrue(focus.waitForExistence(timeout: 10))
            } else if screen == "batterySummary" {
                XCTAssertTrue(app.segmentedControls["battery.period"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.descendants(matching: .any)["battery.parking.count"].exists)
                let capacity = app.buttons["battery.capacity.detail"]
                for _ in 0..<3 where !capacity.exists || !capacity.isHittable { app.swipeUp() }
                XCTAssertTrue(capacity.waitForExistence(timeout: 5)); capacity.tap()
                XCTAssertTrue(app.descendants(matching: .any)["battery.health.reason"].waitForExistence(timeout: 5))
                let ratio = app.staticTexts["battery.health.ratio"]
                XCTAssertTrue(ratio.waitForExistence(timeout: 5)); XCTAssertEqual(ratio.label, "99.9%")
                let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); detail.name = "production-battery-health-five-observations"; detail.lifetime = .keepAlways; add(detail)
                let reference = app.buttons["battery.health.reference"]
                for _ in 0..<3 where !reference.isHittable { app.swipeUp() }
                reference.tap()
                XCTAssertTrue(app.navigationBars["용량 비교 기준"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["충전 기반 참고 용량"].exists)
                let referenceScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); referenceScreen.name = "production-battery-reference"; referenceScreen.lifetime = .keepAlways; add(referenceScreen)
                app.navigationBars["용량 비교 기준"].buttons.element(boundBy: 0).tap()
                app.navigationBars["배터리 용량"].buttons.element(boundBy: 0).tap()
                let usage = app.buttons["battery.usage.detail"]
                for _ in 0..<3 where !usage.exists || !usage.isHittable { app.swipeUp() }
                usage.tap()
                let parking = app.descendants(matching: .any)["battery.parking.count"]
                for _ in 0..<6 where !parking.exists || !parking.isHittable { app.swipeUp() }
                XCTAssertTrue(parking.waitForExistence(timeout: 5))
                app.navigationBars["사용량·주차 분석"].buttons.element(boundBy: 0).tap()
                for _ in 0..<5 { app.swipeDown() }
            } else if screen == "climate" {
                XCTAssertTrue(app.buttons["공조 제어 안내 설명"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.buttons.matching(identifier: "설명").count, 0)
            } else if screen == "parking" {
                XCTAssertTrue(app.staticTexts["검증용 주차장"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.staticTexts["온도 대기 중"].exists)
                let details = app.buttons["parking.telemetry.details"]
                XCTAssertTrue(details.waitForExistence(timeout: 5)); details.tap()
                XCTAssertTrue(app.staticTexts["온도 대기 중"].waitForExistence(timeout: 5))
                details.tap()
            } else if screen == "menu" {
                XCTAssertTrue(app.buttons["주행·안내"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["음성·내비 안내"].exists)
                app.buttons["주행·안내"].tap()
                XCTAssertTrue(app.buttons["음성·내비 안내"].waitForExistence(timeout: 5))
                app.navigationBars["주행·안내"].buttons.element(boundBy: 0).tap()
            }
            else if screen == "month" { XCTAssertTrue(app.navigationBars["월간 결산"].waitForExistence(timeout: 10)) }
            // Accessibility state changes before disclosure/navigation animations finish.
            // Capture the settled layout rather than a transient half-collapsed card.
            Thread.sleep(forTimeInterval: 0.6)
            let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); portrait.name = "production-" + screen + (appearance == "dark" ? "-dark" : "") + "-portrait"; portrait.lifetime = .keepAlways; add(portrait)
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in let size = XCUIScreen.main.screenshot().image.size; return size.width > size.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 10), .completed, screen)
            Thread.sleep(forTimeInterval: 0.6)
            let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); landscape.name = "production-" + screen + (appearance == "dark" ? "-dark" : "") + "-landscape"; landscape.lifetime = .keepAlways; add(landscape)
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
