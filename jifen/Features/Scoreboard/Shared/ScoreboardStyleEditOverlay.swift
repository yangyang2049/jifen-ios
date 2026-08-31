//
//  ScoreboardStyleEditOverlay.swift
//  jifen
//
//  阶段 3：全屏样式编辑悬浮层，1:1 对齐安卓 ScoreboardStyleEditOverlay.kt：
//  常态只绘制顶部确认/退出与右下角收起式工具入口；打开面板时创建阻断触摸的遮罩与锚定面板。
//

import ScoreCore
import SwiftUI

// MARK: - 面板类型与共享 UI 状态（对齐 ScoreboardStyleEditorUiState.kt）

enum ScoreboardStyleEditPanel: Equatable {
    case none
    case background
    case server
    case font
    case theme
    case element
}

@MainActor
@Observable
final class ScoreboardStyleEditorUiState {
    private(set) var activePanel: ScoreboardStyleEditPanel = .none
    private(set) var activeElementKey: ScoreboardStyleElementKeyV2 = .teamName
    private(set) var activeElementSlot: ScoreboardStyleSlotKeyV2 = .sideLeft

    var isPanelOpen: Bool { activePanel != .none }

    func openElement(_ key: ScoreboardStyleElementKeyV2, slot: ScoreboardStyleSlotKeyV2) {
        activeElementKey = key
        activeElementSlot = slot
        activePanel = .element
    }

    func openBackground(_ slot: ScoreboardStyleSlotKeyV2 = .sideLeft) {
        activeElementSlot = slot
        activePanel = .background
    }

    func openPanel(_ panel: ScoreboardStyleEditPanel) {
        guard panel != .none else { return }
        activePanel = panel
    }

    func closePanel() {
        activePanel = .none
    }

    func reset() {
        activePanel = .none
        activeElementSlot = .sideLeft
    }
}

private struct ScoreboardStyleEditorUiStateKey: EnvironmentKey {
    static let defaultValue: ScoreboardStyleEditorUiState? = nil
}

private struct ScoreboardStyleEditingActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 编辑态下注入，供渲染元素点选（styleElementSelectable）使用。
    var scoreboardStyleEditorUiState: ScoreboardStyleEditorUiState? {
        get { self[ScoreboardStyleEditorUiStateKey.self] }
        set { self[ScoreboardStyleEditorUiStateKey.self] = newValue }
    }

    var scoreboardStyleEditingActive: Bool {
        get { self[ScoreboardStyleEditingActiveKey.self] }
        set { self[ScoreboardStyleEditingActiveKey.self] = newValue }
    }
}

/// 编辑态下把计分板元素变成可点选目标：白框高亮 + 点击打开元素面板（对齐安卓 styleElementSelectable）。
struct ScoreboardStyleElementSelectableModifier: ViewModifier {
    let elementKey: ScoreboardStyleElementKeyV2
    var slotKey: ScoreboardStyleSlotKeyV2?
    var borderWidth: CGFloat = 2
    var cornerRadius: CGFloat = 10
    var contentPadding: CGFloat = 6

    @Environment(\.scoreboardStyleEditingActive) private var editing
    @Environment(\.scoreboardStyleEditorUiState) private var uiState

    func body(content: Content) -> some View {
        if editing, let uiState {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: borderWidth)
                )
                .padding(contentPadding)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius + contentPadding, style: .continuous))
                .onTapGesture { uiState.openElement(elementKey, slot: slotKey ?? .sideLeft) }
        } else {
            content
        }
    }
}

extension View {
    func styleElementSelectable(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2? = nil,
        borderWidth: CGFloat = 2,
        cornerRadius: CGFloat = 10,
        contentPadding: CGFloat = 6
    ) -> some View {
        modifier(ScoreboardStyleElementSelectableModifier(
            elementKey: elementKey,
            slotKey: slotKey,
            borderWidth: borderWidth,
            cornerRadius: cornerRadius,
            contentPadding: contentPadding
        ))
    }
}

// MARK: - 常量（对齐安卓面板配色与预设色板）

private enum StyleEditPalette {
    static let accentGreen = Color(hex: "30D158")
    static let accentGreenSoft = Color.white.opacity(0.16)
    static let accentGreenSubtle = Color.white.opacity(0.08)
    static let surfaceBackground = Color.black.opacity(0.5)
    static let elementPanelBackground = Color.black.opacity(0.75)

    /// 常用背景色板（对齐安卓 BACKGROUND_PRESET_COLORS）。
    static let backgroundPresets = [
        "FFFFFF", "FF3B30", "FF9500", "FFCC00", "34C759",
        "00C7BE", "0A84FF", "5856D6", "FF2D55", "111111",
        "F2F2F7", "C7C7CC", "8E8E93", "48484A", "D9C2A3",
        "C2D1C0", "A9C4D8", "C6B8D6", "D6A8B8", "C9C3A5"
    ]

    /// 约束色板：可作为文字颜色候选（对齐安卓 TEXT_COLOR_CANDIDATES）。
    static let textColorCandidates = [
        "111111", "FFFFFF", "DDDDDD", "777777", "E53935",
        "EF6C00", "FDD835", "43A047", "00897B", "039BE5", "6A1B9A"
    ]

    static let usageHintShownKey = "scoreboard_style_edit_usage_hint_v1_shown"
    static let propagationTimeout: TimeInterval = 5
}

/// 背景编辑目标：单槽位或双侧同色（对齐安卓 BACKGROUND_TARGET_BOTH）。
private enum StyleBackgroundTarget: Equatable {
    case slot(ScoreboardStyleSlotKeyV2)
    case both
}

private struct StyleTextColorRequest: Equatable {
    let slot: ScoreboardStyleSlotKeyV2
    let colorMode: ScoreboardStyleColorModeV2
    let colorHex: String
}

private extension String {
    /// 归一化 hex（非法时保留原样用于显示）。
    var styleDisplayHex: String {
        ScoreboardStyleProfileV2.normalizedHex(self) ?? self
    }

    var styleColor: Color {
        guard let normalized = ScoreboardStyleProfileV2.normalizedHex(self) else { return .white }
        return Color(hex: normalized)
    }
}

private func styleColorsEqual(_ lhs: String, _ rhs: String) -> Bool {
    guard let a = ScoreboardStyleProfileV2.normalizedHex(lhs),
          let b = ScoreboardStyleProfileV2.normalizedHex(rhs) else { return false }
    return a == b
}

/// 最近使用色：去重置顶，最多保留 6 个（对齐安卓 commitRecentColor）。
private func mergeRecentStyleColor(_ colors: [String], _ color: String, limit: Int = 6) -> [String] {
    guard let normalized = ScoreboardStyleProfileV2.normalizedHex(color) else { return colors }
    var next = [normalized]
    for existing in colors where !styleColorsEqual(existing, normalized) {
        next.append(existing)
        if next.count >= limit { break }
    }
    return next
}

private extension ScoreboardStyleProfileV2 {
    func textStyle(for elementKey: ScoreboardStyleElementKeyV2, slot: ScoreboardStyleSlotKeyV2) -> ScoreboardStyleTextColorV2? {
        elements?.first(where: { $0.elementKey == elementKey })?
            .textColors.first(where: { $0.slotKey == slot })
    }
}

/// 元素字号 ↔ 排版偏好指标映射（iOS 字号按 score/name/secondary 三档统一管理）。
private func fontMetric(for elementKey: ScoreboardStyleElementKeyV2) -> ScoreboardFontMetric {
    switch elementKey {
    case .mainScore: return .score
    case .teamName, .playerName: return .name
    case .matchTitle, .setScore, .gameScore, .setGameScore: return .secondary
    }
}

// MARK: - 主悬浮层

/// 全屏样式编辑悬浮层（对齐安卓 ScoreboardStyleEditOverlay）。
struct ScoreboardStyleEditOverlayView: View {
    @Bindable var controller: ScoreboardStyleEditorController
    let typographySession: ScoreboardTypographySession?
    let uiState: ScoreboardStyleEditorUiState
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isLargeLayout: Bool { Theme.usesPadLayout }

    @State private var paletteExpanded = false
    @State private var customColorOpen = false
    @State private var recentColors: [String] = []
    @State private var backgroundTarget: StyleBackgroundTarget = .slot(.sideLeft)
    @State private var textColorPropagationRequest: StyleTextColorRequest?
    @State private var textColorPropagationProgress: Double = 1
    @State private var showUsageHint = false
    @State private var propagationDeadline: Date?

    var body: some View {
        ZStack {
            // 编辑模式下拦截穿透到底层计分视图的点击（对齐安卓 interactionLocked）。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { }

            if uiState.activePanel == .none {
                topControls
                paletteEntry
            } else {
                modalPanel
            }

            if let request = textColorPropagationRequest {
                textColorPropagationPrompt(request)
            }

            if controller.isSaving {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("scoreboard_style_saving_blocker")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreboard_style_editor")
        .animation(.easeInOut(duration: 0.18), value: uiState.activePanel)
        .task {
            recentColors = PreferencesManager.shared.scoreboardRecentStyleColors
            let defaults = UserDefaults.standard
            showUsageHint = defaults.string(forKey: StyleEditPalette.usageHintShownKey) != "true"
        }
        .onChange(of: uiState.activePanel) { _, panel in
            if panel != .none {
                paletteExpanded = false
            }
            customColorOpen = false
            if panel == .background {
                backgroundTarget = resolvedInitialBackgroundTarget()
            }
        }
        .onChange(of: textColorPropagationRequest) { old, new in
            guard new != nil, propagationDeadline == nil else { return }
            _ = old
            runPropagationCountdown()
        }
        .overlay {
            if showUsageHint {
                styleEditUsageHint
            }
        }
    }

    // MARK: 顶部确认/退出

    private var cornerControlSize: CGFloat { isLargeLayout ? 56 : 48 }
    private var cornerIconSize: CGFloat { isLargeLayout ? 26 : 22 }

    private var topControls: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: cornerIconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: cornerControlSize, height: cornerControlSize)
                    .background(StyleEditPalette.surfaceBackground)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .opacity(controller.isSaving ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(controller.isSaving)
            .accessibilityLabel(Text(NSLocalizedString(
                "scoreboard_style_exit_edit", value: "退出样式编辑", comment: ""
            )))

            Spacer()

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.system(size: isLargeLayout ? 28 : 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: cornerControlSize, height: cornerControlSize)
                    .background(StyleEditPalette.accentGreen)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(controller.isSaving)
            .accessibilityLabel(Text(NSLocalizedString(
                "scoreboard_style_confirm_edit", value: "确认样式编辑", comment: ""
            )))
        }
        .padding(.horizontal, isLargeLayout ? 20 : 12)
        .padding(.vertical, isLargeLayout ? 14 : 8)
    }

    private func save() {
        _ = controller.save()
    }

    // MARK: 右下角工具条

    private var paletteEntry: some View {
        let capabilities = controller.capabilities
        let draft = controller.effective
        return Group {
            if paletteExpanded {
                expandedPalette(draft, capabilities)
            } else {
                collapsedPaletteButton(draft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: paletteExpanded ? .bottom : .bottomTrailing)
        .padding(.trailing, paletteExpanded ? 0 : (isLargeLayout ? 20 : 12))
        .padding(.bottom, isLargeLayout ? 20 : 12)
    }

    private func collapsedPaletteButton(_ draft: ScoreboardStyleProfileV2) -> some View {
        Button(action: { paletteExpanded = true }) {
            ZStack {
                Circle()
                    .fill(draft.slotBackgroundHex(.sideLeft).styleColor)
                    .frame(width: 18, height: 18)
                    .offset(x: -5)
                Circle()
                    .fill(draft.slotBackgroundHex(.sideRight).styleColor)
                    .frame(width: 18, height: 18)
                    .offset(x: 5)
            }
            .frame(width: isLargeLayout ? 58 : 50, height: isLargeLayout ? 58 : 50)
            .background(StyleEditPalette.surfaceBackground)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(controller.isSaving)
        .accessibilityLabel(Text(NSLocalizedString(
            "scoreboard_style_editor", value: "样式与颜色", comment: ""
        )))
    }

    private func expandedPalette(
        _ draft: ScoreboardStyleProfileV2,
        _ capabilities: ScoreboardStyleEditCapabilities
    ) -> some View {
        let buttonHeight: CGFloat = isLargeLayout ? 56 : 48
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                if capabilities.hasEditableBackground {
                    paletteColorButton(
                        title: NSLocalizedString("scoreboard_style_background", value: "背景", comment: ""),
                        width: isLargeLayout ? 68 : 60,
                        circles: (draft.slotBackgroundHex(.sideLeft), draft.slotBackgroundHex(.sideRight)),
                        action: { uiState.openBackground(.sideLeft) }
                    )
                }
                if capabilities.supportsServerIndicator {
                    paletteDivider
                    paletteColorButton(
                        title: NSLocalizedString("scoreboard_style_serve", value: "指示", comment: ""),
                        width: isLargeLayout ? 68 : 60,
                        circles: (draft.serverIndicatorColorHex ?? "30D158", nil),
                        action: { uiState.openPanel(.server) }
                    )
                }
                if capabilities.supportsTheme {
                    paletteDivider
                    paletteTextButton(
                        top: {
                            themePreviewCard(for: ScoreboardTheme(rawValue: draft.themeCode) ?? .defaultTheme)
                        },
                        bottom: NSLocalizedString("scoreboard_style_theme", value: "主题", comment: ""),
                        width: isLargeLayout ? 80 : 72,
                        action: { uiState.openPanel(.theme) }
                    )
                }
                if capabilities.supportsFont {
                    paletteDivider
                    paletteTextButton(
                        top: {
                            Text("Aa")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        },
                        bottom: NSLocalizedString("menu_font", value: "字体", comment: ""),
                        width: isLargeLayout ? 64 : 56,
                        action: { uiState.openPanel(.font) }
                    )
                }
                paletteDivider
                paletteTextButton(
                    top: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    },
                    bottom: NSLocalizedString("reset", value: "重置", comment: ""),
                    width: isLargeLayout ? 56 : 50,
                    dimmed: !controller.canResetDraft || controller.isSaving,
                    action: { controller.resetDraft() }
                )
                paletteDivider
                Button(action: { paletteExpanded = false }) {
                    VStack(spacing: 2) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(NSLocalizedString("scoreboard_style_collapse_tools", value: "收起样式工具", comment: ""))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .frame(width: isLargeLayout ? 56 : 50, height: buttonHeight)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, isLargeLayout ? 12 : 10)
            .padding(.vertical, 4)
            .background(StyleEditPalette.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: isLargeLayout ? 30 : 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isLargeLayout ? 30 : 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                Spacer(minLength: 0)
            }
        }
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 2)
    }

    private func paletteColorButton(
        title: String,
        width: CGFloat,
        circles: (left: String, right: String?),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(circles.left.styleColor)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.62), lineWidth: 1))
                    if let right = circles.right {
                        Circle()
                            .fill(right.styleColor)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.62), lineWidth: 1))
                            .offset(x: -5)
                    }
                }
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
            }
            .frame(width: width, height: isLargeLayout ? 56 : 48)
        }
        .buttonStyle(.plain)
    }

    private func paletteTextButton(
        @ViewBuilder top: () -> some View,
        bottom: String,
        width: CGFloat,
        dimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                top()
                Text(bottom)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(width: width, height: isLargeLayout ? 56 : 48)
            .opacity(dimmed ? 0.34 : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    /// 当前项目可选主题（斗地主三栏用 ddz_*，其余通用主题）。
    private var scoreThemeOptions: [ScoreboardTheme] {
        capabilities.slotKeys.contains(.sideCenter)
            ? ScoreboardTheme.doudizhuOptions
            : ScoreboardTheme.genericOptions
    }

    /// 主题迷你预览卡片（1:1 对齐安卓 ic_theme_* 图标：
    /// 背景 + 左右侧面板 + 中缝 + 前景数字 "3/5/2"）。
    private func themePreviewCard(for theme: ScoreboardTheme) -> some View {
        let descriptor = theme.previewDescriptor
        return ZStack {
            Rectangle().fill(Color(hex: descriptor.backgroundHex))
            HStack(spacing: 0) {
                Rectangle().fill(descriptor.leftHex.map { Color(hex: $0) } ?? .clear)
                Rectangle().fill(descriptor.rightHex.map { Color(hex: $0) } ?? .clear)
            }
            if let seamHex = descriptor.seamHex {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color(hex: seamHex))
                        .frame(width: descriptor.leftHex != nil ? 2 : 1)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 0) {
                Text("3")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(hex: descriptor.leftDigitHex))
                    .frame(maxWidth: .infinity)
                if let centerDigitHex = descriptor.centerDigitHex {
                    Text("5")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color(hex: centerDigitHex))
                        .frame(maxWidth: .infinity)
                }
                Text("2")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(hex: descriptor.rightDigitHex))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 34, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    // MARK: 取色辅助

    private var capabilities: ScoreboardStyleEditCapabilities { controller.capabilities }
    private var draft: ScoreboardStyleProfileV2 { controller.effective }

    private func resolvedInitialBackgroundTarget() -> StyleBackgroundTarget {
        let slot = uiState.activeElementSlot
        if capabilities.canEditBackground(slot) {
            return .slot(slot)
        }
        if capabilities.canEditBackground(.sideLeft) { return .slot(.sideLeft) }
        return .slot(.sideRight)
    }

    private func slotBackground(_ slot: ScoreboardStyleSlotKeyV2) -> String {
        draft.slotBackgroundHex(slot)
    }

    private func activeBackgroundColor() -> String {
        switch backgroundTarget {
        case .slot(let slot):
            return slotBackground(slot)
        case .both:
            return slotBackground(.sideLeft)
        }
    }

    private func effectiveTextColor() -> String {
        draft.resolvedElementTextHex(uiState.activeElementKey, slotKey: uiState.activeElementSlot)
    }

    private func isAutoContrastActive() -> Bool {
        draft.textStyle(for: uiState.activeElementKey, slot: uiState.activeElementSlot)?
            .colorMode != .manual
    }

    private func previewBackground(_ color: String) {
        switch backgroundTarget {
        case .both:
            controller.updateDraft(
                draft.withPanelBackground(color, for: .sideLeft)
                    .withPanelBackground(color, for: .sideRight)
            )
        case .slot(let slot):
            controller.updateDraft(draft.withPanelBackground(color, for: slot))
        }
    }

    private func previewServerIndicatorColor(_ color: String) {
        var next = draft
        next.serverIndicatorColorHex = ScoreboardStyleProfileV2.normalizedHex(color)
        controller.updateDraft(next)
    }

    private func previewTextColor(_ color: String) {
        let key = uiState.activeElementKey
        let slot = uiState.activeElementSlot
        var next = draft.withElementTextColor(key, slotKey: slot, mode: .manual, colorHex: color)
        if capabilities.globalElementKeys.contains(key) {
            for other in ScoreboardStyleSlotKeyV2.allCases where other != slot && other.legacySlot != nil {
                next = next.withElementTextColor(key, slotKey: other, mode: .manual, colorHex: color)
            }
        }
        controller.updateDraft(next)
    }

    private func previewActiveColor(_ color: String) {
        switch uiState.activePanel {
        case .background: previewBackground(color)
        case .server: previewServerIndicatorColor(color)
        case .element: previewTextColor(color)
        default: break
        }
    }

    private func customPickerColor() -> String {
        switch uiState.activePanel {
        case .background: return activeBackgroundColor()
        case .server: return draft.serverIndicatorColorHex ?? "30D158"
        case .element: return effectiveTextColor()
        default: return "FFFFFF"
        }
    }

    private func setBackgroundTarget(_ target: StyleBackgroundTarget) {
        if target == .both && backgroundTarget != .both {
            let source = activeBackgroundColor()
            controller.updateDraft(
                draft.withPanelBackground(source, for: .sideLeft)
                    .withPanelBackground(source, for: .sideRight)
            )
        }
        backgroundTarget = target
    }

    private func toggleAutoContrast(_ enabled: Bool) {
        let key = uiState.activeElementKey
        let slot = uiState.activeElementSlot
        var next: ScoreboardStyleProfileV2
        if enabled {
            next = draft.withElementTextColor(key, slotKey: slot, mode: .auto, colorHex: "FFFFFF")
        } else {
            next = draft.withElementTextColor(key, slotKey: slot, mode: .manual, colorHex: effectiveTextColor())
        }
        if capabilities.globalElementKeys.contains(key) {
            let mode: ScoreboardStyleColorModeV2 = enabled ? .auto : .manual
            let color = enabled ? "FFFFFF" : effectiveTextColor()
            for other in ScoreboardStyleSlotKeyV2.allCases where other != slot && other.legacySlot != nil {
                next = next.withElementTextColor(key, slotKey: other, mode: mode, colorHex: color)
            }
        }
        controller.updateDraft(next)
    }

    private func selectTheme(_ theme: ScoreboardTheme) {
        var themed = ScoreboardStyleProfileV2.default(for: controller.styleID, theme: theme)
        themed.serverIndicatorColorHex = draft.serverIndicatorColorHex
        controller.updateDraft(themed)
    }

    private func commitRecentColor(_ color: String) {
        let next = mergeRecentStyleColor(recentColors, color)
        if next != recentColors {
            recentColors = next
            PreferencesManager.shared.rememberScoreboardStyleColors(next)
        }
    }

    // MARK: 文字颜色同侧传播

    private func closeElementPanelWithPropagationCheck() {
        let key = uiState.activeElementKey
        let slot = uiState.activeElementSlot
        // 本次对该元素文字色无任何改动（与已保存样式一致）则不弹出「应用到同侧文字」。
        let changed = controller.active.textStyle(for: key, slot: slot) != draft.textStyle(for: key, slot: slot)
        if capabilities.sideElementKeys.contains(key), changed {
            let style = draft.textStyle(for: key, slot: slot)
            textColorPropagationRequest = StyleTextColorRequest(
                slot: slot,
                colorMode: style?.colorMode ?? .auto,
                colorHex: style?.colorHex ?? effectiveTextColor()
            )
        }
        uiState.closePanel()
    }

    private func runPropagationCountdown() {
        guard textColorPropagationRequest != nil else { return }
        propagationDeadline = Date().addingTimeInterval(StyleEditPalette.propagationTimeout)
        textColorPropagationProgress = 1
        Task { @MainActor in
            let deadline = propagationDeadline ?? Date()
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard textColorPropagationRequest != nil else { return }
                let remaining = deadline.timeIntervalSinceNow / StyleEditPalette.propagationTimeout
                textColorPropagationProgress = max(0, min(1, remaining))
            }
            if textColorPropagationRequest != nil {
                textColorPropagationProgress = 0
                textColorPropagationRequest = nil
            }
            propagationDeadline = nil
        }
    }

    private func applyPropagation(_ request: StyleTextColorRequest) {
        var next = draft
        for key in capabilities.sideElementKeys {
            next = next.withElementTextColor(
                key,
                slotKey: request.slot,
                mode: request.colorMode,
                colorHex: request.colorHex
            )
        }
        controller.updateDraft(next)
        textColorPropagationRequest = nil
        propagationDeadline = nil
    }

    // MARK: 面板容器

    private var modalPanel: some View {
        GeometryReader { proxy in
            let isGlobal = uiState.activePanel == .background ||
                uiState.activePanel == .font ||
                uiState.activePanel == .theme ||
                uiState.activePanel == .server
            let panelAlignment: Alignment = {
                if isGlobal { return .center }
                if uiState.activeElementSlot == .sideLeft { return .trailing }
                if uiState.activeElementSlot == .sideRight { return .leading }
                return .center
            }()
            let maxWidth = proxy.size.width - (isLargeLayout ? 64 : 44)
            let maxHeight = proxy.size.height - (isLargeLayout ? 48 : 40)
            let width = min(
                max(isLargeLayout ? 440.0 : 300.0, proxy.size.width * 0.40),
                isLargeLayout ? 560.0 : 420.0,
                proxy.size.width * 0.48
            )
            let height: CGFloat? = switch uiState.activePanel {
            case .element: maxHeight * 0.92
            case .font: maxHeight * 0.62
            default: maxHeight * 0.84
            }

            ZStack {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { uiState.closePanel() }

                panelCard(width: min(width, maxWidth), height: min(height ?? maxHeight, maxHeight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
            }
        }
        .padding(.horizontal, isLargeLayout ? 32 : 22)
        .padding(.vertical, isLargeLayout ? 24 : 20)
        .ignoresSafeArea(edges: .bottom)
    }

    private func panelCard(width: CGFloat, height: CGFloat?) -> some View {
        VStack(spacing: 0) {
            if customColorOpen {
                customColorHeader
            } else {
                panelHeader
            }
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.7)

            ScrollView(showsIndicators: false) {
                if customColorOpen {
                    CircularColorPickerPage(
                        selectedColor: customPickerColor(),
                        isLargeLayout: isLargeLayout,
                        onPreview: { previewActiveColor($0) },
                        onCommit: { commitRecentColor($0) }
                    )
                    .accessibilityIdentifier("scoreboard_style_custom_color_page")
                } else {
                    switch uiState.activePanel {
                    case .background:
                        backgroundPanel
                    case .server:
                        serverIndicatorPanel
                    case .font:
                        fontPanel
                    case .theme:
                        themePanel
                    case .element:
                        elementPanel
                    case .none:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(uiState.activePanel == .element
            ? StyleEditPalette.elementPanelBackground
            : StyleEditPalette.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: isLargeLayout ? 26 : 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: isLargeLayout ? 26 : 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: isLargeLayout ? 26 : 22, style: .continuous))
        .onTapGesture { }
    }

    private var panelHeader: some View {
        HStack {
            Text(panelTitle)
                .font(.system(size: isLargeLayout ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button(action: {
                if uiState.activePanel == .element {
                    closeElementPanelWithPropagationCheck()
                } else {
                    uiState.closePanel()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(StyleEditPalette.accentGreen)
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString(
                "scoreboard_style_complete_panel", value: "完成当前面板", comment: ""
            )))
        }
        .frame(height: isLargeLayout ? 64 : 56)
        .padding(.leading, isLargeLayout ? 24 : 18)
        .padding(.trailing, isLargeLayout ? 14 : 10)
    }

    private var customColorHeader: some View {
        HStack(spacing: isLargeLayout ? 12 : 10) {
            Button(action: { customColorOpen = false }) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: isLargeLayout ? 20 : 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: isLargeLayout ? 44 : 36, height: isLargeLayout ? 44 : 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("back", value: "返回", comment: "")))
            .accessibilityIdentifier("scoreboard_style_custom_color_back")

            Text(NSLocalizedString("style_custom_color", value: "自定义颜色", comment: ""))
                .font(.system(size: isLargeLayout ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
        }
        .frame(height: isLargeLayout ? 64 : 56)
        .padding(.leading, isLargeLayout ? 14 : 10)
        .padding(.trailing, isLargeLayout ? 24 : 18)
    }

    private var panelTitle: String {
        switch uiState.activePanel {
        case .background:
            return NSLocalizedString("style_background_color", value: "背景颜色", comment: "")
        case .server:
            return NSLocalizedString("style_server_indicator", value: "发球指示器", comment: "")
        case .font:
            return NSLocalizedString("font_selection_title", value: "计分字体", comment: "")
        case .theme:
            return NSLocalizedString("theme_selection_title", value: "计分器主题", comment: "")
        case .element:
            return elementPanelTitle
        case .none:
            return ""
        }
    }

    private var elementPanelTitle: String {
        let side = uiState.activeElementSlot
        let styleIDRaw = controller.styleID.rawValue
        switch uiState.activeElementKey {
        case .matchTitle:
            return NSLocalizedString("match_title", value: "比赛抬头", comment: "")
        case .teamName:
            switch side {
            case .sideCenter: return NSLocalizedString("scoreboard_style_center_team_name", value: "中间队名", comment: "")
            case .sideRight: return NSLocalizedString("scoreboard_style_right_team_name", value: "右侧队名", comment: "")
            default: return NSLocalizedString("scoreboard_style_left_team_name", value: "左侧队名", comment: "")
            }
        case .mainScore:
            switch side {
            case .sideCenter: return NSLocalizedString("scoreboard_style_center_main_score", value: "中间大分数", comment: "")
            case .sideRight: return NSLocalizedString("scoreboard_style_right_main_score", value: "右侧大分数", comment: "")
            default: return NSLocalizedString("scoreboard_style_left_main_score", value: "左侧大分数", comment: "")
            }
        case .setScore:
            if styleIDRaw == "snooker" {
                return NSLocalizedString(
                    side == .sideRight
                        ? "scoreboard_style_snooker_right_break_score"
                        : "scoreboard_style_snooker_left_break_score",
                    value: side == .sideRight ? "右侧单杆分数" : "左侧单杆分数",
                    comment: ""
                )
            }
            return NSLocalizedString(
                side == .sideRight ? "scoreboard_style_right_set_score" : "scoreboard_style_left_set_score",
                value: side == .sideRight ? "右侧局分" : "左侧局分",
                comment: ""
            )
        case .gameScore:
            return NSLocalizedString(
                side == .sideRight ? "scoreboard_style_right_game_score" : "scoreboard_style_left_game_score",
                value: side == .sideRight ? "右侧局分" : "左侧局分",
                comment: ""
            )
        case .setGameScore:
            return NSLocalizedString(
                side == .sideRight ? "scoreboard_style_right_set_games_score" : "scoreboard_style_left_set_games_score",
                value: side == .sideRight ? "右侧局分/盘分" : "左侧局分/盘分",
                comment: ""
            )
        case .playerName:
            return NSLocalizedString(
                side == .sideRight ? "scoreboard_style_right_player_name" : "scoreboard_style_left_player_name",
                value: side == .sideRight ? "右侧队员名" : "左侧队员名",
                comment: ""
            )
        }
    }

    // MARK: 各面板

    private var backgroundPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                if capabilities.canEditBackground(.sideLeft) {
                    backgroundTargetButton(.slot(.sideLeft))
                }
                if capabilities.canEditBackground(.sideCenter) {
                    backgroundTargetButton(.slot(.sideCenter))
                }
                if capabilities.canEditBackground(.sideRight) {
                    backgroundTargetButton(.slot(.sideRight))
                }
                if !capabilities.canEditBackground(.sideCenter),
                   capabilities.canEditBackground(.sideLeft),
                   capabilities.canEditBackground(.sideRight) {
                    backgroundTargetButton(.both)
                }
            }
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(3)

            if backgroundTarget == .both {
                HStack(spacing: 8) {
                    Circle()
                        .fill(slotBackground(.sideLeft).styleColor)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("scoreboard_style_both_backgrounds", value: "左右背景", comment: ""))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.56))
                        Text(slotBackground(.sideLeft).styleDisplayHex)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(StyleEditPalette.accentGreenSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(hex: "30D158").opacity(0.52), lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    if capabilities.canEditBackground(.sideLeft) {
                        backgroundOverviewCard(.sideLeft)
                    }
                    if capabilities.canEditBackground(.sideCenter) {
                        backgroundOverviewCard(.sideCenter)
                    }
                    if capabilities.canEditBackground(.sideRight) {
                        backgroundOverviewCard(.sideRight)
                    }
                }
            }

            ColorPickerPanel(
                selectedColor: activeBackgroundColor(),
                recentColors: recentColors,
                presetColors: StyleEditPalette.backgroundPresets,
                showCurrentColor: false,
                isLargeLayout: isLargeLayout,
                onPreview: { previewBackground($0) },
                onCommit: { commitRecentColor($0) },
                onOpenCustom: { customColorOpen = true }
            )
        }
        .padding(isLargeLayout ? 24 : 18)
    }

    private func backgroundTargetButton(_ target: StyleBackgroundTarget) -> some View {
        let title: String = {
            switch target {
            case .slot(.sideLeft): return NSLocalizedString("style_slot_left", value: "左侧", comment: "")
            case .slot(.sideCenter): return NSLocalizedString("style_slot_center", value: "中间", comment: "")
            case .slot(.sideRight): return NSLocalizedString("style_slot_right", value: "右侧", comment: "")
            case .slot: return NSLocalizedString("style_slot_left", value: "左侧", comment: "")
            case .both: return NSLocalizedString("scoreboard_style_both_same", value: "左右同色", comment: "")
            }
        }()
        let selected = backgroundTarget == target
        return Button(action: { setBackgroundTarget(target) }) {
            Text(title)
                .font(.system(size: isLargeLayout ? 14 : 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                .frame(maxWidth: .infinity)
                .frame(height: isLargeLayout ? 40 : 36)
                .background(selected ? StyleEditPalette.accentGreenSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StyleEditPalette.accentGreen.opacity(0.58), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func backgroundOverviewCard(_ slot: ScoreboardStyleSlotKeyV2) -> some View {
        let color = slot == .sideCenter && !capabilities.canEditBackground(.sideCenter)
            ? slotBackground(.sideLeft)
            : slotBackground(slot)
        let title: String = {
            switch slot {
            case .sideLeft: return NSLocalizedString("style_slot_left", value: "左侧", comment: "")
            case .sideCenter: return NSLocalizedString("style_slot_center", value: "中间", comment: "")
            default: return NSLocalizedString("style_slot_right", value: "右侧", comment: "")
            }
        }()
        let selected = backgroundTarget == .slot(slot)
        return Button(action: { setBackgroundTarget(.slot(slot)) }) {
            VStack(spacing: 4) {
                Circle()
                    .fill(color.styleColor)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                Text(color.styleDisplayHex)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(selected ? StyleEditPalette.accentGreenSubtle : Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? StyleEditPalette.accentGreen.opacity(0.62) : Color.white.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var serverIndicatorPanel: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("scoreboard_style_server_shared_hint", value: "左右指示器共用同一种颜色", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)

            ColorPickerPanel(
                selectedColor: draft.serverIndicatorColorHex ?? "30D158",
                recentColors: recentColors,
                presetColors: StyleEditPalette.textColorCandidates,
                showCurrentColor: true,
                isLargeLayout: isLargeLayout,
                onPreview: { previewServerIndicatorColor($0) },
                onCommit: { commitRecentColor($0) },
                onOpenCustom: { customColorOpen = true }
            )
        }
        .padding(isLargeLayout ? 24 : 18)
    }

    private var fontPanel: some View {
        VStack(spacing: 14) {
            Text(NSLocalizedString("scoreboard_style_font_shared_hint", value: "所有文字统一使用所选字体", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(ScoreboardFont.allCases) { font in
                    Button {
                        typographySession?.updateFont(font)
                    } label: {
                        VStack(spacing: 3) {
                            Text("123")
                                .font(font.swiftUIFont(size: 18))
                                .foregroundStyle(.white)
                            Text(font.localizedTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: isLargeLayout ? 78 : 68)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(isLargeLayout ? 24 : 18)
    }

    private var themePanel: some View {
        VStack(spacing: 14) {
            Text(NSLocalizedString(
                "scoreboard_style_theme_override_hint",
                value: "选择主题会覆盖当前配色；之后可继续单独调整",
                comment: ""
            ))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .leading)

            let columns = Array(stride(from: 0, to: scoreThemeOptions.count, by: 3))
            ForEach(columns, id: \.self) { start in
                HStack(spacing: 8) {
                    ForEach(scoreThemeOptions.dropFirst(start).prefix(3)) { theme in
                        let selected = draft.themeCode == theme.rawValue
                        Button(action: { selectTheme(theme) }) {
                            VStack(spacing: 5) {
                                themePreviewCard(for: theme)
                                Text(theme.localizedTitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.68))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: isLargeLayout ? 78 : 68)
                            .background(selected ? StyleEditPalette.accentGreenSoft : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? StyleEditPalette.accentGreen : Color.white.opacity(0.14), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(isLargeLayout ? 24 : 18)
    }

    private var elementPanel: some View {
        let metric = fontMetric(for: uiState.activeElementKey)
        let range = ScoreboardFontSizePolicy.range(isLargeScreen: isLargeLayout)
        let multiplier = typographySession?.effectivePreference.multiplier(for: metric) ?? 1
        return VStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack {
                    Text(NSLocalizedString("scoreboard_style_font_size", value: "字号", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%.2fx", multiplier))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "30D158"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(StyleEditPalette.accentGreenSubtle)
                        .clipShape(Capsule())
                }
                Slider(
                    value: Binding(
                        get: { multiplier },
                        set: { typographySession?.updateMultiplier($0, for: metric, isLargeScreen: isLargeLayout) }
                    ),
                    in: range
                )
                HStack {
                    Text(NSLocalizedString("scoreboard_style_small", value: "小", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.44))
                    Spacer()
                    Text(NSLocalizedString("scoreboard_style_symmetric_size_same", value: "左右侧字号始终一致", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                    Spacer()
                    Text(NSLocalizedString("scoreboard_style_large", value: "大", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.44))
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(height: 0.7)

            VStack(spacing: 10) {
                HStack {
                    Text(NSLocalizedString("style_text_color", value: "文字颜色", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(NSLocalizedString("style_color_automatic", value: "自动", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.64))
                    Toggle("", isOn: Binding(
                        get: { isAutoContrastActive() },
                        set: { toggleAutoContrast($0) }
                    ))
                    .labelsHidden()
                    .tint(StyleEditPalette.accentGreen)
                }
                ColorPickerPanel(
                    selectedColor: effectiveTextColor(),
                    recentColors: recentColors,
                    presetColors: StyleEditPalette.textColorCandidates,
                    showCurrentColor: true,
                    isLargeLayout: isLargeLayout,
                    onPreview: { previewTextColor($0) },
                    onCommit: { commitRecentColor($0) },
                    onOpenCustom: { customColorOpen = true }
                )
                if !ScoreboardStyleColorMath.isReadableTextColor(
                    effectiveTextColor(),
                    on: slotBackground(uiState.activeElementSlot)
                ) {
                    Text(NSLocalizedString(
                        "scoreboard_style_contrast_warning",
                        value: "当前文字色与背景对比度不足，可能看不清",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(isLargeLayout ? 24 : 18)
    }

    // MARK: 传播提示与使用说明

    private func textColorPropagationPrompt(_ request: StyleTextColorRequest) -> some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { textColorPropagationRequest = nil }

            VStack(spacing: 18) {
                Text(NSLocalizedString(
                    "scoreboard_style_apply_color_same_side",
                    value: "将颜色应用于同侧所有文字？",
                    comment: ""
                ))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(action: { textColorPropagationRequest = nil }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                            Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { applyPropagation(request) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                            Text(NSLocalizedString("confirm", value: "确认", comment: ""))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(StyleEditPalette.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color(hex: "1C1C1E").opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .frame(maxWidth: isLargeLayout ? 400 : 340)
            .padding(.horizontal, 24)

            VStack {
                Spacer()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 4)
                        Rectangle()
                            .fill(StyleEditPalette.accentGreen)
                            .frame(width: proxy.size.width * textColorPropagationProgress, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 18)
            .frame(width: isLargeLayout ? 400 : 340)
            .allowsHitTesting(false)
        }
    }

    private var styleEditUsageHint: some View {
        ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissUsageHint() }

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("scoreboard_style_usage_hint_title", value: "样式编辑使用说明", comment: ""))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                usageHintLine("👆", NSLocalizedString("scoreboard_style_usage_hint_select_text", value: "点击任意带框文字，打开对应的编辑面板", comment: ""))
                usageHintLine("🎨", NSLocalizedString("scoreboard_style_usage_hint_text_panel", value: "在面板中调整文字颜色和字号", comment: ""))
                usageHintLine("⚙️", NSLocalizedString("scoreboard_style_usage_hint_more_styles", value: "点击右下角的样式按钮，编辑背景色、主题和字体等", comment: ""))

                Button(action: { dismissUsageHint() }) {
                    Text(NSLocalizedString("scoreboard_usage_hint_got_it", value: "知道了", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .background(Theme.scoreboardDialogSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 36)
        }
    }

    private func usageHintLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon)
                .font(.system(size: 15))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.86))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dismissUsageHint() {
        showUsageHint = false
        UserDefaults.standard.set(true, forKey: StyleEditPalette.usageHintShownKey)
    }
}

// MARK: - 圆形 HSV 取色器（对齐安卓 CircularColorPickerOverlay）

/// 样式面板内二级页使用的圆形 HSV 取色器。拖动手势实时预览（onPreview），松手提交（onCommit）。
struct CircularColorPickerPage: View {
    let selectedColor: String
    var isLargeLayout: Bool
    let onPreview: (String) -> Void
    let onCommit: (String) -> Void

    @State private var previewColor: String

    private var wheelSize: CGFloat { isLargeLayout ? 210 : 168 }
    private var markerSize: CGFloat { isLargeLayout ? 20 : 18 }

    init(selectedColor: String, isLargeLayout: Bool, onPreview: @escaping (String) -> Void, onCommit: @escaping (String) -> Void) {
        self.selectedColor = selectedColor
        self.isLargeLayout = isLargeLayout
        self.onPreview = onPreview
        self.onCommit = onCommit
        _previewColor = State(initialValue: ScoreboardStyleProfileV2.normalizedHex(selectedColor) ?? "FFFFFF")
    }

    var body: some View {
        VStack(spacing: isLargeLayout ? 14 : 10) {
            currentColorRow
            colorWheel
        }
        .padding(.horizontal, isLargeLayout ? 20 : 16)
        .padding(.vertical, isLargeLayout ? 18 : 14)
    }

    private var currentColorRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(previewColor.styleColor)
                .frame(width: isLargeLayout ? 34 : 30, height: isLargeLayout ? 34 : 30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.48), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("style_current_color", value: "当前颜色", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                Text(previewColor)
                    .font(.system(size: isLargeLayout ? 16 : 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var colorWheel: some View {
        let radius = wheelSize / 2
        let hsv = ScoreboardStyleColorMath.colorToHsv(previewColor)
        let angle = (hsv?.hue ?? 0) * .pi / 180
        let saturation = hsv?.saturation ?? 1
        let markerX = radius + cos(angle) * saturation * radius - markerSize / 2
        let markerY = radius + sin(angle) * saturation * radius - markerSize / 2

        return ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    )
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius * 0.58
                    )
                )
            Circle()
                .fill(previewColor.styleColor)
                .frame(width: markerSize, height: markerSize)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 2)
                .offset(x: markerX - radius + markerSize / 2, y: markerY - radius + markerSize / 2)
        }
        .frame(width: wheelSize, height: wheelSize)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = value.location
                    let dx = (point.x - radius) / radius
                    let dy = (point.y - radius) / radius
                    let next = ScoreboardStyleColorMath.colorWheelPointToHex(pointX: dx, pointY: dy)
                    previewColor = next
                    onPreview(next)
                }
                .onEnded { _ in
                    onCommit(previewColor)
                }
        )
    }
}

// MARK: - 色板（常用色 + 最近色 + 自定义入口，对齐安卓 ColorPickerPanel）

struct ColorPickerPanel: View {
    let selectedColor: String
    let recentColors: [String]
    let presetColors: [String]
    var showCurrentColor: Bool
    var isLargeLayout: Bool
    let onPreview: (String) -> Void
    let onCommit: (String) -> Void
    let onOpenCustom: () -> Void

    var body: some View {
        let displayColors: [String] = {
            var result: [String] = []
            func add(_ color: String) {
                guard let normalized = ScoreboardStyleProfileV2.normalizedHex(color),
                      !result.contains(where: { styleColorsEqual($0, normalized) }) else { return }
                result.append(normalized)
            }
            recentColors.forEach(add)
            presetColors.forEach(add)
            return result
        }()

        return VStack(alignment: .leading, spacing: isLargeLayout ? 14 : 12) {
            if showCurrentColor {
                HStack(spacing: 10) {
                    Circle()
                        .fill(ScoreboardStyleProfileV2.normalizedHex(selectedColor).map { Color(hex: $0) } ?? .white)
                        .frame(width: isLargeLayout ? 40 : 34, height: isLargeLayout ? 40 : 34)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.48), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("style_current_color", value: "当前颜色", comment: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.52))
                        Text(selectedColor.styleDisplayHex)
                            .font(.system(size: isLargeLayout ? 16 : 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            }

            Text(NSLocalizedString("style_common_colors", value: "常用颜色", comment: ""))
                .font(.system(size: isLargeLayout ? 13 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            let rows = (displayColors + ["custom"]).chunked(into: 6)
            ForEach(rows.indices, id: \.self) { rowIndex in
                let row = rows[rowIndex]
                HStack(spacing: isLargeLayout ? 8 : 5) {
                    ForEach(row, id: \.self) { value in
                        if value == "custom" {
                            customColorDot
                        } else {
                            let isSelected = styleColorsEqual(selectedColor, value)
                            Button {
                                onPreview(value)
                                onCommit(value)
                            } label: {
                                Circle()
                                    .fill(value.styleColor)
                                    .frame(width: isLargeLayout ? 38 : 32, height: isLargeLayout ? 38 : 32)
                                    .overlay(Circle().strokeBorder(
                                        isSelected ? StyleEditPalette.accentGreen : Color.white.opacity(0.32),
                                        lineWidth: isSelected ? 3 : 1
                                    ))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var customColorDot: some View {
        let size: CGFloat = isLargeLayout ? 38 : 32
        return Button(action: onOpenCustom) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)
                Circle()
                    .fill(Color(hex: "0C0C0C").opacity(0.96))
                    .frame(width: size - (isLargeLayout ? 14 : 12), height: size - (isLargeLayout ? 14 : 12))
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - 挂载入口

extension View {
    /// 样式编辑悬浮层：编辑会话开启时叠加全屏编辑器（对齐安卓 ScoreboardStyleEditorLayer）。
    /// controller 为 nil（尚未开启过编辑会话）时不挂载。
    func scoreboardStyleEditOverlay(
        controller: ScoreboardStyleEditorController?,
        typographySession: ScoreboardTypographySession?,
        uiState: ScoreboardStyleEditorUiState,
        onCancel: @escaping () -> Void
    ) -> some View {
        overlay {
            if let controller, controller.isEditing {
                ScoreboardStyleEditOverlayView(
                    controller: controller,
                    typographySession: typographySession,
                    uiState: uiState,
                    onCancel: onCancel
                )
                .environment(\.scoreboardStyleEditorUiState, uiState)
                .environment(\.scoreboardStyleEditingActive, true)
                .zIndex(400)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller?.isEditing == true)
    }
}
