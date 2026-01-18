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

    @State private var headerDate = ""
    @StateObject private var quickStartManager = QuickStartConfigManager.shared
    @ObservedObject private var scoreboardVM = ScoreboardRecordsViewModel.shared

    enum NavigationDestination: Hashable {
        case tool(ToolItem)
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
                        if type == .scoreboard {
                            onNavigateToTab?(1, gameType)
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
                }
            }
        }
        .onAppear {
            loadData()
            quickStartManager.loadConfig(isLargeScreen: false, is2in1: false)
        }
        .onReceive(scoreboardVM.objectWillChange) { _ in
            updateRecentActivities()
        }
    }

    // MARK: - Private Methods

    private func loadData() {
        updateHeaderDate()
        updateRecentActivities()
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
        let records = scoreboardVM.getRecords()
        recentActivities = records.prefix(5).map { record in
            RecentActivity(
                id: record.id,
                activityType: .scoreboard,
                gameType: record.gameType,
                timestamp: record.timestamp,
                title: "\(record.team1Name) vs \(record.team2Name)",
                description: "\(record.team1FinalScore) : \(record.team2FinalScore)"
            )
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

                RecentRecordsSectionView(records: recentActivities, isDarkTheme: true)
            }
        }
    }
}

#Preview {
    HomeTab()
}
