import Foundation
import ScoreCore
import Testing

@Suite struct ShotTrainingReducerTests {
    private let reducer = ShotTrainingReducer()
    private let startTime = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func fixedModesRecordMadeAndMissedAttemptsAtTheConfiguredValue() {
        let fixedModes: [ShotTrainingMode] = [.fixed1, .fixed2, .fixed3]
        for (index, mode) in fixedModes.enumerated() {
            let points = index + 1
            let initial = ShotTrainingState(mode: mode, startTime: startTime)
            let made = reducer.reduce(state: initial, intent: .recordShot(points: points, made: true), at: 1_700_000_001_230)
            let missed = reducer.reduce(state: made.state, intent: .recordShot(points: points, made: false), at: 1_700_000_002_000)
            let counts = missed.state.counts

            #expect(made.accepted && missed.accepted)
            #expect(made.events == [.shotRecorded(points: points, made: true, counts: made.state.counts)])
            #expect(missed.events == [.shotRecorded(points: points, made: false, counts: counts)])
            #expect(counts.count(points: points, made: true) == 1)
            #expect(counts.count(points: points, made: false) == 1)
            #expect(counts.attempts == 2)
            #expect(counts.points == points)
            #expect(counts.rate == 50)
            #expect(missed.state.startTime == startTime)

            let otherPoints = points == 3 ? 1 : points + 1
            let mismatch = reducer.reduce(state: missed.state, intent: .recordShot(points: otherPoints, made: true), at: 1_700_000_003_000)
            #expect(!mismatch.accepted)
            #expect(mismatch.state == missed.state)
            #expect(mismatch.events.isEmpty)
        }
    }

    @Test func freeModePreservesPointBucketsAndUndoesTheLastAttempt() {
        let initial = ShotTrainingState(mode: .free, startTime: startTime)
        let first = reducer.reduce(state: initial, intent: .recordShot(points: 1, made: true), at: 1_700_000_001_000)
        let second = reducer.reduce(state: first.state, intent: .recordShot(points: 2, made: false), at: 1_700_000_002_000)
        let third = reducer.reduce(state: second.state, intent: .recordShot(points: 3, made: true), at: 1_700_000_003_000)
        #expect(third.state.counts == ShotTrainingCounts(oneMade: 1, twoMiss: 1, threeMade: 1))
        #expect(third.state.counts.points == 4)

        let undo = reducer.reduce(state: third.state, intent: .undoLastShot, at: 1_700_000_004_000)
        #expect(undo.accepted)
        #expect(undo.state == second.state)
        #expect(undo.events == [.shotUndone(counts: second.state.counts)])
        #expect(!reducer.reduce(state: initial, intent: .undoLastShot, at: 1_700_000_004_000).accepted)

        for points in [0, 4] {
            let invalid = reducer.reduce(state: initial, intent: .recordShot(points: points, made: true), at: 1_700_000_004_000)
            #expect(!invalid.accepted)
            #expect(invalid.state == initial)
        }
    }

    @Test func replaysUseTheInjectedTimestampAndRetainItInTheSharedEncoding() throws {
        let initial = ShotTrainingState(mode: .free, startTime: startTime)
        let timestamp: Int64 = 1_700_000_012_345
        let intent = ShotTrainingIntent.recordShot(points: 2, made: true)
        let firstRun = reducer.reduce(state: initial, intent: intent, at: timestamp)
        let secondRun = reducer.reduce(state: initial, intent: intent, at: timestamp)
        let differentTime = reducer.reduce(state: initial, intent: intent, at: timestamp + 1)

        #expect(firstRun.accepted)
        #expect(firstRun.state == secondRun.state)
        #expect(firstRun.events == secondRun.events)
        #expect(firstRun.state != differentTime.state)
        let shot = try #require(firstRun.state.shots.first)
        #expect(Int64((shot.timestamp.timeIntervalSince1970 * 1_000).rounded()) == timestamp)
        let encoded = try JSONEncoder().encode(firstRun.state)
        #expect(try JSONDecoder().decode(ShotTrainingState.self, from: encoded) == firstRun.state)

        for extreme in [Int64.min, Int64.max, Int64.max / 8] {
            let result = reducer.reduce(state: initial, intent: intent, at: extreme)
            #expect(!result.accepted)
            #expect(result.state == initial)
        }
    }

    @Test func overflowFoldsOldestShotsWithoutRestoringThemOnUndo() {
        let oldest = ShotTrainingShot(points: 3, made: true, timestamp: startTime)
        let retained = ShotTrainingShot(points: 1, made: false, timestamp: startTime.addingTimeInterval(1))
        let detailLimit = ShotTrainingState.maxDetailedShots
        let initial = ShotTrainingState(
            mode: .free, startTime: startTime, shots: [oldest] + Array(repeating: retained, count: detailLimit - 1),
            earlierCounts: ShotTrainingCounts(twoMade: 2)
        )
        #expect(detailLimit == 2_048)
        #expect(initial.shots.first == oldest)
        let append = reducer.reduce(state: initial, intent: .recordShot(points: 2, made: false), at: 1_700_000_002_000)
        let capped = append.state
        #expect(capped.shots.count == detailLimit)
        #expect(capped.shots.first == retained)
        #expect(capped.shots.last?.points == 2)
        #expect(capped.earlierCounts == ShotTrainingCounts(twoMade: 2, threeMade: 1))
        #expect(capped.counts == ShotTrainingCounts(oneMiss: detailLimit - 1, twoMade: 2, twoMiss: 1, threeMade: 1))

        let undone = reducer.reduce(state: capped, intent: .undoLastShot, at: 1_700_000_003_000).state
        #expect(undone.shots.count == detailLimit - 1)
        #expect(undone.earlierCounts == capped.earlierCounts)
        #expect(undone.counts == initial.counts)
        #expect(!undone.shots.contains(oldest))

        let lastRetained = ShotTrainingState(mode: .free, startTime: startTime, shots: [retained], earlierCounts: capped.earlierCounts)
        let prefixOnly = reducer.reduce(state: lastRetained, intent: .undoLastShot, at: 1_700_000_004_000).state
        #expect(prefixOnly.shots.isEmpty)
        #expect(prefixOnly.counts == capped.earlierCounts)
        let noUndo = reducer.reduce(state: prefixOnly, intent: .undoLastShot, at: 1_700_000_005_000)
        #expect(!noUndo.accepted)
        #expect(noUndo.state == prefixOnly)
    }

    @Test func standaloneKeepsShotIDsAndCanUndoASpecificBucketBeyondTheLinkedLimit() {
        let oldShot = ShotTrainingShot(id: UUID(), points: 3, made: true, timestamp: startTime)
        let otherShot = ShotTrainingShot(id: UUID(), points: 1, made: false, timestamp: startTime)
        let detailLimit = ShotTrainingState.maxDetailedShots
        let initial = ShotTrainingSession(
            mode: .free, startTime: startTime,
            shots: [oldShot] + Array(repeating: otherShot, count: detailLimit - 1),
            earlierCounts: .init(twoMade: 2)
        )
        let newShotID = UUID()
        let recorded = reducer.reduce(
            state: initial, intent: .recordShot(points: 2, made: false),
            at: 1_700_000_001_000, shotID: newShotID
        )
        #expect(recorded.state.shots.count == detailLimit + 1)
        #expect(recorded.state.shots.first?.id == oldShot.id)
        #expect(recorded.state.shots.last?.id == newShotID)

        let undone = reducer.reduce(
            state: recorded.state, intent: .undoLastShot, at: 1_700_000_002_000,
            undoMade: true, undoPoints: 3
        )
        #expect(undone.accepted)
        #expect(undone.state.shots.count == detailLimit)
        #expect(undone.state.shots.last?.id == newShotID)
        #expect(undone.state.counts == .init(oneMiss: detailLimit - 1, twoMade: 2, twoMiss: 1))
    }

    @Test func finishPreservesCountsAndResetStartsACleanRunInTheSameMode() {
        let initial = ShotTrainingState(mode: .fixed2, startTime: startTime, earlierCounts: ShotTrainingCounts(twoMiss: 1))
        let recorded = reducer.reduce(state: initial, intent: .recordShot(points: 2, made: true), at: 1_700_000_001_000).state
        let finish = reducer.reduce(state: recorded, intent: .finish, at: 1_700_000_002_000)

        #expect(finish.accepted && finish.state.finished)
        #expect(finish.state.startTime == startTime)
        #expect(finish.state.shots == recorded.shots)
        #expect(finish.state.earlierCounts == recorded.earlierCounts)
        #expect(finish.events == [.finished(counts: ShotTrainingCounts(twoMade: 1, twoMiss: 1))])
        for intent: ShotTrainingIntent in [.recordShot(points: 2, made: true), .undoLastShot, .finish] {
            let rejected = reducer.reduce(state: finish.state, intent: intent, at: 1_700_000_003_000)
            #expect(!rejected.accepted)
            #expect(rejected.state == finish.state)
        }

        let reset = reducer.reduce(state: finish.state, intent: .reset, at: 1_700_000_004_000)
        #expect(reset.accepted && !reset.state.finished)
        #expect(reset.events == [.reset])
        #expect(reset.state.mode == .fixed2)
        #expect(reset.state.startTime == startTime.addingTimeInterval(4))
        #expect(reset.state.shots.isEmpty)
        #expect(reset.state.earlierCounts == ShotTrainingCounts())
        #expect(reset.state.counts.attempts == 0)
    }

    @Test func watchMayFinishAnEmptyTraining() {
        let initial = ShotTrainingState(mode: .free, startTime: startTime)
        let finish = reducer.reduce(state: initial, intent: .finish, at: 1_700_000_003_000)
        #expect(finish.accepted && finish.state.finished)
        #expect(finish.events == [.finished(counts: ShotTrainingCounts())])
    }
}
