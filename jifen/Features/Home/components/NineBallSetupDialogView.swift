import SwiftUI

/// 追分开局设置。人数与事件分值直接写入 `SportsSetupResult`，计分板不再
/// 根据页面默认值二次猜测，和鸿蒙/安卓的 setup -> reducer 契约保持一致。
struct NineBallSetupDialogView: View {
    var maxContentHeight: CGFloat = 520
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("🎱")
                Text(NSLocalizedString("game_nine_ball", value: "追分", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)

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

            HStack(spacing: 16) {
                Button(action: cancel) {
                    Text(NSLocalizedString("cancel", comment: ""))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.homeCardDark)
                        .clipShape(Capsule())
                }
                Button(action: confirm) {
                    Text(NSLocalizedString("start_game", comment: ""))
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.primary)
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: Binding(
            get: { activeNameIndex != nil },
            set: { if !$0 { activeNameIndex = nil } }
        )) {
            CommonNameSelectorDialog(nameType: .player) { value in
                if let activeNameIndex { playerNames[activeNameIndex] = value }
                activeNameIndex = nil
            }
        }
    }

    private func scoreStepper(_ key: String, fallback: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...99) {
            HStack {
                Text(NSLocalizedString(key, value: fallback, comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 14))
        }
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

    private func cancel() {
        onCancel?()
    }

    private func confirm() {
        let names = Array(playerNames.prefix(playerCount)).enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? playerLabel(index) : trimmed
        }
        guard Set(names).count == names.count else { return }
        onConfirm(SportsSetupResult(
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
        ))
    }
}
