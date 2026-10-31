//
//  ScoreboardTab.swift
//  jifen
//
//  计分 Tab：分节（运动 / 棋牌 / 计分）+ 网格图标卡片，对齐鸿蒙 ScoreTab。
//

import SwiftUI
import ScoreCore

struct ScoreboardTab: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.usesExpandedPhoneLayout) private var expandedPhone
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
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        ForEach(ScoreboardCatalogSection.allCases) { section in
                            sectionGroup(
                                title: section.title,
                                items: GameCatalog.scoreboardItems(in: section),
                                availableWidth: max(0, min(proxy.size.width - horizontalInset * 2, expandedPhone ? Theme.expandedPhoneContentMaxWidth : (usesExpandedLayout ? 1080 : .infinity)))
                            )
                        }
                    }
                    // 展开手机参照首页留白；iPad 保留原有目录宽度。
                    .frame(maxWidth: expandedPhone ? Theme.expandedPhoneContentMaxWidth : (usesExpandedLayout ? 1080 : .infinity))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, usesExpandedLayout ? Theme.lg : Theme.md)
                    .padding(.bottom, Theme.tabContentBottomPadding)
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
                CenteredSetupDialogPresenter(
                    item: $pendingSetupSport,
                    alignment: pendingSetupSport?.gameType == .multiScoreboard ? .bottom : .center
                ) { sport, dismiss, maxDialogHeight in
                    scoreboardSetupDialog(
                        for: sport,
                        maxDialogHeight: maxDialogHeight,
                        onConfirm: { result in
                            AppAnalytics.scoreSetupConfirmed(
                                gameType: sport.gameType,
                                setup: result,
                                entryPoint: .scoreTab
                            )
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
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            SectionTitleView(title: title)

            LazyVGrid(columns: gridColumns(availableWidth: availableWidth), spacing: gridSpacing) {
                ForEach(items) { sport in
                    SportCardView(sport: sport) {
                        AppAnalytics.trackContentSelection(
                            contentType: "scoreboard",
                            itemID: sport.gameType.analyticsIdentifier,
                            entryPoint: .scoreTab
                        )
                        pendingSetupSport = sport
                    }
                }
            }
        }
    }

    private var gridSpacing: CGFloat {
        Theme.gridSpacing
    }

    private func gridColumns(availableWidth: CGFloat) -> [GridItem] {
        let count = Theme.catalogColumnCount(availableWidth: availableWidth, usesExpandedLayout: usesExpandedLayout)
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count)
    }

    private var usesExpandedLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var horizontalInset: CGFloat {
        expandedPhone ? Theme.expandedPhonePageInset : Theme.pageHorizontalInset(for: horizontalSizeClass)
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
            analyticsEntryPoint: .scoreTab,
            onSetupConsumed: onSetupConsumed,
            onBack: onBack
        )
    }

    private func navigateToSportAfterSetupDismiss(_ sport: ScoreboardCatalogItem) {
        DispatchQueue.main.async {
            guard pendingSetupSport == nil else { return }
            if selectedSport != nil {
                selectedSport = nil
                DispatchQueue.main.async {
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
        if sport.gameType == .basketballTraining {
            ShotTrainingSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if sport.gameType == .nineBall {
            NineBallSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if Self.isCasualSetupGame(sport.gameType) {
            let defaults = DefaultParticipantNames.resolve(for: sport.gameType)
            MultiScoreSetupDialogView(
                gameType: sport.gameType,
                defaultPlayerCount: Self.casualDefaultPlayerCount(for: sport.gameType),
                defaultTeam1Name: defaults.left,
                defaultTeam2Name: defaults.right,
                initialTargetScore: PreferencesManager.shared.unoTargetScore,
                titleEmoji: sport.emoji,
                titleKey: localizationKey(for: sport.gameType),
                titleFallback: sport.title,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else {
            let defaults = DefaultParticipantNames.resolve(for: sport.gameType)
            SportsSetupDialogView(
                gameType: sport.gameType,
                defaultTeam1Name: defaults.left,
                defaultTeam2Name: defaults.right,
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

    var body: some View {
        Button(action: {
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            VStack(spacing: 10) {
                // 仅放大图案，保留原有占位，避免改变格子尺寸和标题位置。
                AppCatalogIcon(gameType: sport.gameType, fallbackEmoji: sport.emoji, size: 44, artworkSize: 56)

                Text(sport.title)
                    .font(.system(size: Theme.fontBody2))
                    .foregroundColor(Theme.textPrimary)
                    .gridCardTitleStyle()
            }
            .padding(.horizontal, 6)
            // 图标加高 4pt 后纵向 padding 各收 2pt，卡片总高与网格节奏保持不变
            .padding(.vertical, Theme.cardPadding - 2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .background(Theme.appCardBackground)
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
