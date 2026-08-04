import Foundation
import LinkCore
import ScoreCore

@MainActor
enum SportsSetupWatchSessionLauncher {
    static func start(
        gameType: GameType,
        config: SportsSetupResult,
        using service: PhoneWatchLinkService
    ) async throws -> UUID {
        let coreGameType: ScoreCore.GameType
        let rules: RallyRuleSet
        switch gameType {
        case .pingpong:
            coreGameType = config.isSingles == false ? .pingpongDoubles : .pingpong
            var configured = RallyRuleSet.pingPong(
                maxSets: config.maxSets ?? 5,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf
            )
            let target = max(1, config.pointsPerSet ?? 11)
            configured.pointsToWinSet = target
            configured.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: coreGameType,
                pointsPerSet: target
            )
            configured.autoChangeSides = config.autoChangeSides ?? true
            rules = configured
        case .badminton:
            coreGameType = config.isSingles == false ? .badmintonDoubles : .badminton
            rules = config.badmintonRules
        case .pickleball:
            coreGameType = config.isSingles == false ? .pickleballDoubles : .pickleball
            var configured = RallyRuleSet.pickleball(
                maxSets: config.maxSets ?? 3,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf
            )
            configured.pointsToWinSet = max(1, config.targetScore ?? 11)
            configured.pointCap = config.scoreCap
            configured.winByTwo = config.winByTwo ?? true
            configured.autoChangeSides = config.autoChangeSides ?? true
            configured.useRallyScoring = config.useRallyScoring ?? false
            configured.nextSetServerModel = .alternateFromOpening
            rules = configured
        case .tennis:
            let tennisType: ScoreCore.GameType = config.isSingles == false ? .tennisDoubles : .tennis
            let tennisRules = TennisRuleSet(
                maxSets: config.maxSets ?? 3,
                tieBreakPoints: config.tieBreakPoints == 10 ? 10 : 7,
                gamesPerSet: config.gamesPerSet ?? 6,
                setScoringMode: config.setScoringMode == "tiebreak_only" ? .tiebreakOnly : .regular,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf,
                usesNoAdScoring: config.tennisDeuceMode == "no_ad",
                autoChangeSides: config.autoChangeSides ?? true
            )
            let opening: MatchSide = config.servingSide == MatchSide.right.rawValue ? .right : .left
            let defaultMembers = DefaultParticipantNames.doublesMembers
            let doublesNames: [String]? = config.isSingles == false ? [
                config.team1Player1Name ?? defaultMembers[0],
                config.team2Player1Name ?? defaultMembers[2],
                config.team1Player2Name ?? defaultMembers[1],
                config.team2Player2Name ?? defaultMembers[3]
            ] : nil
            let tennisState = TennisMatchState(
                leftName: config.team1Name,
                rightName: config.team2Name,
                rules: tennisRules,
                openingServer: opening,
                doublesPlayerNames: doublesNames
            )
            let tennisParticipantNames: [String]? = config.isSingles == false
                ? [config.team1Player1Name, config.team2Player1Name, config.team1Player2Name, config.team2Player2Name]
                    .compactMap { $0 }
                : [config.team1Name, config.team2Name]
            return try await service.startInteractiveOnWatch(
                gameType: tennisType,
                state: tennisState,
                participantNames: tennisParticipantNames
            )
        case .archery:
            let archery = LinkedArcheryState(
                leftName: config.team1Name,
                rightName: config.team2Name,
                currentShooterIsLeft: config.servingSide != MatchSide.right.rawValue
            )
            return try await service.startInteractiveOnWatch(
                snapshot: .archery(archery),
                gameType: .archeryDual
            )
        case .eightBall:
            let beneficiary: MatchSide? = config.eightBallHandicapBeneficiary == "team1" ? .left :
                (config.eightBallHandicapBeneficiary == "team2" ? .right : nil)
            let eight = EightBallState.initial(
                targetPoints: config.maxSets ?? 9,
                handicapRacks: config.eightBallHandicapRacks ?? 0,
                handicapBeneficiary: beneficiary
            )
            return try await service.startInteractiveOnWatch(
                snapshot: .eightBall(eight),
                gameType: .eightBall,
                participantNames: [config.team1Name, config.team2Name]
            )
        case .nineBall:
            let nineConfig = NineBallChaseConfig(
                bigGold: config.nineBallBigGold ?? 10,
                smallGold: config.nineBallSmallGold ?? 7,
                goldenNine: config.nineBallGoldenNine ?? 8,
                normalWin: config.nineBallNormalWin ?? 4,
                ballInHand: config.nineBallBallInHand ?? 1,
                foul: config.nineBallFoul ?? 1
            )
            let nine = NineBallChaseState.initial(
                config: nineConfig,
                playerCount: config.playerCount ?? 2,
                playerNames: config.playerNames ?? []
            )
            return try await service.startInteractiveOnWatch(
                snapshot: .nineBall(nine),
                gameType: .nineBall
            )
        case .snooker:
            let snooker = SnookerState.initial(
                striker: config.servingSide == MatchSide.right.rawValue ? .right : .left,
                maxFrames: config.maxSets ?? 1
            )
            return try await service.startInteractiveOnWatch(
                snapshot: .snooker(snooker),
                gameType: .snooker,
                participantNames: [config.team1Name, config.team2Name]
            )
        default:
            throw PhoneWatchLinkService.InteractiveStartError.watchUnavailable
        }

        let openingServer: MatchSide = config.servingSide == MatchSide.right.rawValue ? .right : .left
        let state = RallyMatchEngine.initial(
            leftName: config.team1Name,
            rightName: config.team2Name,
            rules: rules,
            openingServer: openingServer,
            doubles: linkedDoublesState(for: coreGameType, config: config, openingServer: openingServer)
        )
        return try await service.startInteractiveOnWatch(
            gameType: coreGameType,
            state: state,
            participantNames: Self.rallyParticipantNames(for: config, coreGameType: coreGameType)
        )
    }

    private static func rallyParticipantNames(
        for config: SportsSetupResult,
        coreGameType: ScoreCore.GameType
    ) -> [String] {
        if config.isSingles == false {
            let defaultMembers = DefaultParticipantNames.doublesMembers
            return [
                config.team1Player1Name ?? defaultMembers[0],
                config.team2Player1Name ?? defaultMembers[2],
                config.team1Player2Name ?? defaultMembers[1],
                config.team2Player2Name ?? defaultMembers[3]
            ]
        }
        return [config.team1Name, config.team2Name]
    }

    private static func linkedDoublesState(
        for gameType: ScoreCore.GameType,
        config: SportsSetupResult,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        guard config.isSingles == false else { return nil }
        let defaultMembers = DefaultParticipantNames.doublesMembers
        let names = [
            config.team1Player1Name ?? defaultMembers[0],
            config.team2Player1Name ?? defaultMembers[2],
            config.team1Player2Name ?? defaultMembers[1],
            config.team2Player2Name ?? defaultMembers[3]
        ]
        switch gameType {
        case .pingpongDoubles:
            return .pingPong(
                playerNames: names,
                openingServerSlotIndex: openingServer == .left ? 0 : 1,
                openingReceiverSlotIndex: openingServer == .left ? 3 : 2
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        default:
            return nil
        }
    }
}
