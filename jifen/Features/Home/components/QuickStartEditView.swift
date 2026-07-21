import SwiftUI

struct QuickStartEditView: View {
    @Environment(\.dismiss) var dismiss // For dismissing the sheet

    /// 自定义主卡片可选项目（不含秒表，与「新比赛」弹窗一致）
    private static let editDialogSports: [GameType] = availableSports.filter { $0 != .stopwatch }

    var initialPrimary: GameType = .basketball
    var initialSecondary: GameType = .badminton

    @State private var selectedPrimary: GameType
    @State private var selectedSecondary: GameType

    var onSave: ((GameType, GameType) -> Void)?

    init(initialPrimary: GameType = .basketball, initialSecondary: GameType = .badminton, onSave: ((GameType, GameType) -> Void)? = nil) {
        self.initialPrimary = initialPrimary
        self.initialSecondary = initialSecondary
        self.onSave = onSave
        let list = Self.editDialogSports
        let fallbackPrimary = list.first ?? .basketball
        let fallbackSecondary = list.dropFirst().first ?? fallbackPrimary
        let resolvedPrimary = list.contains(initialPrimary) ? initialPrimary : fallbackPrimary
        let resolvedSecondary = list.contains(initialSecondary) ? initialSecondary : fallbackSecondary
        _selectedPrimary = State(initialValue: resolvedPrimary)
        _selectedSecondary = State(initialValue: resolvedSecondary)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: Theme.md) {
                        sportSection(
                            badge: "1",
                            badgeColor: Theme.homePrimaryCardOrange,
                            title: NSLocalizedString("home_edit_primary_card", comment: "Customize primary card title"),
                            selection: $selectedPrimary,
                            containerWidth: geo.size.width - Theme.lg * 2
                        )

                        sportSection(
                            badge: "2",
                            badgeColor: Theme.homeSecondaryCardBlue,
                            title: NSLocalizedString("home_edit_secondary_card", comment: "Customize secondary card title"),
                            selection: $selectedSecondary,
                            containerWidth: geo.size.width - Theme.lg * 2
                        )
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.md)
                }
            }
            .background(Theme.backgroundColor)
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    onSave?(selectedPrimary, selectedSecondary)
                    dismiss()
                }) {
                    Text(NSLocalizedString("home_complete_and_save", comment: "Save"))
                        .font(.system(size: Theme.fontBody1, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.homeEditButtonGreen)
                        .cornerRadius(.infinity)
                }
                .padding(.horizontal, Theme.lg)
                .padding(.top, Theme.sm)
                .padding(.bottom, Theme.lg)
                .background(Theme.backgroundColor)
            }
            .navigationTitle(NSLocalizedString("home_quick_start", comment: "Quick Start"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.backgroundColor)
    }

    private func sportSection(
        badge: String,
        badgeColor: Color,
        title: String,
        selection: Binding<GameType>,
        containerWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textOnPrimary)
                    .frame(width: 20, height: 20)
                    .background(badgeColor)
                    .cornerRadius(10)

                Text(title)
                    .font(.system(size: Theme.fontBody1, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Spacer()
            }
            .padding(.vertical, Theme.sm)

            LazyVGrid(columns: GameTypeGridLayout.columns(containerWidth: containerWidth), spacing: GameTypeGridLayout.spacing) {
                ForEach(Self.editDialogSports, id: \.self) { sport in
                    SportOptionView(
                        sport: sport,
                        isSelected: selection.wrappedValue == sport,
                        onClickOption: {
                            selection.wrappedValue = sport
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
