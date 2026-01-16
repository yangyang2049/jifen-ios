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
                    Image("ic_edit") // $r('app.media.ic_edit')
                        .resizable()
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
                GridRow { // This is the first logical row of the Grid
                    BentoCardView( // Primary Card - occupies (0,0) and (0,1)
                        title: getGameName(type: primarySport),
                        subtitle: startGameText,
                        icon: getGameIcon(type: primarySport),
                        gradientColors: GAME_GRADIENTS[.basketball] ?? [Theme.homePrimaryCardOrange, Theme.homePrimaryCardOrange],
                        onClickCard: { onPrimaryClick?() }
                    )

                    BentoCardView( // Secondary Card - occupies (1,0)
                        title: getGameName(type: secondarySport),
                        icon: getGameIcon(type: secondarySport),
                        gradientColors: getGameGradient(type: secondarySport),
                        isDarkText: false,
                        onClickCard: { onSecondaryClick?() }
                    )
                }

                GridRow { // This is the second logical row of the Grid
                    // The first cell of this row is already occupied by the primary BentoCardView (due to gridCellRows(2)).
                    // So we need to place an empty view for the first column
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) // Empty cell to push the next item to column 1

                    // New Game Button - occupies (1,1)
                    Button(action: {
                        onNewGameClick?()
                    }) {
                        ZStack(alignment: .bottomTrailing) {
                            VStack(alignment: .leading) {
                                Text(newGameShortText)
                                    .font(.system(size: Theme.fontH5, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                Text(allItemsText)
                                    .font(.system(size: Theme.fontCaption, weight: .regular))
                                    .foregroundColor(Theme.homeOverlayWhite)
                                    .padding(.top, Theme.xs)
                                    .textCase(.uppercase)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(Theme.md)

                            Image("ic_fab_add")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(Theme.homeOverlayDark)
                                        .frame(width: 32, height: 32)
                                )
                                .padding(Theme.md)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.homeCardDark)
                        .cornerRadius(Theme.xxl)
                        .shadow(color: Theme.homeButtonShadow, radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
            .frame(height: 240)
        }
        .padding(.top, Theme.lg) // margin({ top: Spacing.lg })
    }
}