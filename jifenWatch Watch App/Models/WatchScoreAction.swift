import Foundation
import RecordCore
import ScoreCore

struct WatchScoreActionLog: Codable, Sendable, Equatable {
    private(set) var actions: [DetailedScoreAction]
    private var undoCheckpoints: [Set<UUID>]
    private var removedActionIDs: Set<UUID>

    init(startedAt: Date, resumed: WatchScoreActionLog? = nil) {
        if let resumed {
            self = resumed
        } else {
            actions = [Self.startAction(at: startedAt)]
            undoCheckpoints = []
            removedActionIDs = []
        }
    }

    mutating func beginUndoableMutation() {
        undoCheckpoints.append([])
    }

    mutating func rejectUndoableMutation() {
        _ = undoCheckpoints.popLast()
    }

    mutating func clearUndoHistory() {
        undoCheckpoints.removeAll()
    }

    mutating func append(contentsOf newActions: [DetailedScoreAction]) {
        actions.append(contentsOf: newActions)
        if !undoCheckpoints.isEmpty {
            undoCheckpoints[undoCheckpoints.count - 1].formUnion(newActions.map(\.id))
        }
    }

    /// Preserve local actions that have not reached the peer. Explicit
    /// removals remain known even if an older frame provides those IDs again.
    @discardableResult
    mutating func merge(detailedActions: [DetailedScoreAction], removing removedIDs: Set<UUID> = []) -> Bool {
        var changed = removeActions(withIDs: removedIDs)
        var knownIDs = Set(actions.map(\.id))
        for action in detailedActions where !removedActionIDs.contains(action.id) {
            if knownIDs.insert(action.id).inserted {
                actions.append(action)
                changed = true
            }
        }
        if changed {
            actions.sort {
                ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
            }
        }
        return changed
    }

    @discardableResult
    mutating func removeActions(withIDs ids: Set<UUID>) -> Bool {
        guard !ids.isSubset(of: removedActionIDs) else { return false }
        removedActionIDs.formUnion(ids)
        actions.removeAll { ids.contains($0.id) }
        return true
    }

    mutating func omitSecondaryScores() {
        actions = actions.map { ScoreActionProjector.omittingSecondaryScores(from: $0) }
    }

    @discardableResult
    mutating func undo(
        at timestamp: Date = Date(),
        team1Score: Int,
        team2Score: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil
    ) -> Bool {
        guard let checkpoint = undoCheckpoints.popLast() else { return false }
        removeActions(withIDs: checkpoint)
        append(contentsOf: [ScoreActionProjector.action(
            .undo, code: "undo", scores: (team1Score, team2Score),
            sets: Self.scorePair(team1SetScore, team2SetScore), timestamp: timestamp
        )])
        return true
    }

    mutating func reset(at timestamp: Date = Date()) {
        actions = [Self.startAction(at: timestamp)]
        undoCheckpoints.removeAll()
        removedActionIDs.removeAll()
    }

    mutating func appendGameEndIfNeeded(
        at timestamp: Date = Date(),
        team1Score: Int,
        team2Score: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winner: RecordTeam? = nil
    ) {
        guard !actions.contains(where: { $0.type == .matchFinished }) else { return }
        append(contentsOf: [DetailedScoreAction(
            type: .matchFinished,
            epochMilliseconds: Int64((timestamp.timeIntervalSince1970 * 1_000).rounded()),
            scores: [team1Score, team2Score],
            setScores: Self.scorePair(team1SetScore, team2SetScore).map { [$0.0, $0.1] } ?? [],
            winner: winner,
            operationCode: "game_end",
            summary: "game_end"
        )])
    }

    var detailedActions: [DetailedScoreAction] { actions }

    /// Shared with linked finishes and phone records: the reducer-aware tally in
    /// RecordCore, so independent and linked records report the same total.
    var scoreChangeCount: Int { actions.scoreChangeCount }

    private static func startAction(at timestamp: Date) -> DetailedScoreAction {
        ScoreActionProjector.action(.matchStarted, code: "game_start", scores: (0, 0), sets: (0, 0), timestamp: timestamp)
    }

    private static func scorePair(_ left: Int?, _ right: Int?) -> (Int, Int)? {
        guard let left, let right else { return nil }
        return (left, right)
    }
}
