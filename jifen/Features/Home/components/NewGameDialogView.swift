import SwiftUI

// MARK: - New Game Dialog Tab (对齐鸿蒙：计分 / 计时 两个 Tab)

private enum NewGameDialogTab: String, CaseIterable {
    case score = "score"
    case timer = "timer"

    var title: String {
        switch self {
        case .score: return NSLocalizedString("scoreboard_title", comment: "计分")
        case .timer: return NSLocalizedString("tab_timer", comment: "计时")
        }
    }
}

// MARK: - NewGameDialogView

struct NewGameDialogView: View {
    @Environment(\.dismiss) var dismiss

    var onSelect: ((ActivityType, SourcePage, GameType?) -> Void)?
    var onTimerGameSelected: ((GameType) -> Void)?
    var sourcePage: SourcePage = .home

    @State private var selectedTab: NewGameDialogTab = .score

    /// 计分 Tab：全部计分项目
    private static let scoreGameTypes: [GameType] = GameCatalog.scoreboardGameTypes
    /// 计时 Tab：可选计时项目（不含秒表）
    private static let timerGameTypes: [GameType] = GameCatalog.timerSelectableGameTypes.filter { $0 != .stopwatch }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(NewGameDialogTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.lg)
                .padding(.top, Theme.sm)
                .padding(.bottom, Theme.md)

                GeometryReader { geo in
                    ScrollView {
                        LazyVGrid(columns: gridColumns(for: geo.size.width), spacing: Theme.md) {
                            if selectedTab == .score {
                                ForEach(Self.scoreGameTypes, id: \.self) { gameType in
                                    gameItem(gameType: gameType)
                                }
                            } else {
                                ForEach(Self.timerGameTypes, id: \.self) { gameType in
                                    gameItem(gameType: gameType)
                                }
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func gameItem(gameType: GameType) -> some View {
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
