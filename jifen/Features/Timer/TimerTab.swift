//
//  TimerTab.swift
//  jifen
//
//  计时 Tab：围棋/象棋/国际象棋/魔方/秒表/超时等入口。
//

import SwiftUI

struct TimerTab: View {
    @Binding var pendingTimerGameType: GameType?
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDestination: TimerDestination?
    @State private var pendingDualTimerDest: TimerDestination?
    @State private var queuedDualTimerDest: TimerDestination?
    @State private var goTimerConfig = BoardTimerConfig.default(for: .go)
    @State private var xiangqiTimerConfig = BoardTimerConfig.default(for: .xiangqi)
    @State private var chessTimerConfig = BoardTimerConfig.default(for: .chess)
    @State private var checkersTimerConfig = BoardTimerConfig.default(for: .checkers)

    init(pendingTimerGameType: Binding<GameType?> = .constant(nil)) {
        _pendingTimerGameType = pendingTimerGameType
    }

    private static let dualTimerDestinations: Set<TimerDestination> = Set(GameCatalog.timerAllItems.filter { $0.requiresDualSetup })

    private let columns = [
        GridItem(.flexible(), spacing: Theme.spacing),
        GridItem(.flexible(), spacing: Theme.spacing),
        GridItem(.flexible(), spacing: Theme.spacing)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    timerSectionGroup(title: NSLocalizedString("timer_section_board_games", value: "棋类", comment: ""), items: GameCatalog.timerBoardGameItems)
                    timerSectionGroup(title: NSLocalizedString("timer_section_other", value: "其他", comment: ""), items: GameCatalog.timerOtherItems)
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, Theme.md)
                .padding(.bottom, Theme.lg + 56)
            }
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("tab_timer", value: "计时", comment: "Timer tab"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDestination) { dest in
                timerDestinationView(dest)
                    .toolbar(.hidden, for: .tabBar)
            }
            .onChange(of: pendingTimerGameType) { _, newValue in
                guard let g = newValue else { return }
                if let d = GameCatalog.timerDestination(for: g) {
                    if Self.dualTimerDestinations.contains(d) {
                        pendingDualTimerDest = d
                    } else {
                        selectedDestination = d
                    }
                    pendingTimerGameType = nil
                }
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

    private func timerSectionGroup(title: String, items: [TimerDestination]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(title)
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            LazyVGrid(columns: columns, spacing: Theme.spacing) {
                ForEach(items, id: \.self) { dest in
                    Button {
                        VibrationManager.shared.vibrateLight()
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
                        }
                        .padding(.vertical, Theme.md)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 92)
                        .background {
                            if colorScheme == .light {
                                Color.white
                            } else {
                                Rectangle().fill(.ultraThinMaterial)
                            }
                        }
                        .cornerRadius(Theme.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("timer_dest_\(dest.rawValue)")
                    .accessibilityLabel(dest.title)
                }
            }
        }
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
