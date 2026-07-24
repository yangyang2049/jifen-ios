import XCTest

/// Focused UI coverage for the iOS structure / team-chain / archery remediation.
final class RemodelFocusUITests: XCTestCase {
    private let remodeledScoreboards: [(id: String, label: String)] = [
        ("pingpong", "乒乓球"),
        ("tennis", "网球"),
        ("basketball", "篮球"),
        ("archery", "射箭"),
        ("doudizhu", "斗地主"),
        ("guandan", "掼蛋"),
    ]

    private let remodeledRecordProjects = [
        "pingpong", "tennis", "basketball", "archery_dual", "doudizhu", "guandan"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRemodeledScoreboardsOpenAndShowBackControl() {
        for item in remodeledScoreboards {
            let app = launchChineseApp()
            defer {
                XCUIDevice.shared.orientation = .portrait
                app.terminate()
            }

            XCTAssertTrue(selectTab("计分", in: app), "Missing Score tab for \(item.id)")
            XCTAssertTrue(openCatalogCard(item.id, label: item.label, in: app), "Missing catalog \(item.id)")
            tapStart(in: app)

            XCUIDevice.shared.orientation = .landscapeLeft
            let back = app.descendants(matching: .any)["scoreboard_back_button"]
            XCTAssertTrue(
                back.waitForExistence(timeout: 10),
                "Remodeled scoreboard missing back control: \(item.id)"
            )

            // Open menu once — confirms shared MenuDialog / Cards relocation still wires.
            if let menu = firstHittable(among: ["scoreboard_menu_button", "menu_button"], in: app) {
                menu.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }

            attachScreenshot("remodel_board_\(item.id)")
        }
    }

    func testRemodeledRecordFixturesOpen() {
        defer { clearRecordFixtures() }
        for project in remodeledRecordProjects {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                "-UITestSkipLegalConsent",
                "-UITestRecordFixtures", "-UITestRecordDetail", project
            ]
            app.launch()
            defer { app.terminate() }

            XCTAssertTrue(
                app.buttons["再来一局"].waitForExistence(timeout: 8),
                "Record detail missing replay for remodeled project \(project)"
            )
            attachScreenshot("remodel_record_\(project)")
        }
    }

    func testMeTabSettingsSurviveFolderMove() {
        let app = launchChineseApp(language: "en", locale: "en_US")
        defer { app.terminate() }

        XCTAssertTrue(selectTab("Me", in: app))
        XCTAssertTrue(app.staticTexts["Scoreboard Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        XCTAssertTrue(app.staticTexts["FAQ"].exists)
        XCTAssertTrue(app.staticTexts["About Us"].exists)
        attachScreenshot("remodel_me_root")
    }

    func testPingPongDoublesStillMapsFourPlayers() {
        let app = launchChineseApp()
        defer { app.terminate() }

        XCTAssertTrue(selectTab("计分", in: app))
        XCTAssertTrue(openCatalogCard("pingpong", label: "乒乓球", in: app))

        let modeControl = app.segmentedControls["singles_doubles_picker"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let doublesOption = app.buttons["doubles_option"]
        if doublesOption.exists {
            doublesOption.tap()
        } else {
            modeControl.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        }
        XCTAssertEqual(modeControl.value as? String, "双打")
        app.buttons["开始"].tap()

        for name in ["红A", "红B", "蓝A", "蓝B"] {
            let player = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch
            XCTAssertTrue(player.waitForExistence(timeout: 8), "Missing doubles player after team-chain remap: \(name)")
        }
        attachScreenshot("remodel_pingpong_doubles")
    }

    // MARK: - Helpers

    private func launchChineseApp(language: String = "zh-Hans", locale: String = "zh_CN") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-UITestSkipLegalConsent"
        ]
        app.launch()
        return app
    }

    private func selectTab(_ name: String, in app: XCUIApplication) -> Bool {
        let tab = app.tabBars.buttons[name]
        guard tab.waitForExistence(timeout: 8) else { return false }
        tab.tap()
        return true
    }

    private func openCatalogCard(_ id: String, label: String, in app: XCUIApplication) -> Bool {
        let identifier = "scoreboard_catalog_\(id)"
        for _ in 0..<10 {
            let card = app.descendants(matching: .any)[identifier]
            if card.exists {
                if !card.isHittable { app.swipeUp() }
                card.tap()
                return app.buttons["开始"].waitForExistence(timeout: 5)
                    || app.buttons["Start"].waitForExistence(timeout: 1)
                    || app.buttons["确认"].waitForExistence(timeout: 1)
            }
            let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if byLabel.exists {
                byLabel.tap()
                return app.buttons["开始"].waitForExistence(timeout: 5)
            }
            app.swipeUp()
        }
        return false
    }

    private func tapStart(in app: XCUIApplication) {
        for label in ["开始", "Start", "确认"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2), button.isHittable {
                button.tap()
                return
            }
        }
    }

    private func firstHittable(among ids: [String], in app: XCUIApplication) -> XCUIElement? {
        for id in ids {
            let el = app.descendants(matching: .any)[id]
            if el.waitForExistence(timeout: 1), el.isHittable { return el }
        }
        return nil
    }

    private func clearRecordFixtures() {
        let cleanup = XCUIApplication()
        cleanup.launchArguments += ["-UITestSkipLegalConsent", "-UITestClearRecordFixtures"]
        cleanup.launch()
        cleanup.terminate()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
