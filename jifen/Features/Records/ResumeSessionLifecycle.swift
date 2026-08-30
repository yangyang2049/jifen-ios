import Foundation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

enum ResumeSessionLifecycleError: Error, Equatable {
    case missingEnvelope(UUID)
    case unsupportedPayload(ResumePayloadKind, ScoreCore.GameType)
    case invalidPayload(ResumePayloadKind, ScoreCore.GameType)
}

enum ResumeSessionDisposition: Equatable {
    case discardedWithoutProgress
    case archived(recordID: String, recordWritten: Bool)

    var recordWritten: Bool {
        guard case .archived(_, let recordWritten) = self else { return false }
        return recordWritten
    }

    var containsHistoricalRecord: Bool {
        guard case .archived = self else { return false }
        return true
    }
}

/// One transaction boundary for both automatic expiry and an explicit Home
/// discard. A historical record is made durable before the resumable snapshot
/// is removed. If either the record write or cleanup fails, the resume entry is
/// left available for the next reconciliation attempt.
@MainActor
struct AbandonedResumeSessionCoordinator {
    typealias EnvelopeLoader = @MainActor (UUID) throws -> ResumeSessionEnvelope?
    typealias RecordLookup = @MainActor (String) -> ScoreboardRecord?
    typealias RecordWriter = @MainActor (ScoreboardRecord) throws -> Void
    typealias ResumeRemover = @MainActor (UUID) async throws -> Void

    private let retentionPolicy: ResumeSessionRetentionPolicy
    private let envelopeLoader: EnvelopeLoader
    private let recordLookup: RecordLookup
    private let recordWriter: RecordWriter
    private let resumeRemover: ResumeRemover

    init(
        rootURL: URL = ResumeSessionRepository.defaultRootURL(),
        retentionPolicy: ResumeSessionRetentionPolicy = .fortyEightHours,
        envelopeLoader: EnvelopeLoader? = nil,
        recordLookup: @escaping RecordLookup = {
            ScoreboardRecordManager.shared.getRecordById($0)
        },
        recordWriter: @escaping RecordWriter = {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                $0,
                cleanupResumeAfterWrite: false
            )
        },
        resumeRemover: ResumeRemover? = nil
    ) {
        self.retentionPolicy = retentionPolicy
        self.envelopeLoader = envelopeLoader ?? { sessionID in
            try ResumeSessionRepository.loadEnvelope(
                sessionId: sessionID,
                rootURL: rootURL
            )
        }
        self.recordLookup = recordLookup
        self.recordWriter = recordWriter
        self.resumeRemover = resumeRemover ?? { sessionID in
            try await ResumeSessionRepository(rootURL: rootURL).remove(sessionId: sessionID)
        }
    }

    /// Returns `nil` while the session is still inside the 48-hour window.
    func archiveIfExpired(
        sessionID: UUID,
        now: Date = Date()
    ) async throws -> ResumeSessionDisposition? {
        let envelope = try loadEnvelope(sessionID)
        guard retentionPolicy.isExpired(envelope, now: now) else { return nil }
        return try await archive(envelope, abandonedAt: now)
    }

    func abandon(
        sessionID: UUID,
        now: Date = Date()
    ) async throws -> ResumeSessionDisposition {
        try await archive(loadEnvelope(sessionID), abandonedAt: now)
    }

    private func loadEnvelope(_ sessionID: UUID) throws -> ResumeSessionEnvelope {
        guard let envelope = try envelopeLoader(sessionID) else {
            throw ResumeSessionLifecycleError.missingEnvelope(sessionID)
        }
        return envelope
    }

    private func archive(
        _ envelope: ResumeSessionEnvelope,
        abandonedAt: Date
    ) async throws -> ResumeSessionDisposition {
        guard let record = try AbandonedResumeRecordBuilder.build(
            envelope: envelope,
            abandonedAt: abandonedAt
        ) else {
            try await resumeRemover(envelope.sessionId)
            return .discardedWithoutProgress
        }

        let existing = recordLookup(record.id)
        let recordWritten: Bool
        if existing?.status.isHistorical == true {
            recordWritten = false
        } else {
            try recordWriter(record)
            recordWritten = true
        }

        // This is intentionally last. A failed archive remains resumable, and
        // a failed cleanup is safe to retry because the historical write is
        // idempotent by record identifier.
        try await resumeRemover(envelope.sessionId)
        return .archived(recordID: record.id, recordWritten: recordWritten)
    }
}

enum AbandonedResumeRecordBuilder {
    static func build(
        envelope: ResumeSessionEnvelope,
        abandonedAt: Date
    ) throws -> ScoreboardRecord? {
        if envelope.payloadKind == .manualState {
            return try buildManual(envelope: envelope, abandonedAt: abandonedAt)
        }

        switch ScoreboardKernelRegistry.descriptor(for: envelope.gameType).kind {
        case .rally:
            let session: ScoreSession<RallyMatchState, RallyMatchEvent> = try currentSession(
                envelope,
                intent: RallyMatchIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let count = max(eventCount, state.hasMeaningfulScore ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                leftSets: state.leftSets,
                rightSets: state.rightSets,
                operationCount: count,
                configuration: ScoreboardRecordConfiguration.rally(
                    gameType: envelope.gameType,
                    state: state,
                    voiceAnnouncement: session.metadata.extras["voiceAnnouncementEnabled"] == "true",
                    showMatchTime: session.metadata.extras["showMatchTime"] == "true",
                    competitionFormat: state.competitionFormat,
                    competitionPlayerNames: state.competitionPlayerNames
                )
            )

        case .tennis:
            let session: ScoreSession<TennisMatchState, TennisMatchEvent> = try currentSession(
                envelope,
                intent: TennisMatchIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let count = max(eventCount, state.hasMeaningfulScore ? 1 : 0)
            let pointOnly = state.rules.setScoringMode == .tiebreakOnly
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: pointOnly ? state.leftPoints : state.leftGames,
                rightScore: pointOnly ? state.rightPoints : state.rightGames,
                leftSets: pointOnly ? nil : state.leftSets,
                rightSets: pointOnly ? nil : state.rightSets,
                operationCount: count,
                configuration: ScoreboardRecordConfiguration.tennis(
                    gameType: envelope.gameType,
                    state: state,
                    voiceAnnouncement: session.metadata.extras["voiceAnnouncementEnabled"] == "true"
                )
            )

        case .line:
            let session: ScoreSession<LineScoreState, LineScoreEvent> = try currentSession(
                envelope,
                intent: LineScoreIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let count = max(eventCount, state.leftScore != 0 || state.rightScore != 0 ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "minimumScore": AnyCodable(state.rules.minimum),
                    "maximumScore": AnyCodable(state.rules.maximum)
                ]
            )

        case .basketball:
            let session: ScoreSession<BasketballMatchState, BasketballMatchEvent> = try currentSession(
                envelope,
                intent: BasketballMatchIntent.self
            )
            let state = session.state
            let progress = session.events.reduce(into: BasketballProgress()) { result, event in
                result.consume(event)
            }
            let stateHasTimerProgress = state.hasMeaningfulTimerProgress
            let count = max(
                progress.scoreOperations + progress.timerOperations,
                state.leftScore != 0 || state.rightScore != 0 || stateHasTimerProgress ? 1 : 0
            )
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                operationCount: count,
                timerOnly: progress.scoreOperations == 0
                    && state.leftScore == 0
                    && state.rightScore == 0
                    && (progress.timerOperations > 0 || stateHasTimerProgress),
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "basketballMode": AnyCodable(state.gameMode.rawValue),
                    "basketballRuleSet": AnyCodable(state.ruleSet.rawValue)
                ]
            )

        case .eightBall:
            let session: ScoreSession<EightBallState, EightBallEvent> = try currentSession(
                envelope,
                intent: EightBallIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let baselineLeft = state.handicapBeneficiary == .left ? state.handicapRacks : 0
            let baselineRight = state.handicapBeneficiary == .right ? state.handicapRacks : 0
            let stateChanged = state.leftPoints != baselineLeft
                || state.rightPoints != baselineRight
                || state.leftCounts.contains(where: { $0 > 0 })
                || state.rightCounts.contains(where: { $0 > 0 })
            let count = max(eventCount, stateChanged ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: participantName(envelope, index: 0, fallback: "A"),
                rightName: participantName(envelope, index: 1, fallback: "B"),
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "targetScore": AnyCodable(state.targetPoints),
                    "eightBallHandicapRacks": AnyCodable(state.handicapRacks),
                    "eightBallHandicapBeneficiary": AnyCodable(state.handicapBeneficiary?.rawValue ?? "")
                ]
            )

        case .nineBall:
            let session: ScoreSession<NineBallChaseState, NineBallChaseEvent> = try currentSession(
                envelope,
                intent: NineBallChaseIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let stateChanged = state.playerPoints.prefix(state.playerCount).contains(where: { $0 != 0 })
                || state.playerCounts.prefix(state.playerCount).flatMap { $0 }.contains(where: { $0 > 0 })
            let count = max(eventCount, stateChanged ? 1 : 0)
            let players = (0..<state.playerCount).map { index in
                [
                    "name": state.resolvedName(
                        at: index,
                        fallback: envelope.participants[safe: index]?.name
                    ),
                    "finalScore": state.playerPoints[safe: index] ?? 0,
                    "score": state.playerPoints[safe: index] ?? 0
                ] as [String: Any]
            }
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.resolvedName(at: 0, fallback: envelope.participants[safe: 0]?.name),
                rightName: state.resolvedName(at: 1, fallback: envelope.participants[safe: 1]?.name),
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                operationCount: count,
                extraData: [
                    "players": AnyCodable(players),
                    "playerCount": AnyCodable(state.playerCount)
                ],
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "nineBallBigGold": AnyCodable(state.config.bigGold),
                    "nineBallSmallGold": AnyCodable(state.config.smallGold),
                    "nineBallGoldenNine": AnyCodable(state.config.goldenNine),
                    "nineBallNormalWin": AnyCodable(state.config.normalWin),
                    "nineBallBallInHand": AnyCodable(state.config.ballInHand),
                    "nineBallFoul": AnyCodable(state.config.foul)
                ]
            )

        case .snooker:
            let session: ScoreSession<SnookerState, SnookerEvent> = try currentSession(
                envelope,
                intent: SnookerIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let stateChanged = state.leftScore != 0 || state.rightScore != 0
                || state.leftFrames != 0 || state.rightFrames != 0 || state.currentFrame > 1
            let count = max(eventCount, stateChanged ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: participantName(envelope, index: 0, fallback: "A"),
                rightName: participantName(envelope, index: 1, fallback: "B"),
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                leftSets: state.leftFrames,
                rightSets: state.rightFrames,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "maxSets": AnyCodable(state.maxFrames)
                ]
            )

        case .boxing:
            let session: ScoreSession<BoxingMatchState, BoxingMatchEvent> = try currentSession(
                envelope,
                intent: BoxingMatchIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let stateChanged = state.leftTotal != 0 || state.rightTotal != 0
                || state.leftRoundsWon != 0 || state.rightRoundsWon != 0 || state.currentRound > 1
            let count = max(eventCount, stateChanged ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftTotal,
                rightScore: state.rightTotal,
                leftSets: state.leftRoundsWon,
                rightSets: state.rightRoundsWon,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "maxRounds": AnyCodable(state.maxRounds)
                ]
            )

        case .guandan:
            let session: ScoreSession<GuandanMatchState, GuandanSessionEvent> = try currentSession(
                envelope,
                intent: GuandanSessionIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let stateChanged = state.redTeam.currentRank != "2" || state.blueTeam.currentRank != "2"
                || state.phase != .notStarted
            let count = max(eventCount, stateChanged ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.redTeam.name,
                rightName: state.blueTeam.name,
                leftScore: GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
                rightScore: GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank),
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "guandanTripleA": AnyCodable(state.aStageMode == .tripleA),
                    "guandanPassACondition": AnyCodable(state.passACondition.rawValue),
                    "guandanTripleAFallbackRank": AnyCodable(state.tripleAFallbackRank)
                ]
            )

        case .shengji:
            let session: ScoreSession<ShengjiTierState, ShengjiTierEvent> = try currentSession(
                envelope,
                intent: ShengjiTierIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let count = max(eventCount, state.leftIndex != 0 || state.rightIndex != 0 ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: participantName(envelope, index: 0, fallback: "A"),
                rightName: participantName(envelope, index: 1, fallback: "B"),
                leftScore: state.leftIndex,
                rightScore: state.rightIndex,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue)
                ]
            )

        case .archery:
            let session: ScoreSession<ArcheryMatchState, ArcheryMatchEvent> = try currentSession(
                envelope,
                intent: ArcheryMatchIntent.self
            )
            let state = session.state
            let eventCount = session.events.filter(\.isMeaningfulScoreOperation).count
            let stateChanged = state.leftArrowSum != 0 || state.rightArrowSum != 0
                || state.leftSetPoints != 0 || state.rightSetPoints != 0
                || state.arrowsLeftThisSet != 0 || state.arrowsRightThisSet != 0
            let count = max(eventCount, stateChanged ? 1 : 0)
            return try makeRecord(
                envelope: envelope,
                session: session,
                abandonedAt: abandonedAt,
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftArrowSum,
                rightScore: state.rightArrowSum,
                leftSets: state.leftSetPoints,
                rightSets: state.rightSetPoints,
                operationCount: count,
                configuration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(envelope.gameType.rawValue),
                    "servingSide": AnyCodable(
                        state.openingShooterIsLeft ? MatchSide.left.rawValue : MatchSide.right.rawValue
                    )
                ]
            )

        case .multi, .uno, .doudizhu:
            throw ResumeSessionLifecycleError.unsupportedPayload(
                envelope.payloadKind,
                envelope.gameType
            )
        }
    }

    private static func buildManual(
        envelope: ResumeSessionEnvelope,
        abandonedAt: Date
    ) throws -> ScoreboardRecord? {
        guard let state = try? JSONDecoder().decode(
            ManualScoreboardResumeState.self,
            from: envelope.payload
        ), state.schemaVersion == ManualScoreboardResumeState.currentSchemaVersion else {
            throw ResumeSessionLifecycleError.invalidPayload(.manualState, envelope.gameType)
        }
        guard state.hasMeaningfulScoreOrTimerProgress else { return nil }

        var configuration = state.projectConfiguration ?? [:]
        configuration[ScoreboardRecordConfiguration.Key.scoreCoreGameType] = AnyCodable(
            state.scoreCoreGameType.rawValue
        )
        return ScoreboardRecord(
            id: state.recordId,
            gameType: state.gameType,
            startTime: state.startTime,
            endTime: abandonedAt,
            duration: max(0, abandonedAt.timeIntervalSince(state.startTime)),
            team1Name: state.team1Name,
            team2Name: state.team2Name,
            team1FinalScore: state.team1FinalScore,
            team2FinalScore: state.team2FinalScore,
            team1SetScore: state.team1SetScore,
            team2SetScore: state.team2SetScore,
            winner: nil,
            winnerIdentity: nil,
            actions: state.actions,
            detailedActions: state.detailedActions,
            setResults: state.setResults,
            totalScoreChanges: state.totalScoreChanges,
            extraData: state.extraData,
            projectConfiguration: configuration,
            stateSnapshot: state.stateSnapshot,
            status: .abandoned
        )
    }

    private static func currentSession<State, Event, Intent>(
        _ envelope: ResumeSessionEnvelope,
        intent: Intent.Type
    ) throws -> ScoreSession<State, Event>
    where State: Codable & Sendable, Event: Codable & Sendable, Intent: Codable & Sendable {
        do {
            switch envelope.payloadKind {
            case .scoreSession:
                return try JSONDecoder().decode(ScoreSession<State, Event>.self, from: envelope.payload)
            case .scoreSessionBundle:
                return try JSONDecoder().decode(
                    ScoreSessionResumeBundle<State, Event, Intent>.self,
                    from: envelope.payload
                ).currentSession
            case .manualState:
                throw ResumeSessionLifecycleError.unsupportedPayload(.manualState, envelope.gameType)
            }
        } catch let error as ResumeSessionLifecycleError {
            throw error
        } catch {
            throw ResumeSessionLifecycleError.invalidPayload(
                envelope.payloadKind,
                envelope.gameType
            )
        }
    }

    private static func makeRecord<State, Event>(
        envelope: ResumeSessionEnvelope,
        session: ScoreSession<State, Event>,
        abandonedAt: Date,
        leftName: String,
        rightName: String,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int? = nil,
        rightSets: Int? = nil,
        operationCount: Int,
        timerOnly: Bool = false,
        extraData: [String: AnyCodable]? = nil,
        configuration: [String: AnyCodable]
    ) throws -> ScoreboardRecord?
    where State: Codable & Sendable, Event: Codable & Sendable {
        guard operationCount > 0,
              let appGameType = GameType(scoreCoreGameType: envelope.gameType) else {
            return nil
        }
        let startTime = Date(
            timeIntervalSince1970: TimeInterval(envelope.startedAtEpochMilliseconds) / 1_000
        )
        let snapshot = try JSONEncoder().encode(session)
        let startAction = DetailedScoreAction(
            type: .matchStarted,
            epochMilliseconds: envelope.startedAtEpochMilliseconds,
            scores: [0, 0]
        )
        let progressAction = DetailedScoreAction(
            type: timerOnly ? .stateChanged : .scoreChanged,
            epochMilliseconds: envelope.updatedAtEpochMilliseconds,
            scores: [leftScore, rightScore],
            setScores: [leftSets ?? 0, rightSets ?? 0],
            operationCode: timerOnly ? "timer_progress" : "abandoned_snapshot"
        )
        let recordContext = scoreSessionRecordContext(from: envelope)
        let preservedActions = recordContext?.actionLog ?? []
        let preservedDetails = recordContext?.detailedActions ?? []
        let resolvedDetailedActions: [DetailedScoreAction]
        if preservedDetails.isEmpty {
            resolvedDetailedActions = [startAction, progressAction]
        } else {
            // The auxiliary context is the app-layer source of truth for the
            // action/recap timeline. Add only the archive boundary snapshot;
            // never replace the detailed reducer actions with one synthetic
            // score point when a 48-hour cleanup archives a live bundle.
            resolvedDetailedActions = preservedDetails + [progressAction]
        }
        var resolvedConfiguration = configuration
        resolvedConfiguration[ScoreboardRecordConfiguration.Key.scoreCoreGameType] = AnyCodable(
            envelope.gameType.rawValue
        )
        return ScoreboardRecord(
            id: envelope.sessionId.uuidString,
            gameType: appGameType,
            startTime: startTime,
            endTime: abandonedAt,
            duration: max(0, abandonedAt.timeIntervalSince(startTime)),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: leftScore,
            team2FinalScore: rightScore,
            team1SetScore: leftSets,
            team2SetScore: rightSets,
            winner: nil,
            winnerIdentity: nil,
            actions: preservedActions,
            detailedActions: resolvedDetailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: resolvedDetailedActions),
            totalScoreChanges: max(operationCount, recordContext?.actionCount ?? 0),
            extraData: extraData,
            projectConfiguration: resolvedConfiguration,
            stateSnapshot: snapshot,
            status: .abandoned
        )
    }

    /// A generic projection is enough to recover app-layer context without
    /// knowing the bundle's concrete reducer Intent type at this call site.
    /// Unknown/legacy auxiliary bytes intentionally fall back to the existing
    /// synthetic archive snapshot.
    private static func scoreSessionRecordContext(
        from envelope: ResumeSessionEnvelope
    ) -> ScoreSessionRecordContext? {
        guard envelope.payloadKind == .scoreSessionBundle,
              let projection = try? JSONDecoder().decode(
                ResumeBundleAuxiliaryProjection.self,
                from: envelope.payload
              ) else {
            return nil
        }
        return ScoreSessionRecordContext.decode(projection.auxiliaryPayload)
    }

    private static func participantName(
        _ envelope: ResumeSessionEnvelope,
        index: Int,
        fallback: String
    ) -> String {
        let value = envelope.participants[safe: index]?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }
}

private struct ResumeBundleAuxiliaryProjection: Decodable {
    let auxiliaryPayload: Data?
}

private extension ManualScoreboardResumeState {
    var hasMeaningfulScoreOrTimerProgress: Bool {
        if totalScoreChanges > 0
            || team1FinalScore != 0
            || team2FinalScore != 0
            || (team1SetScore ?? 0) != 0
            || (team2SetScore ?? 0) != 0 {
            return true
        }
        if detailedActions?.contains(where: { action in
            switch action.type {
            case .scoreChanged, .setFinished, .roundFinished, .periodFinished:
                return true
            case .stateChanged:
                let code = action.operationCode?.lowercased() ?? ""
                return code.contains("timer") || code.contains("clock") || code.contains("tick")
            default:
                return false
            }
        }) == true {
            return true
        }
        if scoreCoreGameType == .football || scoreCoreGameType == .football5v5,
           let snapshot = stateSnapshot,
           let football = try? JSONDecoder().decode(FootballResumeStateV2.self, from: snapshot),
           football.timer.elapsedSeconds > 0
                || football.timer.stage > 1
                || football.timer.stoppageSeconds.contains(where: { $0 > 0 }) {
            return true
        }
        return actions.contains { raw in
            let normalized = raw.lowercased()
            if normalized.contains("layout:")
                || normalized.contains("exchange")
                || normalized.hasSuffix("|undo")
                || normalized.hasSuffix("|reset")
                || normalized.contains("name") {
                return false
            }
            return normalized.contains("point")
                || normalized.contains("score")
                || normalized.contains("adjust")
                || normalized.contains("round")
                || normalized.contains("settle")
                || normalized.contains("timer")
                || normalized.contains("clock")
                || normalized.contains("tick")
        }
    }
}

private extension RallyMatchState {
    var hasMeaningfulScore: Bool {
        leftPoints != 0 || rightPoints != 0 || leftSets != 0 || rightSets != 0
    }
}

private extension TennisMatchState {
    var hasMeaningfulScore: Bool {
        leftPoints != 0 || rightPoints != 0
            || leftGames != 0 || rightGames != 0
            || leftSets != 0 || rightSets != 0
    }
}

private extension BasketballMatchState {
    var hasMeaningfulTimerProgress: Bool {
        let defaultGameTime = gameMode == .threeXThree
            ? 10 * 60
            : BasketballMatchEngine.periodSeconds(ruleSet)
        let defaultShotTime = BasketballMatchEngine.defaultShotSeconds(gameMode)
        return gameTimeSeconds < defaultGameTime
            || shotTimeSeconds < defaultShotTime
            || currentPeriod > 1
            || isOvertime
    }
}

private struct BasketballProgress {
    var scoreOperations = 0
    var timerOperations = 0

    mutating func consume(_ event: BasketballMatchEvent) {
        guard case .stateChanged(_, let intent, _, _) = event else { return }
        switch intent {
        case .addPoints, .adjustScore:
            scoreOperations += 1
        case .tickClock:
            timerOperations += 1
        default:
            break
        }
    }
}

private extension RallyMatchEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .pointScored, .pointsAdjusted, .sideOut, .setCompleted:
            true
        default:
            false
        }
    }
}

private extension TennisMatchEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .pointScored, .gameCompleted, .setCompleted, .adminAdjusted:
            true
        default:
            false
        }
    }
}

private extension LineScoreEvent {
    var isMeaningfulScoreOperation: Bool {
        guard case .scoreChanged = self else { return false }
        return true
    }
}

private extension EightBallEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .rackWon, .ballPotted, .adminAdjusted:
            true
        default:
            false
        }
    }
}

private extension NineBallChaseEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .chaseApplied, .totalsAdjusted:
            true
        default:
            false
        }
    }
}

private extension SnookerEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .potted, .foul, .frameSettled, .adminCorrected:
            true
        default:
            false
        }
    }
}

private extension BoxingMatchEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .pointsAdded, .roundCompleted, .adminAdjusted:
            true
        default:
            false
        }
    }
}

private extension GuandanSessionEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .roundSettlementApplied, .passARecorded:
            true
        default:
            false
        }
    }
}

private extension ShengjiTierEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .tierAdjusted, .administrativeCorrection:
            true
        default:
            false
        }
    }
}

private extension ArcheryMatchEvent {
    var isMeaningfulScoreOperation: Bool {
        switch self {
        case .arrowScored, .arrowMissed, .setCompleted, .arrowSumAdjusted, .setPointsAdjusted:
            true
        default:
            false
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
