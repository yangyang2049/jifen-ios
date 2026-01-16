//
//  HomeTab.swift
//  jifen
//
//  Home tab with new layout from HarmonyOS
//

import SwiftUI
import UIKit // For UIDevice and UIApplication

struct HomeTab: View {
    // MARK: - State & Callbacks
    var onNavigateToTab: ((Int) -> Void)? = nil // Equivalent to onNavigateToTab?: (index: number) => void;
    // onViewAllActivities and onActivitySelected handled within RecentRecordsSectionView

    // Device & Layout State
    @State private var isWide: Bool = false
    @State private var isDarkTheme: Bool = true // Use black UI theme

    // Data State (These will hold combined records from Scoreboard and Timer)
    @State private var recentActivities: [RecentActivity] = []
    
    // Quick Start Config
    // @State private var quickStartConfig: QuickStartConfig = .defaultPhoneConfig // Removed, now observed via manager

    // Dialog & Sheet Presentation States
    @State private var showQuickStartEditSheet: Bool = false
    @State private var showNewGameDialog: Bool = false
    @State private var showSportsSetupSheet: Bool = false // For SportsSetupDialogView
    @State private var setupGameType: GameType? = nil // To pass to setup dialogs
    @State private var showTimerSettingsSheet: Bool = false
    @State private var selectedTimerGameType: GameType? = nil

    // Managers/ViewModels
    @StateObject private var scoreboardRecordsViewModel = ScoreboardRecordsViewModel.shared // Existing
    // @StateObject private var recordsViewModel = RecordsViewModel.getInstance() // Need to create GameRecordsViewModel
    @StateObject private var quickStartConfigManager = QuickStartConfigManager.shared // New
    @State private var scoreboardRecordsListenerId: UUID? = nil

    // --- State for Timer Settings Sheets (if implemented) ---
    // @State private var goSettings: GoTimerSettings? = nil
    // @State private var xiangqiSettings: XiangqiTimerSettings? = nil
    // @State private var chessSettings: ChessTimerSettings? = nil

    // Date State
    @State private var headerDate: String = ""

    // Debounce (not directly translated to UI, but for data refresh)
    @State private var lastRefreshTime: Date = Date()
    private let refreshDebounceTime: TimeInterval = 1.0 // 1000ms

    // MARK: - Body
    var body: some View {
        NavigationView { // Used for potential navigation stack
            ScrollView(.vertical, showsIndicators: false) { // Scroll()
                VStack(spacing: 0) { // Changed from spacing: 0
                    // 1. Header
                    buildHeader()

                    if isWide {
                        buildDesktopLayout()
                    } else {
                        buildMobileLayout()
                        
                        VStack(alignment: .leading, spacing: Theme.md) {
                            Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                                .font(.system(size: Theme.fontH5, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, Theme.lg)
                            
                            RecentRecordsSectionView(
                                records: recentActivities,
                                isDarkTheme: isDarkTheme
                            )
                            .padding(.horizontal, Theme.lg)
                        }
                        .padding(.top, Theme.lg) // Added top padding
                        // Removed .padding(.top, Theme.lg) from Recent Records section
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(isDarkTheme ? Theme.backgroundColor : Theme.homeBackgroundLight) // backgroundColor
            .navigationBarHidden(true) // Hide default navigation bar

            // Sheets and Dialogs
            .sheet(isPresented: $showQuickStartEditSheet) {
                QuickStartEditView(
                    isDarkTheme: isDarkTheme,
                    initialPrimary: quickStartConfigManager.quickStartConfig.primarySport,
                    initialSecondary: quickStartConfigManager.quickStartConfig.secondarySport,
                    onSave: { primary, secondary in
                        Task { // Use Task for async operation
                            do {
                                try await quickStartConfigManager.setPrimarySport(primary)
                                try await quickStartConfigManager.setSecondarySport(secondary)
                            } catch {
                                print("Error saving quick start config: \(error)")
                            }
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showNewGameDialog) { // Using fullScreenCover for NewGameDialog as it occupies full screen in HarmonyOS
                NewGameDialogView(
                    onSelect: { activityType, sourcePage in
                        handleNewGameSelection(type: activityType, sourcePage: sourcePage)
                    },
                    onTimerGameSelected: { gameType in
                        selectedTimerGameType = gameType
                        showTimerSettingsSheet = true
                    }
                )
            }
            .sheet(isPresented: $showSportsSetupSheet) {
                SportsSetupDialogView(
                    gameType: setupGameType ?? .football, // Default if not set
                    defaultTeam1Name: NSLocalizedString("red_team", comment: "Default Team 1 Name"), // Provide default name
                    defaultTeam2Name: NSLocalizedString("blue_team", comment: "Default Team 2 Name"), // Provide default name
                    // initialMaxSets, initialPointsPerSet, initialTieBreakPoints can be passed if needed
                    onConfirm: { config in
                        navigateToSportsWithConfig(gameType: setupGameType ?? .football, config: config)
                    },
                    onCancel: {
                        showSportsSetupSheet = false
                    }
                )
            }
            .sheet(isPresented: $showTimerSettingsSheet) {
                buildTimerSettingsSheetContent()
            }
        }
        .onAppear {
            updateLayoutState()
            updateHeaderDate()
            initializeDataManagers()
            loadQuickStartConfig()
        }
        .onDisappear {
            if let id = scoreboardRecordsListenerId {
                scoreboardRecordsViewModel.removeListener(id)
            }
            // Cleanup listeners if necessary
            // For SwiftUI @StateObject will handle lifecycle better
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateLayoutState() // Update on orientation change
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshDataOnVisible() // Refresh data when app becomes active
        }
    }

    // MARK: - Private Methods
    
    private func updateHeaderDate() {
        let now = Date()
        let monthDayFormatter = DateFormatter()
        monthDayFormatter.dateFormat = "MM月dd日" // Example for "月" and "日"
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE" // Full weekday name
        
        headerDate = "\(monthDayFormatter.string(from: now))  \(weekdayFormatter.string(from: now))"
    }

    private func updateLayoutState() {
        // This is a simplified check. For accurate tablet/2in1 detection,
        // you might need UIDevice.current.userInterfaceIdiom and screen size.
        // For now, if width > 768 is a reasonable proxy for 'wide' on iOS.
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let width = windowScene.interfaceOrientation.isPortrait ? windowScene.screen.bounds.size.width : windowScene.screen.bounds.size.height
            isWide = width >= 768
        }
        // isDarkTheme can be inferred from @Environment(\.colorScheme)
        isDarkTheme = UITraitCollection.current.userInterfaceStyle == .dark
    }

    private func initializeDataManagers() {
        // Initialize recordsViewModel if it was created
        // timerRecordManager.init(uiContext) // No direct equivalent in SwiftUI view, managers should be initialized elsewhere
        // scoreboardRecordManager.init(uiContext)

        // For now, just register listeners and load initial data
        scoreboardRecordsListenerId = scoreboardRecordsViewModel.addListener {
            updateRecentActivities()
        }
        // If GameRecordsViewModel exists
        // recordsViewModel.addListener {
        //    updateRecentActivities()
        // }
        // recordsViewModel.loadRecordsInBackground()

        updateRecentActivities()
    }

    private func loadQuickStartConfig() {
        quickStartConfigManager.loadConfig(isLargeScreen: isWide, is2in1: false) // is2in1 is not directly mapped
    }

    private func updateRecentActivities() {
        let currentScoreboardRecords = scoreboardRecordsViewModel.getRecords()
        // If GameRecordsViewModel exists, combine its records here too
        // let currentTimerRecords = recordsViewModel.getRecords()
        
        var combinedActivities: [RecentActivity] = []

        // Convert ScoreboardRecordSummary to RecentActivity
        currentScoreboardRecords.forEach { record in
            combinedActivities.append(RecentActivity(
                id: record.id,
                activityType: .scoreboard,
                gameType: record.gameType,
                timestamp: record.timestamp,
                title: "\(record.team1Name) vs \(record.team2Name)",
                description: "\(record.team1FinalScore) : \(record.team2FinalScore)"
            ))
        }

        // Dummy timer records for now if GameRecordsViewModel is not implemented yet
        // If GameRecordsViewModel implemented, retrieve timer records and convert similarly
        let dummyTimerRecord = GameRecordSummary(id: UUID().uuidString, gameType: .go, timestamp: Date().timeIntervalSince1970 - 3600, duration: 1200)
        combinedActivities.append(RecentActivity(id: dummyTimerRecord.id, activityType: .timer, gameType: dummyTimerRecord.gameType, timestamp: dummyTimerRecord.timestamp, title: dummyTimerRecord.title, description: dummyTimerRecord.description))


        // Sort by timestamp desc, take top 5
        recentActivities = combinedActivities.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5).map { $0 }
    }

    private func refreshDataOnVisible() {
        let now = Date()
        if now.timeIntervalSince(lastRefreshTime) < refreshDebounceTime { return }
        lastRefreshTime = now

        // Refresh view models
        scoreboardRecordsViewModel.refreshRecords()
        // recordsViewModel.refreshRecords() // if exists
        updateRecentActivities()
    }

    private func handleNewGameSelection(type: ActivityType, sourcePage: SourcePage) {
        if type == .scoreboard { onNavigateToTab?(1) } // Assuming tab 1 is scoreboard
        else if type == .timer { onNavigateToTab?(2) } // Assuming tab 2 is timer
    }

    private func navigateToGame(gameType: GameType) {
        // This will be handled by the NewGameDialogView's internal logic,
        // which then triggers onSelect or onTimerGameSelected.
        // This function might not be directly called from HomeTab anymore.
    }

    private func navigateToSportsWithConfig(gameType: GameType, config: SportsSetupResult) {
        // TODO: Implement actual navigation to sports scoreboard page
        print("Navigate to sports: \(gameType.displayName) with config: \(config)")
        onNavigateToTab?(1) // Navigate to scoreboard tab
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
        }
        .frame(maxWidth: .infinity, alignment: .leading) // Explicitly make HStack fill width and align its content to leading
        .padding(.horizontal, Theme.lg)
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
    }

    @ViewBuilder
    private func buildMobileLayout() -> some View {
        VStack(spacing: Theme.lg) {
            Group { // Wrap QuickStartGridView
                QuickStartGridView(
                    primarySport: quickStartConfigManager.quickStartConfig.primarySport,
                    secondarySport: quickStartConfigManager.quickStartConfig.secondarySport,
                    isDarkTheme: isDarkTheme,
                    onPrimaryClick: {
                        handleGameItemClick(gameType: quickStartConfigManager.quickStartConfig.primarySport)
                    },
                    onSecondaryClick: {
                        handleGameItemClick(gameType: quickStartConfigManager.quickStartConfig.secondarySport)
                    },
                    onNewGameClick: {
                        showNewGameDialog = true
                    },
                    onEditClick: {
                        showQuickStartEditSheet = true
                    }
                )
            } // End Group for QuickStartGridView

            Group { // Wrap ProToolsSectionView as well
                ProToolsSectionView(
                    isWide: false,
                    isDarkTheme: isDarkTheme,
                    onToolClick: { toolId in
                        handleToolClick(toolId: toolId)
                    }
                )
            } // End Group for ProToolsSectionView
            .padding(.top, Theme.lg)
        }
        .padding(.horizontal, Theme.lg) // Padding for the whole mobile layout
    }

    @ViewBuilder
    private func buildDesktopLayout() -> some View {
        Grid(horizontalSpacing: Theme.lg, verticalSpacing: 0) { // Using Theme.lg as gutter, no vertical space at row level for main content
            GridRow {
                Group { // Wrap the first VStack
                    VStack(spacing: Theme.lg) {
                        QuickStartGridView(
                            primarySport: quickStartConfigManager.quickStartConfig.primarySport,
                            secondarySport: quickStartConfigManager.quickStartConfig.secondarySport,
                            isDarkTheme: isDarkTheme,
                            onPrimaryClick: {
                                handleGameItemClick(gameType: quickStartConfigManager.quickStartConfig.primarySport)
                            },
                            onSecondaryClick: {
                                handleGameItemClick(gameType: quickStartConfigManager.quickStartConfig.secondarySport)
                            },
                            onNewGameClick: {
                                showNewGameDialog = true
                            },
                            onEditClick: {
                                showQuickStartEditSheet = true
                            }
                        )
                        
                        ProToolsSectionView(
                            isWide: true,
                            isDarkTheme: isDarkTheme,
                            onToolClick: { toolId in
                                handleToolClick(toolId: toolId)
                            }
                        )
                    }
                } // End Group
                .gridCellColumns(7)
                
                Group { // Wrap the second VStack
                    VStack(alignment: .leading, spacing: Theme.md) {
                        Text(NSLocalizedString("recent_records", comment: "Recent Records Section Title"))
                            .font(.system(size: Theme.fontH5, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        
                            RecentRecordsSectionView(
                                records: recentActivities,
                                isDarkTheme: isDarkTheme
                            )
                    }
                } // End Group
                .gridCellColumns(5)
                .padding(.leading, Theme.lg)
                .padding(.top, Theme.lg)
            }
        }
        .padding(.horizontal, Theme.lg)
    }

    @ViewBuilder
    private func buildTimerSettingsSheetContent() -> some View {
        Group { // Wrap content in Group
            VStack {
                Text(NSLocalizedString("timer_settings_for", comment: "Timer settings for") + " \(selectedTimerGameType?.displayName ?? NSLocalizedString("unknown", comment: "Unknown"))")
                Button(NSLocalizedString("start_game", comment: "Start Game")) {
                    // TODO: Start the timer game
                    print("Start timer game: \(selectedTimerGameType?.displayName ?? "Unknown")")
                    showTimerSettingsSheet = false
                }
                Button(NSLocalizedString("back_to_new_game", comment: "Back to New Game")) {
                    showTimerSettingsSheet = false
                    showNewGameDialog = true // Go back to New Game dialog
                }
            }
        }
        .presentationDetents([.medium, .large]) // For iOS 16+ sheets
    }

    // Helper function to handle game item clicks (from QuickStartGrid or NewGameDialog)
    private func handleGameItemClick(gameType: GameType) {
        let sports: [GameType] = [.football, .basketball, .volleyball, .pingpong, .badminton, .tennis, .billiards, .boxing, .pickleball]
        if sports.contains(gameType) {
            setupGameType = gameType
            showSportsSetupSheet = true
            return
        }



        let timers: [GameType] = [.go, .xiangqi, .chess]
        if timers.contains(gameType) {
            selectedTimerGameType = gameType
            showTimerSettingsSheet = true
            return
        }

        // Direct Navigation Fallback
        // TODO: Implement direct navigation for specific routes
        print("Direct navigation for: \(gameType.displayName)")
        onNavigateToTab?(1) // Default to scoreboard tab
    }
    
    private func handleToolClick(toolId: String) {
        // TODO: Implement actual navigation to tool pages
        print("Handle tool click for: \(toolId)")
        // Example:
        // if toolId == "whistle" { NavigationLink(destination: WhistleToolView()) }
        // etc.
    }
}

// MARK: - Preview
#Preview {
    HomeTab()
}
