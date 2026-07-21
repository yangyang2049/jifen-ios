//
//  ScoreboardTab.swift
//  jifen
//
//  计分 Tab：分节（运动 / 棋牌 / 计分）+ 网格图标卡片，对齐鸿蒙 ScoreTab。
//

import SwiftUI
import ScoreCore

struct ScoreboardTab: View {
    @State private var selectedSport: ScoreboardCatalogItem?
    @Binding var selectedGame: GameType?
    var onDismiss: () -> Void = {}

    @State private var pendingSetupSport: ScoreboardCatalogItem?
    @State private var appliedSetupResult: SportsSetupResult?
    @State private var appliedSetupGameType: GameType?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.lg) {
                        ForEach(ScoreboardCatalogSection.allCases) { section in
                            sectionGroup(
                                title: section.title,
                                items: GameCatalog.scoreboardItems(in: section),
                                availableWidth: max(0, proxy.size.width - Theme.padding * 2)
                            )
                        }
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.top, Theme.md)
                    .padding(.bottom, Theme.lg + 56)
                }
                .background(Theme.backgroundColor)
            }
            .navigationTitle(NSLocalizedString("tab_score", comment: "Score"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedSport) { sport in
                getScoreboardView(
                    for: sport.gameType,
                    setupResult: appliedSetupGameType == sport.gameType ? appliedSetupResult : nil,
                    onSetupConsumed: {
                        appliedSetupResult = nil
                        appliedSetupGameType = nil
                    },
                    onBack: { selectedSport = nil }
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .overlay {
                CenteredSetupDialogPresenter(item: $pendingSetupSport) { sport, dismiss, maxDialogHeight in
                    scoreboardSetupDialog(
                        for: sport,
                        maxDialogHeight: maxDialogHeight,
                        onConfirm: { result in
                            appliedSetupResult = result
                            appliedSetupGameType = sport.gameType
                            pendingSetupSport = nil
                            if sport.gameType == .nineBall {
                                selectedSport = sport
                            } else {
                                navigateToSportAfterSetupDismiss(sport)
                            }
                        },
                        onCancel: dismiss
                    )
                }
            }
            .task(id: selectedGame) {
                if let game = selectedGame {
                    if let sport = GameCatalog.scoreboardItems.first(where: { $0.gameType == game }) {
                        // 从首页跳转过来也先展示 setup
                        pendingSetupSport = sport
                    }
                    selectedGame = nil
                }
            }
            .onChange(of: selectedSport) { _, sport in
                if sport == nil { onDismiss() }
            }
        }
        .tint(Theme.accentColor)
    }

    private func sectionGroup(title: String, items: [ScoreboardCatalogItem], availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(title)
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            LazyVGrid(columns: gridColumns(availableWidth: availableWidth), spacing: gridSpacing) {
                ForEach(items) { sport in
                    SportCardView(sport: sport) {
                        pendingSetupSport = sport
                    }
                }
            }
        }
    }

    private var gridSpacing: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 8 : 6
    }

    private func gridColumns(availableWidth: CGFloat) -> [GridItem] {
        let count: Int
        if UIDevice.current.userInterfaceIdiom == .pad {
            count = min(6, max(1, Int((availableWidth + gridSpacing) / (150 + gridSpacing))))
        } else {
            count = availableWidth + Theme.padding * 2 < 360 ? 2 : 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count)
    }

    /// 设置弹窗默认名称：与鸿蒙一致，选手/单方用红方蓝方，队伍用红队蓝队或主队客队。
    private static func defaultTeamNames(for gameType: GameType) -> (String, String) {
        switch gameType {
        case .basketball:
            return (
                NSLocalizedString("team_home", comment: ""),
                NSLocalizedString("team_away", comment: "")
            )
        case .football:
            return (
                NSLocalizedString("team_home", comment: ""),
                NSLocalizedString("team_away", comment: "")
            )
        case .volleyball:
            return (
                NSLocalizedString("red_team", comment: ""),
                NSLocalizedString("blue_team", comment: "")
            )
        case .archery, .boxing, .pingpong, .badminton, .tennis, .billiards, .pickleball, .simpleScore:
            return (
                NSLocalizedString("watch_team_red", value: "红方", comment: ""),
                NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
            )
        case .foosball:
            return (
                NSLocalizedString("player_a", value: "选手A", comment: ""),
                NSLocalizedString("player_b", value: "选手B", comment: "")
            )
        default:
            return (
                NSLocalizedString("red_team", comment: ""),
                NSLocalizedString("blue_team", comment: "")
            )
        }
    }

    @ViewBuilder
    private func getScoreboardView(
        for gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        onSetupConsumed: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) -> some View {
        ScoreboardLaunchView(
            gameType: gameType,
            setupResult: setupResult,
            onSetupConsumed: onSetupConsumed,
            onBack: onBack
        )
    }

    private func navigateToSportAfterSetupDismiss(_ sport: ScoreboardCatalogItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pendingSetupSport == nil else { return }
            if selectedSport != nil {
                selectedSport = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    selectedSport = sport
                }
            } else {
                selectedSport = sport
            }
        }
    }

    @ViewBuilder
    private func scoreboardSetupDialog(
        for sport: ScoreboardCatalogItem,
        maxDialogHeight: CGFloat,
        onConfirm: @escaping (SportsSetupResult) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        if sport.gameType == .nineBall {
            NineBallSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if Self.isCasualSetupGame(sport.gameType) {
            let (t1, t2) = Self.defaultTeamNames(for: sport.gameType)
            MultiScoreSetupDialogView(
                gameType: sport.gameType,
                defaultPlayerCount: Self.casualDefaultPlayerCount(for: sport.gameType),
                defaultTeam1Name: t1,
                defaultTeam2Name: t2,
                initialTargetScore: PreferencesManager.shared.unoTargetScore,
                titleEmoji: sport.emoji,
                titleKey: localizationKey(for: sport.gameType),
                titleFallback: sport.title,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else {
            let (t1, t2) = Self.defaultTeamNames(for: sport.gameType)
            SportsSetupDialogView(
                gameType: sport.gameType,
                defaultTeam1Name: t1,
                defaultTeam2Name: t2,
                initialMaxSets: nil,
                initialPointsPerSet: nil,
                initialTieBreakPoints: nil,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        }
    }

    private static func isCasualSetupGame(_ gameType: GameType) -> Bool {
        [.multiScoreboard, .doudizhu, .uno, .guandan, .shengji, .simpleScore].contains(gameType)
    }

    private static func casualDefaultPlayerCount(for gameType: GameType) -> Int {
        switch gameType {
        case .doudizhu: return 3
        case .uno: return PreferencesManager.shared.unoPlayerCount
        case .multiScoreboard: return PreferencesManager.shared.multiScoreboardPlayerCount
        default: return 4
        }
    }

    private func localizationKey(for gameType: GameType) -> String {
        switch gameType {
        case .doudizhu: return "game_doudizhu"
        case .nineBall: return "game_nine_ball"
        case .uno: return "game_uno"
        case .guandan: return "game_guandan"
        case .shengji: return "game_shengji"
        case .simpleScore: return "game_simple_score"
        default: return "game_multi_scoreboard"
        }
    }

}

struct SportCardView: View {
    let sport: ScoreboardCatalogItem
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            VStack(spacing: 10) {
                Text(sport.emoji)
                    .font(.system(size: 40))

                Text(sport.title)
                    .font(.system(size: Theme.fontBody2))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Theme.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .background {
                if colorScheme == .light {
                    Color.white
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .cornerRadius(Theme.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("scoreboard_catalog_\(sport.gameType.rawValue)")
        .accessibilityLabel(sport.title)
    }
}

#Preview {
    ScoreboardTab(selectedGame: .constant(nil), onDismiss: {})
}
