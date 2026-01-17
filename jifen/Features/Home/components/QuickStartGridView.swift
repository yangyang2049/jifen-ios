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
                        onClickCard: { onPrimaryClick?(primarySport) }
                    )

                    VStack(spacing: Theme.md) {
                        BentoCardView( // Secondary Card
                            title: getGameName(type: secondarySport),
                            icon: getGameIcon(type: secondarySport),
                            gradientColors: getGameGradient(type: secondarySport),
                            isDarkText: false,
                            onClickCard: { onSecondaryClick?(secondarySport) }
                        )
                        .frame(maxHeight: .infinity) // Added for equal height

                        // Custom New Game Card matching small sports cards layout
                        Button(action: { onNewGameClick?() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Theme.homeSecondaryCardGreen, Theme.homeSecondaryCardGreen]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )

                                VStack(spacing: 8) {
                                    // Top row: Title left, Icon right
                                    HStack {
                                        // Title on the left (matching small card style)
                                        Text(newGameShortText)
                                            .font(.system(size: Theme.fontBody2, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)

                                        Spacer()

                                        // Smaller plus icon on the right
                                        Image(systemName: "plus")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 20, height: 20)
                                            .foregroundColor(.white)
                                    }

                                    Spacer() // Push content to top
                                }
                                .padding(.vertical, 20)
                                .padding(.horizontal, 12)
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
