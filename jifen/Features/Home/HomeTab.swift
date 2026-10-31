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
import StoreKit
import UIKit

enum HomeLayoutPolicy {
    static let minimumWideWidth: CGFloat = 768
    /// 对齐安卓 isTablet()：窗口最小边 >= 600 视为平板档（首页边距用 64）。
    static let minimumTabletSmallestSide: CGFloat = 600
    /// 对齐安卓 AppSpacing.screenHorizontalTablet。
    static let tabletHorizontalInset: CGFloat = 64

    static func usesWideLayout(size: CGSize, usesExpandedLayout: Bool) -> Bool {
        // 对齐安卓 isWideScreen()：窗口宽 >= 768 即双列，不区分横竖屏。
        usesExpandedLayout && size.width >= minimumWideWidth
    }

    static func horizontalInset(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        min(size.width, size.height) >= minimumTabletSmallestSide
            ? tabletHorizontalInset
            : Theme.pageHorizontalInset(for: horizontalSizeClass)
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
    @Binding var groupInvitation: GroupInvitation?

    init(onNavigateToTab: ((Int, GameType?) -> Void)? = nil,
         groupInvitation: Binding<GroupInvitation?> = .constant(nil)) {
        self.onNavigateToTab = onNavigateToTab
        _groupInvitation = groupInvitation
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var groups = GroupStore.shared
    @State private var recordIdentity = ParticipantIdentityStore.shared
    @State private var privateRecords = PersonalRecordsCloudSync.shared
    @State private var showGroupNoticeLogin = false
    @State private var showHomeQRScan = false
    @State private var pendingGroupNumber: String?
    @State private var groupReminders = GroupActivityReminder.shared
    @State private var groupPush = GroupPushManager.shared
    @State private var upcomingBookings: [LocalBooking] = []
    @State private var unfinishedRecord: UnfinishedGameSummary?
    @State private var showNewGameDialog = false
    @State private var showNationalDayCampaign = false
    @State private var showQuickStartEditSheet = false
    @State private var isDiscardConfirmationPending = false
    @State private var showDiscardConfirmationToast = false
    @State private var discardConfirmationToken = UUID()
    @State private var resumeLoadErrorMessage: String?
    @State private var resumeLoadTask: Task<Void, Never>?
    @State private var resumeLoadGeneration = UUID()
    #if DEBUG
    @State private var groupCaptureHomePrepared = false
    #endif
    /// A scoreboard saves its final live snapshot from `onDisappear`, after the
    /// navigation path has already returned to Home. Only that transition may
    /// consume the next repository notification; ordinary background saves
    /// must not start Home's mutating abandoned-session reconciliation.
    @State private var awaitsPostNavigationResumeSave = false
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
    @StateObject private var timerVM = TimerRecordsViewModel.shared
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
        case groups
        case groupDetail(groupID: String)
        case groupNotices
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

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let isWide = HomeLayoutPolicy.usesWideLayout(
                    size: geo.size,
                    usesExpandedLayout: usesExpandedLayout
                )
                let contentWidth = geo.size.width - HomeLayoutPolicy.horizontalInset(size: geo.size, horizontalSizeClass: horizontalSizeClass) * 2
                // 68pt bar and 8pt gap: the final card can scroll above the floating bar.
                let unfinishedBarClearance: CGFloat = unfinishedRecord == nil ? 0 : 76
                // 顶栏固定（对齐鸿蒙 HomeHeader），内容区独立滚动，便于后续接入同步计分 banner
                VStack(spacing: 0) {
                    HomeHeaderView(
                        headerDate: headerDate,
                        windowWidth: geo.size.width,
                        horizontalInset: HomeLayoutPolicy.horizontalInset(size: geo.size, horizontalSizeClass: horizontalSizeClass),
                        onCastTapped: {
                            // 宽窗口使用 form sheet，合拢后的窄窗口使用页面。
                            if usesExpandedLayout {
                                homeSheet = .cast
                            } else {
                                path.append(NavigationDestination.cast)
                            }
                        },
                        onScanTapped: { showHomeQRScan = true }
                    )

                    ScrollView(showsIndicators: false) {
                        buildContent(isWide: isWide, contentWidth: contentWidth)
                            .padding(.horizontal, HomeLayoutPolicy.horizontalInset(size: geo.size, horizontalSizeClass: horizontalSizeClass))
                            .padding(.top, Theme.sectionSpacing)
                            .padding(.bottom, Theme.tabContentBottomPadding + unfinishedBarClearance)
                    }
                    .overlay(alignment: .bottom) {
                        unfinishedGameBar
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
                        AppAnalytics.track(.commonDataAction, parameters: [
                            .contentType: .string("quick_start"),
                            .actionName: .string("save"),
                            .participantCount: .int(tertiary == nil ? 2 : 3),
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
                            AppAnalytics.trackContentSelection(
                                contentType: "scoreboard",
                                itemID: gameType.analyticsIdentifier,
                                entryPoint: .homeNewGame
                            )
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
                CenteredSetupDialogPresenter(
                    item: $pendingScoreboardSetupItem,
                    alignment: pendingScoreboardSetupItem?.gameType == .multiScoreboard ? .bottom : .center
                ) { item, dismiss, maxDialogHeight in
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
                        .appAnalyticsScreen(AnalyticsScreen.tool(id: tool.id) ?? .toolsPage)
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
                case .groups:
                    #if DEBUG
                    if GroupCaptureFixture.enabled {
                    GroupCaptureRoot { type, _, sessionID in
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }
                    } else {
                    GroupListView { type, _, sessionID in
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }
                    }
                    #else
                    GroupListView { type, _, sessionID in
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }
                    #endif
                case .groupDetail(let groupID):
                    GroupDetailView(groupID: groupID) { type, _, sessionID in
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }
                case .groupNotices:
                    GroupNoticeInbox { type, _, sessionID in
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }
                    .toolbar(.visible, for: .navigationBar)
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
            .navigationDestination(isPresented: Binding(get: { groupInvitation != nil }, set: { if !$0 { groupInvitation = nil } })) {
                if let invitation = groupInvitation {
                    GroupJoinView(initialGroupNo: invitation.groupNo, onStart: { type, _, sessionID in
                        groupInvitation = nil
                        path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
                    }, usesParentNavigation: true)
                    .id(invitation.id)
                    .toolbar(.hidden, for: .tabBar)
                }
            }
            // Own the invitation's visibility inside the active navigation stack.
            .toolbar(groupInvitation == nil ? .automatic : .hidden, for: .tabBar)
        }
        .sheet(item: $homeSheet) { destination in
            HomeFormSheet(destination: destination)
        }
        .sheet(isPresented: $showGroupNoticeLogin, onDismiss: {
            if SessionStore.shared.isAuthenticated { path.append(NavigationDestination.groupNotices) }
        }) { AccountLoginSheet() }
        .sheet(isPresented: $showHomeQRScan, onDismiss: {
            guard let number = pendingGroupNumber else { return }
            pendingGroupNumber = nil
            groupInvitation = GroupInvitation(groupNo: number)
        }) {
            // 群二维码与登录确认共用扫码流。
            // 扫到群码时先关扫码页，等它真正退出后再置 groupInvitation 推入加群页，
            // 避免"关 Sheet + push"同帧发生把 Tab Bar 的隐藏状态覆盖掉。
            QRLoginApprovalView { number in
                pendingGroupNumber = number
                showHomeQRScan = false
            }
        }
        .sheet(item: $groupPush.destination) { destination in
            GroupPushDestinationView(destination: destination) { type, _, sessionID in
                groupPush.destination = nil
                path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
            }
        }
        .sheet(item: $groupReminders.destination) { destination in
            GroupReminderDestinationView(destination: destination) { type, _, sessionID in
                groupReminders.destination = nil
                path.append(NavigationDestination.scoreboard(.init(gameType: type, recordId: sessionID, setupResult: nil, analyticsEntryPoint: .bookingDetail)))
            }
        }
        .onChange(of: groupInvitation) { _, invitation in
            guard invitation != nil else { return }
            homeSheet = nil
            showNewGameDialog = false
            showCreateBookingSheet = false
            showQuickStartEditSheet = false
            showNationalDayCampaign = false
        }
        .sheet(isPresented: $showNationalDayCampaign) {
            NationalDayMembershipSheet(
                onDismiss: { showNationalDayCampaign = false },
                onOpenAccount: {
                    showNationalDayCampaign = false
                    onNavigateToTab?(4, nil)
                }
            )
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if GroupCaptureFixture.enabled && GroupCaptureFixture.nativeScene == "home" {
                Color.clear.frame(width: 1, height: 1).accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("group_capture_identity").accessibilityLabel("group_capture_identity")
                    .accessibilityValue(GroupCaptureFixture.metadata + ";ready=\(groups.groups.count == 3 && groupCaptureHomePrepared)").allowsHitTesting(false)
            }
        }
        #endif
        .task {
            await groups.refresh()
            #if DEBUG
            if GroupCaptureFixture.enabled && GroupCaptureFixture.nativeScene == "home" && !groupCaptureHomePrepared {
                do {
                    try await GroupCaptureFixture.prepareNativeResume()
                    // Do not remove or hide an unrelated native game just to make the fixture look empty.
                    guard try await ResumeSessionRepository().liveEntries().isEmpty else {
                        throw GroupCaptureFailure.invalidFixture("home contains an unrelated live game; preserving it")
                    }
                    unfinishedRecord = nil; resumeLoadErrorMessage = nil; groupCaptureHomePrepared = true
                } catch { resumeLoadErrorMessage = error.localizedDescription }
            }
            #endif
        }
        .onChange(of: SessionStore.shared.user?.id) { _, id in
            groups.sessionDidChange(userID: id)
            Task { await groups.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await groups.refresh() } }
            // 首页恢复前台时评估活动（对齐安卓：前台 → 方向/弹窗合适 → 先活动后评分）。
            evaluateNationalDayCampaign()
        }
        .onChange(of: homeSheet) { _, destination in
            if destination == nil { evaluateNationalDayCampaign() }
        }
        .onChange(of: showNewGameDialog) { _, shown in
            if !shown { evaluateNationalDayCampaign() }
        }
        .onAppear {
            // Home is a normal page: iPad follows the physical device in all
            // directions, while iPhone returns to portrait.
            OrientationLock.shared.unlock()
            evaluateNationalDayCampaign()
            loadData()
            configureQuickStartDefaultsForCurrentDevice()
            scoreboardVM.ensureLoaded()
            timerVM.ensureLoaded()
            privateRecords.schedule()
            loadUpcomingBookings()
            loadUnfinishedRecord()
            #if DEBUG
            if !didHandleUITestRoute, (ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") || (GroupCaptureFixture.enabled && GroupCaptureFixture.nativeScene != "home")) {
                didHandleUITestRoute = true
                path.append(NavigationDestination.groups)
            }
            if !didHandleUITestRoute,
               ProcessInfo.processInfo.arguments.contains("-UITestOpenTools") {
                didHandleUITestRoute = true
                path.append(NavigationDestination.toolsList)
            }
            #endif
        }
        .onChange(of: path.count) { previousCount, count in
            if count == 0 {
                OrientationLock.shared.unlock()
                // Home itself stays mounted while a scoreboard destination is
                // pushed, so returning here does not trigger HomeTab.onAppear.
                awaitsPostNavigationResumeSave = previousCount > 0
                loadUnfinishedRecord()
            } else {
                awaitsPostNavigationResumeSave = false
            }
        }
        .onChange(of: scoreboardVM.records) { _, _ in
            loadUnfinishedRecord()
        }
        .onChange(of: recordIdentity.state.activeLibraryId) { _, _ in
            unfinishedRecord = nil
            resetDiscardConfirmation()
            loadUnfinishedRecord()
        }
        .onChange(of: recordIdentity.state.archivedLibraries) { _, _ in
            loadUnfinishedRecord()
        }
        .onChange(of: privateRecords.phase) { _, _ in
            if unfinishedRecord.map({ !canAccessUnfinishedRecord($0) }) == true {
                unfinishedRecord = nil
                loadUnfinishedRecord()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ResumeSessionRepository.didChangeNotification
            )
        ) { notification in
            guard awaitsPostNavigationResumeSave,
                  path.isEmpty,
                  let changedRootURL = notification.object as? URL,
                  changedRootURL.standardizedFileURL
                    == ResumeSessionRepository.defaultRootURL().standardizedFileURL else {
                return
            }
            awaitsPostNavigationResumeSave = false
            // Scoreboards persist from onDisappear, after navigation has
            // already revealed Home. Reload again when that async write is
            // durable so the resume bar cannot miss the new session.
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

    @ViewBuilder
    private var unfinishedGameBar: some View {
        if let unfinishedRecord, canAccessUnfinishedRecord(unfinishedRecord) {
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
            .padding(.horizontal, Theme.pageHorizontalInset(for: horizontalSizeClass))
            .padding(.bottom, Theme.sm)
            .animation(.easeInOut(duration: 0.2), value: showDiscardConfirmationToast)
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

    private var usesExpandedLayout: Bool { horizontalSizeClass == .regular }

    private var showsTertiaryQuickStartSlot: Bool {
        QuickStartLayoutPolicy.showsTertiarySlot(
            horizontalSizeClass: horizontalSizeClass,
            isPad: usesExpandedLayout
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

    // MARK: - 国庆会员活动（对齐安卓 HomeTabScreen 触发链：先活动、后评分，互斥）

    /// 展示前先经 `reserve()` 持久化时间戳，进程重启/视图重建都不会重复弹出；
    /// 展示当天由 `NationalDayCampaignReviewGate` 抑制评分邀请。
    private func evaluateNationalDayCampaign() {
        guard scenePhase == .active else { return }
        if !NationalDayCampaignPolicy.isActive() {
            showNationalDayCampaign = false
        }
        guard !showNationalDayCampaign else { return }
        // 有其他首页弹窗/表单时不叠加活动弹窗。
        guard homeSheet == nil, !showNewGameDialog, !showQuickStartEditSheet,
              !showCreateBookingSheet, pendingScoreboardSetupItem == nil,
              !isDiscardConfirmationPending else { return }

        Task { @MainActor in
            guard NationalDayCampaignGate.deviceUsesSimplifiedChinese() else { return }
            guard NationalDayCampaignPolicy.isActive() else { return }
            let prompt = NationalDayCampaignPrompt.shared
            guard !prompt.wasShownToday() else { return }
            guard AppStore.canMakePayments else { return }
            // 已有会员（账号会员或本机 StoreKit 权益）不再打扰。
            guard !SessionStore.shared.isVIP else { return }

            let manager = StoreKitPurchaseManager.shared
            if !manager.didLoadProducts || manager.products.isEmpty {
                await manager.loadProducts()
            }
            guard manager.products.contains(where: { $0.id == StoreKitPurchaseManager.lifetimeProductID }) else { return }
            guard prompt.reserve() else { return }
            showNationalDayCampaign = true
        }
    }

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

    private var recentActivities: [RecordsTabRecordItem] {
        Array(RecordListSource.visibleRecords(
            scoreboard: scoreboardVM.records, timers: timerVM.records,
            cloudRecords: privateRecords.remoteRecords, identity: recordIdentity, cloud: privateRecords
        ).prefix(5))
    }

    private func loadUpcomingBookings() {
        upcomingBookings = LocalBookingManager.shared.getUpcomingPendingBookings(limit: 2)
    }

    private func loadUnfinishedRecord() {
        #if DEBUG
        // Capture preparation owns its exact synthetic sessions. Home's normal scanner may archive older live games.
        if GroupCaptureFixture.enabled { return }
        #endif
        resumeLoadTask?.cancel()
        let generation = UUID()
        resumeLoadGeneration = generation
        let libraryId = recordIdentity.state.activeLibraryId


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
                        guard recordIdentity.state.activeLibraryId == libraryId else { return false }
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
                        guard recordIdentity.state.activeLibraryId == libraryId else { throw CancellationError() }
                        return try await lifecycleCoordinator.archiveIfExpired(sessionID: sessionID)
                    },
                    abandon: { sessionID in
                        guard recordIdentity.state.activeLibraryId == libraryId else { throw CancellationError() }
                        return try await lifecycleCoordinator.abandon(sessionID: sessionID)
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

                let entries = try await repository.liveEntries()
                guard resumeLoadGeneration == generation, recordIdentity.state.activeLibraryId == libraryId, !Task.isCancelled else { return }
                let visibleEntries = entries.filter { entry in
                    let key = PersonalRecordAccessPolicy.resumeRecordKey(entry.sessionId)
                    try? recordIdentity.registerLegacyResumeIfNeeded(recordKey: key, expectedLibraryId: libraryId)
                    return PersonalRecordAccessPolicy.allowsNativeRecord(key)
                }
                var outcome = await scanner.scan(visibleEntries)
                var recordsNeedRefresh = outcome.recordsNeedRefresh

                // A missing envelope can be a harmless index/snapshot race.
                // Reload once, never recursively, and keep all per-entry
                // failures isolated inside the scanner.
                if outcome.shouldReload {
                    await Task.yield()
                    guard resumeLoadGeneration == generation, !Task.isCancelled else { return }
                    let reloaded = try await repository.liveEntries()
                    guard resumeLoadGeneration == generation, recordIdentity.state.activeLibraryId == libraryId, !Task.isCancelled else { return }
                    let retriedEntries = reloaded.filter { entry in
                        let key = PersonalRecordAccessPolicy.resumeRecordKey(entry.sessionId)
                        try? recordIdentity.registerLegacyResumeIfNeeded(recordKey: key, expectedLibraryId: libraryId)
                        return PersonalRecordAccessPolicy.allowsNativeRecord(key)
                    }
                    let retriedOutcome = await scanner.scan(retriedEntries)
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

    private func canAccessUnfinishedRecord(_ summary: UnfinishedGameSummary) -> Bool {
        switch summary.source {
        case .resume(let sessionId):
            return PersonalRecordAccessPolicy.allowsNativeRecord(PersonalRecordAccessPolicy.resumeRecordKey(sessionId))
        }
    }

    private func continueUnfinishedGame() {
        guard let unfinishedRecord, canAccessUnfinishedRecord(unfinishedRecord) else { return }
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
        guard let unfinishedRecord, canAccessUnfinishedRecord(unfinishedRecord) else { return }
        switch unfinishedRecord.source {
        case .resume(let sessionId):
            Task {
                do {
                    let disposition = try await AbandonedResumeSessionCoordinator().abandon(
                        sessionID: sessionId
                    )
                    AppAnalytics.track(.scoreboardAction, parameters: [
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
        // 预约开赛成功后把本次实际使用的篮球规则集/节时/加时写回预约，
        // 之后从同一预约再次开赛按锁定值预填（对齐安卓 lockBookingBasketballSetup）。
        LocalBookingManager.shared.lockBasketballSetup(request.bookingId, setup: request.setup)
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
                        isPad: usesExpandedLayout,
                        isWide: true,
                        availableWidth: columnWidth,
                        onToolClick: { tool in
                            trackHomeToolSelection(tool)
                            path.append(NavigationDestination.tool(tool))
                        }
                    )
                }
                .frame(width: columnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    buildGroupsSection()
                    buildCommonDataSection()
                    buildScheduleSection()
                    buildRecentRecordsSection()
                }
                .frame(width: columnWidth, alignment: .topLeading)
            }
        } else {
            VStack(spacing: Theme.sectionSpacing) {
                buildQuickStartSection()
                buildGroupsSection()
                buildScheduleSection()
                buildCommonDataSection()
                ProToolsSectionView(
                    isPad: usesExpandedLayout,
                    isWide: false,
                    onToolClick: { tool in
                        trackHomeToolSelection(tool)
                        path.append(NavigationDestination.tool(tool))
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
    private func buildGroupsSection() -> some View {
        let visibleGroups = Array(groups.groups.lazy.filter(\.isActive).prefix(2))
        if groups.enabled {
            // 标题栏的 44pt 操作按钮已提供上下留白，避免重复叠加标题间距。
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    SectionTitleView(title: groupText("my_groups", "My groups"))
                        .frame(minHeight: 44)
                    Spacer()
                    Button {
                        if SessionStore.shared.isAuthenticated { path.append(NavigationDestination.groupNotices) }
                        else { showGroupNoticeLogin = true }
                    } label: {
                        Image(systemName: "bell").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 20, height: 44)
                            .overlay(alignment: .topTrailing) {
                                if SessionStore.shared.isAuthenticated && groups.unreadCount > 0 {
                                    Circle().fill(Theme.destructiveText).frame(width: 6, height: 6)
                                        .padding(.top, 7).offset(x: Theme.xs).accessibilityHidden(true)
                                }
                            }
                            .frame(width: 44, height: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("home_group_notices")
                        .accessibilityLabel(groupText("notices", "Notifications"))
                        .accessibilityValue(SessionStore.shared.isAuthenticated && groups.unreadCount > 0 ? "\(groups.unreadCount)" : "")
                    Button { path.append(NavigationDestination.groups) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(groupText("my_groups", "My groups"))
                        .accessibilityIdentifier("home_groups")
                }
                VStack(spacing: 12) {
                    if visibleGroups.isEmpty {
                        homeGroupCard(nil)
                    } else {
                        ForEach(visibleGroups) { group in
                            homeGroupCard(group)
                        }
                    }
                }
            }
        }
    }

    private func homeGroupCard(_ group: ScoreGroup?) -> some View {
        Button {
            if let group {
                path.append(NavigationDestination.groupDetail(groupID: group.id))
            } else {
                path.append(NavigationDestination.groups)
            }
        } label: {
            HStack(spacing: 12) {
                if let group {
                    AppCatalogIcon(gameType: group.sport.gameType, size: 40)
                } else {
                    Image(systemName: "person.3").foregroundStyle(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group?.name ?? groupText("list_add_title", "Create or join a group"))
                        .font(.subheadline.weight(.medium))
                    if let group {
                        Text(group.sport.title + " · " + groupMemberCountText(group.memberCount ?? 0))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(groupText("join_hint", "Join with a group number or QR code."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
            .accessibilityIdentifier(group.map { "home_group_card_\($0.id)" } ?? "home_group_empty")
    }

    @ViewBuilder
    private func buildCommonDataSection() -> some View {
        CommonDataSectionView(
            onNamesTapped: {
                // 宽窗口使用 form sheet，保留当前弹层直到用户关闭。
                if usesExpandedLayout {
                    homeSheet = .commonNames
                } else {
                    path.append(NavigationDestination.commonNames)
                }
            },
            onPlacesTapped: {
                if usesExpandedLayout {
                    homeSheet = .commonPlaces
                } else {
                    path.append(NavigationDestination.commonPlaces)
                }
            }
        )
    }

    private func trackHomeToolSelection(_ tool: ToolItem) {
        AppAnalytics.trackContentSelection(
            contentType: "tool",
            itemID: tool.id,
            entryPoint: .homeTools
        )
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
                    AppAnalytics.trackContentSelection(
                        contentType: "scoreboard",
                        itemID: gameType.analyticsIdentifier,
                        entryPoint: .homeQuickStartPrimary
                    )
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onSecondaryClick: { gameType in
                if quickStartTimerTypes.contains(gameType) {
                    onNavigateToTab?(3, gameType)
                } else {
                    pendingScoreboardEntryPoint = .homeQuickStartSecondary
                    AppAnalytics.trackContentSelection(
                        contentType: "scoreboard",
                        itemID: gameType.analyticsIdentifier,
                        entryPoint: .homeQuickStartSecondary
                    )
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
                    AppAnalytics.trackContentSelection(
                        contentType: "scoreboard",
                        itemID: gameType.analyticsIdentifier,
                        entryPoint: .homeQuickStartSecondary
                    )
                    pendingScoreboardSetupItem = ScoreboardSetupItem(gameType: gameType)
                }
            },
            onNewGameClick: {
                showNewGameDialog = true
            },
            onEditClick: {
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
                        showCreateBookingSheet = true
                    } label: {
                        Text(NSLocalizedString("schedule_new_booking", value: "预约新球局", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textOnPrimary)
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
                        AppAnalytics.trackContentSelection(
                            contentType: "booking",
                            itemID: booking.resolvedGameType?.analyticsIdentifier ?? booking.sportType.rawValue,
                            entryPoint: .scheduleList
                        )
                        path.append(NavigationDestination.bookingDetail(bookingId: booking.id))
                    } label: {
                        HStack(spacing: 12) {
                            AppCatalogIcon(bookingSport: booking.sportType, size: 28)
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
