//
//  DualTimerSetupView.swift
//  jifen
//
//  Setup dialog aligned to Harmony BoardTimerSettingsView for Go/Xiangqi/Chess.
//

import SwiftUI

struct DualTimerSetupView: View {
    let gameType: GameType
    let emoji: String
    var initialConfig: BoardTimerConfig? = nil
    var onConfirm: (BoardTimerConfig) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var draftConfig: BoardTimerConfig

    init(
        gameType: GameType,
        emoji: String,
        initialConfig: BoardTimerConfig? = nil,
        onConfirm: @escaping (BoardTimerConfig) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.gameType = gameType
        self.emoji = emoji
        self.initialConfig = initialConfig
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        var resolved = initialConfig ?? BoardTimerConfig.default(for: gameType)
        resolved.normalize()
        _draftConfig = State(initialValue: resolved)
    }

    private var title: String {
        gameType.displayName + NSLocalizedString("setup_suffix", value: "设置", comment: "")
    }

    private var availableModes: [BoardTimeMode] {
        BoardTimerConfig.availableModes(for: gameType)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: true) {
                VStack(spacing: 14) {
                    modeSegment
                    mainTimeSection

                    switch draftConfig.timeMode {
                    case .increment:
                        incrementSection
                    case .byoyomi:
                        byoyomiSection
                    case .delay:
                        delaySection
                    case .countdown:
                        EmptyView()
                    }

                    feedbackSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .frame(maxHeight: .infinity)

            startButton
        }
        .background(Theme.homeDialogBackground)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            HStack {
                Spacer()
                Button {
                    onCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Theme.homeDialogBackground)
    }

    private var modeSegment: some View {
        Picker("", selection: Binding(
            get: { draftConfig.timeMode },
            set: { draftConfig.applyTimeMode($0) }
        )) {
            ForEach(availableModes) { mode in
                Text(mode.localizedTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(height: 36)
    }

    private var mainTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dual_timer_main_time", value: "主时间", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)

            HStack(spacing: 8) {
                numericField(
                    value: Binding(
                        get: { draftConfig.mainMinutes },
                        set: {
                            draftConfig.mainMinutes = max(0, $0)
                            clampMainTime()
                        }
                    ),
                    suffix: NSLocalizedString("minutes", value: "分钟", comment: "")
                )

                numericField(
                    value: Binding(
                        get: { draftConfig.mainSeconds },
                        set: {
                            draftConfig.mainSeconds = min(59, max(0, $0))
                            clampMainTime()
                        }
                    ),
                    suffix: NSLocalizedString("seconds_short", value: "秒", comment: "")
                )
            }
        }
    }

    private var byoyomiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("timer_byoyomi", value: "读秒", comment: "Byoyomi"))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)

            HStack(spacing: 8) {
                numericField(
                    value: Binding(
                        get: { draftConfig.byoyomiSeconds },
                        set: { draftConfig.byoyomiSeconds = max(0, $0) }
                    ),
                    suffix: NSLocalizedString("timer_byoyomi_seconds_per_period", value: "秒/次", comment: "Byoyomi seconds per period")
                )

                numericField(
                    value: Binding(
                        get: { draftConfig.byoyomiPeriods },
                        set: { draftConfig.byoyomiPeriods = max(0, $0) }
                    ),
                    suffix: NSLocalizedString("timer_byoyomi_periods", value: "次", comment: "Byoyomi periods")
                )
            }
        }
    }

    private var incrementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("timer_increment", value: "加秒", comment: "Increment"))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)

            numericField(
                value: Binding(
                    get: { draftConfig.incrementSeconds },
                    set: { draftConfig.incrementSeconds = max(0, $0) }
                ),
                suffix: NSLocalizedString("timer_increment_per_move", value: "秒/步", comment: "Increment per move")
            )
        }
    }

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("timer_mode_delay", value: "延迟", comment: "Delay"))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)

            numericField(
                value: Binding(
                    get: { draftConfig.delaySeconds },
                    set: { draftConfig.delaySeconds = max(0, $0) }
                ),
                suffix: NSLocalizedString("timer_seconds_delay", value: "秒延迟", comment: "Seconds delay")
            )
        }
    }

    private var feedbackSection: some View {
        VStack(spacing: 12) {
            feedbackToggle(
                title: NSLocalizedString("timer_voice_announcement", value: "语音播报", comment: ""),
                value: Binding(
                    get: { draftConfig.voiceEnabled },
                    set: { draftConfig.voiceEnabled = $0 }
                )
            )

            feedbackToggle(
                title: NSLocalizedString("timer_vibration_feedback", value: "震动反馈", comment: ""),
                value: Binding(
                    get: { draftConfig.vibrationEnabled },
                    set: { draftConfig.vibrationEnabled = $0 }
                )
            )
        }
    }

    private func feedbackToggle(title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(Theme.accentColor)
        }
    }

    private func numericField(value: Binding<Int>, suffix: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            TextField(
                "0",
                value: value,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(suffix)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary.opacity(0.7))
                .padding(.trailing, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var startButton: some View {
        Button {
            draftConfig.normalize()
            onConfirm(draftConfig)
        } label: {
            Text(NSLocalizedString("start_game", value: "开始", comment: "Start game"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.primary)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(Theme.homeDialogBackground)
    }

    private func clampMainTime() {
        if draftConfig.mainMinutes == 0 && draftConfig.mainSeconds < BoardTimerConfig.minMainTimeSeconds {
            draftConfig.mainSeconds = BoardTimerConfig.minMainTimeSeconds
        }
    }
}

#Preview {
    DualTimerSetupView(
        gameType: .xiangqi,
        emoji: "🐘",
        initialConfig: BoardTimerConfig.default(for: .xiangqi),
        onConfirm: { _ in }
    )
}
