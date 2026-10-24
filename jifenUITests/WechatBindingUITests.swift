import XCTest

@MainActor final class WechatBindingUITests: XCTestCase {
    private func launch(owner: Bool = false, traditional: Bool = false, subscriptions: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFakeSession", "-UITestSkipLegalConsent", "-UITestWechatBinding",
            "-AppleLanguages", traditional ? "(zh-Hant)" : "(zh-Hans)", "-AppleLocale", traditional ? "zh_TW" : "zh_CN"]
        if owner { app.launchArguments.append("-UITestWechatBindingOwner") }
        if subscriptions == 1 { app.launchArguments.append("-UITestWechatBindingSingleSubscription") }
        if subscriptions > 1 { app.launchArguments.append("-UITestWechatBindingDualSubscriptions") }
        app.launch()
        XCTAssertTrue(app.buttons["wechat_binding_primary"].waitForExistence(timeout: 12))
        return app
    }
    private func capture(_ name: String) {
        UITestScreenshotStore.capture(XCUIApplication(), name: name, testCase: self)
    }
    private func select(_ identifier: String, in app: XCUIApplication, towardBottom: Bool = true) {
        let button = app.buttons[identifier]
        let scroll = app.scrollViews["wechat_binding_content"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        // A clipped cell can report hittable while its center falls under the fixed footer.
        // Bring the whole control into the scroll viewport before tapping.
        for _ in 0..<6 {
            if scroll.frame.insetBy(dx: 0, dy: 8).contains(button.frame) { break }
            if towardBottom { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(scroll.frame.insetBy(dx: 0, dy: 8).contains(button.frame), app.debugDescription)
        button.tap()
        XCTAssertEqual(button.value as? String, "1")
    }
    func testMergeSelectionPreviewAndOkayDismissal() {
        let app = launch()
        XCTAssertFalse(app.staticTexts["第 1 步，共 2 步"].exists)
        capture("wechat-binding-options")
        select("wechat_binding_master_wechat", in: app)
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["确认关联结果"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Apple / 微信"].exists)
        XCTAssertTrue(app.staticTexts["27"].exists)
        XCTAssertTrue(app.staticTexts["ID 20836"].exists)
        capture("wechat-binding-preview")
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["微信已绑定"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["wechat_binding_primary"].label, "好的")
        capture("wechat-binding-success")
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["个人资料"].waitForExistence(timeout: 5))
    }
    func testKeepOwnerBlockCanReturnToMerge() {
        let app = launch(owner: true, traditional: true)
        select("wechat_binding_mode_keep", in: app)
        select("wechat_binding_master_wechat", in: app)
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["確認關聯結果"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["wechat_binding_primary"].isEnabled)
        capture("wechat-binding-owner-blocked-hant")
        app.buttons["返回"].tap()
        select("wechat_binding_mode_merge", in: app, towardBottom: false)
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.buttons["wechat_binding_primary"].isEnabled)
        capture("wechat-binding-merge-hant")
    }
    func testMultipleSubscriptionsShowLocalizedRenewalWarningAndCanConfirm() {
        let app = launch(traditional: true, subscriptions: 2)
        app.buttons["wechat_binding_primary"].tap()
        let warning = app.staticTexts["wechat_binding_automatic_renewal_warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(warning.label, "多份訂閱將繼續分別自動續費。關聯帳號不會取消任何自動續費，如需取消，請到各自的訂閱管理中操作。")
        XCTAssertTrue(app.buttons["wechat_binding_primary"].isEnabled)
        app.scrollViews["wechat_binding_content"].swipeUp()
        capture("wechat-binding-dual-subscriptions-hant")
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["微信已綁定"].waitForExistence(timeout: 5))
    }
    func testSingleSubscriptionDoesNotShowMultipleRenewalWarning() {
        let app = launch(subscriptions: 1)
        app.buttons["wechat_binding_primary"].tap()
        XCTAssertTrue(app.staticTexts["确认关联结果"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["wechat_binding_automatic_renewal_warning"].exists)
        XCTAssertTrue(app.buttons["wechat_binding_primary"].isEnabled)
        capture("wechat-binding-single-subscription")
    }
}
