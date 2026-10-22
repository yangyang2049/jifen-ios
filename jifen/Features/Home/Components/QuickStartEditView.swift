import SwiftUI

/// 快速开始编辑 — 1:1 对齐鸿蒙 `QuickStartEditDialog`：
/// 紧凑宽度显示两个槽位，常规宽度显示三个槽位。
struct QuickStartEditView: View {
    @Environment(\.dismiss) private var dismiss

    /// 自定义主卡片可选项目（不含秒表，与「新比赛」弹窗一致）
    private static let editDialogSports = QuickStartConfig.selectableGameTypes

    private enum Slot: Int, CaseIterable {
        case primary = 1
        case secondary = 2
        case tertiary = 3

        var badge: String { String(rawValue) }

        var shortTitle: String {
            switch self {
            case .primary:
                return NSLocalizedString("home_quick_primary_slot", value: "主卡片", comment: "")
            case .secondary:
                return NSLocalizedString("home_quick_secondary_slot", value: "副卡片", comment: "")
            case .tertiary:
                return NSLocalizedString("home_quick_tertiary_slot", value: "第三卡片", comment: "")
            }
        }

        var editTitle: String {
            switch self {
            case .primary:
                return NSLocalizedString("home_edit_primary_card", value: "设置主卡片 (大)", comment: "")
            case .secondary:
                return NSLocalizedString("home_edit_secondary_card", value: "设置副卡片 (小)", comment: "")
            case .tertiary:
                return NSLocalizedString("home_edit_tertiary_card", value: "设置第三卡片 (小)", comment: "")
            }
        }

        var tint: Color {
            switch self {
            case .primary: return Theme.homePrimaryCardOrange
            case .secondary: return Theme.homeSecondaryCardGreen
            case .tertiary: return Color(hex: "3B82F6")
            }
        }
    }

    var initialPrimary: GameType = QuickStartConfig.defaultPhoneConfig.primarySport
    var initialSecondary: GameType = QuickStartConfig.defaultPhoneConfig.secondarySport
    var initialTertiary: GameType = QuickStartConfig.defaultPhoneConfig.tertiarySport
    var showsTertiarySlot: Bool = false
    var onSave: ((GameType, GameType, GameType?) -> Void)?

    @State private var selectedPrimary: GameType
    @State private var selectedSecondary: GameType
    @State private var selectedTertiary: GameType
    @State private var activeSlot: Slot = .primary

    private let optionColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 4
    )

    init(
        initialPrimary: GameType = QuickStartConfig.defaultPhoneConfig.primarySport,
        initialSecondary: GameType = QuickStartConfig.defaultPhoneConfig.secondarySport,
        initialTertiary: GameType = QuickStartConfig.defaultPhoneConfig.tertiarySport,
        showsTertiarySlot: Bool = false,
        onSave: ((GameType, GameType, GameType?) -> Void)? = nil
    ) {
        self.initialPrimary = initialPrimary
        self.initialSecondary = initialSecondary
        self.initialTertiary = initialTertiary
        self.showsTertiarySlot = showsTertiarySlot
        self.onSave = onSave
        let list = Self.editDialogSports
        let defaults = QuickStartConfig.defaultPhoneConfig
        let fallbackPrimary = defaults.primarySport
        let fallbackSecondary = defaults.secondarySport
        let fallbackTertiary = defaults.tertiarySport
        let resolvedPrimary = list.contains(initialPrimary) ? initialPrimary : fallbackPrimary
        let resolvedSecondary = list.contains(initialSecondary) ? initialSecondary : fallbackSecondary
        let resolvedTertiary = list.contains(initialTertiary) ? initialTertiary : fallbackTertiary
        _selectedPrimary = State(initialValue: resolvedPrimary)
        _selectedSecondary = State(initialValue: resolvedSecondary)
        _selectedTertiary = State(initialValue: resolvedTertiary)
    }

    private var visibleSlots: [Slot] {
        showsTertiarySlot ? Slot.allCases : [.primary, .secondary]
    }

    private var activeSport: Binding<GameType> {
        switch activeSlot {
        case .primary: return $selectedPrimary
        case .secondary: return $selectedSecondary
        case .tertiary: return $selectedTertiary
        }
    }

    private func sport(for slot: Slot) -> GameType {
        switch slot {
        case .primary: selectedPrimary
        case .secondary: selectedSecondary
        case .tertiary: selectedTertiary
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        ForEach(visibleSlots, id: \.self) { slot in
                            slotCard(slot, sport: sport(for: slot))
                        }
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
                                        },
                                        // 图标按卡片边长插值：iPhone 卡片 84pt → 28pt（保持不变），
                                        // iPad / Duo 展开内屏 128pt → 45pt（可见图形约 32pt）。
                                        iconSizeProvider: Theme.quickStartGridIconSize(cardSide:)
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
            .background(Theme.dialogSurfaceBackground)
            .navigationTitle(
                NSLocalizedString("home_customize_quick_start", value: "自定义快捷入口", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: showsTertiarySlot) { _, isVisible in
            if !isVisible && activeSlot == .tertiary {
                activeSlot = .primary
            }
        }
    }

    private func slotCard(_ slot: Slot, sport: GameType) -> some View {
        let isSelected = activeSlot == slot
        return Button {
            activeSlot = slot
        } label: {
            // 卡片高度在 iPhone 是 87pt、iPad / Duo 展开内屏约 132pt；
            // 卡内所有元素按同一比例缩放，避免宽屏下"框大内容小"。
            GeometryReader { geo in
                let scale = min(1.5, max(1, geo.size.height / 87))
                VStack(alignment: .leading, spacing: 6 * scale) {
                    HStack(spacing: 6 * scale) {
                        Text(slot.badge)
                            .font(.system(size: 12 * scale, weight: .bold))
                            .foregroundStyle(Theme.textOnPrimary)
                            .frame(width: 20 * scale, height: 20 * scale)
                            .background(slot.tint, in: Circle())

                        Text(slot.shortTitle)
                            .font(.system(size: 12 * scale, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6 * scale) {
                        AppCatalogIcon(gameType: sport, size: 16 * scale)

                        Text(getGameName(type: sport))
                            .font(.system(size: 16 * scale, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 8 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .aspectRatio(2, contentMode: .fit)
            .background(slotCardBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.homeEditButtonGreen : .clear, lineWidth: 2)
            )
            .shadow(
                color: isSelected ? .clear : Theme.lightModeShadow(0.08),
                radius: 8,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick_start_edit_slot_\(slot.rawValue)")
    }

    private func slotCardBackground(isSelected: Bool) -> Color {
        isSelected ? Theme.editSlotSelectedFill : Theme.editSlotFill
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
                    .background(Theme.dialogControlBackground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                onSave?(
                    selectedPrimary,
                    selectedSecondary,
                    showsTertiarySlot ? selectedTertiary : nil
                )
                dismiss()
            } label: {
                Text(NSLocalizedString("home_complete_and_save", value: "保存", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.homeEditButtonGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
