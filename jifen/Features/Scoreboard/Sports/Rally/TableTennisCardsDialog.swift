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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(selectedStage == .report ? Color.red : Theme.primary,
                                in: RoundedRectangle(cornerRadius: 12))
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
        return Button { selectedSide = side } label: {
            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
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
                    .stroke(selected ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("pingpong_cards_side_\(side == .left ? "left" : "right")")
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
