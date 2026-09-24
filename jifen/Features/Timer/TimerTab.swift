//
//  TimerTab.swift
//  jifen
//
//  计时 Tab：围棋/象棋/国际象棋/魔方/秒表/超时等入口。
//

import SwiftUI

struct TimerTab: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var pendingTimerGameType: GameType?
    @State private var selectedDestination: TimerDestination?
    @State private var pendingDualTimerDest: TimerDestination?
    @State private var queuedDualTimerDest: TimerDestination?
    @State private var goTimerConfig = BoardTimerConfig.default(for: .go)
    @State private var xiangqiTimerConfig = BoardTimerConfig.default(for: .xiangqi)
    @State private var chessTimerConfig = BoardTimerConfig.default(for: .chess)
    @State private var checkersTimerConfig = BoardTimerConfig.default(for: .checkers)
    @State private var stopwatchState = TimerToolStateStore.loadStopwatch()

    init(pendingTimerGameType: Binding<GameType?> = .constant(nil)) {
        _pendingTimerGameType = pendingTimerGameType
    }

    private static let dualTimerDestinations: Set<TimerDestination> = Set(GameCatalog.timerAllItems.filter { $0.requiresDualSetup })

    private var boardGameItems: [TimerDestination] {
        if Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true {
            return [.chess, .checkers, .go, .xiangqi]
        }
        return GameCatalog.timerBoardGameItems
    }

    var body: some View {
        NavigationStack {
            let usesPadLayout = Theme.usesPadLayout

            GeometryReader { proxy in
                let availableWidth = max(
                    0,
                    min(proxy.size.width, usesPadLayout ? 1080 : .infinity) - Theme.pageHorizontalInset * 2
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        timerSectionGroup(
                            title: NSLocalizedString("timer_section_board_games", value: "棋类", comment: ""),
                            items: boardGameItems,
                            availableWidth: availableWidth,
                            usesPadLayout: usesPadLayout
                        )
                        timerSectionGroup(
                            title: NSLocalizedString("timer_section_other", value: "其他", comment: ""),
                            items: GameCatalog.timerOtherItems,
                            availableWidth: availableWidth,
                            usesPadLayout: usesPadLayout
                        )
                    }
                    .frame(maxWidth: usesPadLayout ? 1080 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pageHorizontalInset)
                    .padding(.top, usesPadLayout ? Theme.lg : Theme.md)
                    .padding(.bottom, Theme.tabContentBottomPadding)
                }
                .background(Theme.backgroundColor)
            }
            .navigationTitle(NSLocalizedString("tab_timer", value: "计时", comment: "Timer tab"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDestination) { dest in
                timerDestinationView(dest)
                    .appAnalyticsScreen(AnalyticsScreen.timer(for: dest))
                    .toolbar(.hidden, for: .tabBar)
            }
            .onChange(of: pendingTimerGameType) { _, newValue in
                guard let g = newValue else { return }
                if let d = GameCatalog.timerDestination(for: g) {
                    AppAnalytics.trackContentSelection(
                        contentType: "timer",
                        itemID: g.analyticsIdentifier,
                        entryPoint: .homeNewGame
                    )
                    if Self.dualTimerDestinations.contains(d) {
                        pendingDualTimerDest = d
                    } else {
                        selectedDestination = d
                    }
                    pendingTimerGameType = nil
                }
            }
            .onAppear(perform: refreshStopwatchState)
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                refreshStopwatchState()
            }
            .onChange(of: selectedDestination) { oldValue, newValue in
                guard oldValue == .stopwatch, newValue == nil else { return }
                refreshStopwatchState()
            }
            .onChange(of: pendingDualTimerDest) { _, newValue in
                guard newValue == nil, let queued = queuedDualTimerDest else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard pendingDualTimerDest == nil else { return }
                    selectedDestination = queued
                    queuedDualTimerDest = nil
                }
            }
            .sheet(item: $pendingDualTimerDest) { dest in
                DualTimerSetupView(
                    gameType: gameType(for: dest),
                    emoji: dest.emoji,
                    initialConfig: config(for: dest),
                    onConfirm: { updatedConfig in
                        AppAnalytics.trackTimerAction("setup_confirm", gameType: updatedConfig.gameType.analyticsIdentifier, parameters: [
                            .presetType: .string(updatedConfig.timeMode.rawValue),
                            .durationMS: .int(Int(updatedConfig.totalMainSeconds * 1_000)),
                        ])
                        saveConfig(updatedConfig, for: dest)
                        queuedDualTimerDest = dest
                        pendingDualTimerDest = nil
                    },
                    onCancel: {
                        queuedDualTimerDest = nil
                        pendingDualTimerDest = nil
                    }
                )
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(Theme.accentColor)
    }

    private func timerSectionGroup(
        title: String,
        items: [TimerDestination],
        availableWidth: CGFloat,
        usesPadLayout: Bool
    ) -> some View {
        // 对齐计分/工具 Tab：iPad 固定一行 4 个，窄屏（<360pt）2 列，其余 3 列。
        let columnCount = usesPadLayout ? 4 : (availableWidth + Theme.padding * 2 < 360 ? 2 : 3)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
            count: columnCount
        )

        return VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            SectionTitleView(title: title)

            LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                ForEach(items, id: \.self) { dest in
                    Button {
                        VibrationManager.shared.vibrateLight()
                        AppAnalytics.trackContentSelection(
                            contentType: "timer",
                            itemID: dest.rawValue,
                            entryPoint: .timerTab
                        )
                        if Self.dualTimerDestinations.contains(dest) {
                            pendingDualTimerDest = dest
                        } else {
                            selectedDestination = dest
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Text(dest.emoji)
                                .font(.system(size: 40))
                            Text(dest.title)
                                .font(.system(size: Theme.fontBody2))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if dest == .stopwatch, stopwatchState.phase != .idle {
                                stopwatchSummary
                            }
                        }
                        .padding(.vertical, Theme.cardPadding)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 92)
                        .background(Theme.appCardBackground)
                        .cornerRadius(Theme.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("timer_dest_\(dest.rawValue)")
                    .accessibilityLabel(dest.title)
                }
            }
        }
    }

    private var stopwatchSummary: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: stopwatchState.phase != .running)) { context in
            HStack(spacing: 5) {
                Circle()
                    .fill(stopwatchState.phase == .running ? Theme.accentColor : Theme.textSecondary)
                    .frame(width: 6, height: 6)
                Text(StopwatchSummaryFormatter.elapsed(stopwatchState.elapsedMilliseconds(at: context.date)))
                    .font(.system(size: Theme.fontCaption, weight: .medium, design: .monospaced))
                Text(NSLocalizedString(
                    stopwatchState.phase == .running ? "timer_status_running" : "timer_status_paused",
                    value: stopwatchState.phase == .running ? "运行中" : "已暂停",
                    comment: "Stopwatch status on timer tab"
                ))
                    .font(.system(size: Theme.fontCaption))
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func refreshStopwatchState() {
        stopwatchState = TimerToolStateStore.loadStopwatch()
    }

    @ViewBuilder
    private func timerDestinationView(_ dest: TimerDestination) -> some View {
        switch dest {
        case .stopwatch:
            StopwatchView()
        case .go:
            DualPlayerTimerView(gameType: .go, config: goTimerConfig)
        case .xiangqi:
            DualPlayerTimerView(gameType: .xiangqi, config: xiangqiTimerConfig)
        case .chess:
            DualPlayerTimerView(gameType: .chess, config: chessTimerConfig)
        case .checkers:
            DualPlayerTimerView(gameType: .checkers, config: checkersTimerConfig)
        case .cube:
            CubeTimerView()
        case .timeout:
            TimeoutCountdownView()
        }
    }

    private func gameType(for dest: TimerDestination) -> GameType {
        switch dest {
        case .go:
            return .go
        case .xiangqi:
            return .xiangqi
        case .chess:
            return .chess
        case .checkers:
            return .checkers
        default:
            return .stopwatch
        }
    }

    private func config(for dest: TimerDestination) -> BoardTimerConfig {
        switch dest {
        case .go:
            return goTimerConfig
        case .xiangqi:
            return xiangqiTimerConfig
        case .chess:
            return chessTimerConfig
        case .checkers:
            return checkersTimerConfig
        default:
            return BoardTimerConfig.default(for: .go)
        }
    }

    private func saveConfig(_ config: BoardTimerConfig, for dest: TimerDestination) {
        switch dest {
        case .go:
            goTimerConfig = config
        case .xiangqi:
            xiangqiTimerConfig = config
        case .chess:
            chessTimerConfig = config
        case .checkers:
            checkersTimerConfig = config
        default:
            break
        }
    }
}

#Preview {
    TimerTab()
}
