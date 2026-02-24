//
//  ScoreboardTab.swift
//  jifen
//
//  计分 Tab：分节（运动 / 棋牌 / 计分）+ 网格图标卡片，对齐鸿蒙 ScoreTab。
//

import SwiftUI

struct ScoreboardTab: View {
    @State private var selectedSport: ScoreboardCatalogItem?
    @Binding var selectedGame: GameType?
    var onDismiss: () -> Void = {}

    @State private var pendingSetupSport: ScoreboardCatalogItem?
    @State private var appliedSetupResult: SportsSetupResult?
    @State private var appliedSetupGameType: GameType?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    sectionGroup(title: ScoreboardCatalogSection.sports.title, items: GameCatalog.scoreboardItems(in: .sports))
                    sectionGroup(title: ScoreboardCatalogSection.boardGames.title, items: GameCatalog.scoreboardItems(in: .boardGames))
                    sectionGroup(title: ScoreboardCatalogSection.scoring.title, items: GameCatalog.scoreboardItems(in: .scoring))
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, Theme.md)
                .padding(.bottom, Theme.lg)
            }
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("tab_score", comment: "Score"))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
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
            .sheet(item: $pendingSetupSport) { sport in
                if sport.gameType == .multiScoreboard || sport.gameType == .doudizhu {
                    let isDoudizhu = sport.gameType == .doudizhu
                    MultiScoreSetupDialogView(
                        defaultPlayerCount: isDoudizhu ? 3 : 4,
                        titleEmoji: isDoudizhu ? "🃏" : "👥",
                        titleKey: isDoudizhu ? "game_doudizhu" : "game_multi_scoreboard",
                        titleFallback: isDoudizhu ? "斗地主" : "多人计分",
                        fixedPlayerCount: isDoudizhu ? 3 : nil,
                        onConfirm: { result in
                            appliedSetupResult = result
                            appliedSetupGameType = sport.gameType
                            pendingSetupSport = nil
                            navigateToSportAfterSheetDismiss(sport)
                        },
                        onCancel: {
                            pendingSetupSport = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    let (t1, t2) = Self.defaultTeamNames(for: sport.gameType)
                    SportsSetupDialogView(
                        gameType: sport.gameType,
                        defaultTeam1Name: t1,
                        defaultTeam2Name: t2,
                        initialMaxSets: nil,
                        initialPointsPerSet: nil,
                        initialTieBreakPoints: nil,
                        onConfirm: { result in
                            appliedSetupResult = result
                            appliedSetupGameType = sport.gameType
                            pendingSetupSport = nil
                            navigateToSportAfterSheetDismiss(sport)
                        },
                        onCancel: {
                            pendingSetupSport = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
        .accentColor(Theme.accentColor)
    }

    private func sectionGroup(title: String, items: [ScoreboardCatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(title)
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.spacing),
                GridItem(.flexible(), spacing: Theme.spacing),
                GridItem(.flexible(), spacing: Theme.spacing)
            ], spacing: Theme.spacing) {
                ForEach(items) { sport in
                    SportCardView(sport: sport) {
                        pendingSetupSport = sport
                    }
                }
            }
        }
    }

    private static func defaultTeamNames(for gameType: GameType) -> (String, String) {
        if gameType == .basketball {
            return (
                NSLocalizedString("team_home", comment: ""),
                NSLocalizedString("team_away", comment: "")
            )
        }
        return (
            NSLocalizedString("red_team", comment: ""),
            NSLocalizedString("blue_team", comment: "")
        )
    }

    @ViewBuilder
    private func getScoreboardView(
        for gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        onSetupConsumed: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) -> some View {
        switch gameType {
        case .pingpong:
            PingPongScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .badminton:
            BadmintonScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .tennis:
            TennisScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .basketball:
            BasketballScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .football:
            FootballScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .volleyball:
            VolleyballScoreboardView(showBackButton: false, onNavigationBack: onBack, initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .archery:
            ArcheryScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .boxing:
            BoxingScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .billiards:
            BilliardsScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .pickleball:
            PickleballScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .guandan:
            GuandanScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .doudizhu:
            DoudizhuScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .simpleScore:
            SimpleScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .multiScoreboard:
            MultiScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        case .counter:
            SimpleScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
        default:
            Text(NSLocalizedString("not_implemented", comment: ""))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private func navigateToSportAfterSheetDismiss(_ sport: ScoreboardCatalogItem) {
        // Avoid triggering landscape lock while setup sheet is still dismissing,
        // which can cause a visible double rotation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard pendingSetupSport == nil else { return }
            selectedSport = sport
        }
    }

}

struct SportCardView: View {
    let sport: ScoreboardCatalogItem
    let action: () -> Void

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
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ScoreboardTab(selectedGame: .constant(nil), onDismiss: {})
}
