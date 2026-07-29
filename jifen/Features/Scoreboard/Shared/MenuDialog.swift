//
//  MenuDialog.swift
//  jifen
//
//  Scoreboard operation menu — 1:1 with HarmonyOS MenuDialog
//  (top sync strip / middle match large cards / bottom tools small cards).
//

import SwiftUI

// MARK: - Model

enum ScoreboardMenuGroup: String, Equatable {
    case sync
    case match
    case tools
}

enum ScoreboardMenuCardSize {
    case large
    case medium
    case small
}

struct ScoreboardMenuItem: Identifiable, Equatable {
    var id: String { action }
    let title: String
    let action: String
    let group: ScoreboardMenuGroup
    var icon: String? = nil
    var customText: String? = nil
    var keepDialogOpen: Bool = false
    var confirming: Bool = false
    var enabled: Bool = true
}

enum ScoreboardMenuActionPolicy {
    private static let actionsAllowedWhileScoringLocked: Set<String> = [
        "resync",
        "takeover",
        "endLink",
        "displaySettings",
        "screenshot",
        "exit"
    ]

    static func isAllowedWhileScoringLocked(_ action: String) -> Bool {
        actionsAllowedWhileScoringLocked.contains(action)
    }
}

// MARK: - Default items (aligned with HarmonyOS groups)

enum ScoreboardMenuItemBuilder {
    static func defaultItems(
        showEndGame: Bool = false,
        showExchangeSide: Bool = true,
        showWhistle: Bool = true,
        showScreenshot: Bool = true,
        showDisplaySettings: Bool = true,
        showSettleMatch: Bool = false,
        resetConfirming: Bool = false,
        exchangeConfirming: Bool = false,
        finishConfirming: Bool = false,
        settleConfirming: Bool = false,
        scoringEnabled: Bool = true,
        extraItems: [ScoreboardMenuItem] = []
    ) -> [ScoreboardMenuItem] {
        var items: [ScoreboardMenuItem] = []

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_undo", comment: "Undo"),
                action: "undo",
                group: .match,
                icon: "arrow.uturn.backward",
                keepDialogOpen: true,
                enabled: scoringEnabled
            )
        )

        if showExchangeSide {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_swap_sides", comment: "Exchange sides"),
                    action: "exchangeSide",
                    group: .match,
                    icon: "arrow.left.arrow.right",
                    keepDialogOpen: true,
                    confirming: exchangeConfirming,
                    enabled: scoringEnabled
                )
            )
        }

        let matchExtras = extraItems.filter { $0.group == .match }.map { item in
            var copy = item
            if item.action != "frameRecord" {
                copy.enabled = item.enabled && scoringEnabled
            }
            return copy
        }
        items.append(contentsOf: matchExtras)

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_reset", comment: "Reset"),
                action: "reset",
                group: .match,
                icon: "arrow.counterclockwise",
                keepDialogOpen: true,
                confirming: resetConfirming,
                enabled: scoringEnabled
            )
        )

        if showSettleMatch {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("settle_match", value: "结算", comment: ""),
                    action: "settleMatch",
                    group: .match,
                    icon: "checkmark.seal",
                    keepDialogOpen: true,
                    confirming: settleConfirming,
                    enabled: scoringEnabled
                )
            )
        }

        if showEndGame {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_end_game", value: "结束比赛", comment: "End game"),
                    action: "endGame",
                    group: .match,
                    icon: "flag.checkered",
                    keepDialogOpen: true,
                    confirming: finishConfirming,
                    enabled: scoringEnabled
                )
            )
        }

        if showWhistle {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_whistle", comment: "Whistle"),
                    action: "whistle",
                    group: .tools,
                    icon: "bell.fill",
                    keepDialogOpen: true
                )
            )
        }

        if showDisplaySettings {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("scoreboard_display_settings", value: "显示设置", comment: ""),
                    action: "displaySettings",
                    group: .tools,
                    customText: "Aa"
                )
            )
        }

        if showScreenshot {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_screenshot", comment: "Screenshot"),
                    action: "screenshot",
                    group: .tools,
                    icon: "camera.fill"
                )
            )
        }

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("scoreboard_usage_hint_menu", value: "使用说明", comment: ""),
                action: "usageHint",
                group: .tools,
                customText: "?",
                keepDialogOpen: true
            )
        )

        items.append(contentsOf: extraItems.filter { $0.group == .sync })
        items.append(contentsOf: extraItems.filter { $0.group == .tools })

        return items
    }

    static func orderedMatchItems(_ items: [ScoreboardMenuItem]) -> [ScoreboardMenuItem] {
        let undo = items.filter { $0.action == "undo" }
        let settle = items.filter {
            ($0.action.hasPrefix("settle") && $0.action != "settleFrame") ||
            $0.action == "endGame" ||
            $0.action == "finish" ||
            $0.action == "exit"
        }
        let finalFrameSettlement = items.filter { $0.action == "settleFrame" }
        let middle = items.filter {
            $0.action != "undo" &&
            !$0.action.hasPrefix("settle") &&
            $0.action != "endGame" &&
            $0.action != "finish" &&
            $0.action != "exit"
        }
        return undo + middle + settle + finalFrameSettlement
    }
}

// MARK: - Dialog

struct MenuDialog: View {
    let isVisible: Bool
    let onClose: () -> Void
    let onMenuItemClick: (String) -> Void
    var showEndGame: Bool = false
    var showExchangeSide: Bool = true
    var resetConfirming: Bool = false
    var items: [ScoreboardMenuItem]? = nil
    @State private var showUsageHint = false
    @State private var containerSize: CGSize = .zero

    private let dialogBackground = Color(hex: "2C2C2E")
    private let cardBackground = Color(hex: "3A3A3C")
    private let sectionStrip = Color.white.opacity(0.06)
    private let secondaryText = Color(hex: "98989D")
    private let confirmBackground = Color(hex: "4CAF50").opacity(0.5)

    private var resolvedItems: [ScoreboardMenuItem] {
        items ?? ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: showEndGame,
            showExchangeSide: showExchangeSide,
            resetConfirming: resetConfirming
        )
    }

    private var syncItems: [ScoreboardMenuItem] {
        resolvedItems.filter { $0.group == .sync }
    }

    private var matchItems: [ScoreboardMenuItem] {
        ScoreboardMenuItemBuilder.orderedMatchItems(resolvedItems.filter { $0.group == .match })
    }

    private var toolItems: [ScoreboardMenuItem] {
        resolvedItems.filter { $0.group == .tools }
    }

    private var containerShortSide: CGFloat {
        let shortSide = min(containerSize.width, containerSize.height)
        return shortSide > 0 ? shortSide : 320
    }

    private var isCompact: Bool {
        containerShortSide < 400
    }

    private var dialogWidth: CGFloat {
        Theme.dialogWidth(
            availableWidth: containerSize.width > 0
                ? containerSize.width
                : (Theme.usesPadLayout ? 1_024 : 430),
            role: .scoreboardMenu
        )
    }

    private var syncCardHeight: CGFloat { isCompact ? 44 : 48 }
    private var matchCardHeight: CGFloat { 72 }
    private var toolsCardWidth: CGFloat { isCompact ? 44 : 48 }
    private var toolsCardHeight: CGFloat { isCompact ? 36 : 40 }
    private var sectionPaddingV: CGFloat { isCompact ? 8 : 10 }
    private var toolsRowGap: CGFloat { isCompact ? 10 : 12 }

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    if syncItems.isEmpty {
                        closeOnlyHeader
                    } else {
                        topStrip(items: syncItems)
                    }

                    if !matchItems.isEmpty {
                        matchGrid(items: matchItems)
                    }

                    if !toolItems.isEmpty {
                        toolsBar(items: toolItems)
                    }
                }
                .frame(width: dialogWidth)
                .background(dialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 32, x: 0, y: 12)
                .contentShape(Rectangle())
                .onTapGesture { }
                .overlay(alignment: .topTrailing) {
                    Text(" ")
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Scoreboard menu")
                        .accessibilityIdentifier("scoreboard_menu_dialog")
                }
            }
            .sheet(isPresented: $showUsageHint) {
                ScoreboardUsageHintView()
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                containerSize = size
            }
        }
    }

    // MARK: - Sections

    private var closeOnlyHeader: some View {
        HStack {
            Spacer()
            closeButton
        }
        .padding(.leading, 4)
        .padding(.top, sectionPaddingV)
        .frame(height: syncCardHeight + sectionPaddingV)
    }

    private func topStrip(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 40, height: 32)

            HStack(spacing: 4) {
                ForEach(items) { item in
                    menuCard(item: item, size: .medium, stripItem: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: syncCardHeight)
                }
            }
            .frame(maxWidth: .infinity)

            closeButton
        }
        .padding(.leading, 4)
        .padding(.vertical, sectionPaddingV)
        .background(sectionStrip)
    }

    private func matchGrid(items: [ScoreboardMenuItem]) -> some View {
        VStack(spacing: 6) {
            if items.count <= 3 {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        menuCard(item: item, size: .large, stripItem: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: matchCardHeight)
                    }
                }
            } else {
                let rows = stride(from: 0, to: items.count, by: 3).map { start in
                    Array(items[start..<min(start + 3, items.count)])
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { item in
                            menuCard(item: item, size: .large, stripItem: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: matchCardHeight)
                        }
                        if row.count < 3 {
                            ForEach(0..<(3 - row.count), id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: matchCardHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, sectionPaddingV)
    }

    private func toolsBar(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: toolsRowGap) {
            ForEach(items) { item in
                menuCard(item: item, size: .small, stripItem: true)
                    .frame(width: toolsCardWidth, height: toolsCardHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, sectionPaddingV)
        .padding(.bottom, sectionPaddingV + 2)
        .background(sectionStrip)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: "Close"))
        .accessibilityIdentifier("scoreboard_menu_close_button")
        .padding(.trailing, 8)
    }

    // MARK: - Card

    private func menuCard(item: ScoreboardMenuItem, size: ScoreboardMenuCardSize, stripItem: Bool) -> some View {
        Button {
            guard item.enabled else { return }
            // Always notify parent first so pending green-confirm state can clear
            // when tapping non-confirm actions handled inside the dialog.
            onMenuItemClick(item.action)
            if item.action == "usageHint" {
                showUsageHint = true
                return
            }
            if item.action == "whistle" {
                SoundManager.shared.playSound("whistle")
                return
            }
            if item.action == "screenshot" {
                ScreenshotSaveCoordinator.shared.prepareForCapture()
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    captureScoreboardScreenshot()
                }
                return
            }
            if !item.keepDialogOpen {
                onClose()
            }
        } label: {
            VStack(spacing: size == .large ? 4 : 3) {
                if let customText = item.customText {
                    Text(customText)
                        .font(.system(size: customTextSize(size), weight: .bold))
                        .foregroundColor(.white)
                } else if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize(size), weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(item.title)
                    .font(.system(size: labelSize(size), weight: size == .large ? .medium : .regular))
                    .foregroundColor(size == .large ? .white.opacity(0.82) : secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: stripItem ? 8 : (size == .large ? 12 : 10), style: .continuous)
                    .fill(cardFill(item: item, stripItem: stripItem))
            )
            .opacity(item.enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("scoreboard_menu_action_\(item.action)")
        .disabled(!item.enabled)
    }

    private func cardFill(item: ScoreboardMenuItem, stripItem: Bool) -> Color {
        if item.confirming { return confirmBackground }
        if stripItem { return .clear }
        return cardBackground
    }

    private func iconSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 28
        case .medium: return isCompact ? 18 : 20
        case .small: return isCompact ? 16 : 18
        }
    }

    private func labelSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 12
        case .medium: return 10
        case .small: return 9
        }
    }

    private func customTextSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 28
        case .medium: return 18
        case .small: return 14
        }
    }
}

struct ScoreboardUsageHintView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                usageRow("hand.tap", "scoreboard_usage_tap", "点击计分区加分；部分项目点击后会打开回合或结算面板。")
                usageRow("arrow.uturn.backward", "scoreboard_usage_undo", "误操作后可在菜单中撤销。")
                usageRow("pencil", "scoreboard_usage_edit", "点击铅笔可编辑名称和比分，点击对勾保存。")
                usageRow("arrow.counterclockwise", "scoreboard_usage_reset", "重置、换边、结束比赛、结算等需要再次点击同一按钮确认（按钮会变绿）。")
                usageRow("flag.checkered", "scoreboard_usage_finish", "结束比赛后会保存为已完成记录。")
                usageRow("textformat.size", "scoreboard_usage_display", "显示设置可调整主题、字体和沉浸模式。")
            }
            .navigationTitle(NSLocalizedString("scoreboard_usage_hint_title", value: "计分板使用说明", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", value: "完成", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func usageRow(_ icon: String, _ key: String, _ fallback: String) -> some View {
        Label(NSLocalizedString(key, value: fallback, comment: ""), systemImage: icon)
            .padding(.vertical, 4)
    }
}

private func captureScoreboardScreenshot() {
    ScreenshotSaveCoordinator.shared.captureCurrentWindowAndSubmit()
}

#Preview {
    ZStack {
        Color.red.opacity(0.8)
        MenuDialog(
            isVisible: true,
            onClose: {},
            onMenuItemClick: { _ in },
            showEndGame: true,
            resetConfirming: true
        )
    }
}
