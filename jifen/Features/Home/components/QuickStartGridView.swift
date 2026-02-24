import SwiftUI

struct QuickStartGridView: View {
    let primarySport: GameType
    let secondarySport: GameType
    var isDarkTheme: Bool = true // Default to black UI
    
    var onPrimaryClick: ((GameType) -> Void)? = nil
    var onSecondaryClick: ((GameType) -> Void)? = nil
    var onNewGameClick: (() -> Void)? = nil
    var onEditClick: (() -> Void)? = nil

    @State private var startGameText: String = NSLocalizedString("home_start_game", comment: "Start Game text for QuickStartGrid")
    @State private var startTimerText: String = NSLocalizedString("home_start_timer", value: "Start Timer", comment: "Start Timer text for QuickStartGrid")
    @State private var newGameShortText: String = NSLocalizedString("home_new_game_short", comment: "New Game short text for QuickStartGrid")
    @State private var allItemsText: String = NSLocalizedString("home_all_items", comment: "All Items text for QuickStartGrid")
    @State private var quickStartText: String = NSLocalizedString("home_quick_start", comment: "Quick Start section title")


    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Column()
            // Header
            HStack { // Row()
                HStack(spacing: Theme.sm) { // Row({ space: Spacing.sm })
                    Text(quickStartText)
                        .font(.system(size: Theme.fontH5, weight: .medium)) // FontSizes.h5, FontWeight.Medium
                        .foregroundColor(Theme.textPrimary) // Colors.textPrimary
                }

                Spacer() // For justifyContent(FlexAlign.SpaceBetween)

                Button(action: {
                    onEditClick?()
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 20, height: 20)
                }
                .frame(width: 44, height: 44)
                .background(Color.clear) // backgroundColor(Color.Transparent)
                .cornerRadius(22) // borderRadius(22)
            }
            .frame(maxWidth: .infinity) // width('100%')
            .padding(.bottom, Theme.md) // margin({ bottom: 16 })

            // Grid (using SwiftUI's native Grid for iOS 16+)
            Grid(horizontalSpacing: Theme.md, verticalSpacing: Theme.md) {
                GridRow {
                    Button(action: {
                        onPrimaryClick?(primarySport)
                    }) {
                        BentoCardView( // Primary Card
                            title: getGameName(type: primarySport),
                            subtitle: isQuickStartTimerType(primarySport) ? startTimerText : startGameText,
                            icon: getGameIcon(type: primarySport),
                            gradientColors: getGameGradient(type: primarySport)
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: Theme.md) {
                        Button(action: {
                            onSecondaryClick?(secondarySport)
                        }) {
                            BentoCardView( // Secondary Card
                                title: getGameName(type: secondarySport),
                                subtitle: isQuickStartTimerType(secondarySport) ? startTimerText : startGameText,
                                icon: getGameIcon(type: secondarySport),
                                gradientColors: getGameGradient(type: secondarySport),
                                isDarkText: false
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxHeight: .infinity) // Added for equal height

                        // Custom New Game Card matching small sports cards layout
                        Button(action: { onNewGameClick?() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Theme.primary, Theme.primaryDark]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .top) {
                                        Text(newGameShortText)
                                            .font(.system(size: Theme.fontH5, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .layoutPriority(1)
                                    }

                                    Text(allItemsText)
                                        .font(.system(size: Theme.fontCaption, weight: .regular))
                                        .foregroundColor(Color.white.opacity(0.85))
                                        .textCase(.uppercase)
                                        .padding(.top, Theme.xs)

                                    Spacer()

                                    HStack {
                                        Spacer()
                                        Image(systemName: "plus")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 32, height: 32)
                                            .background(Color.black.opacity(0.2))
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(Theme.md)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxHeight: .infinity) // Added for equal height
                    }
                }
            }
            .frame(height: 240)
        }
    }
}
