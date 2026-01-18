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
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Theme.md) {
                        // Primary Selection
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack(spacing: Theme.sm) {
                                Text("1")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Theme.textOnPrimary)
                                    .frame(width: 20, height: 20)
                                    .background(Theme.homePrimaryCardOrange)
                                    .cornerRadius(10)

                                Text(NSLocalizedString("home_edit_primary_card", comment: "Customize primary card title"))
                                    .font(.system(size: Theme.fontBody1, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)

                                Spacer()
                            }
                            .padding(.vertical, Theme.sm)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.sm) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Secondary Selection
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack(spacing: Theme.sm) {
                                Text("2")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Theme.textOnPrimary)
                                    .frame(width: 20, height: 20)
                                    .background(Theme.homeSecondaryCardBlue)
                                    .cornerRadius(10)

                                Text(NSLocalizedString("home_edit_secondary_card", comment: "Customize secondary card title"))
                                    .font(.system(size: Theme.fontBody1, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)

                                Spacer()
                            }
                            .padding(.vertical, Theme.sm)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.sm) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Save Button
                        Button(action: {
                            onSave?(selectedPrimary, selectedSecondary)
                            dismiss()
                        }) {
                            Text("保存")
                                .font(.system(size: Theme.fontBody1, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Theme.homeEditButtonGreen)
                                .cornerRadius(.infinity)
                        }
                        .padding(.top, Theme.sm)
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.md)
                }
            }
            .navigationTitle(NSLocalizedString("home_quick_start", comment: "Quick Start"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
