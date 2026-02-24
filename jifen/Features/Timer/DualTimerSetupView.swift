//
//  DualTimerSetupView.swift
//  jifen
//
//  Setup dialog aligned to Harmony timer settings for Go/Xiangqi/Chess.
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

        let resolved = initialConfig ?? BoardTimerConfig.default(for: gameType)
        _draftConfig = State(initialValue: resolved)
    }

    private var title: String {
        gameType.displayName + NSLocalizedString("setup_suffix", value: "设置", comment: "")
    }

    private var usesByoyomi: Bool {
        gameType == .go
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    modeSegment
                    mainTimeSection

                    if usesByoyomi {
                        byoyomiSection
                    } else {
                        incrementSection
                    }

                    feedbackSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }

            startButton
        }
        .background(Color(hex: "2C2C2E"))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                onCancel?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Color(hex: "323235"))
    }

    private var modeSegment: some View {
        Picker("", selection: Binding(
            get: { draftConfig.presetMode },
            set: { newMode in
                draftConfig.applyPreset(newMode)
                draftConfig.normalizeInput()
            }
        )) {
            ForEach(BoardTimerPresetMode.allCases) { mode in
                Text(mode.localizedTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(height: 36)
    }

    private var mainTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("dual_timer_main_time", value: "主时间（分钟）", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 8) {
                numericField(
                    value: Binding(
                        get: { draftConfig.mainMinutes },
                        set: { draftConfig.mainMinutes = $0 }
                    ),
                    suffix: NSLocalizedString("minutes", value: "分钟", comment: "")
                )

                numericField(
                    value: Binding(
                        get: { draftConfig.mainSeconds },
                        set: { draftConfig.mainSeconds = min(59, max(0, $0)) }
                    ),
                    suffix: NSLocalizedString("seconds_short", value: "秒", comment: "")
                )
            }
        }
    }

    private var byoyomiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("timer_byoyomi", value: "读秒", comment: "Byoyomi"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { draftConfig.byoyomiEnabled },
                    set: {
                        draftConfig.byoyomiEnabled = $0
                        draftConfig.normalizeInput()
                    }
                ))
                .labelsHidden()
                .tint(Theme.accentColor)
            }

            HStack(spacing: 8) {
                numericField(
                    value: Binding(
                        get: { draftConfig.byoyomiSeconds },
                        set: { draftConfig.byoyomiSeconds = $0 }
                    ),
                    suffix: NSLocalizedString("timer_byoyomi_seconds_per_period", value: "秒/次", comment: "Byoyomi seconds per period"),
                    enabled: draftConfig.byoyomiEnabled
                )

                numericField(
                    value: Binding(
                        get: { draftConfig.byoyomiPeriods },
                        set: { draftConfig.byoyomiPeriods = $0 }
                    ),
                    suffix: NSLocalizedString("timer_byoyomi_periods", value: "次", comment: "Byoyomi periods"),
                    enabled: draftConfig.byoyomiEnabled
                )
            }
        }
    }

    private var incrementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("timer_increment", value: "加时", comment: "Increment"))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { draftConfig.incrementEnabled },
                    set: {
                        draftConfig.incrementEnabled = $0
                        draftConfig.normalizeInput()
                    }
                ))
                .labelsHidden()
                .tint(Theme.accentColor)
            }

            numericField(
                value: Binding(
                    get: { draftConfig.incrementSeconds },
                    set: { draftConfig.incrementSeconds = $0 }
                ),
                suffix: NSLocalizedString("timer_increment_per_move", value: "秒/步", comment: "Increment per move"),
                enabled: draftConfig.incrementEnabled
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
                .foregroundColor(.white.opacity(0.82))
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(Theme.accentColor)
        }
    }

    private func numericField(value: Binding<Int>, suffix: String, enabled: Bool = true) -> some View {
        ZStack(alignment: .bottomTrailing) {
            TextField(
                "0",
                value: value,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundColor(enabled ? .white : .white.opacity(0.35))
            .frame(height: 56)
            .background(enabled ? Color(hex: "343438") : Color(hex: "2A2A2D"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .disabled(!enabled)

            Text(suffix)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .padding(.trailing, 8)
                .padding(.bottom, 6)
        }
    }

    private var startButton: some View {
        Button {
            draftConfig.normalizeInput()
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
        .background(Color(hex: "2C2C2E"))
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
