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
        let names = entry.participants.map(\.name).filter { !$0.isEmpty }
        source = .session(entry.sessionId)
        gameType = appGameType
        matchTitle = names.count >= 2 ? "\(names[0]) vs \(names[1])" : names.joined(separator: " vs ")

        let url = SessionArchiveRepository.defaultRootURL().appendingPathComponent(entry.snapshotPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        switch entry.gameType {
        case .basketball, .threeBasketball:
            guard let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: data) else { return nil }
            scoreText = "\(session.state.leftScore) : \(session.state.rightScore)"
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            guard let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data) else { return nil }
            scoreText = session.state.leftSets > 0 || session.state.rightSets > 0
                ? "\(session.state.leftSets) : \(session.state.rightSets)"
                : "\(session.state.leftPoints) : \(session.state.rightPoints)"
        default:
            return nil
        }
    }
}

struct UnfinishedGameBarView: View {
    let record: UnfinishedGameSummary
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
                    .foregroundColor(Theme.homeNeutralCardTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(closeButtonBackgroundColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, closeButtonGap)

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
        .overlay(
            Capsule()
                .stroke(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.22), radius: 8, x: 0, y: 0)
    }

    private var closeButtonBackgroundColor: Color {
        Color(uiColor: UIColor { traits in
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
