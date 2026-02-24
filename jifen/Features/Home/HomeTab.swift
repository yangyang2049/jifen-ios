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
    @State private var upcomingBookings: [LocalBooking] = []
    @State private var unfinishedRecord: ScoreboardRecord?
    @State private var showNewGameDialog = false
    @State private var showQuickStartEditSheet = false
    @State private var showSettingsSheet = false
    @State private var showDiscardUnfinishedAlert = false
    @State private var showCreateBookingSheet = false
    @State private var path = NavigationPath()
    /// When user selects a scoreboard game from New Game or Quick Start, show setup first for supported sports.
    @State private var pendingScoreboardSetupItem: ScoreboardSetupItem? = nil
    @State private var appliedSetupResult: SportsSetupResult? = nil
    @State private var appliedSetupGameType: GameType? = nil

    // Navigation back handler for scoreboard views
    private func navigateBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    @State private var headerDate = ""
    @StateObject private var quickStartManager = QuickStartConfigManager.shared
    @ObservedObject private var scoreboardVM = ScoreboardRecordsViewModel.shared

    struct ScoreboardNavigationTarget: Hashable {
        let gameType: GameType
        let recordId: String?
    }

    enum NavigationDestination: Hashable {
        case tool(ToolItem)
        case scoreboard(ScoreboardNavigationTarget)
        case toolsList
        case schedule
    }

    /// 与鸿蒙 HomeTab.ets 一致：屏幕宽度 >= 768 时使用两栏布局
    private let wideLayoutThreshold: CGFloat = 768

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let isWide = geo.size.width >= wideLayoutThreshold
                let contentWidth = geo.size.width - Theme.lg * 2
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.lg) {
                        buildHeader()
                        buildContent(isWide: isWide, contentWidth: contentWidth)
                    }
                    .padding(.horizontal, Theme.lg)
                }
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
                            // 所有计分项目均先展示 setup（至少输入名字）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                            }
                        }
                    },
                    onTimerGameSelected: { gameType in
                        onNavigateToTab?(3, gameType)
                    }
                )
            }
            .sheet(item: $pendingScoreboardSetupItem) { item in
                if item.gameType == .multiScoreboard || item.gameType == .doudizhu {
                    let isDoudizhu = item.gameType == .doudizhu
                    MultiScoreSetupDialogView(
                        defaultPlayerCount: isDoudizhu ? 3 : 4,
                        titleEmoji: isDoudizhu ? "🃏" : "👥",
                        titleKey: isDoudizhu ? "game_doudizhu" : "game_multi_scoreboard",
                        titleFallback: isDoudizhu ? "斗地主" : "多人计分",
                        fixedPlayerCount: isDoudizhu ? 3 : nil,
                        onConfirm: { result in
                            appliedSetupResult = result
                            appliedSetupGameType = item.gameType
                            pendingScoreboardSetupItem = nil
                            path.append(
                                NavigationDestination.scoreboard(
                                    ScoreboardNavigationTarget(gameType: item.gameType, recordId: nil)
                                )
                            )
                        },
                        onCancel: {
                            pendingScoreboardSetupItem = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    let (t1, t2) = Self.defaultTeamNames(for: item.gameType)
                    SportsSetupDialogView(
                        gameType: item.gameType,
                        defaultTeam1Name: t1,
                        defaultTeam2Name: t2,
                        initialMaxSets: nil,
                        initialPointsPerSet: nil,
                        initialTieBreakPoints: nil,
                        onConfirm: { result in
                            appliedSetupResult = result
                            appliedSetupGameType = item.gameType
                            pendingScoreboardSetupItem = nil
                            path.append(
                                NavigationDestination.scoreboard(
                                    ScoreboardNavigationTarget(gameType: item.gameType, recordId: nil)
                                )
                            )
                        },
                        onCancel: {
                            pendingScoreboardSetupItem = nil
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
            .sheet(isPresented: $showCreateBookingSheet) {
                CreateBookingPage {
                    loadUpcomingBookings()
                    DispatchQueue.main.async {
                        path.append(NavigationDestination.schedule)
                    }
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .tool(let tool):
                    tool.view
                        .navigationTitle(tool.title)
                        .toolbar(.hidden, for: .tabBar)
                case .scoreboard(let target):
                    getScoreboardView(
                        for: target.gameType,
                        setupResult: appliedSetupGameType == target.gameType ? appliedSetupResult : nil,
                        initialRecordId: target.recordId,
                        onSetupConsumed: {
                            appliedSetupResult = nil
                            appliedSetupGameType = nil
                        }
                    )
                case .toolsList:
                    ToolsListPageView(onToolTap: { path.append($0) })
                        .toolbar(.hidden, for: .tabBar)
                case .schedule:
                    SchedulePage(
                        onStartGame: { gameType in
                            pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                        },
                        onChanged: {
                            loadUpcomingBookings()
                        }
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
            }
            .navigationDestination(for: ToolItem.self) { tool in
                tool.view
                    .navigationTitle(tool.title)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let unfinishedRecord {
                HStack {
                    Spacer(minLength: 0)
                    UnfinishedGameBarView(
                        record: unfinishedRecord,
                        onContinue: { continueUnfinishedGame() },
                        onClose: { showDiscardUnfinishedAlert = true }
                    )
                    .frame(maxWidth: 400)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.sm)
                .padding(.bottom, Theme.sm)
                .background(Color.clear)
            }
        }
        .alert(
            NSLocalizedString("unfinished_discard_title", value: "放弃未完成比赛", comment: ""),
            isPresented: $showDiscardUnfinishedAlert
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("unfinished_discard_button", value: "放弃", comment: "放弃未完成比赛弹窗的确定按钮"), role: .destructive) {
                discardUnfinishedGame()
            }
        } message: {
            Text(NSLocalizedString("unfinished_discard_message", value: "确认放弃当前未完成比赛？", comment: ""))
        }
        .onAppear {
            loadData()
            quickStartManager.loadConfig(isLargeScreen: false, is2in1: false)
            // Refresh records when view appears
            updateRecentActivities()
            loadUpcomingBookings()
            loadUnfinishedRecord()
        }
        .onReceive(scoreboardVM.objectWillChange) { _ in
            updateRecentActivities()
            loadUnfinishedRecord()
        }
    }

    // MARK: - Setup dialog support (aligned with HarmonyOS)

    /// 所有计分项目均先弹出 setup（至少输入名字）
    private static let sportsWithSetup: Set<GameType> = [
        .pingpong, .tennis, .badminton, .football, .basketball, .volleyball,
        .archery, .boxing, .billiards, .pickleball, .guandan, .doudizhu,
        .simpleScore, .multiScoreboard, .counter
    ]

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
        let records = ScoreboardRecordManager.shared.getAllRecordSummaries()
        #if DEBUG
        print("[HomeTab] 📊 Loading \(records.count) total records for recent activities")
        #endif

        let recentRecords = records
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(10)
        #if DEBUG
        print("[HomeTab] 📋 Showing \(recentRecords.count) recent records")
        #endif

        recentActivities = recentRecords.map { record in
            #if DEBUG
            print("[HomeTab] 🎮 Record: \(record.id) - \(record.gameType.rawValue) - \(record.team1FinalScore):\(record.team2FinalScore)")
            #endif
            return RecentActivity(
                id: record.id,
                activityType: .scoreboard,
                gameType: record.gameType,
                timestamp: record.timestamp,
                title: "\(record.team1Name) vs \(record.team2Name)",
                description: "\(record.team1FinalScore) : \(record.team2FinalScore)"
            )
        }
    }

    private func loadUpcomingBookings() {
        upcomingBookings = LocalBookingManager.shared.getUpcomingPendingBookings(limit: 2)
    }

    private func loadUnfinishedRecord() {
        unfinishedRecord = ScoreboardRecordManager.shared.getUnfinishedRecord()
    }

    private func continueUnfinishedGame() {
        guard let unfinishedRecord else { return }
        appliedSetupResult = nil
        appliedSetupGameType = nil
        path.append(
            NavigationDestination.scoreboard(
                ScoreboardNavigationTarget(
                    gameType: unfinishedRecord.gameType,
                    recordId: unfinishedRecord.id
                )
            )
        )
    }

    private func discardUnfinishedGame() {
        _ = ScoreboardRecordManager.shared.discardUnfinishedRecord()
        ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
        loadUnfinishedRecord()
    }

    @ViewBuilder
    private func getScoreboardView(
        for gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: @escaping () -> Void = {}
    ) -> some View {
        switch gameType {
        case .pingpong:
            PingPongScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .badminton:
            BadmintonScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .tennis:
            TennisScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .basketball:
            BasketballScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .football:
            FootballScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .volleyball:
            VolleyballScoreboardView(
                showBackButton: false,
                onNavigationBack: navigateBack,
                initialSetup: setupResult,
                initialRecordId: initialRecordId,
                onSetupConsumed: onSetupConsumed
            )
                .toolbar(.hidden, for: .tabBar)
        case .archery:
            ArcheryScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .boxing:
            BoxingScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .billiards:
            BilliardsScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .pickleball:
            PickleballScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .guandan:
            GuandanScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .doudizhu:
            DoudizhuScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .simpleScore:
            SimpleScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .multiScoreboard:
            MultiScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        case .counter:
            SimpleScoreboardView(initialSetup: setupResult, onSetupConsumed: onSetupConsumed)
                .toolbar(.hidden, for: .tabBar)
        default:
            Text(NSLocalizedString("game_not_supported", value: "暂不支持该项目", comment: ""))
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
    private func buildContent(isWide: Bool, contentWidth: CGFloat = 0) -> some View {
        if isWide {
            // 两栏布局：左 2/3、右 1/3 宽（参考鸿蒙 buildDesktopLayout）
            let spacing = Theme.lg
            let rightWidth = contentWidth > 0 ? (contentWidth - spacing) / 3 : 0
            let leftWidth = contentWidth > 0 ? (contentWidth - spacing) * 2 / 3 : 0
            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: Theme.lg) {
                    buildQuickStartSection()
                    buildScheduleSection()
                    ProToolsSectionView(
                        isWide: true,
                        isDarkTheme: true,
                        onToolClick: { toolId in
                            if let tool = ToolItem.allTools.first(where: { $0.id == toolId }) {
                                path.append(NavigationDestination.tool(tool))
                            }
                        },
                        onEnterToolsPage: {
                            path.append(NavigationDestination.toolsList)
                        }
                    )
                }
                .frame(width: leftWidth > 0 ? leftWidth : nil, alignment: .leading)

                VStack(alignment: .leading, spacing: Theme.md) {
                    Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                        .font(.system(size: Theme.fontH5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)

                    RecentRecordsSectionView(
                        records: recentActivities,
                        isDarkTheme: true,
                        onViewAllTapped: { onNavigateToTab?(1, nil) }
                    )
                }
                .frame(width: rightWidth > 0 ? rightWidth : nil, alignment: .leading)
            }
        } else {
            VStack(spacing: Theme.lg) {
                buildQuickStartSection()
                buildScheduleSection()
                ProToolsSectionView(
                    isWide: false,
                    isDarkTheme: true,
                    onToolClick: { toolId in
                        if let tool = ToolItem.allTools.first(where: { $0.id == toolId }) {
                            path.append(NavigationDestination.tool(tool))
                        }
                    },
                    onEnterToolsPage: {
                        path.append(NavigationDestination.toolsList)
                    }
                )
                buildRecentRecordsSection()
            }
        }
    }

    @ViewBuilder
    private func buildQuickStartSection() -> some View {
        QuickStartGridView(
            primarySport: quickStartManager.quickStartConfig.primarySport,
            secondarySport: quickStartManager.quickStartConfig.secondarySport,
            isDarkTheme: true,
            onPrimaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onSecondaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onNewGameClick: { showNewGameDialog = true },
            onEditClick: { showQuickStartEditSheet = true }
        )
    }

    @ViewBuilder
    private func buildRecentRecordsSection() -> some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            RecentRecordsSectionView(
                records: recentActivities,
                isDarkTheme: true,
                onViewAllTapped: { onNavigateToTab?(1, nil) }
            )
        }
    }

    @ViewBuilder
    private func buildScheduleSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("schedule_title", value: "我的球局", comment: ""))
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    path.append(NavigationDestination.schedule)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if upcomingBookings.isEmpty {
                VStack(spacing: 10) {
                    EmptyStateCourtIcon(size: 40, color: Theme.homeTextDisabledDark)

                    Text(NSLocalizedString("schedule_empty_pending", value: "暂无待进行球局", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.homeTextDisabledDark)
                        .multilineTextAlignment(.center)

                    Button {
                        showCreateBookingSheet = true
                    } label: {
                        Text(NSLocalizedString("schedule_new_booking", value: "预约新球局", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(height: 42)
                            .padding(.horizontal, 20)
                            .background(Theme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(upcomingBookings) { booking in
                    Button {
                        path.append(NavigationDestination.schedule)
                    } label: {
                        HStack(spacing: 12) {
                            Text(booking.sportType.icon)
                                .font(.system(size: 28))
                                .frame(width: 42, height: 42)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(booking.sportType.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(scheduleMetaText(for: booking))
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            scheduleTimeStatusTag(for: booking.dateTime)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatScheduleTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func scheduleMetaText(for booking: LocalBooking) -> String {
        let time = formatScheduleTime(booking.dateTime)
        if booking.location.isEmpty {
            return time
        }
        return "\(time) · \(booking.location)"
    }

    @ViewBuilder
    private func scheduleTimeStatusTag(for date: Date) -> some View {
        let status = getScheduleTimeStatus(scheduledAt: date)
        let style = status.darkStyle

        Text(status.localizedLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    HomeTab()
}
