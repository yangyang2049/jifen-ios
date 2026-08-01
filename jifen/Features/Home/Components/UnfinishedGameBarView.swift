import LinkCore
import PersistenceCore
import ScoreCore
import SessionCore
import SwiftUI

struct UnfinishedGameSummary {
    enum Source {
        case resume(UUID)
        case linked(UUID)
    }

    let source: Source
    let gameType: GameType
    let scoreText: String
    let matchTitle: String
    let linkStatusText: String?
    let linkedSetupResult: SportsSetupResult?

    var recordIdentifier: String {
        switch source {
        case .resume(let id): id.uuidString
        case .linked(let id): id.uuidString
        }
    }

    init?(session entry: ResumeSessionSummary) {
        guard let appGameType = GameType(scoreCoreGameType: entry.gameType) else { return nil }
        source = .resume(entry.sessionId)
        gameType = appGameType
        matchTitle = Self.matchTitle(participants: entry.participants, gameType: entry.gameType)
        linkStatusText = nil
        linkedSetupResult = nil

        let url = ResumeSessionRepository.defaultRootURL().appendingPathComponent(entry.snapshotPath)
        guard let envelopeData = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(
                ResumeSessionEnvelope.self,
                from: envelopeData
              ) else { return nil }
        if envelope.payloadKind == .manualState {
            scoreText = envelope.scoreSummary
            return
        }
        let data = envelope.payload
        switch entry.gameType {
        case .basketball, .threeBasketball:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<BasketballMatchState, BasketballMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            scoreText = "\(session.state.leftScore) : \(session.state.rightScore)"
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<RallyMatchState, RallyMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            scoreText = session.state.leftSets > 0 || session.state.rightSets > 0
                ? "\(session.state.leftSets) : \(session.state.rightSets)"
                : "\(session.state.leftPoints) : \(session.state.rightPoints)"
        case .tennis, .tennisDoubles:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<TennisMatchState, TennisMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            scoreText = "\(session.state.leftSets) : \(session.state.rightSets)"
        case .eightBall:
            guard let bundle = try? JSONDecoder().decode(
                ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self,
                from: data
            ) else { return nil }
            scoreText = "\(bundle.currentSession.state.leftPoints) : \(bundle.currentSession.state.rightPoints)"
        case .nineBall:
            guard let bundle = try? JSONDecoder().decode(
                ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>.self,
                from: data
            ) else { return nil }
            scoreText = bundle.currentSession.state.playerPoints
                .prefix(bundle.currentSession.state.playerCount)
                .map(String.init)
                .joined(separator: " : ")
        case .snooker:
            guard let bundle = try? JSONDecoder().decode(
                ScoreSessionResumeBundle<SnookerState, SnookerEvent, SnookerIntent>.self,
                from: data
            ) else { return nil }
            let state = bundle.currentSession.state
            scoreText = state.maxFrames > 1
                ? "\(state.leftFrames) : \(state.rightFrames)"
                : "\(state.leftScore) : \(state.rightScore)"
        case .archeryDual:
            guard let session = try? JSONDecoder().decode(
                ScoreSession<ArcheryMatchState, ArcheryMatchEvent>.self,
                from: data
            ) else { return nil }
            scoreText = session.state.leftSetPoints > 0 || session.state.rightSetPoints > 0
                ? "\(session.state.leftSetPoints) : \(session.state.rightSetPoints)"
                : "\(session.state.leftArrowSum) : \(session.state.rightArrowSum)"
        default:
            return nil
        }
    }

    init?(linked descriptor: PhoneWatchLinkService.LinkedResumeDescriptor) {
        guard let appGameType = GameType(scoreCoreGameType: descriptor.gameType) else {
            return nil
        }
        source = .linked(descriptor.handle.sessionId)
        gameType = appGameType
        let names = descriptor.setup.participantNames

        switch descriptor.snapshot {
        case .rally(let state):
            scoreText = state.leftSets > 0 || state.rightSets > 0
                ? "\(state.leftSets) : \(state.rightSets)"
                : "\(state.leftPoints) : \(state.rightPoints)"
            matchTitle = Self.racketMatchTitle(
                leftName: state.leftName,
                rightName: state.rightName,
                doublesNames: state.doubles?.playerNames
            )
        case .tennis(let state):
            scoreText = "\(state.leftSets) : \(state.rightSets)"
            matchTitle = Self.racketMatchTitle(
                leftName: state.leftName,
                rightName: state.rightName,
                doublesNames: state.doublesPlayerNames
            )
        case .archery(let state):
            scoreText = state.leftSetPoints > 0 || state.rightSetPoints > 0
                ? "\(state.leftSetPoints) : \(state.rightSetPoints)"
                : "\(state.leftArrowSum) : \(state.rightArrowSum)"
            matchTitle = "\(state.leftName) vs \(state.rightName)"
        case .eightBall(let state):
            scoreText = "\(state.leftPoints) : \(state.rightPoints)"
            matchTitle = Self.namesTitle(names)
        case .nineBall(let state):
            scoreText = state.playerPoints.prefix(state.playerCount)
                .map(String.init)
                .joined(separator: " : ")
            matchTitle = (0..<state.playerCount)
                .map { state.resolvedName(at: $0) }
                .joined(separator: " · ")
        case .snooker(let state):
            scoreText = state.maxFrames > 1
                ? "\(state.leftFrames) : \(state.rightFrames)"
                : "\(state.leftScore) : \(state.rightScore)"
            matchTitle = Self.namesTitle(names)
        }

        let authority = descriptor.role == .phoneController
            ? NSLocalizedString("linked_score_phone_controller", value: "手机主控", comment: "")
            : NSLocalizedString("linked_score_watch_controller", value: "手表主控", comment: "")
        let connection: String
        if descriptor.watchBackgrounded {
            connection = NSLocalizedString("linked_score_interrupted", value: "已中断", comment: "")
        } else if descriptor.isReachable {
            connection = NSLocalizedString("linked_score_connected", value: "已连接", comment: "")
        } else {
            connection = NSLocalizedString("linked_score_disconnected", value: "已断开", comment: "")
        }
        linkStatusText = "\(authority) · \(connection)"
        linkedSetupResult = Self.linkedSetupResult(descriptor)
    }

    static func matchTitle(
        participants: [SessionParticipant],
        gameType: ScoreCore.GameType
    ) -> String {
        let nonemptyName: (SessionParticipant) -> String? = { participant in
            let name = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        let doublesTypes: Set<ScoreCore.GameType> = [
            .pingpongDoubles, .badmintonDoubles, .tennisDoubles,
            .pickleballDoubles, .foosballDoubles
        ]

        if doublesTypes.contains(gameType) {
            var namesByID: [String: String] = [:]
            for participant in participants {
                if let name = nonemptyName(participant) {
                    // Tolerate malformed legacy snapshots that reused a slot ID.
                    namesByID[participant.id] = name
                }
            }
            let left = [namesByID["left-top"], namesByID["left-bottom"]].compactMap { $0 }
            let right = [namesByID["right-top"], namesByID["right-bottom"]].compactMap { $0 }
            if !left.isEmpty, !right.isEmpty {
                return "\(left.joined(separator: "/")) vs \(right.joined(separator: "/"))"
            }

            let names = participants.compactMap(nonemptyName)
            if names.count >= 4 {
                return "\(names[0])/\(names[2]) vs \(names[1])/\(names[3])"
            }
        }

        let names = participants.compactMap(nonemptyName)
        return names.count >= 2 ? "\(names[0]) vs \(names[1])" : names.joined(separator: " vs ")
    }

    private static func racketMatchTitle(
        leftName: String,
        rightName: String,
        doublesNames: [String]?
    ) -> String {
        guard let doublesNames, doublesNames.count >= 4 else {
            return "\(leftName) vs \(rightName)"
        }
        return "\(doublesNames[0])/\(doublesNames[2]) vs \(doublesNames[1])/\(doublesNames[3])"
    }

    private static func namesTitle(_ names: [String]) -> String {
        let trimmed = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return trimmed.count >= 2
            ? "\(trimmed[0]) vs \(trimmed[1])"
            : trimmed.joined(separator: " vs ")
    }

    private static func linkedSetupResult(
        _ descriptor: PhoneWatchLinkService.LinkedResumeDescriptor
    ) -> SportsSetupResult {
        let fallbackNames = descriptor.setup.participantNames
        var result = SportsSetupResult(
            team1Name: fallbackNames.first ?? "",
            team2Name: fallbackNames.dropFirst().first ?? ""
        )
        result.linkedWatchSessionId = descriptor.handle.sessionId
        result.startOnWatch = descriptor.role == .phoneFollower
        result.isSingles = !descriptor.gameType.isDoublesScoreboard

        switch descriptor.snapshot {
        case .rally(let state):
            result.team1Name = state.leftName
            result.team2Name = state.rightName
            result.maxSets = state.rules.maxSets
            result.matchCompletionMode = state.rules.matchCompletionMode
            result.pointsPerSet = state.rules.pointsToWinSet
            result.targetScore = state.rules.pointsToWinSet
            result.winByTwo = state.rules.winByTwo
            result.scoreCap = state.rules.pointCap
            result.autoChangeSides = state.rules.autoChangeSides
            result.useRallyScoring = state.rules.useRallyScoring
            result.servingSide = state.openingServerSide.rawValue
            if let names = state.doubles?.playerNames, names.count >= 4 {
                result.team1Player1Name = names[0]
                result.team2Player1Name = names[1]
                result.team1Player2Name = names[2]
                result.team2Player2Name = names[3]
            }
        case .tennis(let state):
            result.team1Name = state.leftName
            result.team2Name = state.rightName
            result.maxSets = state.rules.maxSets
            result.matchCompletionMode = state.rules.matchCompletionMode
            result.tieBreakPoints = state.rules.tieBreakPoints
            result.gamesPerSet = state.rules.gamesPerSet
            result.setScoringMode = state.rules.setScoringMode.rawValue
            result.tennisDeuceMode = state.rules.usesNoAdScoring ? "no_ad" : "advantage"
            result.autoChangeSides = state.rules.autoChangeSides
            result.servingSide = state.openingServerSide.rawValue
            if let names = state.doublesPlayerNames, names.count >= 4 {
                result.team1Player1Name = names[0]
                result.team2Player1Name = names[1]
                result.team1Player2Name = names[2]
                result.team2Player2Name = names[3]
            }
        case .archery(let state):
            result.team1Name = state.leftName
            result.team2Name = state.rightName
            result.servingSide = state.openingShooterIsLeft ? "left" : "right"
        case .eightBall(let state):
            result.maxSets = state.targetPoints
            result.eightBallHandicapRacks = state.handicapRacks
            result.eightBallHandicapBeneficiary = state.handicapBeneficiary == .left
                ? "team1"
                : (state.handicapBeneficiary == .right ? "team2" : "none")
        case .nineBall(let state):
            result.playerCount = state.playerCount
            result.playerNames = (0..<state.playerCount).map {
                state.resolvedName(at: $0)
            }
            result.nineBallBigGold = state.config.bigGold
            result.nineBallSmallGold = state.config.smallGold
            result.nineBallGoldenNine = state.config.goldenNine
            result.nineBallNormalWin = state.config.normalWin
            result.nineBallBallInHand = state.config.ballInHand
            result.nineBallFoul = state.config.foul
        case .snooker(let state):
            result.maxSets = state.maxFrames
            result.servingSide = state.firstBreaker.rawValue
        }
        return result
    }
}

struct UnfinishedGameBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let record: UnfinishedGameSummary
    var isClosePending = false
    var onContinue: () -> Void
    var onClose: () -> Void

    private let barPadding: CGFloat = 8
    private let closeButtonGap: CGFloat = 12
    private let iconSize: CGFloat = 52

    private var barHeight: CGFloat {
        barPadding + iconSize + barPadding
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(record.gameType.icon)
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(iconBackgroundColor)
                    .clipShape(Circle())
                    .padding(.trailing, 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayScore)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.homeNeutralCardTextPrimary)
                        .lineLimit(1)

                    Text(record.matchTitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.homeNeutralCardTextSecondary)
                        .lineLimit(1)

                    if let status = record.linkStatusText {
                        Text(status)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.primary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onContinue)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isClosePending ? .white : Theme.homeNeutralCardTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(closeButtonBackgroundColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, closeButtonGap)
            .accessibilityLabel(
                isClosePending
                    ? NSLocalizedString("unfinished_abandon_confirm", value: "再点击一次丢弃比赛", comment: "")
                    : NSLocalizedString("unfinished_discard_button", value: "放弃", comment: "")
            )

            Button(action: onContinue) {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.textOnPrimary)
                    .frame(width: iconSize, height: iconSize)
                    .background(Theme.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(barPadding)
        .frame(height: barHeight)
        .background(Theme.homeNeutralCardBackground)
        .clipShape(Capsule())
        .shadow(color: shadowColor, radius: 8, x: 0, y: 0)
        .animation(.easeInOut(duration: 0.2), value: isClosePending)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .clear : Color.black.opacity(0.22)
    }

    private var closeButtonBackgroundColor: Color {
        if isClosePending {
            return Color(uiColor: .systemRed)
        }
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.12)
            }
            return .tertiarySystemFill
        })
    }

    private var iconBackgroundColor: Color {
        (getGameGradient(type: record.gameType).first ?? Color(hex: "#71717A")).opacity(0.5)
    }

    private var displayScore: String {
        record.scoreText
    }
}

struct UnfinishedGameDiscardToast: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(NSLocalizedString("unfinished_abandon_confirm", value: "再点击一次丢弃比赛", comment: ""))
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.homeNeutralCardTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.homeNeutralCardBackground)
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 4, x: 0, y: -2)
    }

    private var shadowColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.1)
    }
}
