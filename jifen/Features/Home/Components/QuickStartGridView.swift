import SwiftUI

struct QuickStartGridView: View {
    let primarySport: GameType
    let secondarySport: GameType
    let tertiarySport: GameType
    let showsTertiarySlot: Bool
    /// 横屏两栏时由 HomeTab 绘制统一标题行，此处仅显示网格
    var showSectionTitle: Bool = true

    var onPrimaryClick: ((GameType) -> Void)? = nil
    var onSecondaryClick: ((GameType) -> Void)? = nil
    var onTertiaryClick: ((GameType) -> Void)? = nil
    var onNewGameClick: (() -> Void)? = nil
    var onEditClick: (() -> Void)? = nil

    @State private var startGameText: String = NSLocalizedString("home_start_game", comment: "Start Game text for QuickStartGrid")
    @State private var startTimerText: String = NSLocalizedString("home_start_timer", value: "Start Timer", comment: "Start Timer text for QuickStartGrid")
    @State private var newGameShortText: String = NSLocalizedString("home_new_game_short", comment: "New Game short text for QuickStartGrid")
    @State private var quickStartText: String = NSLocalizedString("home_quick_start", comment: "Quick Start section title")


    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Column()
            if showSectionTitle {
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
                    .accessibilityIdentifier("home_quick_start_edit")
                }
                .frame(maxWidth: .infinity) // width('100%')
                .padding(.bottom, Theme.sectionContentSpacing)
            }

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
                    .accessibilityIdentifier("home_quick_start_primary")

                    VStack(spacing: Theme.md) {
                        quickStartSportButton(
                            secondarySport,
                            identifier: "home_quick_start_secondary",
                            action: onSecondaryClick
                        )

                        if showsTertiarySlot {
                            quickStartSportButton(
                                tertiarySport,
                                identifier: "home_quick_start_tertiary",
                                action: onTertiaryClick
                            )
                        }

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
                                    Image(systemName: "plus")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer()

                                    Text(newGameShortText)
                                        .font(.system(size: Theme.fontH5, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(Theme.cardPadding)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxHeight: .infinity) // Added for equal height
                        .accessibilityIdentifier("home_quick_start_new_game")
                    }
                }
            }
            .frame(height: showsTertiarySlot ? 320 : 240)
        }
    }

    private func quickStartSportButton(
        _ sport: GameType,
        identifier: String,
        action: ((GameType) -> Void)?
    ) -> some View {
        Button {
            action?(sport)
        } label: {
            BentoCardView(
                title: getGameName(type: sport),
                subtitle: isQuickStartTimerType(sport) ? startTimerText : startGameText,
                icon: getGameIcon(type: sport),
                gradientColors: getGameGradient(type: sport)
            )
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
