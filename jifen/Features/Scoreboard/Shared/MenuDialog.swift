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
        "usageHint",
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
        // “结束”仍属于常规比赛操作；后来增加的“结算”单独放在末尾。
        // 斯诺克的本局记录紧邻结算，固定为倒数第二项。
        let regularItems = items.filter {
            $0.action != "frameRecord" && !$0.action.hasPrefix("settle")
        }
        let frameRecordItems = items.filter { $0.action == "frameRecord" }
        let settlementItems = items.filter { $0.action.hasPrefix("settle") }
        return regularItems + frameRecordItems + settlementItems
    }
}

// MARK: - Dialog

struct MenuDialog: View {
    @Environment(\.scoreboardUsageHintCoordinator) private var usageHintCoordinator
    let isVisible: Bool
    let onClose: () -> Void
    let onMenuItemClick: (String) -> Void
    var showEndGame: Bool = false
    var showExchangeSide: Bool = true
    var resetConfirming: Bool = false
    var items: [ScoreboardMenuItem]? = nil
    var analyticsGameType: GameType? = nil
    @State private var containerSize: CGSize = .zero

    private let dialogBackground = Theme.scoreboardDialogSurface
    private let cardBackground = Theme.scoreboardDialogControl
    private let sectionStrip = Color.white.opacity(0.06)
    private let secondaryText = Theme.scoreboardDialogTextSecondary
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
    private var toolsCardHeight: CGFloat { ScoreboardConstants.minimumTouchTarget }
    private var sectionPaddingV: CGFloat { isCompact ? 8 : 10 }
    private var toolsRowGap: CGFloat { isCompact ? 10 : 12 }

    var body: some View {
        if isVisible {
            ZStack {
                Theme.scoreboardDialogScrim
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
                        .accessibilityLabel(NSLocalizedString("menu", value: "Menu", comment: "Scoreboard menu"))
                        .accessibilityIdentifier("scoreboard_menu_dialog")
                }
            }
            .onAppear {
                var parameters: AnalyticsParameters = [:]
                if let analyticsGameType {
                    parameters[.gameType] = .string(analyticsGameType.analyticsIdentifier)
                }
                AppAnalytics.track(.scoreboardMenuOpen, parameters: parameters)
                AppAnalytics.openDialog("scoreboard_menu", source: analyticsGameType.map {
                    AnalyticsScreen.scoreboard(for: $0, setup: nil)
                } ?? .scoreTab)
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
        ScoreboardDialogCloseButton(
            action: onClose,
            accessibilityIdentifier: "scoreboard_menu_close_button"
        )
        .padding(.trailing, 8)
    }

    // MARK: - Card

    private func menuCard(item: ScoreboardMenuItem, size: ScoreboardMenuCardSize, stripItem: Bool) -> some View {
        Button {
            guard item.enabled else { return }
            trackMenuAction(item)
            // Always notify parent first so pending green-confirm state can clear
            // when tapping non-confirm actions handled inside the dialog.
            onMenuItemClick(item.action)
            if item.action == "usageHint" {
                onClose()
                usageHintCoordinator?.presentFromMenu()
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

    private func trackMenuAction(_ item: ScoreboardMenuItem) {
        var parameters: AnalyticsParameters = [
            .actionName: .string(analyticsActionName(item.action))
        ]
        if let analyticsGameType {
            parameters[.gameType] = .string(analyticsGameType.analyticsIdentifier)
            if item.confirming,
               ["endGame", "finish", "settleMatch"].contains(item.action) {
                AppAnalytics.markNextMatchEndReason(.manualFinish, gameType: analyticsGameType)
            }
        }

        switch item.action {
        case "undo":
            AppAnalytics.track(.scoreUndo, parameters: parameters)
        case "reset" where item.confirming:
            parameters[.result] = .string(AnalyticsResult.success.rawValue)
            AppAnalytics.track(.scoreReset, parameters: parameters)
        case "reset":
            parameters[.result] = .string(AnalyticsResult.requested.rawValue)
            AppAnalytics.track(.scoreboardMenuAction, parameters: parameters)
        default:
            parameters[.result] = .string(AnalyticsResult.requested.rawValue)
            AppAnalytics.track(.scoreboardMenuAction, parameters: parameters)
        }
    }

    private func analyticsActionName(_ action: String) -> String {
        var value = ""
        for character in action {
            if character.isUppercase {
                if !value.isEmpty { value.append("_") }
                value.append(character.lowercased())
            } else {
                value.append(character)
            }
        }
        return value
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
