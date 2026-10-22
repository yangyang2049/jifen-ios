import ScoreCore
import SwiftUI

struct TableTennisCardsDialog: View {
    let leftName: String
    let rightName: String
    let leftColor: Color
    let rightColor: Color
    let leftStatus: PingPongAdministrativeStatus
    let rightStatus: PingPongAdministrativeStatus
    let leftStage: PingPongPenaltyStage
    let rightStage: PingPongPenaltyStage
    let actionDescription: (MatchSide) -> String
    let onClose: () -> Void
    let onConfirm: (MatchSide) -> Void

    @State private var selectedSide: MatchSide?

    private var selectedStage: PingPongPenaltyStage? {
        selectedSide.map { $0 == .left ? leftStage : rightStage }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 520
            let width = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 360,
                padPreferredWidth: 400
            )
            ZStack {
                Theme.scoreboardDialogScrim.ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                ViewThatFits(in: .vertical) {
                    panel(compact: compact)
                    ScrollView { panel(compact: compact) }
                        .scrollBounceBehavior(.basedOnSize)
                }
                .frame(width: width)
                .frame(maxHeight: max(0, proxy.size.height - 24))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("pingpong_cards_dialog")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func panel(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 44)
                Text(NSLocalizedString("tool_red_yellow_card", value: "红黄牌", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                ScoreboardDialogCloseButton(
                    action: onClose,
                    accessibilityIdentifier: "pingpong_cards_close"
                )
            }
            HStack(spacing: 10) {
                player(.left, name: leftName, color: leftColor, status: leftStatus)
                player(.right, name: rightName, color: rightColor, status: rightStatus)
            }
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    if let stage = selectedStage {
                        if stage == .report {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: compact ? 34 : 44))
                                .foregroundStyle(.yellow)
                                .accessibilityHidden(true)
                        } else {
                            penaltyCard(.yellow, compact: compact)
                                .accessibilityIdentifier("pingpong_cards_preview_yellow")
                            if stage == .firstRed || stage == .secondRed {
                                penaltyCard(.red, compact: compact)
                                    .accessibilityIdentifier("pingpong_cards_preview_red_1")
                            }
                            if stage == .secondRed {
                                penaltyCard(.red, compact: compact)
                                    .accessibilityIdentifier("pingpong_cards_preview_red_2")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 54 : 74)
                Text(selectedSide.map(actionDescription)
                     ?? NSLocalizedString("tt_select_side_hint", value: "请先选择选手", comment: ""))
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
                    .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .accessibilityIdentifier("pingpong_cards_next_action")
            }
            .padding(12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Button {
                if let selectedSide { onConfirm(selectedSide) }
            } label: {
                Text(selectedSide == nil
                     ? NSLocalizedString("tt_select_side_hint", value: "请先选择选手", comment: "")
                     : selectedStage == .report
                     ? NSLocalizedString("confirm_forfeit", value: "确认判负", comment: "")
                     : NSLocalizedString("confirm", value: "确认", comment: ""))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(selectedStage == .report ? Theme.actionForeground(on: Color.red) : Theme.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(selectedStage == .report ? Color.red : Theme.primary,
                                in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedSide == nil)
            .opacity(selectedSide == nil ? 0.38 : 1)
            .accessibilityIdentifier("pingpong_cards_confirm")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 12 : 16)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.scoreboardDialogSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func player(
        _ side: MatchSide,
        name: String,
        color: Color,
        status: PingPongAdministrativeStatus
    ) -> some View {
        let selected = selectedSide == side
        let nameColor = Self.nameStripTextColor(panelColor: color, selected: selected)
        return Button { selectedSide = side } label: {
            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(color.opacity(selected ? 0.75 : 0.42))
                TableTennisAdministrativeCards(status: .init(
                    timeoutUsed: false,
                    hasYellowCard: status.hasYellowCard,
                    redCardCount: status.redCardCount
                ), scale: 0.8)
                .frame(height: 30)
                .accessibilityHidden(true)
            }
            .background(selected ? color.opacity(0.45) : Color.white.opacity(0.26))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? nameColor.opacity(0.85) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("pingpong_cards_side_\(side == .left ? "left" : "right")")
    }

    // MARK: - 名条字色

    /// 名条底色是「面板主题色」叠在固定深色弹层（scoreboardDialogSurface #2C2C2E）之上。
    /// 默认主题（红/蓝面板）配白字没问题，但 wrb（白红蓝）的面板色是纯白，
    /// 白底白字对比只有 ≈1.6:1 完全不可读。这里按合成底色的 WCAG 相对亮度自动在
    /// 黑/白之间选字色，既保留主题色辨认度，也能覆盖用户自定义面板色（V2 样式配置）。
    private static func nameStripTextColor(panelColor: Color, selected: Bool) -> Color {
        let composited = compositeOverDialogSurface(panelColor, alpha: selected ? 0.75 : 0.42)
        return readableTextColor(on: composited)
    }

    private static func compositeOverDialogSurface(_ color: Color, alpha: Double) -> Color {
        let surface = UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        surface.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        let weight = CGFloat(alpha) * a
        return Color(
            red: Double(r * weight + sr * (1 - weight)),
            green: Double(g * weight + sg * (1 - weight)),
            blue: Double(b * weight + sb * (1 - weight))
        )
    }

    /// 取对比度更高的一侧（口径与 ScoreboardStyleColorMath.contrastRatio 一致）。
    private static func readableTextColor(on color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return whiteContrast >= blackContrast ? .white : Color(hex: "111111")
    }

    private func penaltyCard(_ color: Color, compact: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.22), lineWidth: 0.75)
            }
            .frame(width: compact ? 38 : 52, height: compact ? 54 : 74)
            .accessibilityElement()
    }
}
