import LinkCore
import ScoreCore
import SwiftUI

/// 追分开局设置。人数与事件分值直接写入 `SportsSetupResult`，计分板不再
/// 根据页面默认值二次猜测，和鸿蒙/安卓的 setup -> reducer 契约保持一致。
struct NineBallSetupDialogView: View {
    private let commonNamesManager = CommonNamesManager.shared

    var initialSetup: SportsSetupResult? = nil
    var maxDialogHeight: CGFloat = 680
    var onConfirm: (SportsSetupResult) -> Void
    var onCancel: (() -> Void)?

    @State private var playerCount = 2
    @State private var playerNames = (1...4).map {
        String.localizedStringWithFormat(
            NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""), $0
        )
    }
    @State private var activeNameIndex: Int?
    @State private var bigGold = 10
    @State private var smallGold = 7
    @State private var goldenNine = 8
    @State private var normalWin = 4
    @State private var ballInHand = 1
    @State private var foul = 1
    @State private var setupSendErrorText = ""

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 6) {
                Text("🎱")
                Text(NSLocalizedString("game_nine_ball", value: "追分", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        } content: { maxContentHeight in
            AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight) {
                VStack(spacing: 18) {
                    Picker("", selection: $playerCount) {
                        ForEach(2...4, id: \.self) { count in
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString("players_count_format", value: "%d人", comment: ""), count
                            )).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 8) {
                        ForEach(0..<playerCount, id: \.self) { index in
                            InlineCommonNameTextField(
                                placeholder: playerLabel(index),
                                text: nameBinding(index),
                                onChevronTap: { activeNameIndex = index }
                            )
                        }
                    }

                    Text(NSLocalizedString("nine_ball_chase_points", value: "事件分值", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    VStack(spacing: 10) {
                        scoreStepper("nine_ball_big_gold", fallback: "大金", value: $bigGold)
                        scoreStepper("nine_ball_small_gold", fallback: "小金", value: $smallGold)
                        scoreStepper("nine_ball_golden_nine", fallback: "黄金九", value: $goldenNine)
                        scoreStepper("nine_ball_normal_win", fallback: "普胜", value: $normalWin)
                        scoreStepper("nine_ball_ball_in_hand", fallback: "自由球", value: $ballInHand)
                        scoreStepper("nine_ball_foul", fallback: "犯规", value: $foul)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        } actions: {
            buildDialogActions()
        }
        .sheet(isPresented: Binding(
            get: { activeNameIndex != nil },
            set: { if !$0 { activeNameIndex = nil } }
        )) {
            CommonNameSelectorDialog(
                nameType: ScoreboardCommonNamePolicy.nameType(for: .nineBall)
            ) { value in
                if let activeNameIndex { playerNames[activeNameIndex] = value }
                activeNameIndex = nil
            }
        }
        .onAppear(perform: applyInitialSetup)
    }

    @ViewBuilder
    private func buildDialogActions() -> some View {
        VStack(spacing: 10) {
            if !setupSendErrorText.isEmpty {
                Text(setupSendErrorText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.destructiveText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button(action: requestCancel) {
                    Text(NSLocalizedString("cancel", comment: ""))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.dialogControlBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                startButton()
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func startButton() -> some View {
        Button {
            Task { await confirm() }
        } label: {
            Text(NSLocalizedString("start_game", comment: ""))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.primary)
        }
        .buttonStyle(.plain)
    }

    private func applyInitialSetup() {
        guard let setup = initialSetup else { return }
        playerCount = min(4, max(2, setup.playerCount ?? setup.playerNames?.count ?? 2))
        for (index, name) in (setup.playerNames ?? []).prefix(4).enumerated() {
            playerNames[index] = name
        }
        bigGold = min(99, max(1, setup.nineBallBigGold ?? bigGold))
        smallGold = min(99, max(1, setup.nineBallSmallGold ?? smallGold))
        goldenNine = min(99, max(1, setup.nineBallGoldenNine ?? goldenNine))
        normalWin = min(99, max(1, setup.nineBallNormalWin ?? normalWin))
        ballInHand = min(99, max(1, setup.nineBallBallInHand ?? ballInHand))
        foul = min(99, max(1, setup.nineBallFoul ?? foul))
    }

    private func scoreStepper(_ key: String, fallback: String, value: Binding<Int>) -> some View {
        let title = NSLocalizedString(key, value: fallback, comment: "")

        return HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                scoreStepButton(
                    systemName: "minus",
                    enabled: value.wrappedValue > 1,
                    accessibilityLabel: String.localizedStringWithFormat(
                        NSLocalizedString("nine_ball_decrease_points", value: "减少%@分值", comment: ""),
                        title
                    )
                ) {
                    value.wrappedValue = max(1, value.wrappedValue - 1)
                }

                Divider()
                    .frame(height: 22)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 40)
                    .accessibilityLabel(String.localizedStringWithFormat(
                        NSLocalizedString("nine_ball_current_points", value: "%@当前分值%d", comment: ""),
                        title,
                        value.wrappedValue
                    ))

                Divider()
                    .frame(height: 22)

                scoreStepButton(
                    systemName: "plus",
                    enabled: value.wrappedValue < 99,
                    accessibilityLabel: String.localizedStringWithFormat(
                        NSLocalizedString("nine_ball_increase_points", value: "增加%@分值", comment: ""),
                        title
                    )
                ) {
                    value.wrappedValue = min(99, value.wrappedValue + 1)
                }
            }
            .frame(height: 40)
            .background(Theme.dialogControlBackground)
            .clipShape(Capsule())
        }
    }

    private func scoreStepButton(
        systemName: String,
        enabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.45))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(get: { playerNames[index] }, set: { playerNames[index] = $0 })
    }

    private func playerLabel(_ index: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
            index + 1
        )
    }

    private func requestCancel() {
        onCancel?()
    }

    @MainActor
    private func confirm() async {
        let names = Array(playerNames.prefix(playerCount)).enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? playerLabel(index) : trimmed
        }
        guard Set(names).count == names.count else { return }

        // Manual names follow the same path as the common-name selector so a
        // name entered here is immediately available in later setups.
        for (index, name) in names.enumerated() where name != playerLabel(index) {
            await commonNamesManager.saveNameIfNeeded(name, .player)
        }

        var result = SportsSetupResult(
            team1Name: names[0],
            team2Name: names[1],
            team3Name: names.count > 2 ? names[2] : nil,
            team4Name: names.count > 3 ? names[3] : nil,
            nineBallBigGold: bigGold,
            nineBallSmallGold: smallGold,
            nineBallGoldenNine: goldenNine,
            nineBallNormalWin: normalWin,
            nineBallBallInHand: ballInHand,
            nineBallFoul: foul,
            playerCount: playerCount,
            playerNames: names
        )

        onConfirm(result)
    }
}
