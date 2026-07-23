import SwiftUI

private enum WatchHomeItem: String, CaseIterable {
    case badminton
    case badmintonDoubles
    case tennis
    case tennisDoubles
    case pingpong
    case pingpongDoubles
    case pickleball
    case pickleballDoubles
    case archery
    case eightBall
    case nineBall
    case snooker
    /// Watch-only tool (not synced to phone).
    case basketball_training
}

private enum WatchHomePreflightPicker {
    case nineBallPlayers
    case basketballTraining
}

struct WatchHomeTabView: View {
    @Binding var scoreboardRoute: WatchScoreboardRoute?
    @State private var orderedItems: [WatchHomeItem] = WatchHomeItem.allCases
    @State private var preflightPicker: WatchHomePreflightPicker?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(orderedItems, id: \.rawValue) { item in
                        WatchPillButton(icon: icon(for: item), title: title(for: item)) {
                            handleTap(item)
                        }
                    }
                }
                .padding(.horizontal, WatchLayout.tabHorizontalPadding)
                .padding(.bottom, 12)
            }

            if let preflightPicker {
                preflightOverlay(preflightPicker)
            }
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("tab_score", comment: "Score"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { updateOrderedItems() }
    }

    private func icon(for item: WatchHomeItem) -> String {
        switch item {
        case .badminton, .badmintonDoubles: return "🏸"
        case .tennis, .tennisDoubles: return "🎾"
        case .pingpong, .pingpongDoubles: return "🏓"
        case .pickleball, .pickleballDoubles: return "🥒"
        case .archery: return "🏹"
        case .eightBall, .nineBall, .snooker: return "🎱"
        case .basketball_training: return "🏀"
        }
    }

    private func title(for item: WatchHomeItem) -> String {
        switch item {
        case .badminton: return NSLocalizedString("game_badminton", comment: "")
        case .badmintonDoubles: return NSLocalizedString("game_badminton_doubles", value: "羽毛球双打", comment: "")
        case .tennis: return NSLocalizedString("game_tennis", comment: "")
        case .tennisDoubles: return NSLocalizedString("game_tennis_doubles", value: "网球双打", comment: "")
        case .pingpong: return NSLocalizedString("game_pingpong", comment: "")
        case .pingpongDoubles: return NSLocalizedString("game_pingpong_doubles", value: "乒乓球双打", comment: "")
        case .pickleball: return NSLocalizedString("game_pickleball", comment: "")
        case .pickleballDoubles: return NSLocalizedString("game_pickleball_doubles", value: "匹克球双打", comment: "")
        case .archery: return NSLocalizedString("game_archery", comment: "")
        case .eightBall: return NSLocalizedString("game_eight_ball", value: "黑八", comment: "")
        case .nineBall: return NSLocalizedString("game_nine_ball", value: "九球", comment: "")
        case .snooker: return NSLocalizedString("game_snooker", value: "斯诺克", comment: "")
        case .basketball_training: return NSLocalizedString("tool_basketball_training", comment: "")
        }
    }

    private func handleTap(_ item: WatchHomeItem) {
        switch item {
        case .nineBall:
            preflightPicker = .nineBallPlayers
        case .basketball_training:
            preflightPicker = .basketballTraining
        default:
            guard let sport = setupSport(for: item) else { return }
            saveLastSelected(item)
            scoreboardRoute = .setup(sport: sport, playerCount: sport.defaultPlayerCount)
        }
    }

    private func setupSport(for item: WatchHomeItem) -> WatchSetupSport? {
        switch item {
        case .badminton: .badminton
        case .badmintonDoubles: .badmintonDoubles
        case .tennis: .tennis
        case .tennisDoubles: .tennisDoubles
        case .pingpong: .pingpong
        case .pingpongDoubles: .pingpongDoubles
        case .pickleball: .pickleball
        case .pickleballDoubles: .pickleballDoubles
        case .archery: .archery
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .basketball_training: nil
        }
    }

    @ViewBuilder
    private func preflightOverlay(_ picker: WatchHomePreflightPicker) -> some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { preflightPicker = nil }

            VStack(spacing: 12) {
                Text(
                    picker == .nineBallPlayers
                        ? NSLocalizedString("watch_setup_select_players", value: "选择人数", comment: "")
                        : NSLocalizedString("watch_bb_select_mode", value: "选择计分方式", comment: "")
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .multilineTextAlignment(.center)

                if picker == .nineBallPlayers {
                    VStack(spacing: 8) {
                        ForEach(2...4, id: \.self) { count in
                            preflightButton(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("watch_setup_player_count", value: "%d 人", comment: ""),
                                    count
                                )
                            ) {
                                preflightPicker = nil
                                saveLastSelected(.nineBall)
                                scoreboardRoute = .setup(sport: .nineBall, playerCount: count)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            trainingModeButton(.onePoint, title: NSLocalizedString("watch_bb_1pt", value: "1分", comment: ""))
                            trainingModeButton(.twoPoint, title: NSLocalizedString("watch_bb_2pt", value: "2分", comment: ""))
                            trainingModeButton(.threePoint, title: NSLocalizedString("watch_bb_3pt", value: "3分", comment: ""))
                        }
                        trainingModeButton(
                            .free,
                            title: NSLocalizedString("watch_bb_free", value: "自由", comment: ""),
                            fillsWidth: true
                        )
                    }
                }
            }
            .padding(14)
            .frame(width: WatchLayout.isCompactScreen ? 184 : 208)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func trainingModeButton(
        _ mode: WatchBasketballTrainingMode,
        title: String,
        fillsWidth: Bool = false
    ) -> some View {
        Button {
            preflightPicker = nil
            saveLastSelected(.basketball_training)
            scoreboardRoute = .basketballTraining(mode: mode)
        } label: {
            Text(title)
                .font(.system(size: fillsWidth ? 16 : 14, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: WatchLayout.isCompactScreen ? 42 : 50)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }

    private func preflightButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func saveLastSelected(_ item: WatchHomeItem) {
        WatchPreferences.shared.setString(item.rawValue, forKey: "watchLastSelectedGame")
    }

    private func updateOrderedItems() {
        let last = WatchPreferences.shared.string(forKey: "watchLastSelectedGame", defaultValue: "")
        guard let lastItem = WatchHomeItem(rawValue: last) else {
            orderedItems = WatchHomeItem.allCases
            return
        }
        var items = WatchHomeItem.allCases
        if let index = items.firstIndex(of: lastItem), index > 0 {
            items.remove(at: index)
            items.insert(lastItem, at: 0)
        }
        orderedItems = items
    }
}
