import SwiftUI

// MARK: - NewGameDialogView

struct NewGameDialogView: View {
    @Environment(\.dismiss) var dismiss

    var onSelect: ((ActivityType, SourcePage, GameType?) -> Void)?
    var onTimerGameSelected: ((GameType) -> Void)?
    var sourcePage: SourcePage = .home

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Game Grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: Theme.md),
                        GridItem(.flexible(), spacing: Theme.md)
                    ], spacing: Theme.md) {
                        ForEach(getScoreboardItems()) { item in
                            Button(action: {
                                handleGameItemClick(item: item)
                            }) {
                                VStack(spacing: 8) {
                                    Text(item.emoji)
                                        .font(.system(size: 32))
                                    Text(NSLocalizedString(item.nameKey, comment: ""))
                                        .font(.system(size: Theme.fontBody2, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .padding(.vertical, Theme.md)
                                .padding(.horizontal, Theme.sm)
                                .background(Theme.surface.opacity(0.5))
                                .cornerRadius(Theme.md)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.md)
                }
            }
            .background(Color.clear)
            .navigationTitle(NSLocalizedString("dialog_new_game_title", comment: "New Game"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func getScoreboardItems() -> [GameItem] {
        return [
            GameItem(type: .basketball, nameKey: "game_basketball", emoji: GameType.basketball.icon, route: "BasketballScoreboard"),
            GameItem(type: .badminton, nameKey: "game_badminton", emoji: GameType.badminton.icon, route: "BadmintonScoreboard"),
            GameItem(type: .pingpong, nameKey: "game_pingpong", emoji: GameType.pingpong.icon, route: "PingPongScoreboard"),
            GameItem(type: .tennis, nameKey: "game_tennis", emoji: GameType.tennis.icon, route: "TennisScoreboard"),
            GameItem(type: .volleyball, nameKey: "game_volleyball", emoji: GameType.volleyball.icon, route: "VolleyballScoreboard"),
            GameItem(type: .football, nameKey: "game_football", emoji: GameType.football.icon, route: "FootballScoreboard"),
        ]
    }



    private func handleGameItemClick(item: GameItem) {
        let gameType = item.type

        // Navigate for all supported games (tennis, pingpong, badminton, basketball, football, volleyball)
        let supportedGames: [GameType] = [.tennis, .pingpong, .badminton, .basketball, .football, .volleyball]

        if supportedGames.contains(gameType) {
            // Close modal and navigate to scoreboard
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onSelect?(.scoreboard, sourcePage, gameType)
            }
        } else {
            // For unsupported games, just close modal (no navigation)
            dismiss()
        }
    }


}
