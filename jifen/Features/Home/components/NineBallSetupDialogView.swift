import LinkCore
import ScoreCore
import SwiftUI

/// 追分开局设置。人数与事件分值直接写入 `SportsSetupResult`，计分板不再
/// 根据页面默认值二次猜测，和鸿蒙/安卓的 setup -> reducer 契约保持一致。
struct NineBallSetupDialogView: View {
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

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
    @State private var isSendingSetupToWatch = false
    @State private var setupSendErrorText = ""
    @State private var showWatchStartConfirm = false
    @State private var showExitWhileSendingConfirm = false
    @State private var showWatchStartGuide = !PreferencesManager.shared.linkedScoreWatchStartGuideShown

    private var canStartOnWatch: Bool {
        AppFeatureFlags.watchLinkEntryEnabled
            && AppFeatureFlags.isWatchLinkSupportedProject(.nineBall)
            && watchLinkService.canStartInteractiveSession
            && (2...4).contains(playerCount)
    }

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
            CommonNameSelectorDialog(nameType: .player) { value in
                if let activeNameIndex { playerNames[activeNameIndex] = value }
                activeNameIndex = nil
            }
        }
        .onAppear(perform: applyInitialSetup)
        .confirmationDialog(
            NSLocalizedString("linked_score_start_confirm_title", value: "在手表开始？", comment: ""),
            isPresented: $showWatchStartConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("linked_score_start_on_watch", value: "在手表开始", comment: "")) {
                dismissWatchStartGuide()
                Task { await confirm(startOnWatch: true) }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "linked_score_start_confirm_message",
                value: "将向手表发送开局请求，请在手表上确认后开始计分；手机将跟随显示。",
                comment: ""
            ))
        }
        .alert(
            NSLocalizedString("linked_score_setup_exit_title", value: "退出同步计分？", comment: ""),
            isPresented: $showExitWhileSendingConfirm
        ) {
            Button(NSLocalizedString("linked_score_setup_exit_confirm", value: "退出", comment: ""), role: .destructive) {
                watchLinkService.cancelPendingSetupHandshake()
                isSendingSetupToWatch = false
                onCancel?()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "linked_score_setup_exit_message",
                value: "现在正在等待手表确认。退出后将取消本次同步计分。",
                comment: ""
            ))
        }
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
                        .background(Theme.homeCardDark)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if canStartOnWatch {
                    HStack(spacing: 0) {
                        startButton(startOnWatch: false)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: 22,
                                bottomLeadingRadius: 22,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            ))

                        Button {
                            showWatchStartConfirm = true
                        } label: {
                            Group {
                                if isSendingSetupToWatch {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "applewatch")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                            }
                            .frame(width: 50, height: 44)
                            .foregroundStyle(.white)
                            .background(Theme.primary.opacity(0.78))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSendingSetupToWatch)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 22,
                            topTrailingRadius: 22
                        ))
                        .accessibilityLabel(NSLocalizedString(
                            "linked_score_start_on_watch",
                            value: "在手表开始",
                            comment: ""
                        ))
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(Capsule())
                    // Overlay so the guide bubble does not expand the start-button layout.
                    .overlay(alignment: .topTrailing) {
                        if showWatchStartGuide {
                            watchStartGuideBubble
                                // Anchor bubble bottom (arrow tip) to the top of the start row.
                                .alignmentGuide(.top) { $0[.bottom] }
                                .offset(x: 4, y: -2)
                        }
                    }
                    .zIndex(showWatchStartGuide ? 1 : 0)
                } else {
                    startButton(startOnWatch: false)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var watchStartGuideBubble: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("linked_score_watch_start_guide_title", value: "手表主控计分", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(NSLocalizedString(
                    "linked_score_watch_start_guide_message",
                    value: "点右侧手表按钮发送到手表，由手表主控；手机同步显示并保存记录。",
                    comment: ""
                ))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                Button(action: dismissWatchStartGuide) {
                    Text(NSLocalizedString("watch_sync_comm_failure_help_confirm", value: "知道了", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 210, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.cardBackground)
                .rotationEffect(.degrees(180))
                .padding(.trailing, 18)
                .offset(y: -1)
        }
    }

    private func startButton(startOnWatch: Bool) -> some View {
        Button {
            Task { await confirm(startOnWatch: startOnWatch) }
        } label: {
            Text(NSLocalizedString("start_game", comment: ""))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.primary)
        }
        .buttonStyle(.plain)
        .disabled(isSendingSetupToWatch)
        .opacity(isSendingSetupToWatch ? 0.7 : 1)
    }

    private func applyInitialSetup() {
        guard let setup = initialSetup else { return }
        playerCount = min(4, max(2, setup.playerCount ?? setup.playerNames?.count ?? 2))
        for (index, name) in (setup.playerNames ?? []).prefix(4).enumerated() {
            playerNames[index] = name
        }
        bigGold = setup.nineBallBigGold ?? bigGold
        smallGold = setup.nineBallSmallGold ?? smallGold
        goldenNine = setup.nineBallGoldenNine ?? goldenNine
        normalWin = setup.nineBallNormalWin ?? normalWin
        ballInHand = setup.nineBallBallInHand ?? ballInHand
        foul = setup.nineBallFoul ?? foul
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

    private func requestCancel() {
        if isSendingSetupToWatch {
            showExitWhileSendingConfirm = true
        } else {
            onCancel?()
        }
    }

    private func dismissWatchStartGuide() {
        guard showWatchStartGuide else { return }
        showWatchStartGuide = false
        PreferencesManager.shared.linkedScoreWatchStartGuideShown = true
    }

    @MainActor
    private func confirm(startOnWatch: Bool = false) async {
        let names = Array(playerNames.prefix(playerCount)).enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? playerLabel(index) : trimmed
        }
        guard Set(names).count == names.count else { return }

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

        if startOnWatch {
            guard canStartOnWatch else {
                setupSendErrorText = PhoneWatchLinkService.InteractiveStartError.watchUnavailable.localizedDescription
                return
            }
            isSendingSetupToWatch = true
            setupSendErrorText = ""
            do {
                let nineConfig = NineBallChaseConfig(
                    bigGold: bigGold,
                    smallGold: smallGold,
                    goldenNine: goldenNine,
                    normalWin: normalWin,
                    ballInHand: ballInHand,
                    foul: foul
                )
                let nine = NineBallChaseState.initial(config: nineConfig, playerCount: playerCount, playerNames: names)
                result.linkedWatchSessionId = try await watchLinkService.startInteractiveOnWatch(
                    snapshot: .nineBall(nine),
                    gameType: .nineBall
                )
                result.startOnWatch = true
            } catch {
                isSendingSetupToWatch = false
                setupSendErrorText = error.localizedDescription
                return
            }
            isSendingSetupToWatch = false
        }

        onConfirm(result)
    }
}
