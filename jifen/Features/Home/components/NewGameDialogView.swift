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
                GeometryReader { geo in
                    ScrollView {
                        LazyVGrid(columns: gridColumns(for: geo.size.width), spacing: Theme.md) {
                            ForEach(GameCatalog.newGameDialogGameTypes, id: \.self) { gameType in
                                Button(action: {
                                    handleGameItemClick(gameType: gameType)
                                }) {
                                    VStack(spacing: 8) {
                                        Text(gameType.icon)
                                            .font(.system(size: 32))
                                        Text(gameType.displayName)
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
        .presentationDetents([.medium, .large])
    }

    private func gridColumns(for containerWidth: CGFloat) -> [GridItem] {
        let horizontalPadding = Theme.lg * 2
        let spacing = Theme.md
        let availableWidth = max(1, containerWidth - horizontalPadding)
        let minItemWidth: CGFloat = 110
        let estimatedCount = Int((availableWidth + spacing) / (minItemWidth + spacing))
        let columnCount = max(3, estimatedCount)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    private func handleGameItemClick(gameType: GameType) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if Set(GameCatalog.timerSelectableGameTypes).contains(gameType) {
                onTimerGameSelected?(gameType)
            } else {
                onSelect?(.scoreboard, sourcePage, gameType)
            }
        }
    }
}
