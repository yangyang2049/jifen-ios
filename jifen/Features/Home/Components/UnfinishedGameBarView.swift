import PersistenceCore
import ScoreCore
import SessionCore
import SwiftUI

struct UnfinishedGameSummary {
    enum Source {
        case legacy(String)
        case session(UUID)
    }

    let source: Source
    let gameType: GameType
    let scoreText: String
    let matchTitle: String

    var recordIdentifier: String {
        switch source {
        case .legacy(let id): id
        case .session(let id): id.uuidString
        }
    }

    init(legacy record: ScoreboardRecord) {
        source = .legacy(record.id)
        gameType = record.gameType
        scoreText = record.displayScore()
        matchTitle = record.displayMatchTitle
    }

    init?(session entry: SessionArchiveEntry) {
        guard let appGameType = GameType(scoreCoreGameType: entry.gameType) else { return nil }
        source = .session(entry.sessionId)
        gameType = appGameType
        matchTitle = Self.matchTitle(participants: entry.participants, gameType: entry.gameType)

        let url = SessionArchiveRepository.defaultRootURL().appendingPathComponent(entry.snapshotPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
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
        default:
            return nil
        }
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
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.22)
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
