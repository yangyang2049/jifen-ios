import SwiftUI

/// 快速开始编辑 — 1:1 对齐鸿蒙 `QuickStartEditDialog`：
/// 上方两个槽位卡片，下方为当前槽位的选项网格。
struct QuickStartEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 自定义主卡片可选项目（不含秒表，与「新比赛」弹窗一致）
    private static let editDialogSports: [GameType] = availableSports.filter { $0 != .stopwatch }

    private enum Slot: Int, CaseIterable {
        case primary = 1
        case secondary = 2

        var badge: String { String(rawValue) }

        var shortTitle: String {
            switch self {
            case .primary:
                return NSLocalizedString("home_quick_primary_slot", value: "主卡片", comment: "")
            case .secondary:
                return NSLocalizedString("home_quick_secondary_slot", value: "副卡片", comment: "")
            }
        }

        var editTitle: String {
            switch self {
            case .primary:
                return NSLocalizedString("home_edit_primary_card", value: "设置主卡片 (大)", comment: "")
            case .secondary:
                return NSLocalizedString("home_edit_secondary_card", value: "设置副卡片 (小)", comment: "")
            }
        }

        var tint: Color {
            switch self {
            case .primary: return Theme.homePrimaryCardOrange
            case .secondary: return Theme.homeSecondaryCardBlue
            }
        }
    }

    var initialPrimary: GameType = .basketball
    var initialSecondary: GameType = .badminton
    var onSave: ((GameType, GameType) -> Void)?

    @State private var selectedPrimary: GameType
    @State private var selectedSecondary: GameType
    @State private var activeSlot: Slot = .primary

    private let optionColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 4
    )

    init(
        initialPrimary: GameType = .basketball,
        initialSecondary: GameType = .badminton,
        onSave: ((GameType, GameType) -> Void)? = nil
    ) {
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

    private var activeSport: Binding<GameType> {
        switch activeSlot {
        case .primary: return $selectedPrimary
        case .secondary: return $selectedSecondary
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        slotCard(.primary, sport: selectedPrimary)
                        slotCard(.secondary, sport: selectedSecondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(activeSlot.badge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textOnPrimary)
                                .frame(width: 20, height: 20)
                                .background(activeSlot.tint, in: Circle())

                            Text(activeSlot.editTitle)
                                .font(.system(size: Theme.fontBody1, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        ScrollView {
                            LazyVGrid(columns: optionColumns, spacing: 8) {
                                ForEach(Self.editDialogSports, id: \.self) { sport in
                                    SportOptionView(
                                        sport: sport,
                                        isSelected: activeSport.wrappedValue == sport,
                                        onClickOption: {
                                            activeSport.wrappedValue = sport
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footerButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
            .background(Theme.backgroundColor)
            .navigationTitle(
                NSLocalizedString("home_customize_quick_start", value: "自定义快捷入口", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.backgroundColor)
    }

    private func slotCard(_ slot: Slot, sport: GameType) -> some View {
        let isSelected = activeSlot == slot
        return Button {
            activeSlot = slot
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(slot.badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textOnPrimary)
                        .frame(width: 20, height: 20)
                        .background(slot.tint, in: Circle())

                    Text(slot.shortTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(getGameIcon(type: sport))
                        .font(.system(size: 16))
                        .lineLimit(1)

                    Text(getGameName(type: sport))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .aspectRatio(2, contentMode: .fit)
            .background(slotCardBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.homeEditButtonGreen : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func slotCardBackground(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return Theme.controlBackground
        }
        return isSelected
            ? Color(hex: "4CAF50").opacity(0.12)
            : Color.white
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                onSave?(selectedPrimary, selectedSecondary)
                dismiss()
            } label: {
                Text(NSLocalizedString("home_complete_and_save", value: "保存", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.homeEditButtonGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
