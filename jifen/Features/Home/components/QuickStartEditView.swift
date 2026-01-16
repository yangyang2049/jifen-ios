import SwiftUI

struct QuickStartEditView: View {
    @Environment(\.dismiss) var dismiss // For dismissing the sheet

    var isDarkTheme: Bool = true
    var initialPrimary: GameType = .basketball
    var initialSecondary: GameType = .badminton

    @State private var selectedPrimary: GameType
    @State private var selectedSecondary: GameType

    var onSave: ((GameType, GameType) -> Void)?

    init(isDarkTheme: Bool = true, initialPrimary: GameType = .basketball, initialSecondary: GameType = .badminton, onSave: ((GameType, GameType) -> Void)? = nil) {
        self.isDarkTheme = isDarkTheme
        self.initialPrimary = initialPrimary
        self.initialSecondary = initialSecondary
        self.onSave = onSave
        _selectedPrimary = State(initialValue: initialPrimary)
        _selectedSecondary = State(initialValue: initialSecondary)
    }

    var body: some View {
        VStack(spacing: 0) { // Column()
            ScrollView(.vertical, showsIndicators: false) { // Scroll()
                VStack(spacing: Theme.md) { // Column({ space: 16 })
                    // Primary Selection
                    VStack(alignment: .leading, spacing: Theme.sm) { // Column({ space: 8 })
                        HStack(spacing: Theme.sm) { // Row({ space: 8 })
                            Text("1")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.textOnPrimary)
                                .frame(width: 20, height: 20)
                                .background(Theme.homePrimaryCardOrange)
                                .cornerRadius(10)
                            
                            Text(NSLocalizedString("home_edit_primary_card", comment: "Customize primary card title"))
                                .font(.system(size: Theme.fontBody1, weight: .medium))
                                .foregroundColor(isDarkTheme ? Theme.textPrimary : .black)
                            
                            Spacer() // layoutWeight(1)
                        }
                        .frame(maxWidth: .infinity) // width('100%')
                        .padding(.vertical, Theme.sm) // padding({ top: 8, bottom: 8 })

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.sm) { // Grid()
                            ForEach(availableSports, id: \.self) { sport in
                                SportOptionView(
                                    sport: sport,
                                    isSelected: selectedPrimary == sport,
                                    isDarkTheme: isDarkTheme,
                                    onClickOption: {
                                        selectedPrimary = sport
                                    }
                                )
                            }
                        }
                        // .rowsGap(8) .columnsGap(8) handled by LazyVGrid spacing
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // alignItems(HorizontalAlign.Start)

                    // Secondary Selection
                    VStack(alignment: .leading, spacing: Theme.sm) { // Column({ space: 8 })
                        HStack(spacing: Theme.sm) { // Row({ space: 8 })
                            Text("2")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.textOnPrimary)
                                .frame(width: 20, height: 20)
                                .background(Theme.homeSecondaryCardGreen)
                                .cornerRadius(10)
                            
                            Text(NSLocalizedString("home_edit_secondary_card", comment: "Customize secondary card title"))
                                .font(.system(size: Theme.fontBody1, weight: .medium))
                                .foregroundColor(isDarkTheme ? Theme.textPrimary : .black)
                            
                            Spacer() // layoutWeight(1)
                        }
                        .frame(maxWidth: .infinity) // width('100%')
                        .padding(.vertical, Theme.sm) // padding({ top: 8, bottom: 8 })

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.sm) { // Grid()
                            ForEach(availableSports, id: \.self) { sport in
                                SportOptionView(
                                    sport: sport,
                                    isSelected: selectedSecondary == sport,
                                    isDarkTheme: isDarkTheme,
                                    onClickOption: {
                                        selectedSecondary = sport
                                    }
                                )
                            }
                        }
                        // .rowsGap(8) .columnsGap(8) handled by LazyVGrid spacing
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // alignItems(HorizontalAlign.Start)
                }
                .padding(.horizontal, Theme.lg) // padding({ left: 24, right: 24
                .padding(.vertical, Theme.md) // top: 16, bottom: 16
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // layoutWeight(1)
            // .scrollBar(BarState.Auto) -> SwiftUI ScrollView shows indicators by default
            
            // Footer Button
            VStack(spacing: 0) { // Column()
                Button(action: {
                    onSave?(selectedPrimary, selectedSecondary)
                    dismiss() // Dismiss the sheet after saving
                }) {
                    Text(NSLocalizedString("home_complete_and_save", comment: "Complete and Save button"))
                        .font(.system(size: Theme.fontBody1, weight: .bold)) // fontSize(18), fontWeight(FontWeight.Bold)
                        .foregroundColor(.black) // Colors.black
                        .frame(maxWidth: .infinity) // width('100%')
                        .frame(height: 56) // height(56)
                        .background(Theme.homeEditButtonGreen) // backgroundColor(Colors.homeEditButtonGreen)
                        .cornerRadius(.infinity) // type(ButtonType.Capsule)
                }
            }
            .padding(Theme.lg) // padding(24)
            .background(isDarkTheme ? Theme.homeCardDark : Theme.homeCardLight) // backgroundColor
            .overlay( // border
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(isDarkTheme ? Theme.homeOverlayBorder : Theme.homeDividerLight),
                alignment: .top
            )
        }
        .background(isDarkTheme ? Theme.homeCardDark : Theme.homeCardLight) // width('100%'), backgroundColor
    }
}
