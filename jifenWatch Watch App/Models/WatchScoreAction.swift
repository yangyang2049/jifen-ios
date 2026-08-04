import Foundation
import RecordCore
import ScoreCore

enum WatchScoreActionType: String, Codable, Sendable {
    case gameStart
    case scoreAdd
    case scoreSubtract
    case setEnd
    case gameEnd
    case undo
    case reset
    case sideChange
    case serveChange
    case editScore
    case foul
    case timeout
    case periodEnd
    case roundEnd
    case stateChange
    case stop
    case resume
}

struct WatchScoreAction: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let timestamp: Date
    let actionType: WatchScoreActionType
    let description: String
    var team: RecordTeam?
    var team1Score: Int?
    var team2Score: Int?
    var team1SetScore: Int?
    var team2SetScore: Int?
    var scoreChange: Int?
    var setNumber: Int?
    var gameNumber: Int?
    var roundNumber: Int?
    var periodNumber: Int?
    var winner: RecordTeam?
    var participants: [ParticipantScoreSnapshot]?
    var operationCode: String?

    init(actionType: WatchScoreActionType,
         description: String,
         team: RecordTeam? = nil,
         team1Score: Int? = nil,
         team2Score: Int? = nil,
         team1SetScore: Int? = nil,
         team2SetScore: Int? = nil,
         scoreChange: Int? = nil,
         setNumber: Int? = nil,
         gameNumber: Int? = nil,
         roundNumber: Int? = nil,
         periodNumber: Int? = nil,
         winner: RecordTeam? = nil,
         participants: [ParticipantScoreSnapshot]? = nil,
         operationCode: String? = nil,
         timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.timestamp = timestamp
        self.actionType = actionType
        self.description = description
        self.team = team
        self.team1Score = team1Score
        self.team2Score = team2Score
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
        self.scoreChange = scoreChange
        self.setNumber = setNumber
        self.gameNumber = gameNumber
        self.roundNumber = roundNumber
        self.periodNumber = periodNumber
        self.winner = winner
        self.participants = participants
        self.operationCode = operationCode
    }

    nonisolated init(detailedAction: DetailedScoreAction) {
        id = detailedAction.id.uuidString
        timestamp = detailedAction.epochMilliseconds.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
        } ?? Date()
        actionType = switch detailedAction.type {
        case .matchStarted: .gameStart
        case .scoreChanged: (detailedAction.scoreChange ?? 0) < 0 ? .scoreSubtract : .scoreAdd
        case .setFinished: .setEnd
        case .roundFinished: .roundEnd
        case .periodFinished: .periodEnd
        case .matchFinished: .gameEnd
        case .undo: .undo
        case .reset: .reset
        case .sideChanged: .sideChange
        case .serveChanged: .serveChange
        case .foul: .foul
        case .timeout: .timeout
        case .stateChanged: .stateChange
        }
        description = detailedAction.summary ?? detailedAction.operationCode ?? detailedAction.type.rawValue
        team = detailedAction.team
        team1Score = detailedAction.scores.indices.contains(0) ? detailedAction.scores[0] : nil
        team2Score = detailedAction.scores.indices.contains(1) ? detailedAction.scores[1] : nil
        team1SetScore = detailedAction.setScores.indices.contains(0) ? detailedAction.setScores[0] : nil
        team2SetScore = detailedAction.setScores.indices.contains(1) ? detailedAction.setScores[1] : nil
        scoreChange = detailedAction.scoreChange
        setNumber = detailedAction.setNumber
        gameNumber = detailedAction.gameNumber
        roundNumber = detailedAction.roundNumber
        periodNumber = detailedAction.periodNumber
        winner = detailedAction.winner
        participants = detailedAction.participants
        operationCode = detailedAction.operationCode
    }

    var detailedAction: DetailedScoreAction {
        DetailedScoreAction(
            id: UUID(uuidString: id) ?? UUID(),
            type: detailedType,
            epochMilliseconds: Int64(timestamp.timeIntervalSince1970 * 1_000),
            team: team,
            scores: scorePair(team1Score, team2Score),
            setScores: scorePair(team1SetScore, team2SetScore),
            setNumber: setNumber,
            gameNumber: gameNumber,
            roundNumber: roundNumber,
            periodNumber: periodNumber,
            scoreChange: scoreChange,
            winner: winner,
            participants: participants ?? [],
            operationCode: operationCode,
            summary: description.isEmpty ? nil : description
        )
    }

    private var detailedType: DetailedScoreActionType {
        switch actionType {
        case .gameStart: .matchStarted
        case .scoreAdd, .scoreSubtract: .scoreChanged
        case .setEnd: .setFinished
        case .gameEnd: .matchFinished
        case .undo: .undo
        case .reset: .reset
        case .sideChange: .sideChanged
        case .serveChange: .serveChanged
        case .editScore: .stateChanged
        case .foul: .foul
        case .timeout: .timeout
        case .periodEnd: .periodFinished
        case .roundEnd: .roundFinished
        case .stateChange, .stop, .resume: .stateChanged
        }
    }

    private func scorePair(_ left: Int?, _ right: Int?) -> [Int] {
        guard let left, let right else { return [] }
        return [left, right]
    }
}

struct WatchScoreActionLog: Codable, Sendable, Equatable {
    var actions: [WatchScoreAction]
    var undoCheckpoints: [Int]

    init(startedAt: Date, resumed: WatchScoreActionLog? = nil) {
        if let resumed {
            self = resumed
        } else {
            actions = [Self.startAction(at: startedAt)]
            undoCheckpoints = []
        }
    }

    mutating func beginUndoableMutation() {
        undoCheckpoints.append(actions.count)
    }

    mutating func rejectUndoableMutation() {
        _ = undoCheckpoints.popLast()
    }

    mutating func append(contentsOf newActions: [WatchScoreAction]) {
        actions.append(contentsOf: newActions)
    }

    mutating func merge(detailedActions: [DetailedScoreAction]) {
        guard !detailedActions.isEmpty else { return }
        actions = detailedActions.map(WatchScoreAction.init).sorted {
            ($0.timestamp, $0.id) < ($1.timestamp, $1.id)
        }
        undoCheckpoints = []
    }

    mutating func omitSecondaryScores() {
        for index in actions.indices {
            actions[index].team1SetScore = nil
            actions[index].team2SetScore = nil
            actions[index].gameNumber = nil
        }
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
        if checkpoint < actions.count {
            actions.removeSubrange(checkpoint..<actions.count)
        }
        actions.append(WatchScoreAction(
            actionType: .undo,
            description: "undo",
            team1Score: team1Score,
            team2Score: team2Score,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore,
            operationCode: "undo",
            timestamp: timestamp
        ))
        return true
    }

    mutating func reset(at timestamp: Date = Date()) {
        actions = [Self.startAction(at: timestamp)]
        undoCheckpoints = []
    }

    mutating func appendGameEndIfNeeded(
        at timestamp: Date = Date(),
        team1Score: Int,
        team2Score: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winner: RecordTeam? = nil
    ) {
        guard actions.last?.actionType != .gameEnd else { return }
        actions.append(WatchScoreAction(
            actionType: .gameEnd,
            description: "game_end",
            team1Score: team1Score,
            team2Score: team2Score,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore,
            winner: winner,
            operationCode: "game_end",
            timestamp: timestamp
        ))
    }

    var detailedActions: [DetailedScoreAction] {
        actions.map(\.detailedAction)
    }

    var scoreChangeCount: Int {
        actions.reduce(into: 0) { count, action in
            switch action.actionType {
            case .scoreAdd, .scoreSubtract:
                if action.scoreChange != 0
                    || action.operationCode == "archery_arrow"
                    || action.operationCode == "archery_miss" {
                    count += 1
                }
            case .editScore:
                if action.scoreChange != 0 { count += 1 }
            case .foul:
                if action.scoreChange != 0,
                   action.operationCode?.hasPrefix("basketball_") != true {
                    count += 1
                }
            default:
                break
            }
        }
    }

    private static func startAction(at timestamp: Date) -> WatchScoreAction {
        WatchScoreAction(
            actionType: .gameStart,
            description: "game_start",
            team1Score: 0,
            team2Score: 0,
            team1SetScore: 0,
            team2SetScore: 0,
            operationCode: "game_start",
            timestamp: timestamp
        )
    }
}

enum WatchScoreActionProjector {
    static func rally(
        intent: RallyMatchIntent,
        events: [RallyMatchEvent],
        state: RallyMatchState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        var projected: [WatchScoreAction] = []
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                projected.append(action(
                    .scoreAdd, code: "point", side: side,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    delta: 1, setNumber: state.currentSet, timestamp: timestamp
                ))
            case .pointsAdjusted(let side, let delta, let left, let right):
                projected.append(action(
                    delta < 0 ? .scoreSubtract : .scoreAdd,
                    code: "adjust", side: side,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    delta: delta, setNumber: state.currentSet, timestamp: timestamp
                ))
            case .sideOut(let servingSide, let left, let right):
                projected.append(action(
                    .serveChange, code: "side_out", side: servingSide,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .setCompleted(let winner, let number, let left, let right, let leftSets, let rightSets):
                projected.append(action(
                    .setEnd, code: "set_completed", side: winner,
                    scores: (left, right), sets: (leftSets, rightSets),
                    setNumber: number, winner: winner, timestamp: timestamp
                ))
            case .sidesExchangeReminder:
                projected.append(action(
                    .stateChange, code: "side_change_reminder",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .sidesExchanged:
                projected.append(action(
                    .sideChange, code: "exchange_sides",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .matchFinished(let winner):
                projected.append(action(
                    .gameEnd, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), winner: winner,
                    timestamp: timestamp
                ))
            case .matchReset:
                break
            }
        }

        if projected.isEmpty {
            switch intent {
            case .adjustPoints(let side, let delta):
                projected.append(action(
                    .editScore, code: "adjust_points", side: side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .adjustSets(let side, let delta):
                projected.append(action(
                    .editScore, code: "adjust_sets", side: side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .setNames, .setDoublesPlayerName:
                projected.append(action(
                    .stateChange, code: "edit_name",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .reset:
                break
            default:
                break
            }
        }
        return projected
    }

    static func tennis(
        intent: TennisMatchIntent,
        events: [TennisMatchEvent],
        state: TennisMatchState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        var projected: [WatchScoreAction] = []
        let hasGamesLayer = state.rules.setScoringMode != .tiebreakOnly
        let secondaryScores: (Int, Int)? = hasGamesLayer
            ? (state.leftSets, state.rightSets)
            : nil
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                projected.append(action(
                    .scoreAdd, code: "tennis_point", side: side,
                    scores: (left, right), sets: secondaryScores,
                    delta: 1, setNumber: state.leftSets + state.rightSets + 1,
                    gameNumber: hasGamesLayer ? state.leftGames + state.rightGames + 1 : nil,
                    timestamp: timestamp
                ))
            case .gameCompleted(let winner, let leftGames, let rightGames, let tieBreak):
                projected.append(action(
                    .roundEnd, code: tieBreak ? "tiebreak_completed" : "game_completed",
                    side: winner, scores: (leftGames, rightGames),
                    sets: secondaryScores,
                    gameNumber: hasGamesLayer ? leftGames + rightGames : nil, winner: winner,
                    timestamp: timestamp
                ))
            case .setCompleted(let winner, let number, let leftGames, let rightGames, let leftSets, let rightSets):
                projected.append(action(
                    .setEnd, code: "tennis_set_completed", side: winner,
                    scores: (leftGames, rightGames),
                    sets: hasGamesLayer ? (leftSets, rightSets) : nil,
                    setNumber: number, winner: winner, timestamp: timestamp
                ))
            case .sidesExchangeReminder:
                projected.append(action(
                    .stateChange, code: "side_change_reminder",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, timestamp: timestamp
                ))
            case .sidesExchanged:
                projected.append(action(
                    .sideChange, code: "exchange_sides",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, timestamp: timestamp
                ))
            case .namesChanged:
                projected.append(action(
                    .stateChange, code: "edit_name",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, timestamp: timestamp
                ))
            case .adminAdjusted:
                let sideAndDelta: (MatchSide?, Int?) = switch intent {
                case .adjustPoints(let side, let delta),
                     .adjustGames(let side, let delta),
                     .adjustSets(let side, let delta): (side, delta)
                default: (nil, nil)
                }
                projected.append(action(
                    .editScore, code: "edit_score", side: sideAndDelta.0,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, delta: sideAndDelta.1,
                    setNumber: state.leftSets + state.rightSets + 1,
                    gameNumber: hasGamesLayer ? state.leftGames + state.rightGames + 1 : nil,
                    timestamp: timestamp
                ))
            case .matchFinished(let winner):
                projected.append(action(
                    .gameEnd, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, winner: winner,
                    timestamp: timestamp
                ))
            case .matchReset:
                break
            }
        }
        return projected
    }

    static func archery(
        events: [ArcheryMatchEvent],
        state: ArcheryMatchState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        events.compactMap { event in
            switch event {
            case .arrowScored(let side, let points, let left, let right):
                return action(
                    .scoreAdd,
                    code: "archery_arrow",
                    side: side, scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: points,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .arrowMissed(let side, let left, let right):
                return action(
                    .scoreAdd,
                    code: "archery_miss",
                    side: side, scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: 0,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .setReady(let number, let left, let right, _, _):
                return action(
                    .stateChange, code: "archery_set_ready", scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .closestToCenterRequired(let number, _):
                return action(
                    .stateChange, code: "archery_closest_to_center", scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .shootOffRepeated(let number):
                return action(
                    .stateChange, code: "archery_repeat_shoot_off", scores: (0, 0),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .setCompleted(let number, let winner, let leftSets, let rightSets):
                return action(
                    .setEnd, code: "archery_set_completed", side: winner,
                    scores: (state.leftArrowSum, state.rightArrowSum), sets: (leftSets, rightSets),
                    setNumber: number, winner: winner, timestamp: timestamp
                )
            case .matchFinished(let winner):
                return action(
                    .gameEnd, code: "game_end", scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), winner: winner,
                    timestamp: timestamp
                )
            case .arrowSumAdjusted(let side, let delta):
                return action(
                    .editScore, code: "archery_adjust_arrow_sum", side: side,
                    scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .setPointsAdjusted(let side, let delta):
                return action(
                    .editScore, code: "archery_adjust_set_points", side: side,
                    scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .namesChanged:
                return action(.stateChange, code: "edit_name", scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .openingShooterChanged, .shooterSelected:
                return action(.serveChange, code: "archery_shooter_changed", side: state.currentShooter, scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChange, code: "exchange_sides", scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .matchReset:
                return nil
            }
        }
    }

    static func eightBall(
        events: [EightBallEvent],
        state: EightBallState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        var projected: [WatchScoreAction] = events.compactMap { event in
            switch event {
            case .rackWon(let side):
                return action(.scoreAdd, code: "eight_ball_rack", side: side,
                              scores: (state.leftPoints, state.rightPoints), delta: 1,
                              roundNumber: state.leftPoints + state.rightPoints, timestamp: timestamp)
            case .ballPotted(let side, let ball):
                return action(.scoreAdd, code: "eight_ball_pot_\(ball)", side: side,
                              scores: (state.leftPoints, state.rightPoints), delta: 1,
                              roundNumber: state.leftPoints + state.rightPoints, timestamp: timestamp)
            case .adminAdjusted:
                return action(.editScore, code: "eight_ball_admin_adjust",
                              scores: (state.leftPoints, state.rightPoints), timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChange, code: "exchange_sides",
                              scores: (state.leftPoints, state.rightPoints), timestamp: timestamp)
            case .reset:
                return nil
            case .matchFinished:
                return action(
                    .gameEnd, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    winner: state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right),
                    timestamp: timestamp
                )
            }
        }
        if state.finished, !projected.contains(where: { $0.actionType == .gameEnd }) {
            projected.append(action(
                .gameEnd, code: "game_end", scores: (state.leftPoints, state.rightPoints),
                winner: state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right),
                timestamp: timestamp
            ))
        }
        return projected
    }

    static func nineBall(
        events: [NineBallChaseEvent],
        state: NineBallChaseState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        let participants = (0..<state.playerCount).map { index in
            ParticipantScoreSnapshot(
                id: "player_\(index)",
                name: state.resolvedName(at: index, fallback: "player_\(index + 1)"),
                score: state.playerPoints.indices.contains(index) ? state.playerPoints[index] : 0,
                role: "player"
            )
        }
        return events.map { event in
            switch event {
            case .chaseApplied(let player, let scorePlayer, let kind, let delta):
                let type: WatchScoreActionType = kind == .foul ? .foul : (delta >= 0 ? .scoreAdd : .scoreSubtract)
                return action(
                    type, code: "nine_ball_\(kind.rawValue)",
                    side: scorePlayer < 2 ? (scorePlayer == 0 ? .left : .right) : nil,
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    delta: delta, roundNumber: player + 1,
                    participants: participants, timestamp: timestamp
                )
            case .totalsAdjusted:
                return action(
                    .editScore, code: "nine_ball_adjust_total",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            case .sidesExchanged:
                return action(
                    .sideChange, code: "exchange_sides",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            case .matchFinished:
                return action(
                    .gameEnd, code: "game_end",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            }
        }
    }

    static func snooker(
        intent: SnookerIntent,
        events: [SnookerEvent],
        state: SnookerState,
        timestamp: Date
    ) -> [WatchScoreAction] {
        let actor: MatchSide? = switch intent {
        case .confirmStriker(let side), .potBallAsSide(let side, _),
             .foulFromSide(let side, _, _), .missFromPanel(let side),
             .handoverFromPanel(let side): side
        case .potBall, .foul, .miss, .handover: state.striker
        case .settleFrame(let winner): winner
        case .confirmNextFrame, .finishMatch, .reset, .adminCorrect, .exchangeSides: nil
        }
        return events.map { event in
            switch event {
            case .potted(let points):
                return action(.scoreAdd, code: "snooker_pot", side: actor,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames), delta: points,
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .foul(let points):
                let code: String = switch intent {
                case .foulFromSide(_, _, let switchTurn), .foul(_, let switchTurn):
                    switchTurn ? "snooker_foul" : "snooker_foul_continue"
                default:
                    "snooker_foul"
                }
                return action(.foul, code: code, side: actor,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames), delta: points,
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .turnChanged(let side):
                let code: String = switch intent {
                case .miss, .missFromPanel: "snooker_miss"
                case .handover, .handoverFromPanel: "snooker_handover"
                default: "snooker_turn_changed"
                }
                return action(.serveChange, code: code, side: side,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .frameSettled(let winner, let frame):
                return action(.setEnd, code: "snooker_frame_settled", side: winner,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: frame, winner: winner, timestamp: timestamp)
            case .nextFrameStarted(let frame):
                return action(.stateChange, code: "snooker_next_frame",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: frame, timestamp: timestamp)
            case .matchFinished:
                return action(.gameEnd, code: "game_end",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              winner: state.leftFrames == state.rightFrames ? nil : (state.leftFrames > state.rightFrames ? .left : .right),
                              timestamp: timestamp)
            case .adminCorrected:
                return action(.editScore, code: "snooker_admin_correct",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .reset:
                return action(.reset, code: "reset",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChange, code: "exchange_sides",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            }
        }
    }

    static func action(
        _ type: WatchScoreActionType,
        code: String,
        side: MatchSide? = nil,
        scores: (Int, Int),
        sets: (Int, Int)? = nil,
        delta: Int? = nil,
        setNumber: Int? = nil,
        gameNumber: Int? = nil,
        roundNumber: Int? = nil,
        periodNumber: Int? = nil,
        winner: MatchSide? = nil,
        participants: [ParticipantScoreSnapshot]? = nil,
        timestamp: Date = Date()
    ) -> WatchScoreAction {
        WatchScoreAction(
            actionType: type,
            description: code,
            team: side.map { $0 == .left ? .team1 : .team2 },
            team1Score: scores.0,
            team2Score: scores.1,
            team1SetScore: sets?.0,
            team2SetScore: sets?.1,
            scoreChange: delta,
            setNumber: setNumber,
            gameNumber: gameNumber,
            roundNumber: roundNumber,
            periodNumber: periodNumber,
            winner: winner.map { $0 == .left ? .team1 : .team2 },
            participants: participants,
            operationCode: code,
            timestamp: timestamp
        )
    }

}
