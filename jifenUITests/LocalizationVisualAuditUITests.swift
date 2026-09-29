import XCTest

/// Screenshot matrix for reviewed localizations. The host-side runner refuses
/// to start until every requested locale passes the human-review promotion
/// gate, so machine drafts can never masquerade as UI-tested languages.
final class LocalizationVisualAuditUITests: XCTestCase {
    private struct AuditLocale {
        let code: String
        let configuration: UITestLocale.Configuration
        let isRTL: Bool

        var filePrefix: String {
            code.replacingOccurrences(of: "-", with: "_")
        }
    }

    private let priorityLocales = [
        AuditLocale(code: "ja", configuration: UITestLocale.ja, isRTL: false),
        AuditLocale(code: "ko", configuration: UITestLocale.ko, isRTL: false),
        AuditLocale(code: "de", configuration: UITestLocale.de, isRTL: false),
        AuditLocale(code: "it", configuration: UITestLocale.it, isRTL: false),
        AuditLocale(code: "nl", configuration: UITestLocale.nl, isRTL: false),
        AuditLocale(code: "sv", configuration: UITestLocale.sv, isRTL: false),
        AuditLocale(code: "fr", configuration: UITestLocale.fr, isRTL: false),
        AuditLocale(code: "fr-CA", configuration: UITestLocale.frCA, isRTL: false),
        AuditLocale(code: "ru", configuration: UITestLocale.ru, isRTL: false),
        AuditLocale(code: "uk", configuration: UITestLocale.uk, isRTL: false),
        AuditLocale(code: "es-MX", configuration: UITestLocale.esMX, isRTL: false),
        AuditLocale(code: "es-ES", configuration: UITestLocale.esES, isRTL: false),
        AuditLocale(code: "pt-BR", configuration: UITestLocale.ptBR, isRTL: false),
        AuditLocale(code: "pt-PT", configuration: UITestLocale.ptPT, isRTL: false),
    ]

    private let rtlLocales = [
        AuditLocale(code: "ar", configuration: UITestLocale.ar, isRTL: true),
        AuditLocale(code: "he", configuration: UITestLocale.he, isRTL: true),
        AuditLocale(code: "ur", configuration: UITestLocale.ur, isRTL: true),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testCapturePriorityLocales() {
        for locale in selected(from: priorityLocales) {
            XCTContext.runActivity(named: "Visual audit \(locale.code)") { _ in
                capture(locale)
            }
        }
    }

    func testCaptureRTLLocales() {
        for locale in selected(from: rtlLocales) {
            XCTContext.runActivity(named: "RTL visual audit \(locale.code)") { _ in
                capture(locale)
            }
        }
    }

    // Dedicated entry points let the host runner select exact locales with
    // -only-testing. Xcode 27 no longer reliably forwards arbitrary host
    // environment variables into the XCTest runner process.
    func testCaptureJa() { captureLocale("ja") }
    func testCaptureKo() { captureLocale("ko") }
    func testCaptureDe() { captureLocale("de") }
    func testCaptureIt() { captureLocale("it") }
    func testCaptureNl() { captureLocale("nl") }
    func testCaptureSv() { captureLocale("sv") }
    func testCaptureFr() { captureLocale("fr") }
    func testCaptureFrCA() { captureLocale("fr-CA") }
    func testCaptureRu() { captureLocale("ru") }
    func testCaptureUk() { captureLocale("uk") }
    func testCaptureEsMX() { captureLocale("es-MX") }
    func testCaptureEsES() { captureLocale("es-ES") }
    func testCapturePtBR() { captureLocale("pt-BR") }
    func testCapturePtPT() { captureLocale("pt-PT") }
    func testCaptureAr() { captureLocale("ar") }
    func testCaptureHe() { captureLocale("he") }
    func testCaptureUr() { captureLocale("ur") }

    func testCaptureCompactControls() {
        for locale in priorityLocales + rtlLocales.filter({ $0.code == "ar" }) {
            captureCompactControls(locale)
        }
    }

    func testCaptureCompactRomanceControls() {
        for locale in priorityLocales.filter({ ["es-ES", "es-MX", "pt-BR", "pt-PT", "it"].contains($0.code) }) {
            captureCompactControls(locale)
        }
    }

    func testCaptureContextualLabels() {
        for locale in priorityLocales + rtlLocales.filter({ $0.code == "ar" }) {
            var app = launch(locale)
            if tapTab(3, in: app) {
                let chess = element("timer_dest_chess", in: app)
                XCTAssertTrue(chess.waitForExistence(timeout: 5))
                chess.tap()
                snap(app, locale, "17_buttons_timer_setup")
            }
            app.terminate()

            app = launch(locale)
            if tapTab(4, in: app) {
                let account = element("settings_account_entry", in: app)
                XCTAssertTrue(account.waitForExistence(timeout: 5))
                account.tap()
                XCTAssertTrue(element("account_login_terms_link", in: app).waitForExistence(timeout: 5))
                snap(app, locale, "18_buttons_login")
            }
            app.terminate()

            app = launch(locale)
            if tapTab(2, in: app) {
                let guandan = element("scoreboard_catalog_guandan", in: app)
                if scrollUntilHittable(guandan, in: app) {
                    guandan.tap()
                    snap(app, locale, "19_buttons_guandan_setup")
                } else {
                    XCTFail("\(locale.code): Guandan setup missing")
                }
            }
            app.terminate()
        }
    }

    func testCaptureAccountTitles() {
        for locale in priorityLocales + rtlLocales.filter({ $0.code == "ar" }) {
            let app = launch(locale)
            if tapTab(4, in: app) {
                snap(app, locale, "15_buttons_me")
            }
            if tapTab(3, in: app) {
                let chess = element("timer_dest_chess", in: app)
                XCTAssertTrue(chess.waitForExistence(timeout: 5))
                chess.tap()
                snap(app, locale, "17_buttons_timer_setup")
            }
            app.terminate()
        }
    }

    private func captureCompactControls(_ locale: AuditLocale) {
        let app = launch(locale)
        defer { app.terminate() }
        guard waitForTab(0, in: app) else {
            XCTFail("\(locale.code): home tab missing")
            return
        }
        snap(app, locale, "10_buttons_home")
        app.swipeUp()
        snap(app, locale, "11_buttons_home_tools")
        if tapTab(2, in: app) {
            snap(app, locale, "12_buttons_score_catalog")
            // Keep the long shooting-training label in the clear area between
            // the navigation and tab bars instead of swiping past that row.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            snap(app, locale, "13_buttons_score_catalog_lower")
        }
        if tapTab(3, in: app) {
            snap(app, locale, "14_buttons_timer_catalog")
        }
        if tapTab(4, in: app) {
            snap(app, locale, "15_buttons_me")
            let membership = element("settings_membership_entry", in: app)
            guard scrollUntilHittable(membership, in: app) else {
                XCTFail("\(locale.code): membership entry missing")
                return
            }
            membership.tap()
            waitForMembershipToSettle(in: app)
            snap(app, locale, "16_buttons_membership")
        }
    }

    /// Focused retest for long legal copy, including the three-link subscription
    /// sentence as well as the default two-link lifetime sentence.
    func testCaptureMembershipReview() {
        for locale in (priorityLocales + rtlLocales).filter({ ["fr", "fr-CA", "ru", "ar", "it", "nl", "sv"].contains($0.code) }) {
            let app = launch(locale)
            defer { app.terminate() }
            guard tapTab(4, in: app) else { continue }
            let membership = element("settings_membership_entry", in: app)
            guard scrollUntilHittable(membership, in: app) else {
                XCTFail("\(locale.code): membership entry is missing")
                continue
            }
            membership.tap()
            waitForMembershipToSettle(in: app)
            snap(app, locale, "06_membership")
            let monthly = element("membership_plan_iscoreboard_monthly_vip", in: app)
            guard scrollUntilHittable(monthly, in: app) else {
                XCTFail("\(locale.code): monthly plan is missing")
                continue
            }
            monthly.tap()
            snap(app, locale, "06_membership_subscription")
        }
    }

    private func captureLocale(_ code: String) {
        guard let locale = (priorityLocales + rtlLocales).first(where: { $0.code == code }) else {
            XCTFail("Unknown visual-audit locale: \(code)")
            return
        }
        XCTContext.runActivity(named: "Visual audit \(locale.code)") { _ in
            capture(locale)
        }
    }

    /// LOCALIZATION_VISUAL_AUDIT_LOCALES is optional and comma-separated. It
    /// lets the host script rerun one promoted locale without recapturing all.
    private func selected(from locales: [AuditLocale]) -> [AuditLocale] {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["TEST_RUNNER_LOCALIZATION_VISUAL_AUDIT_LOCALES"]
                ?? environment["LOCALIZATION_VISUAL_AUDIT_LOCALES"],
              !raw.isEmpty else {
            return locales
        }
        let requested = Set(raw.split(separator: ",").map(String.init))
        return locales.filter { requested.contains($0.code) }
    }

    private func capture(_ locale: AuditLocale) {
        var app = launch(locale)
        guard waitForTab(0, in: app) else {
            XCTFail("\(locale.code): home tab did not appear")
            app.terminate()
            return
        }

        snap(app, locale, "01_home")
        if locale.isRTL {
            attachRTLMetrics(
                app,
                locale: locale,
                stage: "home",
                identifiers: ["main_tab_0", "main_tab_1", "main_tab_2", "main_tab_3", "main_tab_4", "home_cast_button", "home_quick_start_primary"]
            )
        }

        if tapTab(2, in: app) {
            _ = element("scoreboard_catalog_pingpong", in: app).waitForExistence(timeout: 5)
            snap(app, locale, "02_score_catalog")

            let pingPong = element("scoreboard_catalog_pingpong", in: app)
            if scrollUntilHittable(pingPong, in: app) {
                pingPong.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.7))
                snap(app, locale, "03_pingpong_setup")
            } else {
                XCTFail("\(locale.code): ping-pong setup entry is missing")
            }
        }
        app.terminate()

        app = launch(locale)
        if tapTab(3, in: app) {
            _ = element("timer_dest_go", in: app).waitForExistence(timeout: 5)
            snap(app, locale, "04_timer_catalog")
        }
        if tapTab(4, in: app) {
            _ = element("settings_account_entry", in: app).waitForExistence(timeout: 5)
            snap(app, locale, "05_me")
            if locale.isRTL {
                attachRTLMetrics(
                    app,
                    locale: locale,
                    stage: "me",
                    identifiers: ["main_tab_0", "main_tab_4", "settings_account_entry", "settings_membership_entry", "settings_website_entry"]
                )
            }

            let membership = element("settings_membership_entry", in: app)
            if scrollUntilHittable(membership, in: app) {
                membership.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                waitForMembershipToSettle(in: app)
                snap(app, locale, "06_membership")
            } else {
                XCTFail("\(locale.code): membership entry is missing")
            }
        }
        app.terminate()

        app = launch(locale)
        if tapTab(4, in: app) {
            let faq = element("settings_faq_entry", in: app)
            if scrollUntilHittable(faq, in: app) {
                faq.tap()
                let longQuestion = element("settings_faq_question_5", in: app)
                if scrollUntilHittable(longQuestion, in: app) {
                    longQuestion.tap()
                    _ = element("settings_faq_answer_5", in: app).waitForExistence(timeout: 4)
                    snap(app, locale, "07_faq_long_top")
                    app.swipeUp()
                    snap(app, locale, "08_faq_long_continuation", settle: 0.4)
                } else {
                    XCTFail("\(locale.code): long FAQ item is missing")
                }
            } else {
                XCTFail("\(locale.code): FAQ entry is missing")
            }
        }
        app.terminate()

        app = launch(locale, recordFixture: true, accessibilityText: true)
        let recap = element("record_detail_section_all", in: app)
        XCTAssertTrue(recap.waitForExistence(timeout: 10), "\(locale.code): record recap fixture did not open")
        if recap.exists {
            snap(app, locale, "09_record_detail_accessibility_xxxl")
        }
        app.terminate()
    }

    private func launch(
        _ locale: AuditLocale,
        recordFixture: Bool = false,
        accessibilityText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += UITestLocale.launchArguments(locale.configuration) + [
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
            "-UITestScreenshotMode", "1",
        ]
        if accessibilityText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        }
        if recordFixture {
            app.launchArguments += [
                "-UITestRecordFixtures",
                "-UITestRecordDetail", "pingpong",
            ]
        } else {
            // Remove only our own fixtures before the next locale's home page.
            app.launchArguments += ["-UITestClearRecordFixtures"]
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12), "\(locale.code): app failed to launch")
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    @discardableResult
    private func tapTab(_ index: Int, in app: XCUIApplication) -> Bool {
        let tab = element("main_tab_\(index)", in: app)
        guard tab.waitForExistence(timeout: 8) else {
            XCTFail("Missing tab identifier main_tab_\(index)")
            return false
        }
        if !tab.isSelected { tab.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        return true
    }

    private func waitForTab(_ index: Int, in app: XCUIApplication) -> Bool {
        element("main_tab_\(index)", in: app).waitForExistence(timeout: 12)
    }

    /// Some SwiftUI controls expose both a container and its child with the
    /// same accessibility identifier on iPad. Always select one stable match
    /// so querying state or tapping does not fail with an ambiguous snapshot.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        if identified.exists || !identifier.hasPrefix("main_tab_") {
            return identified
        }

        // SwiftUI does not expose the custom tab identifier in every RTL
        // script (notably Urdu), even though the semantic TabBar buttons are
        // present in stable order. Keep identifiers as the primary path and
        // use the semantic tab index only as a UI-test fallback.
        guard let index = Int(identifier.dropFirst("main_tab_".count)) else {
            return identified
        }
        return app.tabBars.buttons.element(boundBy: index)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<10 {
            if element.waitForExistence(timeout: 0.6), element.isHittable { return true }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists && element.isHittable
    }

    /// StoreKit product loading can take longer on a freshly booted iPad
    /// simulator. Avoid archiving the transient spinner as the membership UI.
    private func waitForMembershipToSettle(in app: XCUIApplication) {
        let spinner = app.progressIndicators.firstMatch
        guard spinner.waitForExistence(timeout: 1) else { return }
        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: spinner
        )
        _ = XCTWaiter.wait(for: [disappeared], timeout: 12)
    }

    private func snap(_ app: XCUIApplication, _ locale: AuditLocale, _ name: String, settle: TimeInterval = 0.7) {
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        UITestScreenshotStore.capture(
            app,
            name: "\(locale.filePrefix)_\(name)",
            testCase: self,
            settleNanoseconds: 200_000_000
        )
    }

    /// Evidence only: no RTL layout is auto-fixed by this test. The report can
    /// compare mirrored tab order and key-control frames before implementation.
    private func attachRTLMetrics(
        _ app: XCUIApplication,
        locale: AuditLocale,
        stage: String,
        identifiers: [String]
    ) {
        var frames: [String: [String: Double]] = [:]
        for identifier in identifiers {
            let element = element(identifier, in: app)
            guard element.exists else { continue }
            frames[identifier] = [
                "minX": Double(element.frame.minX),
                "midX": Double(element.frame.midX),
                "maxX": Double(element.frame.maxX),
                "minY": Double(element.frame.minY),
                "maxY": Double(element.frame.maxY),
            ]
        }

        let homeMidX = frames["main_tab_0"]?["midX"]
        let meMidX = frames["main_tab_4"]?["midX"]
        var tabOrderMirrored: Any = NSNull()
        if let homeMidX, let meMidX {
            tabOrderMirrored = homeMidX > meMidX
        }
        let payload: [String: Any] = [
            "locale": locale.code,
            "stage": stage,
            "device": UITestScreenshotStore.devicePrefix,
            "appFrame": [
                "width": Double(app.frame.width),
                "height": Double(app.frame.height),
            ],
            "homeTabIsRightOfMeTab": tabOrderMirrored,
            "frames": frames,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "\(UITestScreenshotStore.devicePrefix)_\(locale.filePrefix)_rtl_metrics_\(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
