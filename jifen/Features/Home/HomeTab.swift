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
    /// 对齐安卓 isTablet()：窗口最小边 >= 600 视为平板档（首页边距用 64）。
    static let minimumTabletSmallestSide: CGFloat = 600
    /// 对齐安卓 AppSpacing.screenHorizontalTablet。
    static let tabletHorizontalInset: CGFloat = 64

    static func usesWideLayout(size: CGSize, isPad: Bool) -> Bool {
        // 对齐安卓 isWideScreen()：窗口宽 >= 768 即双列，不区分横竖屏。
        isPad && size.width >= minimumWideWidth
    }

    static func horizontalInset(size: CGSize) -> CGFloat {
        min(size.width, size.height) >= minimumTabletSmallestSide
            ? tabletHorizontalInset
            : Theme.pageHorizontalInset
    }
}

struct HomeResumeSessionScanOutcome<Candidate> {
    var candidate: Candidate?
    var recordsNeedRefresh = false
    var shouldReload = false
    var hasUnreadableEntry = false
    var isCancelled = false
}

/// Selects one resumable match without letting a damaged or concurrently
/// removed index entry discard an otherwise valid older match. The candidate
/// is fully decoded before any entries older than it are archived.
struct HomeResumeSessionScanner<Candidate> {
    typealias ReconcileCommittedRecord = (ResumeSessionSummary) async -> Bool
    typealias ArchiveIfExpired = (UUID) async throws -> ResumeSessionDisposition?
    typealias Abandon = (UUID) async throws -> ResumeSessionDisposition
    typealias CandidateLoader = (ResumeSessionSummary) async -> Candidate?
    typealias FailureHandler = (Error, ResumeSessionSummary) -> Void

    let reconcileCommittedRecord: ReconcileCommittedRecord
    let archiveIfExpired: ArchiveIfExpired
    let abandon: Abandon
    let loadCandidate: CandidateLoader
    let onFailure: FailureHandler

    func scan(_ entries: [ResumeSessionSummary]) async -> HomeResumeSessionScanOutcome<Candidate> {
        var outcome = HomeResumeSessionScanOutcome<Candidate>()
        var candidateIndex: Int?
        var hasUnresolvedNewerEntry = false

        // Entries are newest-first. Reconcile terminal/expired entries while
        // searching, but do not prune anything older than the candidate until
        // that candidate's snapshot and payload have both decoded.
        for (index, entry) in entries.enumerated() {
            guard !Task.isCancelled else {
                outcome.isCancelled = true
                return outcome
            }

            if await reconcileCommittedRecord(entry) {
                continue
            }

            do {
                if let disposition = try await archiveIfExpired(entry.sessionId) {
                    outcome.recordsNeedRefresh = outcome.recordsNeedRefresh
                        || disposition.containsHistoricalRecord
                    continue
                }
            } catch {
                onFailure(error, entry)
                outcome.shouldReload = true
                outcome.hasUnreadableEntry = true
                hasUnresolvedNewerEntry = true
                continue
            }

            guard let candidate = await loadCandidate(entry) else {
                // The index and snapshot may have crossed during an atomic
                // save. Leave the entry untouched and give the repository one
                // bounded reload instead of failing the entire Home scan.
                outcome.shouldReload = true
                outcome.hasUnreadableEntry = true
                hasUnresolvedNewerEntry = true
                continue
            }

            outcome.candidate = candidate
            candidateIndex = index
            break
        }

        guard let candidateIndex else { return outcome }

        // If a newer entry could not be resolved, showing this valid fallback
        // is safe, but deleting anything behind it is not. A later reload can
        // determine the true ordering once the concurrent write settles.
        guard !hasUnresolvedNewerEntry else { return outcome }

        for entry in entries.dropFirst(candidateIndex + 1) {
            guard !Task.isCancelled else {
                outcome.isCancelled = true
                return outcome
            }

            if await reconcileCommittedRecord(entry) {
                continue
            }

            do {
                let disposition = try await abandon(entry.sessionId)
                outcome.recordsNeedRefresh = outcome.recordsNeedRefresh
                    || disposition.containsHistoricalRecord
            } catch {
                // One damaged/missing entry must not prevent later entries from
                // being reconciled. Every successful cleanup remains
                // record-first and the failed item is safe to retry.
                onFailure(error, entry)
                outcome.shouldReload = true
                outcome.hasUnreadableEntry = true
            }
        }

        return outcome
    }
}

struct HomeTab: View {
    var onNavigateToTab: ((Int, GameType?) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var recentActivities: [RecentActivity] = []
    @State private var upcomingBookings: [LocalBooking] = []
    @State private var unfinishedRecord: UnfinishedGameSummary?
    @State private var showNewGameDialog = false
    @State private var showQuickStartEditSheet = false
    @State private var isDiscardConfirmationPending = false
    @State private var showDiscardConfirmationToast = false
    @State private var discardConfirmationToken = UUID()
    @State private var resumeLoadErrorMessage: String?
    @State private var resumeLoadTask: Task<Void, Never>?
    @State private var resumeLoadGeneration = UUID()
    @AppStorage("home_discard_chip_shown_count") private var discardConfirmationToastShownCount = 0
    @State private var showCreateBookingSheet = false
    @State private var path = NavigationPath()
    @State private var homeSheet: HomeFormSheetDestination?
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
        var exactScoreCoreGameType: ScoreCore.GameType? = nil
        var automaticallyShowsUsageHint = true
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
        case cast
    }

    /// iPad 上以对话框（form sheet）呈现的首页页面（对齐安卓平板端 Dialog 形态）。
    enum HomeFormSheetDestination: String, Identifiable {
        case commonNames
        case commonPlaces
        case cast

        var id: String { rawValue }
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
                let contentWidth = geo.size.width - HomeLayoutPolicy.horizontalInset(size: geo.size) * 2
                // 顶栏固定（对齐鸿蒙 HomeHeader），内容区独立滚动，便于后续接入同步计分 banner
                VStack(spacing: 0) {
                    HomeHeaderView(
                        headerDate: headerDate,
                        horizontalInset: HomeLayoutPolicy.horizontalInset(size: geo.size),
                        onCastTapped: {
                            AppAnalytics.openPage(from: .homeTab, to: .castPage)
                            // 对齐安卓平板端：iPad 上投屏与同步以对话框（form sheet）呈现。
                            if Theme.usesPadLayout {
                                homeSheet = .cast
                            } else {
                                path.append(NavigationDestination.cast)
                            }
                        }
                    )

                    ScrollView(showsIndicators: false) {
                        buildContent(isWide: isWide, contentWidth: contentWidth)
                            .padding(.horizontal, HomeLayoutPolicy.horizontalInset(size: geo.size))
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
                    initialTertiary: quickStartManager.quickStartConfig.tertiarySport,
                    showsTertiarySlot: showsTertiaryQuickStartSlot,
                    onSave: { primary, secondary, tertiary in
                        let identifiers = [primary, secondary] + (tertiary.map { [$0] } ?? [])
                        AppAnalytics.track(.saveQuickStart, parameters: [
                            .contentType: .string("quick_start"),
                            .itemID: .string(identifiers.map(\.analyticsIdentifier).joined(separator: ",")),
                            .result: .string(AnalyticsResult.success.rawValue)
                        ])
                        Task {
                            try? await quickStartManager.setSports(
                                primary: primary,
                                secondary: secondary,
                                tertiary: tertiary
                            )
                        }
                    }
                )
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
                        exactScoreCoreGameType: target.exactScoreCoreGameType,
                        automaticallyShowsUsageHint: target.automaticallyShowsUsageHint,
                        analyticsEntryPoint: target.analyticsEntryPoint,
                        onSetupConsumed: {}
                    )
                case .toolsList:
                    ToolsListPageView(onToolTap: { path.append($0) })
                        .toolbar(.hidden, for: .tabBar)
                case .schedule:
                    SchedulePage(
                        onStartBooking: { request in
                            await startScheduledBooking(request)
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
                        onStartBooking: { request in
                            await startScheduledBooking(request)
                        },
                        onChanged: {
                            loadUpcomingBookings()
                        }
                    )
                    .toolbar(.hidden, for: .tabBar)
                case .cast:
                    CastConnectionView()
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .navigationDestination(for: ToolItem.self) { tool in
                tool.view
                    .navigationTitle(tool.title)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .sheet(item: $homeSheet) { destination in
            HomeFormSheet(destination: destination)
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
            configureQuickStartDefaultsForCurrentDevice()
            scoreboardVM.ensureLoaded()
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

    private func configureQuickStartDefaultsForCurrentDevice() {
        quickStartManager.configureDefaultsIfNeeded(
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

    private var showsTertiaryQuickStartSlot: Bool {
        QuickStartLayoutPolicy.showsTertiarySlot(
            horizontalSizeClass: horizontalSizeClass,
            isPad: Theme.usesPadLayout
        )
    }

    // MARK: - Setup dialog support (aligned with HarmonyOS)

    /// 所有计分项目均先弹出 setup（至少输入名字）
    private static let sportsWithSetup: Set<GameType> = [
        .pingpong, .tennis, .badminton, .football, .basketball, .volleyball,
        .archery, .boxing, .billiards, .pickleball, .guandan, .doudizhu,
        .simpleScore, .multiScoreboard, .counter
    ]

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
        let records = scoreboardVM.records
        #if DEBUG
        print("[HomeTab] 📊 Deriving recent activities from \(records.count) cached records")
        #endif

        let recentRecords = records
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
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
        resumeLoadTask?.cancel()
        let generation = UUID()
        resumeLoadGeneration = generation


        resumeLoadTask = Task { @MainActor in
            defer {
                if resumeLoadGeneration == generation {
                    resumeLoadTask = nil
                }
            }

            let repository = ResumeSessionRepository()
            do {
                let finishedCoordinator = FinishedSessionCommitCoordinator(
                    resumeRemover: { sessionId in
                        try await repository.remove(sessionId: sessionId)
                    }
                )
                let lifecycleCoordinator = AbandonedResumeSessionCoordinator()
                let scanner = HomeResumeSessionScanner<UnfinishedGameSummary>(
                    reconcileCommittedRecord: { entry in
                        let committedRecordID = ManualResumeSessionStore.recordID(
                            for: entry.sessionId
                        ) ?? entry.sessionId.uuidString
                        guard let reconciliation = await finishedCoordinator.reconcileCommittedRecord(
                            recordID: committedRecordID,
                            sessionId: entry.sessionId
                        ) else { return false }
                        if let cleanupError = reconciliation.cleanupError {
                            ScoreboardPersistenceFailureReporter.report(
                                cleanupError,
                                context: "Failed to reconcile finished resume \(entry.sessionId.uuidString)"
                            )
                        }
                        return true
                    },
                    archiveIfExpired: { sessionID in
                        try await lifecycleCoordinator.archiveIfExpired(sessionID: sessionID)
                    },
                    abandon: { sessionID in
                        try await lifecycleCoordinator.abandon(sessionID: sessionID)
                    },
                    loadCandidate: { entry in
                        await UnfinishedGameSummary.load(session: entry)
                    },
                    onFailure: { error, entry in
                        #if DEBUG
                        print(
                            "[HomeTab] Resume entry \(entry.sessionId.uuidString) "
                                + "could not be reconciled: \(error.localizedDescription)"
                        )
                        #endif
                    }
                )

                var outcome = await scanner.scan(try await repository.liveEntries())
                var recordsNeedRefresh = outcome.recordsNeedRefresh

                // A missing envelope can be a harmless index/snapshot race.
                // Reload once, never recursively, and keep all per-entry
                // failures isolated inside the scanner.
                if outcome.shouldReload {
                    await Task.yield()
                    guard resumeLoadGeneration == generation, !Task.isCancelled else { return }
                    let retriedOutcome = await scanner.scan(try await repository.liveEntries())
                    recordsNeedRefresh = recordsNeedRefresh || retriedOutcome.recordsNeedRefresh
                    outcome = retriedOutcome
                }

                guard resumeLoadGeneration == generation, !Task.isCancelled else { return }

                if recordsNeedRefresh {
                    ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
                }

                guard resumeLoadGeneration == generation, !Task.isCancelled else { return }


                unfinishedRecord = outcome.candidate
                resumeLoadErrorMessage = outcome.candidate == nil && outcome.hasUnreadableEntry
                    ? NSLocalizedString(
                        "resume_load_invalid",
                        value: "The saved match is damaged and cannot be resumed.",
                        comment: ""
                    )
                    : nil
            } catch {
                guard resumeLoadGeneration == generation, !Task.isCancelled else { return }

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
        let automaticallyShowsUsageHint: Bool
        switch unfinishedRecord.source {
        case .resume:
            recordId = unfinishedRecord.recordIdentifier
            setupResult = nil
            automaticallyShowsUsageHint = true
        }
        path.append(
            NavigationDestination.scoreboard(
                    ScoreboardNavigationTarget(
                        gameType: unfinishedRecord.gameType,
                        recordId: recordId,
                        setupResult: setupResult,
                        exactScoreCoreGameType: unfinishedRecord.exactScoreCoreGameType,
                        automaticallyShowsUsageHint: automaticallyShowsUsageHint,
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
        switch unfinishedRecord.source {
        case .resume(let sessionId):
            Task {
                do {
                    let disposition = try await AbandonedResumeSessionCoordinator().abandon(
                        sessionID: sessionId
                    )
                    AppAnalytics.track(.scoreboardMenuAction, parameters: [
                        .gameType: .string(unfinishedRecord.gameType.analyticsIdentifier),
                        .actionName: .string("discard_unfinished"),
                        .result: .string(AnalyticsResult.success.rawValue)
                    ])
                    if disposition.containsHistoricalRecord {
                        ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
                    }
                    loadUnfinishedRecord()
                } catch {
                    NotificationCenter.default.post(
                        name: .scoreboardPersistenceFailed,
                        object: nil
                    )
                }
            }
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

    /// A scheduled start is accepted only after its exact initial state is in
    /// the resume repository. The detail page completes the booking after this
    /// returns true, which also removes its pending reminders.
    private func startScheduledBooking(_ request: BookingStartRequest) async -> Bool {
        guard let resumeSessionId = await BookingStartPersistence.persist(request) else {
            return false
        }
        pendingScoreboardEntryPoint = .bookingDetail
        path.append(
            NavigationDestination.scoreboard(
                ScoreboardNavigationTarget(
                    gameType: request.gameType,
                    recordId: resumeSessionId,
                    setupResult: request.setup,
                    analyticsEntryPoint: .bookingDetail
                )
            )
        )
        return true
    }

    @ViewBuilder
    private func scoreboardSetupDialog(
        for gameType: GameType,
        maxDialogHeight: CGFloat,
        onConfirm: @escaping (SportsSetupResult) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        if gameType == .basketballTraining {
            ShotTrainingSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if gameType == .nineBall {
            NineBallSetupDialogView(
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else if Self.isCasualSetupGame(gameType) {
            let defaults = DefaultParticipantNames.resolve(for: gameType)
            MultiScoreSetupDialogView(
                gameType: gameType,
                defaultPlayerCount: Self.casualDefaultPlayerCount(for: gameType),
                defaultTeam1Name: defaults.left,
                defaultTeam2Name: defaults.right,
                initialTargetScore: PreferencesManager.shared.unoTargetScore,
                titleEmoji: gameType.icon,
                titleKey: Self.localizationKey(for: gameType),
                titleFallback: gameType.displayName,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else {
            let defaults = DefaultParticipantNames.resolve(for: gameType)
            SportsSetupDialogView(
                gameType: gameType,
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

    @ViewBuilder
    private func getScoreboardView(
        for gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        exactScoreCoreGameType: ScoreCore.GameType? = nil,
        automaticallyShowsUsageHint: Bool = true,
        analyticsEntryPoint: AnalyticsEntryPoint = .homeNewGame,
        onSetupConsumed: @escaping () -> Void = {}
    ) -> some View {
        ScoreboardLaunchView(
            gameType: gameType,
            setupResult: setupResult,
            initialResumeSessionId: initialResumeSessionId,
            exactScoreCoreGameType: exactScoreCoreGameType,
            automaticallyShowsUsageHint: automaticallyShowsUsageHint,
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
                // 对齐安卓平板端：iPad 上常用名称以对话框（form sheet）呈现。
                if Theme.usesPadLayout {
                    homeSheet = .commonNames
                } else {
                    path.append(NavigationDestination.commonNames)
                }
            },
            onPlacesTapped: {
                AppAnalytics.openPage(from: .homeTab, to: .commonPlacesPage)
                if Theme.usesPadLayout {
                    homeSheet = .commonPlaces
                } else {
                    path.append(NavigationDestination.commonPlaces)
                }
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
            tertiarySport: quickStartManager.quickStartConfig.tertiarySport,
            showsTertiarySlot: showsTertiaryQuickStartSlot,
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
            onTertiaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    // Tertiary is the third small quick-start card. Reuse the
                    // existing secondary-card analytics entry point rather than
                    // broadening analytics scope for this local feature port.
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
            SectionTitleView(title: NSLocalizedString("recent_records", comment: "Recent Records Section Title"))

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
                SectionTitleView(title: NSLocalizedString("schedule_title", value: "我的球局", comment: ""))
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

/// iPad 首页对话框容器（对齐本机 SettingsFormSheet：NavigationStack + 右上角关闭 + form sheet）。
private struct HomeFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: HomeTab.HomeFormSheetDestination

    var body: some View {
        NavigationStack {
            destinationContent
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { dismiss() }
                    }
                }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .commonNames:
            CommonNamesManagementView()
        case .commonPlaces:
            CommonPlacesManagementView()
        case .cast:
            CastConnectionView()
        }
    }
}
