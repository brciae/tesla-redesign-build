import XCTest

final class InteractionTests: XCTestCase {
    func testSpotifySettingsValidateClientIDAndShowLocalPhoneConnection() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["settings-menu-probe"]; app.launch()
        let entry = app.staticTexts["Spotify 연결"]
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        app.buttons["연동 설정"].tap()
        let field = app.textFields["spotify.clientID"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        let connect = app.buttons["spotify.connect"]
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32)); field.typeText("not-a-client-id")
        XCTAssertFalse(connect.isEnabled)
        captureSystemCard("Spotify local phone settings invalid Client ID requires developer app registration")
        // No external login is invoked by a UI test.
    }
    func testProductionSettingsMenuGroupsAndDirectCardSettings() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["settings-menu-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["안내·알림"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts.matching(identifier: "잠금화면·아일랜드").count, 1)
        captureSystemCard("Production settings menu guidance and alerts first")
        app.staticTexts["잠금화면·아일랜드"].tap()
        XCTAssertTrue(app.switches["실시간 현황 표시"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        for section in ["주행·충전", "차량 관리", "연결·기록", "화면·꾸미기", "자동화", "앱 정보"] {
            let title = app.staticTexts[section]
            for _ in 0..<7 where !title.isHittable { app.swipeUp() }
            XCTAssertTrue(title.isHittable, "Missing menu group: \(section)")
            captureSystemCard("Production settings menu \(section)")
        }
    }
    func testLiveActivitySettingsAreVisibleWithoutHiddenDiagnostics() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["live-activity-settings-probe"]; app.launch()
        XCTAssertTrue(app.navigationBars["잠금화면·아일랜드"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.switches["실시간 현황 표시"].exists)
        XCTAssertTrue(app.buttons["실시간 현황 다시 시작"].exists)
        XCTAssertTrue(app.buttons["iPhone 앱 설정 열기"].exists)
        captureSystemCard("Live Activity production settings visible status and controls")
    }
    private func showSystemLockScreenPresentation(_ app: XCUIApplication) -> XCUIApplication {
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let top = board.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.85)))
        return board
    }
    private func captureSystemCard(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testSystemLockScreenNavigationCardStartsWithoutFirstLocationTick() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["system-navigation-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 8))
        var board = showSystemLockScreenPresentation(app)
        let card = board.staticTexts["길안내 준비 중"]
        let rendered = card.waitForExistence(timeout: 12)
        captureSystemCard("System Lock Screen navigation card without vehicle")
        XCTAssertTrue(rendered, "Real installed widget must render in the system Lock Screen presentation")
        app.activate()
        app.buttons["상태 갱신"].tap()
        board = showSystemLockScreenPresentation(app)
        XCTAssertTrue(board.staticTexts["오크밸리1길 우회전"].waitForExistence(timeout: 12))
        captureSystemCard("System Lock Screen navigation card updated guidance")
        app.activate()
        app.buttons["세션 종료"].tap()
        XCTAssertTrue(app.staticTexts["차량 연결·길안내·충전 시작 후 표시 가능"].waitForExistence(timeout: 8))
        board = showSystemLockScreenPresentation(app)
        let removed = NSPredicate { _, _ in !board.staticTexts["길안내 준비 중"].exists && !board.staticTexts["오크밸리1길 우회전"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 12), .completed)
        captureSystemCard("System Lock Screen navigation card removed after end")
        app.activate()
    }
    func testSystemLockScreenChargingCardProgressStaleAndEnd() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["system-charging-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 8))
        var board = showSystemLockScreenPresentation(app)
        let rendered = board.staticTexts["충전 중"].waitForExistence(timeout: 12)
        captureSystemCard("System Lock Screen charging card initial")
        XCTAssertTrue(rendered)
        XCTAssertTrue(board.staticTexts["60%"].exists)
        XCTAssertTrue(board.staticTexts["목표 80%"].exists)
        XCTAssertTrue(board.staticTexts["7.2 kW"].exists)
        app.activate(); app.buttons["상태 갱신"].tap()
        board = showSystemLockScreenPresentation(app)
        XCTAssertTrue(board.staticTexts["62%"].waitForExistence(timeout: 12))
        captureSystemCard("System Lock Screen charging card updated progress")
        app.activate(); app.buttons["수신 지연"].tap()
        board = showSystemLockScreenPresentation(app)
        XCTAssertTrue(board.staticTexts["충전 업데이트 대기"].waitForExistence(timeout: 12))
        XCTAssertFalse(board.staticTexts["62%"].exists)
        captureSystemCard("System Lock Screen charging card stale hides old values")
        app.activate(); app.buttons["세션 종료"].tap()
        XCTAssertTrue(app.staticTexts["차량 연결·길안내·충전 시작 후 표시 가능"].waitForExistence(timeout: 8))
        board = showSystemLockScreenPresentation(app)
        let removed = NSPredicate { _, _ in !board.staticTexts["충전 업데이트 대기"].exists && !board.staticTexts["충전 중"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 12), .completed)
        captureSystemCard("System Lock Screen charging card removed after end")
        app.activate()
    }
    func testSupportingCopyCollapsedDetailScrollableAndFullAddress() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["copy-readability-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["최근 20회 주행 기준"].waitForExistence(timeout: 8))
        let fullNote = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "상세 설명 끝.")).firstMatch
        XCTAssertFalse(fullNote.exists, "Long explanation must be collapsed on the summary")
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        capture("Shared production copy collapsed supporting explanation")
        app.buttons["설명"].tap()
        XCTAssertTrue(fullNote.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["닫기"].exists)
        app.scrollViews.firstMatch.swipeUp()
        capture("Shared production copy full explanation scrollable")
        app.buttons["닫기"].tap()
        app.buttons["계산 근거 설명"].tap()
        XCTAssertTrue(fullNote.waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        app.buttons["긴 주소 보기"].tap()
        let address = app.staticTexts["경기도 용인시 처인구 포곡읍 둔전리 힐스테이트 용인둔전역 아파트 단지 정문 주차장 입구"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(address.frame.height, 20, "Long address must wrap at readable size")
        capture("Production recent destination full address wraps without ellipsis")
    }
    func testConciseGuidanceAcrossThemesAndRotation() {
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "long-guidance-probe"]; app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for title in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
                app.segmentedControls.buttons[title].tap()
                let named = app.staticTexts["동작대교 오른쪽 진출"].firstMatch
                let action = app.staticTexts["오른쪽 진출"].firstMatch
                XCTAssertTrue(named.waitForExistence(timeout: 3) || action.exists)
                XCTAssertFalse(app.staticTexts["동작대교 · 국립현충원 · 강남역 · 서울역 · 한강대로 오른쪽 진출"].exists)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "Concise guidance \(title) \(orientation == .portrait ? "portrait" : "landscape")"
                shot.lifetime = .keepAlways; add(shot)
            }
        }
    }

    func testLockScreenNavigationCardWithoutVehicleUpdatesStaleAndEnd() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["lock-screen-navigation-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["live.navigation.distance"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["live.navigation.distance"].label, "2.4 km")
        XCTAssertTrue(app.staticTexts["9시 방향 출구"].exists)
        XCTAssertFalse(app.staticTexts["힐스테이트 용인둔전역 아파트 정문"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["live.navigation.arrival"].firstMatch.exists)
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        capture("Lock Screen shared card long destination and roundabout without vehicle")
        app.buttons["차량 없이 카드 시작"].tap()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 8))
        app.buttons["다음 안내 수신"].tap()
        XCTAssertEqual(app.staticTexts["live.navigation.distance"].label, "300 m")
        XCTAssertTrue(app.staticTexts["오크밸리1길 우회전"].exists)
        capture("Lock Screen shared card updated turn and arrival")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["live.navigation.distance"].waitForExistence(timeout: 5))
        app.buttons["위치 수신 중단"].tap()
        XCTAssertTrue(app.staticTexts["길안내 업데이트 대기"].exists)
        XCTAssertFalse(app.staticTexts["live.navigation.distance"].exists)
        XCTAssertFalse(app.staticTexts["오크밸리1길 우회전"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["live.navigation.arrival"].firstMatch.exists)
        capture("Lock Screen shared card stale hides old turn distance and ETA")
        app.buttons["안내 종료"].tap()
        XCTAssertTrue(app.staticTexts["live.navigation.ended"].exists)
        XCTAssertTrue(app.staticTexts["차량 연결·길안내·충전 시작 후 표시 가능"].waitForExistence(timeout: 5))
        capture("Lock Screen guidance ended without vehicle")
    }

    func testRecoveredChargeTimingAndRemovedScreenBriefing() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["record-recovery-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["충전 종료 반영됨"].waitForExistence(timeout: 8))
        for prefix in ["충전 시작:", "충전 종료:", "충전 최초 관측:", "마지막 수신:"] {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch.exists)
        }
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "브리핑")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Recovered charge timing without screen briefing"; shot.lifetime = .keepAlways; add(shot)
    }
    func testPlaybackSourceIconsAcrossThemesAndSourceChanges() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "media-source-probe"]; app.launch()
        let icon = app.descendants(matching: .any).matching(identifier: "navigation.media.source").firstMatch
        for source in ["Spotify", "Apple Music", "YouTube Music", "TIDAL", "Bluetooth", "USB", "AUX", "FM", "YouTube", "Netflix", "Disney+", "브라우저", "게임", "정보 없음"] {
            let label = source == "정보 없음" ? "재생 소스 정보 없음" : source
            XCTAssertTrue(icon.waitForExistence(timeout: 5))
            XCTAssertEqual(icon.label, "재생 소스: \(label)")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Playback source \(source)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["media.source.next"].tap()
        }
        for title in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
            app.segmentedControls.buttons[title].tap()
            XCTAssertTrue(icon.waitForExistence(timeout: 5))
            XCTAssertEqual(icon.label, "재생 소스: Spotify")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Playback icon theme \(title)"; shot.lifetime = .keepAlways; add(shot)
        }
    }
    func testDashboardShadeSliderAndWhiteGuidance() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "shade-probe", "roundabout-probe"]; app.launch()
        let slider = app.sliders["navigation.shade.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        for (position, label) in [(CGFloat(0), "0%"), (CGFloat(1), "100%"), (CGFloat(0.45), "45%")] {
            slider.adjust(toNormalizedSliderPosition: position)
            XCTAssertEqual(app.staticTexts["navigation.shade.percent"].label, label)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "White guidance dashboard shade \(label)"; shot.lifetime = .keepAlways; add(shot)
        }
    }
    func testTrafficRefreshBlocksRepeatedTapAndKeepsRouteOnFailure() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["traffic-refresh-probe"]; app.launch()
        let button = app.buttons["navigation.traffic.refresh"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertFalse(button.isEnabled)
        XCTAssertTrue(app.staticTexts["기존 경로 A"].exists)
        app.buttons["응답 실패"].tap()
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(app.staticTexts["갱신 지연 · 기존 경로 유지"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Traffic refresh control failure preserves existing route fixture"; shot.lifetime = .keepAlways; add(shot)
    }
    func testRobotWithoutFootRodsSurvivesAppSwitching() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["robot-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["로봇 모델 로드됨"].waitForExistence(timeout: 15))
        for title in ["대기", "비행"] {
            if title == "비행" { app.buttons["비행"].tap() }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Robot removed foot rods \(title)"; shot.lifetime = .keepAlways; add(shot)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.otherElements["robot.scene"].waitForExistence(timeout: 5))
        }
    }
    func testJunctionStaysInGuidanceAndDisappearsAfterExit() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["fullscreen-navigation-probe", "junction-probe"]; app.launch()
        for title in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
            XCTAssertTrue(app.buttons["navigation.chrome.open"].waitForExistence(timeout: 5))
            app.buttons["navigation.chrome.open"].tap()
            app.buttons[title].tap()
            app.buttons["navigation.chrome.close"].tap()
            let junction = app.otherElements["navigation.junction"]
            XCTAssertTrue(junction.waitForExistence(timeout: 3))
            let region = app.otherElements["navigation.junction.region"].firstMatch
            XCTAssertTrue(region.exists)
            XCTAssertTrue(region.frame.insetBy(dx: -1, dy: -1).contains(junction.frame))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Junction contained in guidance \(title)"; shot.lifetime = .keepAlways; add(shot)
        }
        app.buttons["navigation.chrome.open"].tap()
        app.buttons["진출 지점 통과"].tap()
        app.buttons["navigation.chrome.close"].tap()
        XCTAssertFalse(app.otherElements["navigation.junction"].exists)
    }
    func testLiveActivityViewsAndBackgroundReturn() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["live-activity-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["300미터 앞 우회전"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["업데이트 대기"].exists)
        XCTAssertTrue(app.staticTexts["배터리 72%"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["live.activity.minimal"].firstMatch.exists)
        let gain = app.sliders["voice.gain.길안내 음량"]
        gain.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(app.staticTexts["200%"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Live activity shared views compact expanded and stale"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            let background = NSPredicate { _, _ in
                app.state == .runningBackground || app.state == .runningBackgroundSuspended
            }
            let entered = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: background, object: app)], timeout: 8) == .completed
            XCTAssertTrue(entered, "App did not enter background; state=\(app.state.rawValue)")
            app.activate()
            XCTAssertTrue(app.staticTexts["300미터 앞 우회전"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["200%"].exists, "Background return must preserve the local slider state without a relaunch")
        }
    }
    func testActualLiveActivityExtensionOnHomeScreen() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["live-activity-probe"]; app.launch()
        app.buttons["실제 실시간 현황 시작"].tap()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        // Activity.request returns before the widget service finishes its first snapshot.
        let snapshotDelay = expectation(description: "Widget service first snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { snapshotDelay.fulfill() }
        wait(for: [snapshotDelay], timeout: 6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Actual ActivityKit widget extension on home screen"; shot.lifetime = .keepAlways; add(shot)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // A successful Activity.request alone does not prove the extension rendered.
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.038))
        island.press(forDuration: 1.2)
        let rendered = springboard.staticTexts["300미터 앞 우회전"].waitForExistence(timeout: 10)
        let expandedShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedShot.name = "Actual Live Activity expanded rendering verification"
        expandedShot.lifetime = .keepAlways; add(expandedShot)
        XCTAssertTrue(rendered, "ActivityKit request succeeded but the real widget extension did not render guidance")
        app.activate()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 5))
        app.buttons["실시간 현황 다시 시작"].tap()
        XCTAssertTrue(app.staticTexts["실시간 현황 요청됨 · 화면 표시 별도 확인"].waitForExistence(timeout: 8))
        app.buttons["음악 동시 표시 시험"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30))
        let play = safari.buttons["테스트 음악 재생"]
        guard play.waitForExistence(timeout: 45) else { XCTFail("Local music page did not load in Safari"); return }
        play.tap()
        XCTAssertTrue(safari.buttons["테스트 음악 재생 중"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let musicDelay = expectation(description: "Music and Live Activity snapshots")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { musicDelay.fulfill() }
        wait(for: [musicDelay], timeout: 6)
        let sharedShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sharedShot.name = "Actual Live Activity with Safari music playback"; sharedShot.lifetime = .keepAlways; add(sharedShot)
        safari.terminate(); app.activate()
    }
    func testChargingMapDestinationAndRejectedVehicleSend() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["charging-map-probe"]; app.launch()
        XCTAssertTrue(app.buttons["charging.destination"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["3/8대 가능"].exists)
        XCTAssertFalse(app.buttons["충전소 새로고침"].frame.intersects(app.segmentedControls.firstMatch.frame))
        let mapShot = XCTAttachment(screenshot: app.screenshot()); mapShot.name = "Nearby charging map and selected station"; mapShot.lifetime = .keepAlways; add(mapShot)
        app.segmentedControls.buttons["급속"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "공공 검증 충전소").firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["급속 1/1대 · 완속 0/1대"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "비회원 표준가 470")).firstMatch.waitForExistence(timeout: 5))
        let publicShot = XCTAttachment(screenshot: app.screenshot()); publicShot.name = "Public charger rapid and slow categories"; publicShot.lifetime = .keepAlways; add(publicShot)
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

    func testCachedSafetySpeechTracksDistanceAndSpeed() {
        let app = XCUIApplication(); app.launchArguments = ["voice-playback-probe", "voice-distance-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["캐시 안내 · 통과 취소 및 속도별 재생 차단 확인"].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Cached safety guidance passed-point cancellation and speed gate"; shot.lifetime = .keepAlways; add(shot)
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

    func testPublishedTariffDefaultsToNonmemberAndMemberCheckbox() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["published-tariff-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["예상 충전금액 3570원"].waitForExistence(timeout: 10))
        let toggle = app.switches["charging.member.플러그링크"]
        XCTAssertEqual(toggle.value as? String, "0")
        let baseline = XCTAttachment(screenshot: app.screenshot()); baseline.name = "Published operator tariff defaults to nonmember with source"; baseline.lifetime = .keepAlways; add(baseline)
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts["예상 충전금액 2920원"].waitForExistence(timeout: 5))
        let member = XCTAttachment(screenshot: app.screenshot()); member.name = "Published operator tariff after own member checkbox"; member.lifetime = .keepAlways; add(member)
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["예상 충전금액 3570원"].waitForExistence(timeout: 5))
        app.buttons["사업자 전체 요금표"].tap()
        XCTAssertTrue(app.navigationBars["사업자 공식 충전 단가"].waitForExistence(timeout: 5))
        let catalog = XCTAttachment(screenshot: app.screenshot()); catalog.name = "Published operator catalog conditions and missing rates"; catalog.lifetime = .keepAlways; add(catalog)
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
        let result = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "음성 상태 18/18 검증 완료", "실패 ·")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 90))
        XCTAssertEqual(result.label, "음성 상태 18/18 검증 완료")
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
        XCTAssertTrue(app.staticTexts["주행·배터리 요약"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["battery.health.reason"].label.contains("기준 용량 미등록"))
        XCTAssertFalse(app.staticTexts["현재 지수 100%"].exists)
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Battery summary and missing same-method reference"; top.lifetime = .keepAlways; add(top)
        let exclusions = app.buttons["battery.health.exclusions"]
        XCTAssertTrue(exclusions.exists); exclusions.tap()
        XCTAssertTrue(app.staticTexts["SOC 변화 20%p 미만"].exists)
        captureSystemCard("Battery degradation qualifying charges and exclusion reasons")
        exclusions.tap()
        app.buttons["같은 종류 기준 등록 예시"].tap()
        XCTAssertTrue(app.staticTexts["battery.health.reason"].label.contains("동일 종류 기준"))
        for period in ["7일", "30일", "90일"] {
            app.segmentedControls.buttons[period].tap()
            XCTAssertTrue(app.segmentedControls.buttons[period].isSelected)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Battery baseline"; shot.lifetime = .keepAlways; add(shot)
        app.swipeUp()
        let graphs = XCTAttachment(screenshot: app.screenshot()); graphs.name = "Battery separate SOC events and trip consumption"; graphs.lifetime = .keepAlways; add(graphs)
        app.swipeUp()
        let trips = XCTAttachment(screenshot: app.screenshot()); trips.name = "Battery trip rows and parking precision"; trips.lifetime = .keepAlways; add(trips)
        let parkingReasons = app.buttons["battery.parking.reasons"]
        for _ in 0..<6 where !parkingReasons.isHittable { app.swipeUp() }
        XCTAssertTrue(parkingReasons.isHittable); parkingReasons.tap()
        XCTAssertTrue(app.staticTexts["양 끝 잔량 미확인"].exists)
        captureSystemCard("Parking measured short interval and excluded endpoint reason directly accessible")
    }
    func testHomeChargingRadiusAndDatedSave() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["home-charging-probe"]; app.launch()
        let slider = app.sliders["home.charge.radius"]
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "Home charging apartment radius and map"; initial.lifetime = .keepAlways; add(initial)
        slider.adjust(toNormalizedSliderPosition: 0.5)
        let save = app.buttons["home.charge.save"]
        for _ in 0..<3 where !save.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.88)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)))
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "주소·범위 저장됨")).firstMatch.waitForExistence(timeout: 5))
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Home address effective history saved"; saved.lifetime = .keepAlways; add(saved)
    }
    func testChargingFourTimeBands() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["charging-time-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["charging.time.bands"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["charging.time.bands"].label.contains("오전 06:00") && app.staticTexts["charging.time.bands"].label.contains("11:59"))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "23~9시")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Charging four time bands"; shot.lifetime = .keepAlways; add(shot)
    }
    func testAttachmentDownsampleAndMalformedInput() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["attachment-safety-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["PASS 사진 축소·손상 입력 방어"].waitForExistence(timeout: 12))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Bounded image decoding and malformed input"; shot.lifetime = .keepAlways; add(shot)
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
    func testTripRecordSummaryAndSelectedComparison() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["trip-record-probe"]; app.launch()
        XCTAssertTrue(app.staticTexts["샘플 출발지"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["28.00"].exists && app.staticTexts["4.00"].exists)
        let summary = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); summary.name = "Trip record endpoints four metrics and guidance timeline"; summary.lifetime = .keepAlways; add(summary)
        app.buttons["다른 주행과 비교"].tap()
        XCTAssertTrue(app.staticTexts["trip.compare.time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["trip.compare.time"].label.contains("+2분"))
        XCTAssertTrue(app.staticTexts["trip.compare.efficiency"].label.contains("전비 -"))
        let comparison = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); comparison.name = "Trip comparison signed time and efficiency with separate units"; comparison.lifetime = .keepAlways; add(comparison)
    }
    func testContextSpeechSettingsAndRoutineOmission() {
        let app = XCUIApplication(); app.launchArguments = ["context-speech-probe"]; app.launch()
        let toggle = app.switches["automation.ai.speech"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        // SwiftUI Form exposes a row-sized switch and its actual UISwitch child.
        // The row midpoint is label whitespace and does not toggle the control.
        let thumb = toggle.switches.firstMatch
        XCTAssertTrue(thumb.exists, "Expected the actual switch control")
        if toggle.value as? String != "1" { thumb.tap() }
        XCTAssertEqual(toggle.value as? String, "1", "AI setting must actually turn on")
        XCTAssertTrue(app.switches["automation.ai.routine"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["automation.ai.example"].tap()
        XCTAssertTrue(app.staticTexts["automation.ai.preview"].label.contains("82퍼센트"))
        XCTAssertTrue(app.staticTexts["automation.ai.preview"].label.contains("실내 온도가 높습니다"))
        app.buttons["automation.ai.omit.example"].tap()
        XCTAssertTrue(app.staticTexts["automation.ai.preview"].label.contains("생략함"))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "AI context speech consent settings and nonessential greeting omission"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "1", "AI setting must persist after relaunch")
        thumb.tap() // Keep subsequent playback tests on their original local-only path.
        XCTAssertEqual(toggle.value as? String, "0")
    }
    func testTripEnergyForecastAcrossThemesAndRotation() {
        let app = XCUIApplication(); app.launchArguments = ["navigation-probe", "energy-forecast-probe"]; app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            for theme in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
                let button = app.segmentedControls.buttons[theme]
                XCTAssertTrue(button.waitForExistence(timeout: 8)); button.tap()
                let forecast = app.staticTexts["energy.forecast.arrival"].firstMatch
                XCTAssertTrue(forecast.waitForExistence(timeout: 5), "forecast absent: \(theme)")
                XCTAssertTrue(forecast.label.contains("도착 예상 65.8%"))
                XCTAssertTrue(forecast.isHittable, "forecast clipped: \(theme)")
                XCTAssertTrue(app.staticTexts["energy.forecast.consumption"].firstMatch.label.contains("1.6 kWh"))
                if theme == "파노라마", orientation == .portrait {
                    let gear = app.descendants(matching: .any).matching(identifier: "navigation.panorama.gear").firstMatch
                    XCTAssertTrue(gear.waitForExistence(timeout: 3))
                    XCTAssertGreaterThan(gear.frame.minY, app.staticTexts["energy.forecast.consumption"].firstMatch.frame.maxY + 4,
                                         "Forecast must not cover the panorama gear selector")
                }
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "Trip energy forecast \(theme) \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        app.buttons["navigation.empty"].tap()
        XCTAssertFalse(app.staticTexts["energy.forecast.arrival"].firstMatch.exists)
        XCUIDevice.shared.orientation = .portrait
        app.terminate(); app.launchArguments = ["energy-history-probe"]; app.launch()
        let comparison = app.staticTexts["energy.forecast.comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 8)); XCTAssertTrue(comparison.label.contains("실제 64%"))
        XCTAssertTrue(app.otherElements["energy.forecast.chart"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["도착 전 배터리 부족 예상"].exists)
        let historyShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        historyShot.name = "Trip energy actual arrival comparison and battery shortage"; historyShot.lifetime = .keepAlways; add(historyShot)
        app.buttons["energy.forecast.charge.example"].tap()
        XCTAssertTrue(app.staticTexts["energy.forecast.charging"].label.contains("+10.0%p"))
        XCTAssertTrue(app.staticTexts["energy.forecast.comparison"].label.contains("실제 74%"))
        let chargeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        chargeShot.name = "Trip energy graph with observed intermediate charging"; chargeShot.lifetime = .keepAlways; add(chargeShot)
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
    func testNoVehicleRouteStopVisibleWithoutOpeningChromeAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["fullscreen-navigation-probe", "no-vehicle-route-probe", "reset-route-probe"]
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for title in ["클러스터", "투어링", "미니멀", "파노라마", "포커스", "관제"] {
            let stop = app.buttons["navigation.parked.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 8)); XCTAssertTrue(stop.isHittable)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
            XCTAssertTrue(app.buttons["navigation.chrome.open"].exists)
            app.buttons["navigation.chrome.open"].tap()
            XCTAssertTrue(app.buttons["navigation.chrome.close"].waitForExistence(timeout: 4))
            app.buttons[title].tap()
            XCTAssertTrue(stop.isHittable)
            let panel = app.otherElements["navigation.chrome.panel"].firstMatch
            let separated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                panel.exists && stop.exists && stop.frame.minY >= panel.frame.maxY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [separated], timeout: 4), .completed, "Open toolbar overlaps maneuver/stop: \(title)")
            captureSystemCard("Integrated route stop and expanded toolbar \(title) \(orientation.rawValue)")
            app.buttons["navigation.chrome.close"].tap()
            XCTAssertTrue(app.buttons["navigation.chrome.open"].waitForExistence(timeout: 4))
            let pause = app.buttons["일시정지"].firstMatch
            XCTAssertTrue(pause.exists)
            XCTAssertFalse(stop.frame.intersects(pause.frame), "Route stop overlaps music control: \(title)")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "No vehicle persistent route stop \(title) \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        app.buttons["navigation.parked.stop"].tap()
        XCTAssertTrue(app.staticTexts["fullscreen.stopped"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["navigation.parked.stop"].exists)
        app.terminate()
        app.launchArguments = ["fullscreen-navigation-probe", "no-vehicle-route-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fullscreen.stopped"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["navigation.parked.stop"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Explicit route stop remains cleared after relaunch"; shot.lifetime = .keepAlways; add(shot)
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
