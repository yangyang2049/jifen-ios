//
//  ScoreboardStyleEditOverlay.swift
//  jifen
//
//  阶段 3：全屏样式编辑悬浮层，1:1 对齐安卓 ScoreboardStyleEditOverlay.kt：
//  常态只绘制顶部确认/退出与右下角收起式工具入口；打开面板时创建阻断触摸的遮罩与锚定面板。
//

import ScoreCore
import SwiftUI
import PhotosUI

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
    var contentPadding: CGFloat = 0

    @Environment(\.scoreboardStylePreviewSwapped) private var previewSwapped
    @Environment(\.scoreboardStyleEditingActive) private var editing
    @Environment(\.scoreboardStyleEditorUiState) private var uiState

    private var selectedSlot: ScoreboardStyleSlotKeyV2 {
        guard previewSwapped else { return slotKey ?? .sideLeft }
        if slotKey == .sideLeft { return .sideRight }
        if slotKey == .sideRight { return .sideLeft }
        return slotKey ?? .sideLeft
    }

    func body(content: Content) -> some View {
        if editing, let uiState {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: borderWidth)
                )
                .padding(contentPadding)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius + contentPadding, style: .continuous))
                .highPriorityGesture(TapGesture().onEnded { uiState.openElement(elementKey, slot: selectedSlot) })
                .accessibilityIdentifier("style_element_\(elementKey.rawValue)_\((slotKey ?? .sideLeft).rawValue)")
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
        contentPadding: CGFloat = 0
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
    /// 工作台整体底色（与安卓 ScoreboardStyleEditOverlay `0xFF0E131A` 一致）。
    static let workbenchCanvas = Color(hex: "0E131A")
    /// 元素面板比普通面板再亮一档，保证选中态与正文可读。
    static let elementPanelBackground = Color(hex: "1F252D")
    /// 面板内控件/胶囊底色（对齐安卓 `0xFF272D35`）。
    static let controlBackground = Color(hex: "272D35")

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
}

/// 背景编辑目标：单槽位或双侧同色（对齐安卓 BACKGROUND_TARGET_BOTH）。
private enum StyleBackgroundTarget: Equatable {
    case slot(ScoreboardStyleSlotKeyV2)
    case both
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

// MARK: - 主悬浮层

/// 全屏样式编辑悬浮层（对齐安卓 ScoreboardStyleEditOverlay）。
struct ScoreboardStyleEditOverlayView: View {
    /// Clearance for previews whose content begins at the very top edge.
    static var topControlsReservedHeight: CGFloat { Theme.usesPadLayout ? 84 : 64 }

    @Bindable var controller: ScoreboardStyleEditorController
    let typographySession: ScoreboardTypographySession?
    let uiState: ScoreboardStyleEditorUiState
    var onCancel: () -> Void

    private var isLargeLayout: Bool { Theme.usesPadLayout }

    @ObservedObject private var displayOutputs = ScoreboardDisplayOutputs.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var imageBusy = false
    @State private var imageError = false
    @State private var imageUndo: ScoreboardPhotoImageUndo?
    @State private var fullPreview = false
    @State private var castPreview = false
    @State private var workbenchTab = "theme"
    @State private var customColorOpen = false
    @State private var recentColors: [String] = []
    @State private var backgroundTarget: StyleBackgroundTarget = .slot(.sideLeft)
    /// 当前预览画布尺寸（随“本机 / 投屏”切换），用于判断字号是否还能放大。
    @State private var previewViewportSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if fullPreview {
                    ZStack {
                        workbenchPreview(viewport: previewViewport(geometry.size)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("scoreboard_style_full_match_preview")
                        VStack {
                            Spacer()
                            previewTargetChips(tagPrefix: "full_preview", floating: true)
                                .frame(width: min(220, max(140, geometry.size.width - 160)))
                                .padding(.bottom, 16)
                        }.frame(maxWidth: .infinity)
                        VStack {
                            Spacer()
                            HStack { Spacer()
                                Button { fullPreview = false } label: {
                                    Image(systemName: "xmark").font(.system(size: 22, weight: .semibold))
                                        .frame(width: 48, height: 48).background(.black.opacity(0.6), in: Circle())
                                }.accessibilityLabel(String(localized: "style_preview_exit"))
                                .accessibilityIdentifier("scoreboard_style_back_to_editor").padding(16)
                            }
                        }
                    }
                } else {
                    // 横屏（可用宽 >= 高）即左右分栏；左右各半、顶栏等高 48，竖线贯穿到底。
                    // 不用固定宽度阈值：手机横屏只有 780pt 左右，定 900 会退化成上下布局。
                    // 横屏时 tab 并进右半顶栏；竖屏时退回设置区顶部。
                    if geometry.size.width >= geometry.size.height {
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                workbenchHeader
                                previewPane(viewport: previewViewport(geometry.size))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }.frame(width: geometry.size.width * 0.5)
                            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                            VStack(spacing: 0) {
                                workbenchTabBar
                                workbenchControls(showTabs: false)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }.frame(maxWidth: .infinity)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        workbenchHeader
                        previewPane(viewport: previewViewport(geometry.size)).frame(height: geometry.size.height * 0.43)
                        workbenchControls(showTabs: true)
                    }
                }
            }
            .background(StyleEditPalette.workbenchCanvas).foregroundStyle(.white)
            .disabled(controller.isSaving || imageBusy)
            .overlay { if imageBusy { ProgressView().tint(.white) } }
            // 字号面板需要知道预览画布尺寸，才能判断某元素的字号是否还能放大。
            .onChange(of: previewViewport(geometry.size), initial: true) { _, viewport in
                previewViewportSize = viewport
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreboard_style_editor")
        .ignoresSafeArea(.all, edges: fullPreview ? .all : [])
        .preferredColorScheme(.dark)
        .task { recentColors = PreferencesManager.shared.scoreboardRecentStyleColors }
        .task(id: imageUndo) {
            guard imageUndo != nil else { return }
            do { try await Task.sleep(for: .seconds(5)); imageUndo = nil } catch { }
        }
        .onChange(of: uiState.activePanel) { _, panel in
            customColorOpen = false
            switch panel {
            case .element, .server: workbenchTab = draft.isPhotoTheme ? "background" : "free"
            case .background: workbenchTab = "background"; backgroundTarget = resolvedInitialBackgroundTarget()
            case .font: workbenchTab = (draft.isPhotoTheme || !capabilities.supportsFont) ? "background" : "font"
            default: workbenchTab = "theme"
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            // 快速连续选图时取消上一次：旧任务不得清掉 busy 或回写过期图片。
            photoLoadTask?.cancel()
            imageBusy = true
            photoLoadTask = Task {
                defer {
                    if !Task.isCancelled { imageBusy = false; selectedPhoto = nil }
                }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        if !Task.isCancelled { imageError = true }
                        return
                    }
                    // ImageIO 解码 + 降采样 + JPEG 编码全部在主线程之外完成（与
                    // ScoreboardPhotoBackground 的 .task 同一策略），只把 Sendable 的
                    // data URL 字符串带回主线程，避免大图阻塞转场/拖动。
                    let encoded = await Task.detached(priority: .userInitiated) {
                        ScoreboardBackdrop.downsample(data).flatMap(ScoreboardBackdrop.jpegDataURL)
                    }.value
                    guard !Task.isCancelled, let encoded else {
                        if !Task.isCancelled { imageError = true }
                        return
                    }
                    var next = draft; var backdrop = next.backdrop ?? ScoreboardBackdrop()
                    backdrop.imageData = encoded; next.backdrop = backdrop; imageUndo = nil; controller.updateDraft(next)
                } catch {
                    if !Task.isCancelled { imageError = true }
                }
            }
        }
        .alert(String(localized: "style_workbench_photo_failed"), isPresented: $imageError) {
            // Localizable.strings 无 "ok" 键（仅 ParticipantIdentity / VIPCommunity 有），
            // 用 47 个语言均存在的 got_it，避免缺键时显示原始标识符。
            Button(String(localized: "got_it"), role: .cancel) { }
        }
    }

    private var workbenchHeader: some View {
        HStack(spacing: 4) {
            Button(action: onCancel) { Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "scoreboard_style_exit_edit")).accessibilityIdentifier("scoreboard_style_cancel")
            Text(String(localized: "style_workbench_title")).font(.system(size: 18, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            // 重置改为极简纯文字按钮（无图标/无背景/无边框），由 Spacer 推到顶栏最右侧。
            // 视觉用短文案「重置」/ "Reset"，读屏仍读完整的「恢复默认样式」。
            Button { imageUndo = nil; controller.resetDraft() } label: {
                Text(String(localized: "style_workbench_reset_short"))
                    .font(.system(size: 13))
                    .foregroundStyle(controller.canResetDraft ? Color(hex: "ADB5C2") : Color(hex: "555B65"))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain).disabled(!controller.canResetDraft)
                .accessibilityLabel(String(localized: "style_workbench_reset"))
                .accessibilityIdentifier("scoreboard_style_reset")
        }.padding(.horizontal, 12).frame(height: 48)
            .accessibilityElement(children: .contain).accessibilityIdentifier("scoreboard_style_header")
    }

    private var workbenchActions: some View {
        HStack(spacing: 10) {
            Button { fullPreview = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 14))
                    Text(String(localized: "style_workbench_full_preview")).font(.system(size: 12))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity).frame(minHeight: 44)
                    .background(StyleEditPalette.controlBackground, in: Capsule())
            }.accessibilityIdentifier("scoreboard_style_full_preview")
            Button(action: save) {
                Text(String(localized: "save")).font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .background(StyleEditPalette.accentGreen, in: Capsule())
            }.accessibilityIdentifier("scoreboard_style_save")
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreboard_style_actions")
    }

    private func previewViewport(_ size: CGSize) -> CGSize {
        if castPreview { return CGSize(width: 1280, height: 720) }
        return size
    }

    private func previewPane(viewport: CGSize) -> some View {
        VStack(spacing: 0) {
            workbenchPreview(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scoreboard_style_live_preview")
            // 画布级控件放画布下方：参与布局、不覆盖预览、无独立底栏。
            previewTargetChips()
                .frame(maxWidth: .infinity, alignment: .center)
        }.padding(12)
    }

    private func previewState(_ source: ScoreboardDisplayState) -> ScoreboardDisplayState {
        var state = source
        let font = typographySession?.effectivePreference.font ?? ScoreboardFont(displayCode: source.appearance.fontCode) ?? .default
        let swapped = source.sportString("team0ScreenSide") == "right" || source.teams.first?.id == "team_1"
        var style = ScoreboardDisplayStyle(profile: draft, fontCode: font.wireCode).projected(team0OnRight: swapped)
        style.fontSizeMultipliers = typographySession?.effectivePreference.resolvedElementMultipliers ?? source.appearance.fontSizeMultipliers ?? [:]
        state.appearance.style = style; state.appearance.theme = draft.themeCode
        state.appearance.fontCode = font.rawValue; state.appearance.fontSizeMultipliers = style.fontSizeMultipliers
        state.appearance.backgroundHex = draft.backgroundHex
        state.appearance.leftPanelHex = style.panelColor(slot: "side_left") ?? source.appearance.leftPanelHex
        state.appearance.rightPanelHex = style.panelColor(slot: "side_right") ?? source.appearance.rightPanelHex
        state.appearance.centerPanelHex = style.panelColor(slot: "side_center") ?? source.appearance.centerPanelHex
        state.appearance.leftTextHex = style.renderColor("teamName", slot: "side_left") ?? source.appearance.leftTextHex
        state.appearance.rightTextHex = style.renderColor("teamName", slot: "side_right") ?? source.appearance.rightTextHex
        state.appearance.leftScoreHex = style.renderColor("mainScore", slot: "side_left") ?? source.appearance.leftScoreHex
        state.appearance.rightScoreHex = style.renderColor("mainScore", slot: "side_right") ?? source.appearance.rightScoreHex
        state.appearance.leftSecondaryHex = style.renderColor("setGameScore", slot: "side_left") ?? style.renderColor("setScore", slot: "side_left") ?? source.appearance.leftSecondaryHex
        state.appearance.rightSecondaryHex = style.renderColor("setGameScore", slot: "side_right") ?? style.renderColor("setScore", slot: "side_right") ?? source.appearance.rightSecondaryHex
        return state
    }

    private func workbenchPreview(viewport: CGSize) -> some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / max(1, viewport.width), geometry.size.height / max(1, viewport.height))
            Group {
                if let source = displayOutputs.displayState {
                    // 本机篮球是三栏（左队 / 中栏 / 右队），投屏模板只有两栏；用投屏模板
                    // 冒充本机预览会让左右队各占一半，与本机实际比例不符，所以本机单独走
                    // 三栏几何。三栏里只模拟队名与主分，中栏留空，也不模拟计分按钮——
                    // 编辑时本机中栏本来就是纯黑，按钮不是样式的一部分。
                    if !castPreview, isBasketball(source.gameType) {
                        basketballLocalPreview(state: previewState(source), viewport: viewport)
                            .environment(\.scoreboardStyleEditingActive, workbenchTab == "free" && !fullPreview)
                            .environment(\.scoreboardStylePreviewSwapped, source.sportString("team0ScreenSide") == "right" || source.teams.first?.id == "team_1")
                    } else {
                        ScoreboardExternalLiveView(state: previewState(source), projection: .synchronizedDisplay)
                            .environment(\.scoreboardStyleEditingActive, workbenchTab == "free" && !fullPreview)
                            .environment(\.scoreboardStylePreviewSwapped, source.sportString("team0ScreenSide") == "right" || source.teams.first?.id == "team_1")
                    }
                } else { Color.black }
            }
            .frame(width: viewport.width, height: viewport.height)
            .scaleEffect(scale)
            .frame(width: viewport.width * scale, height: viewport.height * scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .allowsHitTesting(workbenchTab == "free" && !fullPreview)
        }
        // 预览窗在编辑左栏是圆角卡片。原先只用 `.clipped()` 裁内容、再把圆角只画在
        // 背景上，内容四角会露出方形；这里改为先铺黑底、再对整块做圆角裁剪，
        // 让背景与内容一起被切圆。全屏预览保持直角铺满。
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: fullPreview ? 0 : 8, style: .continuous))
    }

    private func isBasketball(_ gameType: String) -> Bool {
        gameType == "basketball" || gameType == "three_basketball"
    }

    /// 篮球三栏预览的侧栏几何：与本机渲染用同一套公式。
    private func basketballPreviewSideGeometry() -> (panel: CGSize, layout: BasketballTeamPanelLayoutMetrics)? {
        let viewport = previewViewportSize
        guard viewport.width > 1, viewport.height > 1 else { return nil }
        let centerW = min(viewport.width, ScoreboardLayoutMetrics.basketballCenterWidth(screenWidth: viewport.width))
        let sideW = max(0, (viewport.width - centerW) / 2)
        let panel = CGSize(width: sideW, height: viewport.height)
        let layout = ScoreboardLayoutMetrics.basketballTeamPanelLayout(
            panelSize: panel, outerSafeAreaInset: 0, isLargeScreen: isLargeLayout
        )
        return (panel, layout)
    }

    /// 篮球三栏下的槽位归属：交换左右后，`sideLeft` 可能对应第二支队。
    private func basketballTeam(state: ScoreboardDisplayState, slot: ScoreboardStyleSlotKeyV2) -> ScoreboardDisplayTeam? {
        let swapped = state.sportString("team0ScreenSide") == "right" || state.teams.first?.id == "team_1"
        let index: Int
        switch slot {
        case .sideLeft: index = swapped ? 1 : 0
        case .sideRight: index = swapped ? 0 : 1
        default: index = 0
        }
        return state.teams.indices.contains(index) ? state.teams[index] : nil
    }

    /// 当前几何下该元素字号倍率的「有效上限」。
    ///
    /// 篮球侧栏很窄（SE 上主分可用宽约 180pt），主分基础字号本身就已超过宽度上限，
    /// 于是倍率往上调完全不生效——滑块能拖、数字会变、实际字号不动，用户报告为
    /// “篮球字号调节没用”。这里算出真正还能放大的最大倍率，供字号面板封顶与提示。
    /// 非篮球项目返回 nil，保持原有行为。
    private func elementEffectiveUpperBound(
        _ key: ScoreboardStyleElementKeyV2,
        range: ClosedRange<Double>
    ) -> Double? {
        guard let source = displayOutputs.displayState, isBasketball(source.gameType) else { return nil }
        guard let geometry = basketballPreviewSideGeometry() else { return nil }
        let state = previewState(source)
        let team = basketballTeam(state: state, slot: uiState.activeElementSlot)
        let base = typographySession?.effectivePreference
            ?? .default(font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default)
        let metric: ScoreboardFontMetric = key == .mainScore ? .score : .name
        let nameText = team?.name ?? ""
        let scoreText = "\(team?.score ?? 0)"
        return ScoreboardFontSizeSaturation.effectiveUpperBound(
            range: range,
            step: ScoreboardFontSizePolicy.step
        ) { multiplier in
            var preference = base
            preference.setMultiplier(multiplier, for: metric)
            let result = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .basketball,
                    containerSize: geometry.panel,
                    nameText: nameText,
                    scoreText: scoreText,
                    secondaryText: "",
                    preference: preference,
                    horizontalPadding: 0,
                    nameAvailableWidth: geometry.layout.nameContentWidth,
                    scoreAvailableWidth: geometry.layout.scoreContentWidth,
                    reservedHeight: 76,
                    isLargeScreen: isLargeLayout
                )
            )
            return key == .mainScore ? result.scoreFontSize : result.nameFontSize
        }
    }

    /// 本机篮球预览：严格复用本机的三栏几何（左右队 = (宽 - 中栏)/2，中栏 =
    /// `basketballCenterWidth`），只渲染队名与主分，中栏留黑，不渲染计分按钮/犯规/时钟。
    /// 避让位置沿用本机同一套 `basketballTeamPanelLayout` 计算，保证预览与本机一致。
    private func basketballLocalPreview(state: ScoreboardDisplayState, viewport: CGSize) -> some View {
        let centerW = min(viewport.width, ScoreboardLayoutMetrics.basketballCenterWidth(screenWidth: viewport.width))
        let sideW = max(0, (viewport.width - centerW) / 2)
        let sideSize = CGSize(width: sideW, height: viewport.height)
        let isPad = Theme.usesPadLayout
        let leftLayout = ScoreboardLayoutMetrics.basketballTeamPanelLayout(
            panelSize: sideSize, outerSafeAreaInset: 0, isLargeScreen: isPad
        )
        let rightLayout = ScoreboardLayoutMetrics.basketballTeamPanelLayout(
            panelSize: sideSize, outerSafeAreaInset: 0, isLargeScreen: isPad
        )
        let scoreContentWidth = min(leftLayout.scoreContentWidth, rightLayout.scoreContentWidth)
        let nameContentWidth = min(leftLayout.nameContentWidth, rightLayout.nameContentWidth)
        let swapped = state.sportString("team0ScreenSide") == "right" || state.teams.first?.id == "team_1"
        let visualTeams: [(ScoreboardStyleSlotKeyV2, ScoreboardDisplayTeam?)] = swapped
            ? [(.sideRight, state.teams.first), (.sideLeft, state.teams.count > 1 ? state.teams[1] : nil)]
            : [(.sideLeft, state.teams.first), (.sideRight, state.teams.count > 1 ? state.teams[1] : nil)]
        return HStack(spacing: 0) {
            basketballLocalPanel(
                team: visualTeams[0].1, slot: visualTeams[0].0, state: state,
                panelSize: sideSize, layout: leftLayout,
                scoreContentWidth: scoreContentWidth, nameContentWidth: nameContentWidth
            )
            .frame(width: sideW)
            // 编辑态本机中栏就是纯黑：不模拟时钟/暂停/节次。
            Color.black.frame(width: centerW)
            basketballLocalPanel(
                team: visualTeams[1].1, slot: visualTeams[1].0, state: state,
                panelSize: sideSize, layout: rightLayout,
                scoreContentWidth: scoreContentWidth, nameContentWidth: nameContentWidth
            )
            .frame(width: sideW)
        }
        .frame(width: viewport.width, height: viewport.height)
    }

    private func basketballLocalPanel(
        team: ScoreboardDisplayTeam?,
        slot: ScoreboardStyleSlotKeyV2,
        state: ScoreboardDisplayState,
        panelSize: CGSize,
        layout: BasketballTeamPanelLayoutMetrics,
        scoreContentWidth: CGFloat,
        nameContentWidth: CGFloat
    ) -> some View {
        let typography = typographySession?.effectivePreference
            ?? .default(font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default)
        let resolved = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .basketball,
                containerSize: panelSize,
                nameText: team?.name ?? "",
                scoreText: "\(team?.score ?? 0)",
                secondaryText: "",
                preference: typography,
                horizontalPadding: 0,
                nameAvailableWidth: nameContentWidth,
                scoreAvailableWidth: scoreContentWidth,
                reservedHeight: 76,
                isLargeScreen: Theme.usesPadLayout
            )
        )
        let style = ScoreboardDisplayStyle(
            profile: draft,
            fontCode: (ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default).wireCode
        )
        let slotKey = slot.rawValue
        return ZStack {
            Color(hex: style.panelColor(slot: slotKey) ?? state.appearance.backgroundHex)
            VStack(spacing: 0) {
                Text(team?.name ?? "")
                    .font(ScoreboardNameFont.font(
                        code: style.nameFontCode,
                        inherited: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default,
                        size: resolved.nameFontSize
                    ))
                    .foregroundStyle(Color(hex: style.renderColor("teamName", slot: slotKey) ?? "#FFFFFF"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height))
                    .frame(maxWidth: .infinity)
                    .styleElementSelectable(.teamName, slotKey: slot)
                Spacer(minLength: 0)
                Text("\(team?.score ?? 0)")
                    .font(typography.font.swiftUIFont(
                        size: resolved.scoreFontSize
                            * ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "\(team?.score ?? 0)")
                    ))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: style.renderColor("mainScore", slot: slotKey) ?? "#FFFFFF"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity)
                    .styleElementSelectable(.mainScore, slotKey: slot)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BasketballTeamPanelLayoutMetrics.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewTargetChips(tagPrefix: String = "preview", floating: Bool = false) -> some View {
        HStack(spacing: floating ? 4 : 6) {
            // 非浮动版：黑底上两个紧凑选项居中，不留横贯整栏的容器。
            if !floating { Spacer(minLength: 0) }
            previewTargetChip(String(localized: "style_workbench_phone"), cast: false, tagPrefix: tagPrefix, floating: floating)
            previewTargetChip(String(localized: "style_workbench_cast"), cast: true, tagPrefix: tagPrefix, floating: floating)
            if !floating { Spacer(minLength: 0) }
        }
        .padding(floating ? 4 : 0)
        .frame(maxWidth: floating ? 220 : CGFloat.infinity)
        .frame(height: floating ? 44 : 48)
        .background {
            if floating {
                RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.6))
            }
        }
    }

    private func previewTargetChip(_ label: String, cast: Bool, tagPrefix: String, floating: Bool) -> some View {
        Button { castPreview = cast } label: {
            Text(label).font(.system(size: floating ? 12 : 14)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(minWidth: floating ? 0 : 64, maxWidth: floating ? CGFloat.infinity : 132)
                .frame(height: 36)
                .background(castPreview == cast ? StyleEditPalette.accentGreen.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: floating ? 18 : 10))
        }
        .buttonStyle(.plain)
        // 视觉 36，命中区 48（iOS HIG / Material 最小触摸目标）。
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityAddTraits(castPreview == cast ? .isSelected : [])
        .accessibilityIdentifier("scoreboard_style_\(tagPrefix)_\(cast ? "cast" : "phone")")
    }

    /// 定稿 A 方案：等宽通栏 tab + 选中项底部 2pt 绿线，高 48。
    /// 横屏并进右半顶栏，竖屏置于设置区顶部；不与内容区 workbenchChoice 复用样式。
    private var workbenchTabBar: some View {
        HStack(spacing: 0) {
            ForEach(draft.isPhotoTheme ? ["theme", "background"] : workbenchTabs, id: \.self) { tab in
                Button {
                    customColorOpen = false; workbenchTab = tab
                    if tab == "background" { uiState.openBackground() }
                    else if tab == "font" { uiState.openPanel(.font) }
                    else if tab == "theme" { uiState.openPanel(.theme) }
                    else { uiState.openElement(capabilities.elementKeys.first ?? .mainScore, slot: .sideLeft) }
                } label: {
                    Text(String(localized: String.LocalizationValue("style_workbench_" + tab)))
                        .font(.system(size: 14, weight: workbenchTab == tab ? .semibold : .regular))
                        .foregroundStyle(workbenchTab == tab ? StyleEditPalette.accentGreen : Color(hex: "ADB5C2"))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if workbenchTab == tab {
                                Rectangle().fill(StyleEditPalette.accentGreen).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(workbenchTab == tab ? .isSelected : [])
                .accessibilityIdentifier("scoreboard_style_tab_\(tab)")
            }
        }.frame(height: 48)
    }

    private func workbenchChoice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 40)
                .foregroundStyle(selected ? StyleEditPalette.accentGreen : Color(hex: "ADB5C2"))
                .background(selected ? StyleEditPalette.accentGreen.opacity(0.22) : StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 工作台标签：照片主题只保留主题/背景；字体标签按 `capabilities.supportsFont` 门控
    /// （与改造前工具条的 `if capabilities.supportsFont` 保持一致）。
    private var workbenchTabs: [String] {
        var tabs = ["theme", "background"]
        if capabilities.supportsFont { tabs.append("font") }
        tabs.append("free")
        return tabs
    }

    private func workbenchControls(showTabs: Bool) -> some View {
        VStack(spacing: 0) {
            // 横屏时 tab 已在右半顶栏，这里不重复；竖屏时置于设置区顶部。
            if showTabs {
                workbenchTabBar
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if customColorOpen {
                        customColorHeader
                        CircularColorPickerPage(selectedColor: customPickerColor(), isLargeLayout: isLargeLayout,
                            onPreview: { previewActiveColor($0) }, onCommit: { commitRecentColor($0) })
                    } else if workbenchTab == "theme" {
                        workbenchThemes
                    } else if workbenchTab == "background" {
                        if draft.isPhotoTheme { photoBackgroundControls } else { backgroundPanel }
                    } else if workbenchTab == "font" {
                        independentFontPanel
                    } else {
                        freeEditingControls
                    }
                }.padding(12)
            }
            // 不挂 .id(workbenchTab + draft.themeCode)：切 tab/主题只换内容，
            // 不重建 ScrollView（否则硬切并丢失滚动位置）。
            Divider()
            workbenchActions
        }.background(Color(hex: "1A1F26"))
    }

    private var workbenchThemes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "style_workbench_current")).foregroundStyle(.secondary)
            HStack {
                if draft.isPhotoTheme { photoThumbnail.frame(width: 64, height: 36) }
                else { themePreviewCard(for: ScoreboardTheme(rawValue: draft.themeCode) ?? .defaultTheme) }
                Text(draft.isPhotoTheme ? String(localized: "style_workbench_photo") : (ScoreboardTheme(rawValue: draft.themeCode) ?? .defaultTheme).localizedTitle)
                Spacer()
                if draft.isPhotoTheme { Button(String(localized: "style_workbench_settings")) { workbenchTab = "background"; uiState.openBackground() } }
                else { Image(systemName: "checkmark.circle.fill").foregroundStyle(StyleEditPalette.accentGreen) }
            }.padding(12).background(StyleEditPalette.accentGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(String(localized: "style_workbench_available")).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(scoreThemeOptions.filter { $0.rawValue != draft.themeCode }) { theme in
                    Button { selectTheme(theme) } label: {
                        VStack { themePreviewCard(for: theme); Text(theme.localizedTitle).font(.caption).lineLimit(1) }
                            .frame(maxWidth: .infinity).frame(height: 68).background(StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("scoreboard_style_theme_\(theme.rawValue)")
                }
                if ScoreboardStyleProfileV2.supportsPhotoTheme(controller.styleID), !draft.isPhotoTheme {
                    Button {
                        var next = ScoreboardStyleProfileV2.photoTheme(for: controller.styleID)
                        next.backdrop = draft.backdrop ?? ScoreboardBackdrop()
                        next.nameFontCode = draft.nameFontCode; next.serverIndicatorHidden = draft.serverIndicatorHidden; next.serverIndicatorStyle = draft.serverIndicatorStyle
                        next.serverIndicatorColorHex = draft.serverIndicatorColorHex
                        controller.updateDraft(next)
                    } label: {
                        VStack { photoThumbnail.frame(width: 40, height: 23); Text(String(localized: "style_workbench_photo")).font(.caption) }
                            .frame(maxWidth: .infinity).frame(height: 68).background(StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("scoreboard_style_theme_event_background")
                }
            }
        }
    }

    private var photoThumbnail: some View {
        ScoreboardPhotoBackground(backdrop: draft.backdrop ?? ScoreboardBackdrop()).clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var photoBackgroundControls: some View {
        // 排布对齐安卓 PhotoThemeBackgroundControls：图片区 → 图片操作 → 压暗/透明度，
        // 发球指示器单独作为最后一段（安卓在 ScoreboardStyleEditOverlay 里也是在
        // PhotoThemeBackgroundControls 之后调用 ServerStyleChoices）。旧实现把发球
        // 指示器插在缩略图和“选择图片”之间，切断了图片操作组。
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                photoThumbnail.frame(height: 110)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(String(localized: "style_workbench_select_photo"), systemImage: "photo")
                }.accessibilityIdentifier("scoreboard_style_select_photo")
                Button(String(localized: "style_workbench_restore_photo")) {
                    if let image = draft.backdrop?.imageData { imageUndo = .init(imageData: image) }
                    var next = draft; next.backdrop?.imageData = nil; controller.updateDraft(next)
                }.disabled(draft.backdrop?.imageData == nil)
                .accessibilityIdentifier("scoreboard_style_restore_photo")
                if let imageUndo {
                    Button(String(localized: "undo")) {
                        if let restored = imageUndo.restoring(draft.backdrop ?? ScoreboardBackdrop()) {
                            var next = draft; next.backdrop = restored; controller.updateDraft(next)
                        }
                        self.imageUndo = nil
                    }.accessibilityIdentifier("scoreboard_style_undo_photo")
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 12) {
                photoAdjustment(
                    title: String(localized: "style_workbench_dim"),
                    value: { draft.backdrop?.dim ?? 0.30 },
                    range: 0...0.8,
                    identifier: "scoreboard_style_photo_dim"
                ) { value in
                    var next = draft
                    var background = next.backdrop ?? ScoreboardBackdrop()
                    background.dim = value
                    next.backdrop = background
                    controller.updateDraft(next)
                }
                photoAdjustment(
                    title: String(localized: "style_workbench_opacity"),
                    value: { draft.backdrop?.panelOpacity ?? 0.84 },
                    range: 0.15...1,
                    identifier: "scoreboard_style_photo_opacity"
                ) { value in
                    var next = draft
                    var background = next.backdrop ?? ScoreboardBackdrop()
                    background.panelOpacity = value
                    next.backdrop = background
                    controller.updateDraft(next)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            serverStyleChoices

            Text(String(localized: "style_workbench_image_advice")).font(.caption).foregroundStyle(.secondary)
            // CC BY-SA 4.0 署名：创作者 + 许可名称 + 许可链接。原始作品 URI 与版权声明
            // 需由版权方补充（已登记 TODO.md），常量 URL 不再强制解包。
            if let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/") {
                Link("Photo: KeepActive.com.au · CC BY-SA 4.0", destination: licenseURL)
                    .font(.caption2)
                    .accessibilityIdentifier("scoreboard_style_photo_credit")
            }
        }.tint(StyleEditPalette.accentGreen)
    }

    /// 图片主题的单项滑杆：标题与百分比同一行，滑杆在下（对齐安卓 PhotoThemeAdjustment）。
    /// 绑定必须实时读回当前值，不能用传入的快照，否则拖动时滑块会回弹。
    private func photoAdjustment(
        title: String,
        value: @escaping () -> Double,
        range: ClosedRange<Double>,
        identifier: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value().formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).monospacedDigit()
            }
            Slider(value: Binding(get: value, set: onChange), in: range)
                .accessibilityIdentifier(identifier)
        }
    }

    private var independentFontPanel: some View {
        let inheritedFont = typographySession?.effectivePreference.font ?? .default
        let selectedNameFont = draft.nameFontCode ?? inheritedFont.wireCode
        let standardNameFonts = ["default", "rounded", "serif"]
        let nameFonts = standardNameFonts.contains(selectedNameFont) ? standardNameFonts : standardNameFonts + [selectedNameFont]
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "style_workbench_name_font")).font(.system(size: 13, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 3), spacing: 8) {
                ForEach(nameFonts, id: \.self) { code in
                    Button {
                        var next = draft; next.nameFontCode = code; controller.updateDraft(next)
                    } label: {
                        HStack(spacing: 4) {
                            Text(standardNameFonts.contains(code)
                                 ? String(localized: String.LocalizationValue("style_workbench_name_" + code))
                                 : (ScoreboardFont(displayCode: code) ?? inheritedFont).localizedTitle)
                                .font(ScoreboardNameFont.font(code: code, inherited: inheritedFont, size: 12))
                                .lineLimit(1).minimumScaleFactor(0.75)
                            if selectedNameFont == code { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(StyleEditPalette.accentGreen) }
                        }.frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(selectedNameFont == code ? StyleEditPalette.accentGreen.opacity(0.22) : StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("scoreboard_style_name_font_\(code)")
                        .accessibilityAddTraits(selectedNameFont == code ? .isSelected : [])
                }
            }
            Text(String(localized: "style_workbench_score_font")).font(.system(size: 13, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 4), spacing: 8) {
                ForEach(ScoreboardFont.allCases) { font in
                    Button {
                        if draft.nameFontCode == nil {
                            var next = draft; next.nameFontCode = inheritedFont.wireCode; controller.updateDraft(next)
                        }
                        typographySession?.updateFont(font)
                    } label: {
                        VStack(spacing: 6) {
                            Text("123").font(font.swiftUIFont(size: 23)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(font.localizedTitle).font(.system(size: 11)).foregroundStyle(Color(hex: "ADB5C2"))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 76)
                            .background(inheritedFont == font ? StyleEditPalette.accentGreen.opacity(0.22) : StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("scoreboard_style_score_font_\(font.wireCode)")
                        .accessibilityAddTraits(inheritedFont == font ? .isSelected : [])
                }
            }
        }
    }

    private var serverStyleChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "style_server_indicator"))
            HStack {
                workbenchChoice(String(localized: "style_server_arrow"), selected: draft.serverIndicatorStyle != "sport") {
                    var next = draft; next.serverIndicatorStyle = "arrow"; controller.updateDraft(next)
                }.accessibilityIdentifier("scoreboard_style_server_style_arrow")
                workbenchChoice(String(localized: "style_server_sport"), selected: draft.serverIndicatorStyle == "sport") {
                    var next = draft; next.serverIndicatorStyle = "sport"; controller.updateDraft(next)
                }.accessibilityIdentifier("scoreboard_style_server_style_sport")
            }
        }
    }

    private var freeEditingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(capabilities.elementKeys, id: \.self) { key in
                        workbenchChoice(elementLabel(key), selected: uiState.activePanel != .server && uiState.activeElementKey == key) {
                            uiState.openElement(key, slot: uiState.activeElementSlot)
                        }
                    }
                    if capabilities.supportsServerIndicator {
                        workbenchChoice(String(localized: "style_server_indicator"), selected: uiState.activePanel == .server) { uiState.openPanel(.server) }
                    }
                }
            }
            if uiState.activePanel == .server {
                serverStyleChoices
                Toggle(String(localized: "style_workbench_server_visible"), isOn: Binding(get: { !draft.serverIndicatorHidden }, set: { value in
                    var next = draft; next.serverIndicatorHidden = !value; controller.updateDraft(next)
                })).tint(StyleEditPalette.accentGreen).accessibilityIdentifier("scoreboard_style_server_visible")
                serverIndicatorPanel
            } else {
                if !capabilities.globalElementKeys.contains(uiState.activeElementKey) {
                    HStack {
                        ForEach(capabilities.slotKeys, id: \.self) { slot in
                            workbenchChoice(slot.rawValue == "side_left" ? String(localized: "style_slot_left") : slot.rawValue == "side_center" ? String(localized: "style_slot_center") : String(localized: "style_slot_right"), selected: uiState.activeElementSlot == slot) {
                                uiState.openElement(uiState.activeElementKey, slot: slot)
                            }
                        }
                    }
                }
                elementPanel
            }
        }
    }

    private func elementLabel(_ key: ScoreboardStyleElementKeyV2) -> String {
        switch key {
        case .matchTitle: return String(localized: "style_workbench_match_title")
        case .teamName: return String(localized: "style_workbench_team_name")
        case .playerName: return String(localized: "style_workbench_player_name")
        case .mainScore: return String(localized: "style_workbench_main_score")
        case .setScore: return String(localized: "style_workbench_set_score")
        case .gameScore: return String(localized: "style_workbench_game_score")
        case .setGameScore: return String(localized: "style_workbench_set_game_score")
        }
    }

    private func save() {
        _ = controller.save()
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
        themed.serverIndicatorHidden = draft.serverIndicatorHidden
        themed.serverIndicatorStyle = draft.serverIndicatorStyle
        themed.nameFontCode = draft.nameFontCode
        themed.backdrop = draft.backdrop
        controller.updateDraft(themed)
    }

    private func commitRecentColor(_ color: String) {
        let next = mergeRecentStyleColor(recentColors, color)
        if next != recentColors {
            recentColors = next
            PreferencesManager.shared.rememberScoreboardStyleColors(next)
        }
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

    // MARK: 各面板

    private var backgroundPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
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
            .padding(4)
            .background(StyleEditPalette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
        // 与“本机 / 投屏”分段控件同款：外层容器 12pt 圆角 + 4pt 内边距，
        // 内层选中块 8pt 圆角，两段同心，避免圆角套圆角。
        return Button(action: { setBackgroundTarget(target) }) {
            Text(title)
                .font(.system(size: isLargeLayout ? 14 : 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: isLargeLayout ? 40 : 36)
                .background(
                    selected ? StyleEditPalette.accentGreenSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    private var elementPanel: some View {
        let range = ScoreboardFontSizePolicy.range(isLargeScreen: isLargeLayout)
        let multiplier = typographySession?.effectivePreference.multiplier(for: uiState.activeElementKey) ?? 1
        // 该元素在当前几何下已无法放大（如 SE 篮球侧栏的主分：基础字号已超过宽度上限）。
        // 此时冻结滑块并给出说明，避免“能拖、数字在变、字号不动”的假象。
        let effectiveUpper = elementEffectiveUpperBound(uiState.activeElementKey, range: range)
        let isFontSizeFrozen = effectiveUpper.map { $0 <= 1.0 + 1e-9 } ?? false
        let sliderRange = effectiveUpper.map { range.lowerBound ... max(range.lowerBound, $0) } ?? range
        return VStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack {
                    Text(NSLocalizedString("scoreboard_style_font_size", value: "字号", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    if isFontSizeFrozen {
                        Text(NSLocalizedString(
                            "scoreboard_style_font_size_device_max",
                            value: "已达本机上限",
                            comment: ""
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                        .accessibilityIdentifier("scoreboard_style_font_size_capped")
                    } else {
                        Text(String(format: "%.2fx", multiplier))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "30D158"))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(StyleEditPalette.accentGreenSubtle)
                            .clipShape(Capsule())
                    }
                }
                Slider(
                    value: Binding(
                        get: { multiplier },
                        set: { typographySession?.updateElementMultiplier($0, for: uiState.activeElementKey, isLargeScreen: isLargeLayout) }
                    ),
                    in: sliderRange
                )
                .disabled(isFontSizeFrozen)
                .opacity(isFontSizeFrozen ? 0.4 : 1)
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

    @State private var containerWidth: CGFloat = 0

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

            // 列数随容器宽度自适应（宽面板一行多放、窄面板少放避免溢出），圆点尺寸不变、格子等宽撑满整行；
            // 与安卓 WorkbenchColors / 鸿蒙 columnsTemplate 同一换算：columns = floor((宽 + 间距) / (圆点 + 间距))，
            // 首帧未量到宽度时退回原来的 6 列。
            let dotSize: CGFloat = isLargeLayout ? 38 : 32
            let swatchGap: CGFloat = isLargeLayout ? 8 : 5
            let columns = containerWidth > 0 ? max(3, Int((containerWidth + swatchGap) / (dotSize + swatchGap))) : 6
            let rows = (displayColors + ["custom"]).chunked(into: columns)
            ForEach(rows.indices, id: \.self) { rowIndex in
                let row = rows[rowIndex]
                HStack(spacing: swatchGap) {
                    ForEach(0..<columns, id: \.self) { index in
                        ZStack {
                            if index < row.count {
                                let value = row[index]
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
                                            .frame(width: dotSize, height: dotSize)
                                            .overlay(Circle().strokeBorder(
                                                isSelected ? StyleEditPalette.accentGreen : Color.white.opacity(0.32),
                                                lineWidth: isSelected ? 3 : 1
                                            ))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
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
        .environment(\.scoreboardStyleEditorUiState, uiState)
        .environment(\.scoreboardStyleEditingActive, controller?.isEditing == true)
        .animation(.easeInOut(duration: 0.2), value: controller?.isEditing == true)
    }
}

private struct ScoreboardStylePreviewSwappedKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var scoreboardStylePreviewSwapped: Bool {
        get { self[ScoreboardStylePreviewSwappedKey.self] }
        set { self[ScoreboardStylePreviewSwappedKey.self] = newValue }
    }
}
private struct ScoreboardServerSelectableModifier: ViewModifier {
    var hidden: Bool
    @Environment(\.scoreboardStyleEditingActive) private var editing
    @Environment(\.scoreboardStyleEditorUiState) private var uiState
    func body(content: Content) -> some View {
        if editing, let uiState {
            content.opacity(hidden ? 0.25 : 1).padding(8).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.6), lineWidth: 2))
                .contentShape(Rectangle()).onTapGesture { uiState.openPanel(.server) }
                .accessibilityIdentifier("scoreboard_style_element_server")
        } else { content.opacity(hidden ? 0 : 1) }
    }
}
extension View {
    func styleServerSelectable(hidden: Bool = false) -> some View { modifier(ScoreboardServerSelectableModifier(hidden: hidden)) }
}
