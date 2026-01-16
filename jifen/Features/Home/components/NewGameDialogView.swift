import SwiftUI

// MARK: - NewGameDialogView

struct NewGameDialogView: View {
    @Environment(\.dismiss) var dismiss // For dismissing the sheet

    var onSelect: ((ActivityType, SourcePage) -> Void)?
    var onTimerGameSelected: ((GameType) -> Void)? // Changed from String to GameType for type safety
    var sourcePage: SourcePage = .home

    @State private var currentTabIndex: Int = 0
    @State private var showTimerSettings: Bool = false
    @State private var selectedTimerGameType: GameType? = nil // Changed from String to GameType

    // For nested dialogs/sheets
    @State private var showSportsSetup: Bool = false
    @State private var setupGameType: GameType? = nil // To pass to setup dialogs
    @State private var showCardGameSetup: Bool = false
    // For timer settings, these will be passed to HomeTab for sheet presentation


    var body: some View {
        VStack(spacing: 0) {
            // Top blank area, dismiss dialog on tap
            Color.clear
                .contentShape(Rectangle()) // Make the clear color tappable
                .onTapGesture {
                    dismiss()
                }
                .layoutPriority(1)

            // Dialog Content
            HStack(spacing: 0) {
                // Left blank area, dismiss dialog on tap
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .layoutPriority(1)

                if showTimerSettings && selectedTimerGameType != nil {
                    // Show timer settings view
                    buildTimerSettingsView()
                    .contentShape(Rectangle()) // Make it tappable to prevent dismissal from outside
                    .onTapGesture {} // Block tap gesture from propagating to dismiss dialog
                } else {
                    // Show game list
                    VStack(spacing: 0) {
                        // Title and Close Button
                        HStack {
                            Text(NSLocalizedString("dialog_new_game_title", comment: "New Game"))
                                .font(.system(size: Theme.fontH5, weight: .medium))
                                .foregroundColor(Theme.textPrimary)

                            Spacer()

                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark.circle.fill") // Using SF Symbol for close
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(Theme.textSecondary) // Adjust color as needed
                            }
                        }
                        .padding(.horizontal, Theme.lg)
                        .padding(.vertical, Theme.md)

                        // Divider
                        Divider()
                            .overlay(Theme.homeDividerLight)
                            .frame(height: 0.5)

                        // Tabs
                        VStack(spacing: 0) { // Using VStack to simulate Tabs behavior without actual Tabs
                            Picker("", selection: $currentTabIndex) {
                                Text(NSLocalizedString("tab_score", comment: "Scoreboard Tab")).tag(0)
                                Text(NSLocalizedString("tab_timer", comment: "Timer Tab")).tag(1)
                            }
                            .pickerStyle(.segmented) // Segmented picker is a good approximation for tabs
                            .padding(.horizontal, Theme.md)
                            .padding(.vertical, Theme.sm)
                            .background(Theme.homeDialogBackground) // Assuming homeDialogBackground is defined
                            
                            if currentTabIndex == 0 {
                                buildGameList(getScoreboardItems())
                            } else {
                                buildGameList(getTimerItems())
                            }
                        }
                        .background(Theme.homeDialogBackground)
                        .cornerRadius(Theme.md) // Adjust as needed
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // layoutWeight(1)
                    }
                    .frame(width: 350, height: 500) // Approximate width and height for the dialog content
                    .background(Theme.homeDialogBackground)
                    .cornerRadius(Theme.md) // borderRadius
                    .shadow(radius: 5) // Basic shadow
                    .contentShape(Rectangle()) // To prevent taps on transparent areas closing the dialog
                    .onTapGesture {} // Block tap gesture
                }

                // Right blank area, dismiss dialog on tap
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)

            // Bottom blank area, dismiss dialog on tap
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4).ignoresSafeArea()) // Dim background
    }

    private func getScoreboardItems() -> [GameItem] {
        return [
            GameItem(type: .volleyball, nameKey: "tab_volleyball", emoji: GameType.volleyball.icon, route: "VolleyballScoreboard"),
            GameItem(type: .pingpong, nameKey: "tab_pingpong", emoji: GameType.pingpong.icon, route: "PingPongScoreboard"),
            GameItem(type: .tennis, nameKey: "tab_tennis", emoji: GameType.tennis.icon, route: "TennisScoreboard"),
            GameItem(type: .boxing, nameKey: "tab_boxing", emoji: GameType.boxing.icon, route: "BoxingScoreboard"),
            GameItem(type: .guandan, nameKey: "tab_guandan", emoji: GameType.guandan.icon, route: "GuandanScore"),
            GameItem(type: .doudizhu, nameKey: "tab_doudizhu", emoji: GameType.doudizhu.icon, route: "DoudizhuScore"),
            GameItem(type: .multiScoreboard, nameKey: "tab_multi_score", emoji: GameType.multiScoreboard.icon, route: "MultiGroupScore"),
            GameItem(type: .football, nameKey: "tab_football", emoji: GameType.football.icon, route: "FootballScoreboard"),
            GameItem(type: .basketball, nameKey: "tab_basketball", emoji: GameType.basketball.icon, route: "BasketballScoreboard"),
            GameItem(type: .badminton, nameKey: "tab_badminton", emoji: GameType.badminton.icon, route: "BadmintonScoreboard"),
        ]
    }

    private func getTimerItems() -> [GameItem] {
        return [
            GameItem(type: .xiangqi, nameKey: "timer_xiangqi", emoji: GameType.xiangqi.icon, route: "XiangqiTimer"),
            GameItem(type: .go, nameKey: "timer_go", emoji: GameType.go.icon, route: "GoTimer"),
            GameItem(type: .chess, nameKey: "timer_chess", emoji: GameType.chess.icon, route: "ChessTimer"),
        ]
    }

    @ViewBuilder
    private func buildGameList(_ items: [GameItem]) -> some View {
        List {
            ForEach(items) { item in
                Button(action: {
                    handleGameItemClick(item: item)
                }) {
                    buildGameItem(item: item)
                }
                .buttonStyle(PlainButtonStyle()) // To remove default button styling
            }
        }
        .listStyle(.plain)
        // .scrollBar(BarState.Off) handled by listStyle
        // .divider - handled by List default or custom separators
    }

    @ViewBuilder
    private func buildGameItem(item: GameItem) -> some View {
        HStack(spacing: Theme.md) { // Row({ space: 16 })
            // Emoji Icon
            Text(item.emoji)
                .font(.system(size: 28))

            // Name
            Text(NSLocalizedString(item.nameKey, comment: ""))
                .font(.system(size: Theme.fontBody1, weight: .regular))
                .foregroundColor(Theme.textPrimary)
                .layoutPriority(1) // layoutWeight(1)

            // Arrow
            Image(systemName: "chevron.right") // Image($r('app.media.chevron_forward'))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(Theme.textSecondary) // Assuming default color
        }
        .frame(maxWidth: .infinity, alignment: .leading) // width('100%'), justifyContent(FlexAlign.SpaceBetween), alignItems(VerticalAlign.Center)
        .frame(height: 64)
        .padding(.horizontal, Theme.lg) // padding({ left: 20, right: 20 })
        .background(Theme.homeDialogBackground)
    }

    private func handleGameItemClick(item: GameItem) {
        let gameType = item.type
        
        // 1. Sports Games - Show setup dialog
        let sports: [GameType] = [.football, .basketball, .volleyball, .pingpong, .badminton, .tennis, .billiards, .boxing, .pickleball]
        if sports.contains(gameType) {
            dismiss() // Close current dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // Simulate setTimeout
                setupGameType = gameType
                showSportsSetup = true
            }
            return
        }

        // 2. Card Games - Show setup dialog
        let cards: [GameType] = [.doudizhu, .guandan, .simpleScore, .multiScoreboard]
        if cards.contains(gameType) {
            dismiss() // Close current dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // Simulate setTimeout
                setupGameType = gameType
                showCardGameSetup = true
            }
            return
        }

        // 3. Timer Games - Notify parent to show bindSheet
        let timers: [GameType] = [.go, .xiangqi, .chess]
        if timers.contains(gameType) {
            dismiss() // Close current dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // Simulate setTimeout
                onTimerGameSelected?(gameType)
            }
            return
        }

        // 4. Direct Navigation Fallback
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Simulate setTimeout
            // TODO: Implement actual navigation using item.route (e.g., using a NavigationStack or similar)
            print("Direct navigation to: \(item.route)")
            onSelect?(.scoreboard, sourcePage) // Assuming direct navigations are scoreboard types
        }
    }

    @ViewBuilder
    private func buildTimerSettingsView() -> some View {
        // Placeholder for Timer Settings Views
        VStack {
            Text("Timer Settings for \(selectedTimerGameType?.displayName ?? "Unknown")")
            Button("Start Game") {
                startTimerGame()
            }
            Button("Back") {
                showTimerSettings = false
                selectedTimerGameType = nil
            }
        }
        .frame(width: 350, height: 500) // Match dialog size
        .background(Theme.homeDialogBackground)
        .cornerRadius(Theme.md)
    }

    private func startTimerGame() {
        guard let gameType = selectedTimerGameType else { return }

        // TODO: Implement actual navigation to timer pages with settings
        print("Starting timer game: \(gameType.displayName)")
        dismiss()
        onSelect?(.timer, sourcePage) // Notify parent that a timer game was selected
    }
}

