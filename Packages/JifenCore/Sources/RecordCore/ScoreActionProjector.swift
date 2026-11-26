import Foundation
import ScoreCore

/// Projects accepted sport events into the shared action history.
public enum ScoreActionProjector {
    public static func rally(
        intent: RallyMatchIntent,
        events: [RallyMatchEvent],
        state: RallyMatchState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        var projected: [DetailedScoreAction] = []
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                projected.append(action(
                    .scoreChanged, code: "point", side: side,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    delta: 1, setNumber: state.currentSet, timestamp: timestamp
                ))
            case .pointsAdjusted(let side, let delta, let left, let right):
                projected.append(action(
                    .scoreChanged,
                    code: "adjust", side: side,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    delta: delta, setNumber: state.currentSet, timestamp: timestamp
                ))
            case .sideOut(let servingSide, let left, let right):
                projected.append(action(
                    .serveChanged, code: "side_out", side: servingSide,
                    scores: (left, right), sets: (state.leftSets, state.rightSets),
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .setCompleted(let winner, let number, let left, let right, let leftSets, let rightSets):
                projected.append(action(
                    .setFinished, code: "set_completed", side: winner,
                    scores: (left, right), sets: (leftSets, rightSets),
                    setNumber: number, winner: winner, timestamp: timestamp
                ))
            case .sidesExchangeReminder:
                projected.append(action(
                    .stateChanged, code: "side_change_reminder",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .sidesExchanged:
                projected.append(action(
                    .sideChanged, code: "exchange_sides",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .matchFinished(let winner):
                projected.append(action(
                    .matchFinished, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), winner: winner,
                    timestamp: timestamp
                ))
            case .matchReset:
                break
            case .pingPongAdministrativeAction(let administrativeAction):
                projected.append(action(
                    .stateChanged,
                    code: "pingpong_\(administrativeAction.type.rawValue)",
                    side: administrativeAction.side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets),
                    timestamp: timestamp
                ))
            case .badmintonMisconduct(let misconduct):
                projected.append(action(
                    .stateChanged,
                    code: "badminton_misconduct_\(misconduct.kind.rawValue)",
                    side: misconduct.side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets),
                    timestamp: timestamp
                ))
            case .officialBreakChanged:
                break
            }
        }

        if projected.isEmpty {
            switch intent {
            case .adjustPoints(let side, let delta):
                projected.append(action(
                    .stateChanged, code: "adjust_points", side: side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .adjustSets(let side, let delta):
                projected.append(action(
                    .stateChanged, code: "adjust_sets", side: side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                ))
            case .setNames, .setDoublesPlayerName:
                projected.append(action(
                    .stateChanged, code: "edit_name",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets), timestamp: timestamp
                ))
            case .pingPongAdministrativeAction(let type, let side):
                projected.append(action(
                    .stateChanged,
                    code: "pingpong_\(type.rawValue)",
                    side: side,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: (state.leftSets, state.rightSets),
                    timestamp: timestamp
                ))
            case .reset:
                break
            default:
                break
            }
        }
        return projected
    }

    public static func tennis(
        intent: TennisMatchIntent,
        events: [TennisMatchEvent],
        state: TennisMatchState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        var projected: [DetailedScoreAction] = []
        let hasGamesLayer = state.rules.setScoringMode != .tiebreakOnly
        let secondaryScores: (Int, Int)? = hasGamesLayer
            ? (state.leftSets, state.rightSets)
            : nil
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                projected.append(action(
                    .scoreChanged, code: "tennis_point", side: side,
                    scores: (left, right), sets: secondaryScores,
                    delta: 1, setNumber: state.leftSets + state.rightSets + 1,
                    gameNumber: hasGamesLayer ? state.leftGames + state.rightGames + 1 : nil,
                    timestamp: timestamp
                ))
            case .gameCompleted(let winner, let leftGames, let rightGames, let tieBreak):
                projected.append(action(
                    .roundFinished, code: tieBreak ? "tiebreak_completed" : "game_completed",
                    side: winner, scores: (leftGames, rightGames),
                    sets: secondaryScores,
                    gameNumber: hasGamesLayer ? leftGames + rightGames : nil, winner: winner,
                    timestamp: timestamp
                ))
            case .setCompleted(let winner, let number, let leftGames, let rightGames, let leftSets, let rightSets):
                projected.append(action(
                    .setFinished, code: "tennis_set_completed", side: winner,
                    scores: (leftGames, rightGames),
                    sets: hasGamesLayer ? (leftSets, rightSets) : nil,
                    setNumber: number, winner: winner, timestamp: timestamp
                ))
            case .sidesExchangeReminder:
                projected.append(action(
                    .stateChanged, code: "side_change_reminder",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, timestamp: timestamp
                ))
            case .sidesExchanged:
                projected.append(action(
                    .sideChanged, code: "exchange_sides",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, timestamp: timestamp
                ))
            case .namesChanged:
                projected.append(action(
                    .stateChanged, code: "edit_name",
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
                    .stateChanged, code: "edit_score", side: sideAndDelta.0,
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, delta: sideAndDelta.1,
                    setNumber: state.leftSets + state.rightSets + 1,
                    gameNumber: hasGamesLayer ? state.leftGames + state.rightGames + 1 : nil,
                    timestamp: timestamp
                ))
            case .matchFinished(let winner):
                projected.append(action(
                    .matchFinished, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    sets: secondaryScores, winner: winner,
                    timestamp: timestamp
                ))
            case .matchReset:
                break
            case .officialBreakChanged:
                break
            }
        }
        return projected
    }

    public static func archery(
        events: [ArcheryMatchEvent],
        state: ArcheryMatchState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        events.compactMap { event in
            switch event {
            case .arrowScored(let side, let points, let left, let right):
                return action(
                    .scoreChanged,
                    code: "archery_arrow",
                    side: side, scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: points,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .arrowMissed(let side, let left, let right):
                return action(
                    .scoreChanged,
                    code: "archery_miss",
                    side: side, scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: 0,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .setReady(let number, let left, let right, _, _):
                return action(
                    .stateChanged, code: "archery_set_ready", scores: (left, right),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .closestToCenterRequired(let number, _):
                return action(
                    .stateChanged, code: "archery_closest_to_center", scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .shootOffRepeated(let number):
                return action(
                    .stateChanged, code: "archery_repeat_shoot_off", scores: (0, 0),
                    sets: (state.leftSetPoints, state.rightSetPoints), setNumber: number,
                    timestamp: timestamp
                )
            case .setCompleted(let number, let winner, let leftSets, let rightSets):
                return action(
                    .setFinished, code: "archery_set_completed", side: winner,
                    scores: (state.leftArrowSum, state.rightArrowSum), sets: (leftSets, rightSets),
                    setNumber: number, winner: winner, timestamp: timestamp
                )
            case .matchFinished(let winner):
                return action(
                    .matchFinished, code: "game_end", scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), winner: winner,
                    timestamp: timestamp
                )
            case .arrowSumAdjusted(let side, let delta):
                return action(
                    .stateChanged, code: "archery_adjust_arrow_sum", side: side,
                    scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .setPointsAdjusted(let side, let delta):
                return action(
                    .stateChanged, code: "archery_adjust_set_points", side: side,
                    scores: (state.leftArrowSum, state.rightArrowSum),
                    sets: (state.leftSetPoints, state.rightSetPoints), delta: delta,
                    setNumber: state.currentSet, timestamp: timestamp
                )
            case .namesChanged:
                return action(.stateChanged, code: "edit_name", scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .openingShooterChanged, .shooterSelected:
                return action(.serveChanged, code: "archery_shooter_changed", side: state.currentShooter, scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChanged, code: "exchange_sides", scores: (state.leftArrowSum, state.rightArrowSum), sets: (state.leftSetPoints, state.rightSetPoints), timestamp: timestamp)
            case .matchReset:
                return nil
            }
        }
    }

    public static func eightBall(
        events: [EightBallEvent],
        state: EightBallState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        var projected: [DetailedScoreAction] = events.compactMap { event in
            switch event {
            case .rackWon(let side):
                return action(.scoreChanged, code: "eight_ball_rack", side: side,
                              scores: (state.leftPoints, state.rightPoints), delta: 1,
                              roundNumber: state.leftPoints + state.rightPoints, timestamp: timestamp)
            case .ballPotted(let side, let ball):
                return action(.scoreChanged, code: "eight_ball_pot_\(ball)", side: side,
                              scores: (state.leftPoints, state.rightPoints), delta: 1,
                              roundNumber: state.leftPoints + state.rightPoints, timestamp: timestamp)
            case .adminAdjusted:
                return action(.stateChanged, code: "eight_ball_admin_adjust",
                              scores: (state.leftPoints, state.rightPoints), timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChanged, code: "exchange_sides",
                              scores: (state.leftPoints, state.rightPoints), timestamp: timestamp)
            case .reset:
                return nil
            case .matchFinished:
                return action(
                    .matchFinished, code: "game_end",
                    scores: (state.leftPoints, state.rightPoints),
                    winner: state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right),
                    timestamp: timestamp
                )
            }
        }
        if state.finished, !projected.contains(where: { $0.type == .matchFinished }) {
            projected.append(action(
                .matchFinished, code: "game_end", scores: (state.leftPoints, state.rightPoints),
                winner: state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right),
                timestamp: timestamp
            ))
        }
        return projected
    }

    public static func nineBall(
        events: [NineBallChaseEvent],
        state: NineBallChaseState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
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
                let type: DetailedScoreActionType = kind == .foul ? .foul : .scoreChanged
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
            case .chaseTransferred(let player, let kind, let deltas, _, let continuePlayer, _, _, _):
                // transfer 语义下 deltas 对每个玩家是“零和转账”，取行动者自己的
                // 变化量作为 scoreChange；比赛模式犯规给对手加分（行动者 delta 为 0），
                // 此时取受分者变化量，让详情页与 totalScoreChanges 统计口径一致。
                let ownDelta = deltas.indices.contains(player) ? deltas[player] : 0
                let effectiveDelta: Int = {
                    if kind == .handoff { return 0 }
                    if ownDelta != 0 { return ownDelta }
                    if let receiver = continuePlayer, deltas.indices.contains(receiver) {
                        return deltas[receiver]
                    }
                    return ownDelta
                }()
                let type: DetailedScoreActionType = kind == .handoff
                    ? .stateChanged
                    : (kind == .foul ? .foul : .scoreChanged)
                return action(
                    type, code: "nine_ball_\(kind.rawValue)",
                    side: player < 2 ? (player == 0 ? .left : .right) : nil,
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    delta: kind == .handoff ? nil : effectiveDelta, roundNumber: player + 1,
                    participants: participants, timestamp: timestamp
                )
            case .breakerChanged:
                return action(
                    .stateChanged, code: "nine_ball_breaker_changed",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            case .totalsAdjusted:
                return action(
                    .stateChanged, code: "nine_ball_adjust_total",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            case .sidesExchanged:
                return action(
                    .sideChanged, code: "exchange_sides",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            case .matchFinished:
                return action(
                    .matchFinished, code: "game_end",
                    scores: (
                        state.playerPoints.indices.contains(0) ? state.playerPoints[0] : 0,
                        state.playerPoints.indices.contains(1) ? state.playerPoints[1] : 0
                    ),
                    participants: participants, timestamp: timestamp
                )
            }
        }
    }

    public static func snooker(
        intent: SnookerIntent,
        events: [SnookerEvent],
        state: SnookerState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
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
                return action(.scoreChanged, code: "snooker_pot", side: actor,
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
                return action(.serveChanged, code: code, side: side,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .frameSettled(let winner, let frame):
                return action(.setFinished, code: "snooker_frame_settled", side: winner,
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: frame, winner: winner, timestamp: timestamp)
            case .nextFrameStarted(let frame):
                return action(.stateChanged, code: "snooker_next_frame",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: frame, timestamp: timestamp)
            case .matchFinished:
                return action(.matchFinished, code: "game_end",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              winner: state.leftFrames == state.rightFrames ? nil : (state.leftFrames > state.rightFrames ? .left : .right),
                              timestamp: timestamp)
            case .adminCorrected:
                return action(.stateChanged, code: "snooker_admin_correct",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .reset:
                return action(.reset, code: "reset",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChanged, code: "exchange_sides",
                              scores: (state.leftScore, state.rightScore),
                              sets: (state.leftFrames, state.rightFrames),
                              roundNumber: state.currentFrame, timestamp: timestamp)
            }
        }
    }

    /// 足球：进球/减球的动作带上半场与比赛时钟，供记录详情呈现 `53′` 与 `45+2′`。
    public static func football(
        intent: FootballMatchIntent,
        events: [FootballMatchEvent],
        state: FootballMatchState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        let scores = (state.leftScore, state.rightScore)
        let period = state.timer.stage
        var projected: [DetailedScoreAction] = events.compactMap { event in
            switch event {
            case .goalScored(let side, let left, let right, let period, let elapsed):
                return action(
                    .scoreChanged, code: "goal", side: side,
                    scores: (left, right), delta: 1,
                    footballPeriod: period, footballElapsedSeconds: elapsed,
                    timestamp: timestamp
                )
            case .goalSubtracted(let side, let left, let right, let period, let elapsed):
                return action(
                    .scoreChanged, code: "goal_subtracted", side: side,
                    scores: (left, right), delta: -1,
                    footballPeriod: period, footballElapsedSeconds: elapsed,
                    timestamp: timestamp
                )
            case .kickedOff:
                return action(.stateChanged, code: "football_kick_off", scores: scores,
                              footballPeriod: period, timestamp: timestamp)
            case .clockToggled(let isRunning, let period):
                return action(
                    .stateChanged,
                    code: isRunning ? "football_clock_start" : "football_clock_pause",
                    scores: scores, footballPeriod: period, timestamp: timestamp
                )
            case .stoppageAdded(let seconds, let period):
                return action(.stateChanged, code: "football_stoppage_add", scores: scores,
                              delta: seconds, footballPeriod: period, timestamp: timestamp)
            case .stoppageUndone(let seconds, let period):
                return action(.stateChanged, code: "football_stoppage_undo", scores: scores,
                              delta: -seconds, footballPeriod: period, timestamp: timestamp)
            case .stageAdvanced(let newStage):
                return action(.stateChanged, code: "football_stage_advanced", scores: scores,
                              footballPeriod: newStage, timestamp: timestamp)
            case .namesChanged:
                return action(.stateChanged, code: "edit_name", scores: scores, timestamp: timestamp)
            case .sidesExchanged:
                return action(.sideChanged, code: "exchange_sides", scores: scores, timestamp: timestamp)
            case .matchFinished(let winner):
                return action(.matchFinished, code: "game_end", scores: scores, winner: winner,
                              timestamp: timestamp)
            case .matchReset:
                return nil
            }
        }
        if projected.isEmpty {
            switch intent {
            case .setNames:
                projected.append(action(.stateChanged, code: "edit_name", scores: scores, timestamp: timestamp))
            case .exchangeSides:
                projected.append(action(.sideChanged, code: "exchange_sides", scores: scores, timestamp: timestamp))
            case .reset:
                break
            case .startClock, .pauseClock, .toggleClock, .kickOff, .advanceStage,
                 .addStoppage, .undoLastStoppage, .goal, .subtractGoal, .finish:
                break
            }
        }
        return projected
    }

    /// 投篮训练：每次出手一条动作，命中带投入分数，完赛补一条结束动作。
    public static func shotTraining(
        intent: ShotTrainingIntent,
        events: [ShotTrainingEvent],
        state: ShotTrainingState,
        timestamp: Date
    ) -> [DetailedScoreAction] {
        let counts = state.counts
        let scores = (counts.missed, counts.made)
        var projected: [DetailedScoreAction] = events.compactMap { event in
            switch event {
            case .shotRecorded(let points, let made, let counts):
                let code = "training_\(points)pt_\(made ? "made" : "miss")"
                return action(
                    made ? .scoreChanged : .stateChanged, code: code,
                    side: made ? .right : .left,
                    scores: (counts.missed, counts.made),
                    delta: made ? points : 0,
                    timestamp: timestamp
                )
            case .shotUndone(let counts):
                return action(
                    .stateChanged, code: "training_undo",
                    scores: (counts.missed, counts.made), timestamp: timestamp
                )
            case .finished(let counts):
                let attempts = max(1, counts.attempts)
                let percentage = Int((Double(counts.made) / Double(attempts) * 100).rounded())
                // 与手机/手表既有训练记录一致：完赛动作保留命中率摘要。
                return DetailedScoreAction(
                    type: .matchFinished,
                    epochMilliseconds: Int64((timestamp.timeIntervalSince1970 * 1_000).rounded()),
                    scores: [counts.missed, counts.made],
                    operationCode: "training_finished",
                    summary: "training_rate_\(percentage)"
                )
            case .reset:
                return nil
            }
        }
        if projected.isEmpty {
            switch intent {
            case .reset, .finish, .undoLastShot:
                break
            case .recordShot(let points, let made):
                let code = "training_\(points)pt_\(made ? "made" : "miss")"
                projected.append(action(
                    made ? .scoreChanged : .stateChanged, code: code,
                    side: made ? .right : .left, scores: scores,
                    delta: made ? points : 0, timestamp: timestamp
                ))
            }
        }
        return projected
    }

    /// 详细动作构造（共享字段映射口径）。
    public static func action(
        _ type: DetailedScoreActionType,
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
        footballPeriod: Int? = nil,
        footballElapsedSeconds: Int? = nil,
        timestamp: Date = Date()
    ) -> DetailedScoreAction {
        DetailedScoreAction(
            type: type,
            epochMilliseconds: Int64((timestamp.timeIntervalSince1970 * 1_000).rounded()),
            team: side.map { $0 == .left ? .team1 : .team2 },
            scores: [scores.0, scores.1],
            setScores: sets.map { [$0.0, $0.1] } ?? [],
            setNumber: setNumber,
            gameNumber: gameNumber,
            roundNumber: roundNumber,
            periodNumber: periodNumber,
            scoreChange: delta,
            winner: winner.map { $0 == .left ? .team1 : .team2 },
            participants: participants ?? [],
            operationCode: code,
            summary: code,
            footballPeriod: footballPeriod,
            footballElapsedSeconds: footballElapsedSeconds
        )
    }

    public static func omittingSecondaryScores(from action: DetailedScoreAction) -> DetailedScoreAction {
        guard !action.setScores.isEmpty || action.gameNumber != nil else { return action }
        return DetailedScoreAction(
            id: action.id,
            type: action.type,
            epochMilliseconds: action.epochMilliseconds,
            team: action.team,
            scores: action.scores,
            setNumber: action.setNumber,
            roundNumber: action.roundNumber,
            periodNumber: action.periodNumber,
            gameTimeSeconds: action.gameTimeSeconds,
            scoreChange: action.scoreChange,
            winner: action.winner,
            loser: action.loser,
            landlord: action.landlord,
            winners: action.winners,
            losers: action.losers,
            farmers: action.farmers,
            participants: action.participants,
            operationCode: action.operationCode,
            operationPayload: action.operationPayload,
            summary: action.summary,
            footballPeriod: action.footballPeriod,
            footballElapsedSeconds: action.footballElapsedSeconds
        )
    }
}
