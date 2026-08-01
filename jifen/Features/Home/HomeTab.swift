//
//  HomeTab.swift
//  jifen
//
//  Simplified home tab - clean and focused
//

import SwiftUI
import Combine
import PersistenceCore
import ScoreCore
import UIKit

enum HomeLayoutPolicy {
    static let minimumWideWidth: CGFloat = 768

    static func usesWideLayout(size: CGSize, isPad: Bool) -> Bool {
        isPad
            && size.width >= minimumWideWidth
            && size.width > size.height
    }
}

struct HomeTab: View {
    var onNavigateToTab: ((Int, GameType?) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    @State private var recentActivities: [RecentActivity] = []
    @State private var upcomingBookings: [LocalBooking] = []
    @State private var unfinishedRecord: UnfinishedGameSummary?
    @State private var showNewGameDialog = false
    @State private var showQuickStartEditSheet = false
    @State private var isDiscardConfirmationPending = false
    @State private var showDiscardConfirmationToast = false
    @State private var discardConfirmationToken = UUID()
    @State private var resumeLoadErrorMessage: String?
    @AppStorage("home_discard_chip_shown_count") private var discardConfirmationToastShownCount = 0
    @State private var showCreateBookingSheet = false
    @State private var path = NavigationPath()
    @State private var didHandleUITestRoute = false
    /// When user selects a scoreboard game from New Game or Quick Start, show setup first for supported sports.
    @State private var pendingScoreboardSetupItem: ScoreboardSetupItem? = nil
    @State private var pendingScoreboardEntryPoint: AnalyticsEntryPoint = .homeNewGame

    // Navigation back handler for scoreboard views
    private func navigateBack() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    @State private var headerDate = ""
    @StateObject private var quickStartManager = QuickStartConfigManager.shared
    @State private var scoreboardVM = ScoreboardRecordsViewModel.shared

    private static let discardConfirmationDuration: TimeInterval = 3
    private static let discardConfirmationToastMaximumShownCount = 3

    struct ScoreboardNavigationTarget: Hashable {
        let gameType: GameType
        let recordId: String?
        let setupResult: SportsSetupResult?
        let analyticsEntryPoint: AnalyticsEntryPoint
    }

    enum NavigationDestination: Hashable {
        case tool(ToolItem)
        case scoreboard(ScoreboardNavigationTarget)
        case toolsList
        case schedule
        case commonNames
        case commonPlaces
        case bookingDetail(bookingId: String)
    }

    private var isDarkTheme: Bool {
        colorScheme == .dark
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let isWide = HomeLayoutPolicy.usesWideLayout(
                    size: geo.size,
                    isPad: Theme.usesPadLayout
                )
                let contentWidth = geo.size.width - Theme.pageHorizontalInset * 2
                // 顶栏固定（对齐鸿蒙 HomeHeader），内容区独立滚动，便于后续接入同步计分 banner
                VStack(spacing: 0) {
                    HomeHeaderView(headerDate: headerDate)
                        .padding(.horizontal, Theme.pageHorizontalInset)

                    ScrollView(showsIndicators: false) {
                        buildContent(isWide: isWide, contentWidth: contentWidth)
                            .padding(.horizontal, Theme.pageHorizontalInset)
                            .padding(.top, Theme.sectionSpacing)
                            .padding(.bottom, Theme.tabContentBottomPadding)
                    }
                }
            }
            .background(Theme.backgroundColor)
            .navigationBarHidden(true)
            .sheet(isPresented: $showQuickStartEditSheet) {
                QuickStartEditView(
                    initialPrimary: quickStartManager.quickStartConfig.primarySport,
                    initialSecondary: quickStartManager.quickStartConfig.secondarySport,
                    onSave: { primary, secondary in
                        AppAnalytics.track(.saveQuickStart, parameters: [
                            .contentType: .string("quick_start"),
                            .itemID: .string("\(primary.analyticsIdentifier),\(secondary.analyticsIdentifier)"),
                            .result: .string(AnalyticsResult.success.rawValue)
                        ])
                        Task {
                            try? await quickStartManager.setPrimarySport(primary)
                            try? await quickStartManager.setSecondarySport(secondary)
                        }
                    }
                )
                .presentationBackground(Theme.dialogSurfaceBackground)
            }
            .sheet(isPresented: $showNewGameDialog) {
                NewGameDialogView(
                    onSelect: { type, source, gameType in
                        if type == .scoreboard, let gameType = gameType {
                            pendingScoreboardEntryPoint = .homeNewGame
                            AppAnalytics.track(.scoreItemSelect, parameters: [
                                .gameType: .string(gameType.analyticsIdentifier),
                                .sourcePage: .string(AnalyticsScreen.homeTab.rawValue),
                                .entryPoint: .string(AnalyticsEntryPoint.homeNewGame.rawValue)
                            ])
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
            .overlay {
                CenteredSetupDialogPresenter(item: $pendingScoreboardSetupItem) { item, dismiss, maxDialogHeight in
                    scoreboardSetupDialog(
                        for: item.gameType,
                        maxDialogHeight: maxDialogHeight,
                        onConfirm: { result in
                            AppAnalytics.scoreSetupConfirmed(
                                gameType: item.gameType,
                                setup: result,
                                entryPoint: pendingScoreboardEntryPoint
                            )
                            pendingScoreboardSetupItem = nil
                            navigateToScoreboardAfterSetupDismiss(item.gameType, setupResult: result)
                        },
                        onCancel: dismiss
                    )
                }
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
                        .analyticsScreen(AnalyticsScreen.tool(id: tool.id) ?? .toolsPage, source: .homeTab)
                        .navigationTitle(tool.title)
                        .toolbar(.hidden, for: .tabBar)
                case .scoreboard(let target):
                    getScoreboardView(
                        for: target.gameType,
                        setupResult: target.setupResult,
                        initialResumeSessionId: target.recordId,
                        analyticsEntryPoint: target.analyticsEntryPoint,
                        onSetupConsumed: {}
                    )
                case .toolsList:
                    ToolsListPageView(onToolTap: { path.append($0) })
                        .toolbar(.hidden, for: .tabBar)
                case .schedule:
                    SchedulePage(
                        onStartGame: { gameType in
                            pendingScoreboardEntryPoint = .bookingDetail
                            pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                        },
                        onChanged: {
                            loadUpcomingBookings()
                        }
                    )
                    .toolbar(.hidden, for: .tabBar)
                case .commonNames:
                    CommonNamesManagementView()
                        .toolbar(.hidden, for: .tabBar)
                case .commonPlaces:
                    CommonPlacesManagementView()
                        .toolbar(.hidden, for: .tabBar)
                case .bookingDetail(let bookingId):
                    BookingDetailPage(
                        bookingId: bookingId,
                        onStartGame: { gameType in
                            pendingScoreboardEntryPoint = .bookingDetail
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
                VStack(spacing: Theme.sm) {
                    if showDiscardConfirmationToast {
                        UnfinishedGameDiscardToast()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    HStack {
                        Spacer(minLength: 0)
                        UnfinishedGameBarView(
                            record: unfinishedRecord,
                            isClosePending: isDiscardConfirmationPending,
                            onContinue: { continueUnfinishedGame() },
                            onClose: { handleDiscardUnfinishedGameTap() }
                        )
                        .frame(maxWidth: 400)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, Theme.pageHorizontalInset)
                .padding(.bottom, Theme.sm)
                .background(Color.clear)
                .animation(.easeInOut(duration: 0.2), value: showDiscardConfirmationToast)
            }
        }
        .onAppear {
            // Home is a normal page: iPad follows the physical device in all
            // directions, while iPhone returns to portrait.
            OrientationLock.shared.unlock()
            loadData()
            loadQuickStartConfigForCurrentLayout()
            // Refresh records when view appears
            updateRecentActivities()
            loadUpcomingBookings()
            loadUnfinishedRecord()
            #if DEBUG
            if !didHandleUITestRoute,
               ProcessInfo.processInfo.arguments.contains("-UITestOpenTools") {
                didHandleUITestRoute = true
                path.append(NavigationDestination.toolsList)
            }
            #endif
        }
        .onChange(of: path.count) { _, count in
            if count == 0 {
                OrientationLock.shared.unlock()
            }
        }
        .onChange(of: scoreboardVM.records) { _, _ in
            updateRecentActivities()
            loadUnfinishedRecord()
        }
        .onChange(of: watchLinkService.resumeStateToken) { _, _ in
            loadUnfinishedRecord()
        }
        .onChange(of: unfinishedRecord?.recordIdentifier) { _, _ in
            resetDiscardConfirmation()
        }
        .alert(
            NSLocalizedString("resume_load_failed_title", value: "Unable to Resume Match", comment: ""),
            isPresented: resumeLoadErrorBinding
        ) {
            Button(NSLocalizedString("got_it", comment: ""), role: .cancel) {}
        } message: {
            Text(resumeLoadErrorMessage ?? "")
        }
    }

    private var resumeLoadErrorBinding: Binding<Bool> {
        Binding(
            get: { resumeLoadErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    resumeLoadErrorMessage = nil
                }
            }
        )
    }

    private func loadQuickStartConfigForCurrentLayout() {
        quickStartManager.loadConfig(
            isLargeScreen: Theme.usesPadLayout,
            is2in1: isRunningAsMacApp
        )
    }

    private var isRunningAsMacApp: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    // MARK: - Setup dialog support (aligned with HarmonyOS)

    /// 所有计分项目均先弹出 setup（至少输入名字）
    private static let sportsWithSetup: Set<GameType> = [
        .pingpong, .tennis, .badminton, .football, .basketball, .volleyball,
        .archery, .boxing, .billiards, .pickleball, .guandan, .doudizhu,
        .simpleScore, .multiScoreboard, .counter
    ]

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
        case .archery, .boxing, .pingpong, .badminton, .tennis, .billiards, .eightBall, .snooker, .pickleball, .simpleScore:
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
                title: record.displayMatchTitle,
                description: record.displayScore(),
                syncFrom: record.isSyncedFromWatch ? "watch" : nil
            )
        }
    }

    private func loadUpcomingBookings() {
        upcomingBookings = LocalBookingManager.shared.getUpcomingPendingBookings(limit: 2)
    }

    private func loadUnfinishedRecord() {
        if let linked = watchLinkService.linkedResumeDescriptor {
            // When a linked descriptor exists we must resolve it here and return.
            // Falling through to the repository Task would recurse indefinitely
            // because the descriptor never clears on its own.
            if let summary = UnfinishedGameSummary(linked: linked) {
                unfinishedRecord = summary
            } else {
                unfinishedRecord = nil
            }
            return
        }
        Task {
            let repository = ResumeSessionRepository()
            // At most one Resume GameBar: prune any stacked live sessions first.
            do {
                if let entry = try await repository.retainNewestLiveSession() {
                    guard let summary = UnfinishedGameSummary(session: entry) else {
                        unfinishedRecord = nil
                        resumeLoadErrorMessage = NSLocalizedString(
                            "resume_load_invalid",
                            value: "The saved match is damaged and cannot be resumed.",
                            comment: ""
                        )
                        return
                    }
                    guard watchLinkService.linkedResumeDescriptor == nil else {
                        loadUnfinishedRecord()
                        return
                    }
                    unfinishedRecord = summary
                    resumeLoadErrorMessage = nil
                    return
                }
                unfinishedRecord = nil
                resumeLoadErrorMessage = nil
            } catch {
                guard watchLinkService.linkedResumeDescriptor == nil else {
                    loadUnfinishedRecord()
                    return
                }
                unfinishedRecord = nil
                resumeLoadErrorMessage = String(
                    format: NSLocalizedString(
                        "resume_load_failed_format",
                        value: "Could not load the saved match: %@",
                        comment: ""
                    ),
                    error.localizedDescription
                )
            }
        }
    }

    private func continueUnfinishedGame() {
        guard let unfinishedRecord else { return }
        resetDiscardConfirmation()
        let recordId: String?
        let setupResult: SportsSetupResult?
        switch unfinishedRecord.source {
        case .resume:
            recordId = unfinishedRecord.recordIdentifier
            setupResult = nil
        case .linked:
            recordId = nil
            setupResult = unfinishedRecord.linkedSetupResult
        }
        path.append(
            NavigationDestination.scoreboard(
                    ScoreboardNavigationTarget(
                        gameType: unfinishedRecord.gameType,
                        recordId: recordId,
                        setupResult: setupResult,
                        analyticsEntryPoint: .unfinishedBar
                )
            )
        )
    }

    private func handleDiscardUnfinishedGameTap() {
        guard unfinishedRecord != nil else {
            resetDiscardConfirmation()
            return
        }

        if isDiscardConfirmationPending {
            resetDiscardConfirmation()
            discardUnfinishedGame()
            return
        }

        isDiscardConfirmationPending = true
        let clampedShownCount = max(
            0,
            min(Self.discardConfirmationToastMaximumShownCount, discardConfirmationToastShownCount)
        )
        if clampedShownCount < Self.discardConfirmationToastMaximumShownCount {
            discardConfirmationToastShownCount = clampedShownCount + 1
            showDiscardConfirmationToast = true
        } else {
            discardConfirmationToastShownCount = clampedShownCount
            showDiscardConfirmationToast = false
        }

        let token = UUID()
        discardConfirmationToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.discardConfirmationDuration) {
            guard discardConfirmationToken == token else { return }
            resetDiscardConfirmation()
        }
    }

    private func resetDiscardConfirmation() {
        discardConfirmationToken = UUID()
        isDiscardConfirmationPending = false
        showDiscardConfirmationToast = false
    }

    private func discardUnfinishedGame() {
        guard let unfinishedRecord else { return }
        AppAnalytics.track(.scoreboardMenuAction, parameters: [
            .gameType: .string(unfinishedRecord.gameType.analyticsIdentifier),
            .actionName: .string("discard_unfinished"),
            .result: .string(AnalyticsResult.success.rawValue)
        ])
        switch unfinishedRecord.source {
        case .resume(let sessionId):
            Task {
                do {
                    try await ResumeSessionRepository().remove(sessionId: sessionId)
                    ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
                    loadUnfinishedRecord()
                } catch {
                    NotificationCenter.default.post(
                        name: .scoreboardPersistenceFailed,
                        object: nil
                    )
                }
            }
        case .linked(let sessionId):
            watchLinkService.leaveSession(sessionId)
            loadUnfinishedRecord()
        }
    }

    private func navigateToScoreboardAfterSetupDismiss(
        _ gameType: GameType,
        setupResult: SportsSetupResult
    ) {
        DispatchQueue.main.async {
            guard pendingScoreboardSetupItem == nil else { return }
            path.append(
                NavigationDestination.scoreboard(
                    ScoreboardNavigationTarget(
                        gameType: gameType,
                        recordId: nil,
                        setupResult: setupResult,
                        analyticsEntryPoint: pendingScoreboardEntryPoint
                    )
                )
            )
        }
    }

    @ViewBuilder
    private func scoreboardSetupDialog(
        for gameType: GameType,
        maxDialogHeight: CGFloat,
        onConfirm: @escaping (SportsSetupResult) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        if gameType == .nineBall {
            NineBallSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if Self.isCasualSetupGame(gameType) {
            let (t1, t2) = Self.defaultTeamNames(for: gameType)
            MultiScoreSetupDialogView(
                gameType: gameType,
                defaultPlayerCount: Self.casualDefaultPlayerCount(for: gameType),
                defaultTeam1Name: t1,
                defaultTeam2Name: t2,
                initialTargetScore: PreferencesManager.shared.unoTargetScore,
                titleEmoji: gameType.icon,
                titleKey: Self.localizationKey(for: gameType),
                titleFallback: gameType.displayName,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else {
            let (t1, t2) = Self.defaultTeamNames(for: gameType)
            SportsSetupDialogView(
                gameType: gameType,
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

    @ViewBuilder
    private func getScoreboardView(
        for gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        analyticsEntryPoint: AnalyticsEntryPoint = .homeNewGame,
        onSetupConsumed: @escaping () -> Void = {}
    ) -> some View {
        ScoreboardLaunchView(
            gameType: gameType,
            setupResult: setupResult,
            initialResumeSessionId: initialResumeSessionId,
            analyticsEntryPoint: analyticsEntryPoint,
            onSetupConsumed: onSetupConsumed,
            onBack: navigateBack
        )
        .toolbar(.hidden, for: .tabBar)
    }

    private static func localizationKey(for gameType: GameType) -> String {
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
    // MARK: - @ViewBuilder Layouts

    @ViewBuilder
    private func buildContent(isWide: Bool, contentWidth: CGFloat = 0) -> some View {
        if isWide {
            let spacing = Theme.sectionSpacing
            let columnWidth = contentWidth > 0 ? max(0, (contentWidth - spacing) / 2) : 0

            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    buildQuickStartSection()
                    ProToolsSectionView(
                        isPad: Theme.usesPadLayout,
                        isWide: true,
                        isDarkTheme: isDarkTheme,
                        availableWidth: columnWidth,
                        onToolClick: { tool in
                            trackHomeToolSelection(tool)
                            path.append(NavigationDestination.tool(tool))
                        }
                    )
                }
                .frame(width: columnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    buildCommonDataSection()
                    buildScheduleSection()
                    buildRecentRecordsSection()
                }
                .frame(width: columnWidth, alignment: .topLeading)
            }
        } else {
            VStack(spacing: Theme.sectionSpacing) {
                buildQuickStartSection()
                buildScheduleSection()
                buildCommonDataSection()
                ProToolsSectionView(
                    isPad: Theme.usesPadLayout,
                    isWide: false,
                    isDarkTheme: isDarkTheme,
                    onToolClick: { tool in
                        trackHomeToolSelection(tool)
                        path.append(NavigationDestination.tool(tool))
                    },
                    onEnterToolsPage: {
                        AppAnalytics.openPage(from: .homeTab, to: .toolsPage, entryPoint: .homeTools)
                        path.append(NavigationDestination.toolsList)
                    }
                )
                buildRecentRecordsSection()
            }
        }
    }

    @ViewBuilder
    private func buildCommonDataSection() -> some View {
        CommonDataSectionView(
            onNamesTapped: {
                AppAnalytics.openPage(from: .homeTab, to: .commonNamesPage)
                path.append(NavigationDestination.commonNames)
            },
            onPlacesTapped: {
                AppAnalytics.openPage(from: .homeTab, to: .commonPlacesPage)
                path.append(NavigationDestination.commonPlaces)
            }
        )
    }

    private func trackHomeToolSelection(_ tool: ToolItem) {
        AppAnalytics.track(.toolItemSelect, parameters: [
            .toolID: .string(tool.id),
            .sourcePage: .string(AnalyticsScreen.homeTab.rawValue),
            .entryPoint: .string(AnalyticsEntryPoint.homeTools.rawValue)
        ])
    }

    @ViewBuilder
    private func buildQuickStartSection(showSectionTitle: Bool = true) -> some View {
        QuickStartGridView(
            primarySport: quickStartManager.quickStartConfig.primarySport,
            secondarySport: quickStartManager.quickStartConfig.secondarySport,
            showSectionTitle: showSectionTitle,
            onPrimaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    pendingScoreboardEntryPoint = .homeQuickStartPrimary
                    AppAnalytics.track(.scoreItemSelect, parameters: [
                        .gameType: .string(gameType.analyticsIdentifier),
                        .sourcePage: .string(AnalyticsScreen.homeTab.rawValue),
                        .entryPoint: .string(AnalyticsEntryPoint.homeQuickStartPrimary.rawValue)
                    ])
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onSecondaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    pendingScoreboardEntryPoint = .homeQuickStartSecondary
                    AppAnalytics.track(.scoreItemSelect, parameters: [
                        .gameType: .string(gameType.analyticsIdentifier),
                        .sourcePage: .string(AnalyticsScreen.homeTab.rawValue),
                        .entryPoint: .string(AnalyticsEntryPoint.homeQuickStartSecondary.rawValue)
                    ])
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onNewGameClick: {
                AppAnalytics.openDialog("new_game", source: .homeTab)
                showNewGameDialog = true
            },
            onEditClick: {
                AppAnalytics.openDialog("quick_start_edit", source: .homeTab)
                showQuickStartEditSheet = true
            }
        )
    }

    @ViewBuilder
    private func buildRecentRecordsSection() -> some View {
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            RecentRecordsSectionView(
                records: recentActivities,
                isDarkTheme: isDarkTheme,
                onViewAllTapped: { onNavigateToTab?(1, nil) }
            )
        }
    }

    @ViewBuilder
    private func buildScheduleSection() -> some View {
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            HStack {
                Text(NSLocalizedString("schedule_title", value: "我的球局", comment: ""))
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    AppAnalytics.openPage(from: .homeTab, to: .scheduleList, entryPoint: .scheduleList)
                    path.append(NavigationDestination.schedule)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_schedule_all_button")
                .accessibilityLabel(NSLocalizedString("schedule_title", value: "我的球局", comment: ""))
            }

            if upcomingBookings.isEmpty {
                VStack(spacing: 10) {
                    EmptyStateCourtIcon(size: 40, color: Theme.homeNeutralCardTextTertiary)

                    Text(NSLocalizedString("schedule_empty_pending", value: "暂无待进行球局", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.homeNeutralCardTextSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        AppAnalytics.openPage(from: .homeTab, to: .createBookingPage, entryPoint: .scheduleList)
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
                .padding(Theme.cardPadding)
                .background(Theme.homeNeutralCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(upcomingBookings) { booking in
                    Button {
                        AppAnalytics.openPage(from: .homeTab, to: .bookingDetailPage, entryPoint: .scheduleList)
                        AppAnalytics.track(.selectContent, parameters: [
                            .contentType: .string("booking"),
                            .actionName: .string("view")
                        ])
                        path.append(NavigationDestination.bookingDetail(bookingId: booking.id))
                    } label: {
                        HStack(spacing: 12) {
                            Text(booking.sportType.icon)
                                .font(.system(size: 28))
                                .frame(width: 42, height: 42)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(booking.sportType.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Theme.homeNeutralCardTextPrimary)
                                    .lineLimit(1)
                                Text(scheduleMetaText(for: booking))
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.homeNeutralCardTextSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            scheduleTimeStatusTag(for: booking.dateTime)
                        }
                        .padding(.horizontal, Theme.compactCardPadding)
                        .padding(.vertical, Theme.compactCardPadding)
                        .frame(maxWidth: .infinity)
                        .background(Theme.homeNeutralCardBackground)
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
        let style = status.style

        Text(status.localizedLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDarkTheme ? Theme.homeCardTextPrimary : style.textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(scheduleStatusBackground(status, style: style))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func scheduleStatusBackground(
        _ status: ScheduleTimeStatus,
        style: ScheduleTimeStatusStyle
    ) -> Color {
        if !isDarkTheme {
            return style.backgroundColor
        }
        switch status {
        case .scheduled:
            return Color.white.opacity(0.12)
        case .startingSoon, .ready, .overdue:
            return style.borderColor.opacity(0.42)
        }
    }
}

#Preview {
    HomeTab()
}
