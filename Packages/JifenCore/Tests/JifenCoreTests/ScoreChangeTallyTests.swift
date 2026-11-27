import Foundation
import RecordCore
import ScoreCore
import Testing

/// Shared totalScoreChanges semantics: linked phone/Watch records and the
/// independent Watch scoreboard must count the same events.
struct ScoreChangeTallyTests {
    private func action(
        _ type: DetailedScoreActionType,
        code: String? = nil,
        scoreChange: Int? = nil
    ) -> DetailedScoreAction {
        DetailedScoreAction(
            type: type, epochMilliseconds: 1_700_000_000_000, scores: [0, 0],
            scoreChange: scoreChange, operationCode: code
        )
    }

    @Test func zeroPointArcheryArrowsStillCountAsScoringAttempts() {
        let arrow = action(.scoreChanged, code: "archery_arrow", scoreChange: 0)
        let miss = action(.scoreChanged, code: "archery_miss", scoreChange: 0)
        let realArrow = action(.scoreChanged, code: "archery_arrow", scoreChange: 9)

        #expect([arrow].scoreChangeCount == 1)
        #expect([miss].scoreChangeCount == 1)
        #expect([realArrow].scoreChangeCount == 1)
    }

    @Test func nonScoringActionsNeverCount() {
        let actions = [
            action(.matchStarted, code: "game_start", scoreChange: 0),
            action(.stateChanged, code: "edit_name"),
            action(.stateChanged, code: "archery_set_ready", scoreChange: 0),
            action(.stateChanged, code: "archery_closest_to_center", scoreChange: 0),
            action(.stateChanged, code: "basketball_period_changed", scoreChange: 0),
            action(.sideChanged, code: "exchange_sides", scoreChange: 0),
            action(.serveChanged, code: "pingpong_serve", scoreChange: 0),
            action(.timeout, code: "basketball_timeout", scoreChange: 0),
            action(.reset, code: "reset", scoreChange: 0),
            action(.matchFinished, code: "game_end", scoreChange: 0),
            action(.undo, code: "undo", scoreChange: 0)
        ]
        #expect(actions.scoreChangeCount == 0)
    }

    @Test func basketballFoulsAreNotScoreChanges() {
        let foul = action(.foul, code: "basketball_foul", scoreChange: 0)
        let adjustedFoul = action(.foul, code: "basketball_foul_adjust", scoreChange: 2)
        let basketballAdjust = action(.stateChanged, code: "basketball_adjust_score", scoreChange: 2)
        let footballFoul = action(.foul, code: "football_foul", scoreChange: 1)

        #expect([foul].scoreChangeCount == 0)
        #expect([adjustedFoul].scoreChangeCount == 0)
        #expect([basketballAdjust].scoreChangeCount == 0)
        #expect([footballFoul].scoreChangeCount == 1)
    }

    @Test func administrativeAdjustmentsCountAndUnknownStateChangesDoNot() {
        let adjustments = [
            action(.stateChanged, code: "adjust_points", scoreChange: 1),
            action(.stateChanged, code: "adjust_sets", scoreChange: -1),
            action(.stateChanged, code: "edit_score", scoreChange: 3),
            action(.stateChanged, code: "archery_adjust_arrow_sum", scoreChange: 2),
            action(.stateChanged, code: "archery_adjust_set_points", scoreChange: 1),
            action(.stateChanged, code: "eight_ball_admin_adjust", scoreChange: 1),
            action(.stateChanged, code: "nine_ball_adjust_total", scoreChange: 1),
            action(.stateChanged, code: "snooker_admin_correct", scoreChange: 1)
        ]
        #expect(adjustments.scoreChangeCount == 8)
        #expect([action(.stateChanged, code: "something_else", scoreChange: 5)].scoreChangeCount == 0)
        #expect([action(.stateChanged, code: nil, scoreChange: 5)].scoreChangeCount == 0)
    }

    @Test func archeryReducerEventsProduceTheSameTally() {
        // Real projector output, not hand-built actions: a zero-point arrow and
        // a miss are scoring attempts, set readiness is not.
        let state = ArcheryMatchState(leftName: "红方", rightName: "蓝方")
        let events: [ArcheryMatchEvent] = [
            .arrowScored(side: .left, points: 0, leftArrowSum: 0, rightArrowSum: 0),
            .arrowMissed(side: .right, leftArrowSum: 0, rightArrowSum: 0),
            .setReady(setNumber: 1, leftArrowSum: 0, rightArrowSum: 0, pendingLeftSetPoints: 0, pendingRightSetPoints: 0),
            .arrowScored(side: .left, points: 9, leftArrowSum: 9, rightArrowSum: 0)
        ]
        let actions = ScoreActionProjector.archery(
            events: events, state: state, timestamp: Date(timeIntervalSince1970: 1)
        )
        #expect(actions.map(\.operationCode) == [
            "archery_arrow", "archery_miss", "archery_set_ready", "archery_arrow"
        ])
        #expect(actions.scoreChangeCount == 3)
    }

    @Test func aFullRecordTallyMatchesTheIndependentWatchCount() {
        // A Watch eight-ball match: start, two racks, an administrative
        // correction, then the finish marker. The independent scoreboard and a
        // linked record must both report three score changes.
        let actions = [
            action(.matchStarted, code: "game_start", scoreChange: 0),
            action(.scoreChanged, code: "eight_ball_rack", scoreChange: 1),
            action(.scoreChanged, code: "eight_ball_rack", scoreChange: 1),
            action(.stateChanged, code: "edit_name"),
            action(.stateChanged, code: "eight_ball_admin_adjust", scoreChange: 1),
            action(.matchFinished, code: "game_end", scoreChange: 0)
        ]
        #expect(actions.scoreChangeCount == 3)
    }
}
