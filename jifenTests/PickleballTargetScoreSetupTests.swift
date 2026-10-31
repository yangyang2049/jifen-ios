import ScoreCore
import XCTest
@testable import jifen

/// 任务一：匹克球目标分放开 1–99（安卓 3.4 `normalizeTargetScore` / 鸿蒙同语义）。
@MainActor
final class PickleballTargetScoreSetupTests: XCTestCase {
    private func makeDraft(
        targetScore: Int,
        scoreCap: Int? = nil,
        maxSets: Int = 3
    ) -> SportsSetupDraft {
        var draft = SportsSetupDraft()
        draft.selectedMaxSets = maxSets
        draft.pickleballTargetScore = targetScore
        draft.pickleballScoreCap = scoreCap
        return draft
    }

    func testCustomTargetRestoresFromSetupAndReachesResult() throws {
        let setup = SportsSetupResult(team1Name: "A", team2Name: "B", targetScore: 13)
        var draft = SportsSetupDraft()
        let suite = "pickleball-target-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        draft.initialize(
            gameType: .pickleball,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil,
            preferences: PreferencesManager(defaults: defaults)
        )
        XCTAssertEqual(draft.pickleballTargetScore, 13)
        XCTAssertEqual(draft.customPickleballTargetText, "13")

        let result = draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true)
        XCTAssertEqual(result.targetScore, 13)
        XCTAssertNil(result.scoreCap)
        XCTAssertEqual(result.pickleballRules.pointsToWinSet, 13)
        XCTAssertEqual(result.pickleballRules.sportProfile, .pickleball)
    }

    func testPresetTargetsKeepEmptyCustomTextAndScoreCapSemantics() {
        var draft = makeDraft(targetScore: 11, scoreCap: 13)
        XCTAssertEqual(draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true).scoreCap, 13)

        draft = makeDraft(targetScore: 21, scoreCap: 13)
        let twentyOne = draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true)
        XCTAssertEqual(twentyOne.targetScore, 21)
        XCTAssertNil(twentyOne.scoreCap)
        XCTAssertNil(twentyOne.pickleballRules.pointCap)

        draft = makeDraft(targetScore: 9, scoreCap: 13)
        let nine = draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true)
        XCTAssertEqual(nine.targetScore, 9)
        XCTAssertNil(nine.scoreCap)
        XCTAssertEqual(nine.pickleballRules.pointsToWinSet, 9)
    }

    func testOutOfRangeTargetIsClampedIntoOneToNinetyNine() {
        var draft = makeDraft(targetScore: 150)
        XCTAssertEqual(draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true).targetScore, 99)

        draft = makeDraft(targetScore: 0)
        XCTAssertEqual(draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true).targetScore, 1)

        draft = makeDraft(targetScore: -4)
        XCTAssertEqual(draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true).targetScore, 1)
    }

    func testCustomTargetSurvivesRecordRestart() throws {
        let record = ScoreboardRecord(
            id: UUID().uuidString,
            gameType: .pickleball,
            startTime: Date(),
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 12,
            team2FinalScore: 7,
            totalScoreChanges: 19,
            projectConfiguration: [
                "targetScore": AnyCodable(12),
                "maxSets": AnyCodable(3),
                "winByTwo": AnyCodable(true)
            ]
        )
        let restored = try JSONDecoder().decode(ScoreboardRecord.self, from: JSONEncoder().encode(record))
        let setup = ScoreboardRecordConfiguration.setup(from: restored)
        XCTAssertEqual(setup.targetScore, 12)
        XCTAssertEqual(setup.pickleballRules.pointsToWinSet, 12)

        var draft = SportsSetupDraft()
        draft.pickleballTargetScore = setup.targetScore ?? 11
        draft.customPickleballTargetText = setup.targetScore == 11 ? "" : "\(setup.targetScore ?? 11)"
        XCTAssertEqual(
            draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true).pickleballRules.pointsToWinSet,
            12
        )
    }

    func testLegacySetupWithoutTargetStillUsesEleven() {
        let setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        XCTAssertEqual(setup.pickleballRules.pointsToWinSet, 11)
        XCTAssertEqual(setup.pickleballRules.maxSets, 3)
    }

    func testPresetSetSelectionKeepsAndroidDefaultTargetBehaviour() {
        var draft = makeDraft(targetScore: 13, maxSets: 3)
        draft.selectMatchCompletionPreset(1, gameType: .pickleball)
        XCTAssertEqual(draft.pickleballTargetScore, 15)
        XCTAssertEqual(draft.customPickleballTargetText, "")
        draft.selectMatchCompletionPreset(3, gameType: .pickleball)
        XCTAssertEqual(draft.pickleballTargetScore, 11)
    }
}