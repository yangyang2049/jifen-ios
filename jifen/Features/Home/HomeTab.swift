//
//  HomeTab.swift
//  jifen
//
//  Simplified home tab - clean and focused
//

import SwiftUI
import Combine

struct HomeTab: View {
    var onNavigateToTab: ((Int, GameType?) -> Void)? = nil

    @State private var recentActivities: [RecentActivity] = []
    @State private var showNewGameDialog = false
    @State private var showQuickStartEditSheet = false
    @State private var showSettingsSheet = false
    @State private var path = NavigationPath()

    // Navigation back handler for scoreboard views
    private func navigateBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    @State private var headerDate = ""
    @StateObject private var quickStartManager = QuickStartConfigManager.shared
    @ObservedObject private var scoreboardVM = ScoreboardRecordsViewModel.shared

    enum NavigationDestination: Hashable {
        case tool(ToolItem)
        case scoreboard(GameType)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.lg) {
                    buildHeader()
                    buildContent()
                }
                .padding(.horizontal, Theme.lg)
            }
            .background(Theme.backgroundColor)
            .navigationBarHidden(true)
            .sheet(isPresented: $showQuickStartEditSheet) {
                QuickStartEditView(
                    isDarkTheme: true,
                    initialPrimary: quickStartManager.quickStartConfig.primarySport,
                    initialSecondary: quickStartManager.quickStartConfig.secondarySport,
                    onSave: { primary, secondary in
                        Task {
                            try? await quickStartManager.setPrimarySport(primary)
                            try? await quickStartManager.setSecondarySport(secondary)
                        }
                    }
                )
            }
            .sheet(isPresented: $showNewGameDialog) {
                NewGameDialogView(
                    onSelect: { type, source, gameType in
                        if type == .scoreboard, let gameType = gameType {
                            path.append(NavigationDestination.scoreboard(gameType))
                        }
                    }
                )
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .tool(let tool):
                    tool.view.navigationTitle(tool.title)
                case .scoreboard(let gameType):
                    getScoreboardView(for: gameType)
                }
            }
            .onChange(of: path) { oldPath, newPath in
                // Unlock orientation when navigating away from scoreboard
                if oldPath.count > newPath.count {
                    OrientationLock.shared.unlock()
                }
            }
        }
        .onAppear {
            loadData()
            quickStartManager.loadConfig(isLargeScreen: false, is2in1: false)
            // Refresh records when view appears
            updateRecentActivities()
        }
        .onReceive(scoreboardVM.objectWillChange) { _ in
            updateRecentActivities()
        }
    }

    // MARK: - Private Methods

    private func loadData() {
        updateHeaderDate()
    }



    private func updateHeaderDate() {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale.current
        weekdayFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEE", options: 0, locale: Locale.current)

        headerDate = "\(dateFormatter.string(from: now))  \(weekdayFormatter.string(from: now))"
    }

    private func updateRecentActivities() {
        let records = ScoreboardRecordManager.shared.loadAllRecords()
        print("[HomeTab] 📊 Loading \(records.count) total records for recent activities")

        // Show up to 3 most recent game records
        let recentRecords = records.prefix(3)
        print("[HomeTab] 📋 Showing \(recentRecords.count) recent records")

        recentActivities = recentRecords.map { record in
            print("[HomeTab] 🎮 Record: \(record.id) - \(record.gameType.rawValue) - \(record.team1FinalScore):\(record.team2FinalScore)")
            return RecentActivity(
                id: record.id,
                activityType: .scoreboard,
                gameType: record.gameType,
                timestamp: record.startTime.timeIntervalSince1970,
                title: "\(record.team1Name) vs \(record.team2Name)",
                description: "\(record.team1FinalScore) : \(record.team2FinalScore)"
            )
        }
    }

    @ViewBuilder
    private func getScoreboardView(for gameType: GameType) -> some View {
        switch gameType {
        case .pingpong:
            PingPongScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        case .badminton:
            BadmintonScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        case .tennis:
            TennisScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        case .basketball:
            BasketballScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        case .football:
            FootballScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        case .volleyball:
            VolleyballScoreboardView(showBackButton: false, onNavigationBack: navigateBack)
                .toolbar(.hidden, for: .tabBar)
        default:
            // Unsupported scoreboard games - this shouldn't happen since NewGameDialogView only shows supported games
            Text("Game not supported")
                .foregroundColor(.white)
        }
    }
    // MARK: - @ViewBuilder Layouts

    @ViewBuilder
    private func buildHeader() -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("app_name", comment: "App Name"))
                    .font(.system(size: Theme.fontH4, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.bottom, 2)

                Text(headerDate)
                    .font(.system(size: Theme.fontCaption, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            .layoutPriority(1)

            Spacer()

            Button(action: { showSettingsSheet = true }) {
                Image(systemName: "gear")
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
    }

    @ViewBuilder
    private func buildContent() -> some View {
        VStack(spacing: Theme.lg) {
            QuickStartGridView(
                primarySport: quickStartManager.quickStartConfig.primarySport,
                secondarySport: quickStartManager.quickStartConfig.secondarySport,
                isDarkTheme: true,
                onPrimaryClick: { gameType in
                    if [.tennis, .pingpong, .badminton, .basketball, .football, .volleyball].contains(gameType) {
                        onNavigateToTab?(1, gameType)
                    }
                },
                onSecondaryClick: { gameType in
                    if [.tennis, .pingpong, .badminton, .basketball, .football, .volleyball].contains(gameType) {
                        onNavigateToTab?(1, gameType)
                    }
                },
                onNewGameClick: { showNewGameDialog = true },
                onEditClick: { showQuickStartEditSheet = true }
            )

            ProToolsSectionView(
                isWide: false,
                isDarkTheme: true,
                onToolClick: { toolId in
                    if let tool = ToolItem.allTools.first(where: { $0.id == toolId }) {
                        path.append(NavigationDestination.tool(tool))
                    }
                }
            )

            VStack(alignment: .leading, spacing: Theme.md) {
                Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                RecentRecordsSectionView(
                    records: recentActivities,
                    isDarkTheme: true,
                    onViewAllTapped: { onNavigateToTab?(2, nil) }
                )
            }
        }
    }
}

#Preview {
    HomeTab()
}
