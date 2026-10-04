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
        AuditLocale(code: "ca", configuration: UITestLocale.ca, isRTL: false),
        AuditLocale(code: "pl", configuration: UITestLocale.pl, isRTL: false),
        AuditLocale(code: "ro", configuration: UITestLocale.ro, isRTL: false),
        AuditLocale(code: "cs", configuration: UITestLocale.cs, isRTL: false),
        AuditLocale(code: "sk", configuration: UITestLocale.sk, isRTL: false),
        AuditLocale(code: "sl", configuration: UITestLocale.sl, isRTL: false),
        AuditLocale(code: "hr", configuration: UITestLocale.hr, isRTL: false),
        AuditLocale(code: "da", configuration: UITestLocale.da, isRTL: false),
        AuditLocale(code: "nb", configuration: UITestLocale.nb, isRTL: false),
        AuditLocale(code: "fi", configuration: UITestLocale.fi, isRTL: false),
        AuditLocale(code: "hu", configuration: UITestLocale.hu, isRTL: false),
        AuditLocale(code: "el", configuration: UITestLocale.el, isRTL: false),
        AuditLocale(code: "hi", configuration: UITestLocale.hi, isRTL: false),
        AuditLocale(code: "bn", configuration: UITestLocale.bn, isRTL: false),
        AuditLocale(code: "mr", configuration: UITestLocale.mr, isRTL: false),
        AuditLocale(code: "gu", configuration: UITestLocale.gu, isRTL: false),
        AuditLocale(code: "pa", configuration: UITestLocale.pa, isRTL: false),
        AuditLocale(code: "ta", configuration: UITestLocale.ta, isRTL: false),
        AuditLocale(code: "te", configuration: UITestLocale.te, isRTL: false),
        AuditLocale(code: "kn", configuration: UITestLocale.kn, isRTL: false),
        AuditLocale(code: "ml", configuration: UITestLocale.ml, isRTL: false),
        AuditLocale(code: "or", configuration: UITestLocale.or, isRTL: false),
        AuditLocale(code: "tr", configuration: UITestLocale.tr, isRTL: false),
        AuditLocale(code: "vi", configuration: UITestLocale.vi, isRTL: false),
        AuditLocale(code: "th", configuration: UITestLocale.th, isRTL: false),
        AuditLocale(code: "id", configuration: UITestLocale.id, isRTL: false),
        AuditLocale(code: "ms", configuration: UITestLocale.ms, isRTL: false),
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
    func testCaptureCa() { captureLocale("ca") }
    func testCapturePl() { captureLocale("pl") }
    func testCaptureRo() { captureLocale("ro") }
    func testCaptureCs() { captureLocale("cs") }
    func testCaptureSk() { captureLocale("sk") }
    func testCaptureSl() { captureLocale("sl") }
    func testCaptureHr() { captureLocale("hr") }
    func testCaptureDa() { captureLocale("da") }
    func testCaptureNb() { captureLocale("nb") }
    func testCaptureFi() { captureLocale("fi") }
    func testCaptureHu() { captureLocale("hu") }
    func testCaptureEl() { captureLocale("el") }
    func testCaptureHi() { captureLocale("hi") }
    func testCaptureBn() { captureLocale("bn") }
    func testCaptureMr() { captureLocale("mr") }
    func testCaptureGu() { captureLocale("gu") }
    func testCapturePa() { captureLocale("pa") }
    func testCaptureTa() { captureLocale("ta") }
    func testCaptureTe() { captureLocale("te") }
    func testCaptureKn() { captureLocale("kn") }
    func testCaptureMl() { captureLocale("ml") }
    func testCaptureOr() { captureLocale("or") }
    func testCaptureTr() { captureLocale("tr") }
    func testCaptureVi() { captureLocale("vi") }
    func testCaptureTh() { captureLocale("th") }
    func testCaptureId() { captureLocale("id") }
    func testCaptureMs() { captureLocale("ms") }

    func testSportsVoiceLanguageEntryAndMissingGuide() {
        let samples = (priorityLocales + rtlLocales).filter { ["fr-CA", "es-MX", "pt-BR", "ar", "ur", "gu"].contains($0.code) }
        for locale in samples {
            let app = launch(locale, voiceMissing: true)
            XCTAssertTrue(tapTab(2, in: app))
            let pingPong = element("scoreboard_catalog_pingpong", in: app)
            XCTAssertTrue(scrollUntilHittable(pingPong, in: app))
            pingPong.tap()
            let sides = element("setup_feature_auto_change_sides", in: app)
            XCTAssertTrue(scrollUntilHittable(sides, in: app))
            let voice = element("setup_feature_voice_announcement", in: app)
            let supported = supportsSportsVoice(locale)
            XCTAssertEqual(voice.exists, supported, locale.code)
            XCTAssertTrue(sides.isHittable)
            snap(app, locale, "voice_support_entry")
            if supported {
                XCTAssertTrue(voice.isHittable)
                voice.tap()
                let alert = app.alerts.firstMatch
                XCTAssertTrue(alert.waitForExistence(timeout: 4), "missing voice must explain download")
                snap(app, locale, "voice_missing_download")
                if alert.exists { alert.buttons.firstMatch.tap() }
                XCTAssertEqual(voice.value as? String, "0", "missing voice must leave toggle off")
            }
            app.terminate()
        }
    }

    private func supportsSportsVoice(_ locale: AuditLocale) -> Bool {
        locale.code != "ur" && (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 || !["gu", "ml", "or", "pa"].contains(locale.code))
    }

    func testSportsVoiceUnsupportedSingleCardLayout() {
        for locale in (priorityLocales + rtlLocales).filter({ ["ur", "gu"].contains($0.code) && !supportsSportsVoice($0) }) {
            let app = launch(locale)
            XCTAssertTrue(tapTab(2, in: app))
            let badminton = element("scoreboard_catalog_badminton", in: app)
            XCTAssertTrue(scrollUntilHittable(badminton, in: app))
            badminton.tap()
            let sides = element("setup_feature_auto_change_sides", in: app)
            XCTAssertTrue(scrollUntilHittable(sides, in: app))
            XCTAssertFalse(element("setup_feature_voice_announcement", in: app).exists)
            XCTAssertTrue(sides.isHittable)
            snap(app, locale, "voice_unsupported_single_switch")
            app.terminate()
        }
    }

    func testCaptureCompactControls() {
        for locale in priorityLocales + rtlLocales.filter({ $0.code == "ar" }) {
            captureCompactControls(locale)
        }
    }

    /// Focused regression for two-line setup cards and localized record units.
    /// Run on a narrow iPhone and iPad; attachments preserve rendered evidence.
    func testCaptureSetupAndRecordLocalizationFixes() {
        let locales = priorityLocales.filter { ["de", "it", "nl", "uk"].contains($0.code) }
            + [AuditLocale(code: "zh-Hans", configuration: UITestLocale.zhHans, isRTL: false)]
        for locale in locales {
            if ["de", "it", "nl"].contains(locale.code) {
                let app = launch(locale)
                if tapTab(2, in: app) {
                    let pingPong = element("scoreboard_catalog_pingpong", in: app)
                    XCTAssertTrue(scrollUntilHittable(pingPong, in: app))
                    pingPong.tap()
                    app.swipeUp()
                    let changeSides = element("setup_feature_auto_change_sides", in: app)
                    XCTAssertTrue(scrollUntilHittable(changeSides, in: app))
                    for key in ["auto_change_sides", "show_match_time", "voice_announcement"] {
                        XCTAssertTrue(element("setup_feature_\(key)", in: app).isHittable)
                    }
                    snap(app, locale, "fix_setup_two_line_labels")
                }
                app.terminate()
            }

            let app = launch(locale, recordFixture: true)
            XCTAssertTrue(element("record_detail_section_all", in: app).waitForExistence(timeout: 10))
            snap(app, locale, "fix_record_units_and_sets")
            app.terminate()
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
            guard selectMonthlyPlan(in: app) else { continue }
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
                let changeSides = element("setup_feature_auto_change_sides", in: app)
                XCTAssertTrue(scrollUntilHittable(changeSides, in: app))
                for key in ["auto_change_sides", "show_match_time"] + (supportsSportsVoice(locale) ? ["voice_announcement"] : []) {
                    XCTAssertTrue(element("setup_feature_\(key)", in: app).isHittable)
                }
                snap(app, locale, "03b_setup_features")
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
                if selectMonthlyPlan(in: app) {
                    snap(app, locale, "06_membership_subscription")
                }
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
        accessibilityText: Bool = false,
        voiceMissing: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += UITestLocale.launchArguments(locale.configuration) + [
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
            "-UITestScreenshotMode", "1",
        ]
        if voiceMissing { app.launchArguments += ["-UITestSportsVoiceMissing"] }
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

    private func selectMonthlyPlan(in app: XCUIApplication) -> Bool {
        let monthly = element("membership_plan_iscoreboard_monthly_vip", in: app)
        // A partially visible card can be hittable while its center is behind
        // the fixed purchase footer. Move the whole card into the content area.
        let contentBottom = app.frame.minY + app.frame.height * 0.65
        for _ in 0..<8 {
            if monthly.exists, monthly.isHittable, monthly.frame.maxY < contentBottom { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        guard monthly.exists, monthly.isHittable, monthly.frame.maxY < contentBottom else {
            XCTFail("Monthly plan is not fully visible above the purchase footer")
            return false
        }
        monthly.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in monthly.isSelected }, object: monthly
        )
        let didSelect = XCTWaiter.wait(for: [selected], timeout: 5) == .completed
        XCTAssertTrue(didSelect, "Monthly plan must be selected before capturing subscription agreements")
        return didSelect
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
