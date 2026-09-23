import XCTest
@testable import jifen

@MainActor
final class AppAnalyticsTests: XCTestCase {
    private final class RecordingSink: AnalyticsSink {
        private(set) var events: [(name: String, attributes: [String: Any])] = []

        func track(event: String, attributes: [String: Any]) {
            events.append((event, attributes))
        }
    }

    override func tearDown() {
        AppAnalytics.restoreProductionSink()
        super.tearDown()
    }

    func testRegisteredEventAndParameterNamesRespectAnalyticsLimits() {
        for event in AnalyticsEvent.allCases {
            XCTAssertLessThanOrEqual(event.rawValue.count, AnalyticsNormalizer.maxEventIDLength, event.rawValue)
            XCTAssertEqual(AnalyticsNormalizer.eventID(event.rawValue), event.rawValue)
        }
        for parameter in AnalyticsParameter.allCases {
            XCTAssertLessThanOrEqual(parameter.rawValue.count, AnalyticsNormalizer.maxParameterKeyLength, parameter.rawValue)
        }
    }

    func testNormalizerSanitizesIdentifiersAndTruncatesValues() {
        XCTAssertEqual(AnalyticsNormalizer.eventID(" 9 Bad Event! "), "event_9_bad_event")
        let longValue = String(repeating: "a", count: 140)
        let attributes = AnalyticsNormalizer.attributes([
            .contentType: .string(longValue),
            .result: .string("success")
        ])
        XCTAssertEqual((attributes["content_type"] as? String)?.count, 100)
        XCTAssertEqual(attributes["result"] as? String, "success")
    }

    func testNormalizerRejectsFirebaseReservedEventNamesAndPrefixes() {
        let representativeReservedNames = [
            "ad_impression",
            "app_store_subscription_renew",
            "dynamic_link_first_open",
            "error",
            "firebase_in_app_message_impression",
            "in_app_purchase",
            "notification_open",
            "screen_view",
            "session_start_with_rollout"
        ]
        for name in representativeReservedNames {
            XCTAssertNil(AnalyticsNormalizer.eventID(name), name)
        }
        XCTAssertNil(AnalyticsNormalizer.eventID("firebase_custom"))
        XCTAssertNil(AnalyticsNormalizer.eventID("google_custom"))
        XCTAssertNil(AnalyticsNormalizer.eventID("ga_custom"))
    }

    func testToolOutcomeDoesNotReuseLifecycleResult() {
        let attributes = AnalyticsNormalizer.attributes([
            .result: .string(AnalyticsResult.success.rawValue),
            .outcome: .string("heads")
        ])

        XCTAssertEqual(attributes["result"] as? String, "success")
        XCTAssertEqual(attributes["outcome"] as? String, "heads")
    }

    func testAllGameTimerAndToolCatalogEntriesHaveAnalyticsMappings() {
        XCTAssertEqual(AnalyticsScreen.feedbackPage.rawValue, "feedback_page")
        XCTAssertFalse(AnalyticsScreen.allCases.map(\.rawValue).contains("app_shell"))
        let screenNames = AnalyticsScreen.allCases.map(\.rawValue)
        XCTAssertEqual(Set(screenNames).count, screenNames.count)
        XCTAssertTrue(screenNames.allSatisfy { !$0.isEmpty && $0.count <= 100 })
        XCTAssertEqual(
            Set(AnalyticsScreen.allCases.map(\.analyticsScreenClass)),
            Set(["tab", "scoreboard", "timer", "tool", "record_detail", "schedule", "account", "settings", "display"])
        )
        for gameType in GameType.allCases {
            XCTAssertFalse(gameType.analyticsIdentifier.isEmpty)
            XCTAssertFalse(AnalyticsScreen.scoreboard(for: gameType, setup: nil).rawValue.isEmpty)
        }
        for timer in TimerDestination.allCases {
            XCTAssertFalse(AnalyticsScreen.timer(for: timer).rawValue.isEmpty)
        }
        for tool in ToolItem.allTools {
            XCTAssertNotNil(AnalyticsScreen.tool(id: tool.id), "Missing tool analytics mapping: \(tool.id)")
        }

        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .football5v5, setup: nil), .football5v5Scoreboard)
        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .shuttlecock, setup: nil), .shuttlecockScoreboard)
        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .squash, setup: nil), .squashScoreboard)
        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .softTennis, setup: nil), .softTennisScoreboard)
        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .padel, setup: nil), .padelScoreboard)
        XCTAssertEqual(AnalyticsScreen.scoreboard(for: .counter, setup: nil), .counterScoreboard)
    }

    func testMatchLaunchContextEmitsScoreboardOpenOnlyOnce() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink)
        let context = MatchAnalyticsContext(
            gameType: .football,
            setup: nil,
            entryPoint: .homeNewGame
        )

        context.trackLaunch(isResume: false)
        context.trackLaunch(isResume: false)

        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.scoreboardOpen.rawValue }.count, 1)
        XCTAssertEqual(sink.events.first?.attributes["session_state"] as? String, "new")
        XCTAssertEqual(sink.events.first?.attributes["entry_point"] as? String, "home_new_game")
    }

    func testTypedParametersNeverExposeUndeclaredKeys() {
        let parameters = AnalyticsParameters(
            Dictionary(uniqueKeysWithValues: AnalyticsParameter.allCases.map { ($0, AnalyticsValue.string("value")) })
        )
        let attributes = AnalyticsNormalizer.attributes(parameters)
        XCTAssertLessThanOrEqual(attributes.count, AnalyticsNormalizer.maxParameterCount)
        XCTAssertTrue(Set(attributes.keys).isSubset(of: Set(AnalyticsParameter.allCases.map(\.rawValue))))
    }

    func testAnalyticsContractHasNoSensitiveFreeTextParameters() {
        let forbidden = [
            "name", "account", "phone", "email", "body", "note", "location",
            "record_id", "cast_code", "error_message", "notification_payload"
        ]
        let keys = Set(AnalyticsParameter.allCases.map(\.rawValue))
        for key in forbidden {
            XCTAssertFalse(keys.contains(key), "Sensitive analytics parameter must stay excluded: \(key)")
        }
    }

    func testCollectionGateBlocksBeforeConsentAndAllowsAfterConsent() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink, collectionAllowed: false)
        AppAnalytics.trackContentSelection(contentType: "scoreboard", itemID: "football")
        XCTAssertTrue(sink.events.isEmpty)

        AppAnalytics.installSinkForTesting(sink, collectionAllowed: true)
        AppAnalytics.trackContentSelection(contentType: "scoreboard", itemID: "football")
        XCTAssertEqual(sink.events.map(\.name), [AnalyticsEvent.selectContent.rawValue])
    }

    func testShareCompletionMapsSuccessCancellationAndFailureOnce() {
        let cases: [(Bool, Error?, String?)] = [
            (true, nil, AnalyticsEvent.share.rawValue),
            (false, nil, nil),
            (false, NSError(domain: "test", code: 1), AnalyticsEvent.shareFailed.rawValue)
        ]

        for (completed, error, expectedEvent) in cases {
            let sink = RecordingSink()
            AppAnalytics.installSinkForTesting(sink)
            let coordinator = AnalyticsActivityView.Coordinator(contentType: "score_record")
            coordinator.complete(completed: completed, error: error)
            coordinator.complete(completed: completed, error: error)
            XCTAssertEqual(sink.events.map(\.name), expectedEvent.map { [$0] } ?? [])
            XCTAssertFalse(sink.events.flatMap { $0.attributes.values }.contains { ($0 as? String) == "test" })
        }
    }

    func testFinishedRecordTransitionEmitsFinishAndSaveOnlyOnce() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var draft = ScoreboardRecord(
            id: "local-test-id",
            gameType: .football,
            startTime: startedAt,
            team1Name: "not uploaded",
            team2Name: "not uploaded",
            team1FinalScore: 1,
            team2FinalScore: 0,
            winner: "team_0",
            totalScoreChanges: 1,
            status: .draft
        )
        var finished = draft
        finished.status = .finished
        finished.endTime = startedAt.addingTimeInterval(90)
        finished.duration = 90

        AppAnalytics.scoreboardRecordSaved(finished, previous: draft)
        draft = finished
        AppAnalytics.scoreboardRecordSaved(finished, previous: draft)

        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.matchFinish.rawValue }.count, 1)
        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.recordSave.rawValue }.count, 1)
        let finish = sink.events.first { $0.name == AnalyticsEvent.matchFinish.rawValue }
        XCTAssertEqual(finish?.attributes["duration_ms"] as? Int, 90_000)
        XCTAssertEqual(finish?.attributes["winner"] as? String, "side_a")
        XCTAssertNil(finish?.attributes["id"])
        XCTAssertFalse(finish?.attributes.values.contains { ($0 as? String) == "local-test-id" } ?? true)
    }

    func testTypedLoginShareAndPurchaseHelpersUseOnlyContractFields() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink)

        AppAnalytics.trackLoginSuccess(method: "apple")
        AppAnalytics.trackAuthResult(method: "password", result: .failed, errorCategory: "invalid_credential")
        AppAnalytics.trackSuccessfulShare(contentType: "score_record", method: "system_share_sheet")
        AppAnalytics.trackPurchaseFlow(.started, flow: "purchase", itemID: "product_id")

        XCTAssertEqual(
            sink.events.map(\.name),
            ["login", "auth_result", "share", "purchase_flow"]
        )
        XCTAssertEqual(sink.events[0].attributes["method"] as? String, "apple")
        XCTAssertEqual(sink.events[1].attributes["error_category"] as? String, "invalid_credential")
        XCTAssertEqual(sink.events[2].attributes["content_type"] as? String, "score_record")
        XCTAssertEqual(sink.events[3].attributes["flow"] as? String, "purchase")
        XCTAssertNil(sink.events[3].attributes["price"])
        XCTAssertNil(sink.events[3].attributes["currency"])
    }

    func testManualEndReasonIsConsumedByNextFinishedRecord() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink)
        let draft = ScoreboardRecord(
            id: "manual-test-id",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 2_000),
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 1,
            team2FinalScore: 0,
            totalScoreChanges: 1,
            status: .draft
        )
        var finished = draft
        finished.status = .finished
        AppAnalytics.markNextMatchEndReason(.manualFinish, gameType: .tennis)
        AppAnalytics.scoreboardRecordSaved(finished, previous: draft)

        let finish = sink.events.first { $0.name == AnalyticsEvent.matchFinish.rawValue }
        XCTAssertEqual(finish?.attributes["end_reason"] as? String, "manual_finish")
    }
}
