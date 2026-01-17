import SwiftUI

struct QuickStartGridView: View {
    let primarySport: GameType
    let secondarySport: GameType
    var isDarkTheme: Bool = true // Default to black UI
    
    var onPrimaryClick: (() -> Void)? = nil
    var onSecondaryClick: (() -> Void)? = nil
    var onNewGameClick: (() -> Void)? = nil
    var onEditClick: (() -> Void)? = nil

    @State private var startGameText: String = NSLocalizedString("home_start_game", comment: "Start Game text for QuickStartGrid")
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
                    BentoCardView( // Primary Card
                        title: getGameName(type: primarySport),
                        subtitle: startGameText,
                        icon: getGameIcon(type: primarySport),
                        gradientColors: [Theme.homePrimaryCardOrange, Theme.homePrimaryCardOrange],
                        onClickCard: { onPrimaryClick?() }
                    )

                    VStack(spacing: Theme.md) {
                        BentoCardView( // Secondary Card
                            title: getGameName(type: secondarySport),
                            icon: getGameIcon(type: secondarySport),
                            gradientColors: getGameGradient(type: secondarySport),
                            isDarkText: false,
                            onClickCard: { onSecondaryClick?() }
                        )
                        .frame(maxHeight: .infinity) // Added for equal height

                        BentoCardView(
                            title: newGameShortText,
                            subtitle: allItemsText,
                            icon: "➕",
                            gradientColors: [Theme.homeSecondaryCardGreen, Theme.homeSecondaryCardGreen],
                            showDecorativeBars: false, // Added to remove deco lines
                            onClickCard: { onNewGameClick?() }
                        )
                        .frame(maxHeight: .infinity) // Added for equal height
                    }
                }
            }
            .frame(height: 240)
        }
    }
}
