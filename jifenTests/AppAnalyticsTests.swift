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

    func testRegisteredEventAndParameterNamesRespectUmengLimits() {
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

    func testToolOutcomeDoesNotReuseLifecycleResult() {
        let attributes = AnalyticsNormalizer.attributes([
            .result: .string(AnalyticsResult.success.rawValue),
            .outcome: .string("heads")
        ])

        XCTAssertEqual(attributes["result"] as? String, "success")
        XCTAssertEqual(attributes["outcome"] as? String, "heads")
    }

    func testAllGameTimerAndToolCatalogEntriesHaveAnalyticsMappings() {
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
    }

    func testMatchLaunchContextDeduplicatesSwiftUIReappear() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink)
        let context = MatchAnalyticsContext(
            gameType: .football,
            setup: nil,
            entryPoint: .homeNewGame
        )

        context.trackLaunch(isResume: false)
        context.trackLaunch(isResume: false)

        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.screenView.rawValue }.count, 1)
        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.startGame.rawValue }.count, 1)
    }

    func testTypedParametersNeverExposeUndeclaredKeys() {
        let parameters = AnalyticsParameters(
            Dictionary(uniqueKeysWithValues: AnalyticsParameter.allCases.map { ($0, AnalyticsValue.string("value")) })
        )
        let attributes = AnalyticsNormalizer.attributes(parameters)
        XCTAssertLessThanOrEqual(attributes.count, AnalyticsNormalizer.maxParameterCount)
        XCTAssertTrue(Set(attributes.keys).isSubset(of: Set(AnalyticsParameter.allCases.map(\.rawValue))))
    }

    func testCollectionGateBlocksBeforeConsentAndAllowsAfterConsent() {
        let sink = RecordingSink()
        AppAnalytics.installSinkForTesting(sink, collectionAllowed: false)
        AppAnalytics.track(.scoreItemSelect, parameters: [.gameType: .string("football")])
        XCTAssertTrue(sink.events.isEmpty)

        AppAnalytics.installSinkForTesting(sink, collectionAllowed: true)
        AppAnalytics.track(.scoreItemSelect, parameters: [.gameType: .string("football")])
        XCTAssertEqual(sink.events.map(\.name), [AnalyticsEvent.scoreItemSelect.rawValue])
    }

    func testShareCompletionMapsSuccessCancellationAndFailureOnce() {
        let cases: [(Bool, Error?, String)] = [
            (true, nil, "success"),
            (false, nil, "cancelled"),
            (false, NSError(domain: "test", code: 1), "failed")
        ]

        for (completed, error, expected) in cases {
            let sink = RecordingSink()
            AppAnalytics.installSinkForTesting(sink)
            let coordinator = AnalyticsActivityView.Coordinator(contentType: "score_record")
            coordinator.complete(completed: completed, error: error)
            coordinator.complete(completed: completed, error: error)
            XCTAssertEqual(sink.events.count, 1)
            XCTAssertEqual(sink.events.first?.attributes["result"] as? String, expected)
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
        XCTAssertEqual(sink.events.filter { $0.name == AnalyticsEvent.saveRecord.rawValue }.count, 1)
        let finish = sink.events.first { $0.name == AnalyticsEvent.matchFinish.rawValue }
        XCTAssertEqual(finish?.attributes["duration_ms"] as? Int, 90_000)
        XCTAssertEqual(finish?.attributes["winner"] as? String, "side_a")
        XCTAssertNil(finish?.attributes["id"])
        XCTAssertFalse(finish?.attributes.values.contains { ($0 as? String) == "local-test-id" } ?? true)
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
