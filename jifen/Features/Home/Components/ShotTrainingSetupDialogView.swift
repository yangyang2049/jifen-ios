import SwiftUI

nonisolated enum ShotTrainingMode: String, Codable, CaseIterable, Identifiable {
    case fixed1 = "fixed_1"
    case fixed2 = "fixed_2"
    case fixed3 = "fixed_3"
    case free

    var id: String { rawValue }

    var fixedPoints: Int? {
        switch self {
        case .fixed1: return 1
        case .fixed2: return 2
        case .fixed3: return 3
        case .free: return nil
        }
    }

    /// 与鸿蒙端 ShotTrainingLaunchDialog 同一批文案：分区徽标和这里共用 1/2/3 分 + 自由。
    var title: String {
        switch self {
        case .fixed1: return NSLocalizedString("shot_training_1pt", value: "1 分", comment: "")
        case .fixed2: return NSLocalizedString("shot_training_2pt", value: "2 分", comment: "")
        case .fixed3: return NSLocalizedString("shot_training_3pt", value: "3 分", comment: "")
        case .free: return NSLocalizedString("shot_training_free", value: "自由", comment: "")
        }
    }
}

struct ShotTrainingSetupDialogView: View {
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    var maxDialogHeight: CGFloat = 680
    var initialMode: ShotTrainingMode = .fixed1
    let allowsStartOnWatch: Bool
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var mode: ShotTrainingMode
    @State private var watchStartTask: Task<Void, Never>?
    @State private var watchStartError: String?
    @State private var showWatchNotForeground = false
    @State private var showExitWhileSendingConfirm = false

    private var canStartOnWatch: Bool {
        allowsStartOnWatch && AppFeatureFlags.watchLinkEntryEnabled
            && AppFeatureFlags.isWatchLinkSupportedOnCurrentDevice
            && AppFeatureFlags.isWatchLinkSupportedProject(.basketballTraining)
    }

    init(
        maxDialogHeight: CGFloat = 680,
        initialMode: ShotTrainingMode = .fixed1,
        allowsStartOnWatch: Bool = false,
        onConfirm: ((SportsSetupResult) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.maxDialogHeight = maxDialogHeight
        self.initialMode = initialMode
        self.allowsStartOnWatch = allowsStartOnWatch
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 8) {
                AppCatalogIcon(gameType: .basketballTraining, size: 17)
                Text(NSLocalizedString("shot_training_setup_title", value: "投篮训练", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        } content: { _ in
            VStack(alignment: .leading, spacing: Theme.md) {
                // 鸿蒙端 ShotTrainingLaunchDialog：四个模式一行等宽胶囊。
                HStack(spacing: 6) {
                    ForEach(ShotTrainingMode.allCases) { option in
                        Button {
                            mode = option
                        } label: {
                            Text(option.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(mode == option ? Theme.textOnPrimary : Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(mode == option ? Theme.primary : Theme.dialogControlBackground)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(NSLocalizedString(
                    "shot_training_mode_help",
                    value: "固定模式每次记录同一分值；自由模式可在每次出手时选择 1、2 或 3 分。",
                    comment: ""
                ))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                if let watchStartError {
                    Text(watchStartError)
                        .font(.footnote)
                        .foregroundStyle(Theme.destructiveText)
                }
            }
            .disabled(watchStartTask != nil)
            .padding(.horizontal, Theme.lg)
            .padding(.vertical, Theme.md)
        } actions: {
            HStack(spacing: Theme.md) {
                Button(action: cancel) {
                    Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 100, height: 44)
                        .background(Theme.dialogControlBackground, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: 0) {
                    Button {
                        onConfirm?(setupResult)
                    } label: {
                        Text(NSLocalizedString("start_game", value: "开始", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.primary)
                    }
                    .buttonStyle(.plain)

                    if canStartOnWatch {
                        Button(action: startOnWatch) {
                            Group {
                                if watchStartTask != nil {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "applewatch")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 50, height: 44)
                            .background(Theme.primary.opacity(0.78))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sports_setup_watch_start")
                        .accessibilityLabel(NSLocalizedString(
                            "linked_score_start_on_watch", value: "在手表开始", comment: ""
                        ))
                        .linkedScoreWatchStartGuide(
                            isEligible: canStartOnWatch,
                            dismissWhen: watchStartTask != nil
                        )
                    }
                }
                .clipShape(Capsule())
                .disabled(watchStartTask != nil)
            }
            .padding(.horizontal, Theme.lg)
            .padding(.top, Theme.sm)
            .padding(.bottom, Theme.md)
        }
        .alert(
            NSLocalizedString("linked_score_watch_not_foreground_title", value: "请打开手表 App", comment: ""),
            isPresented: $showWatchNotForeground
        ) {
            Button(NSLocalizedString("got_it", value: "知道了", comment: ""), role: .cancel) {}
        } message: {
            Text(PhoneWatchLinkService.InteractiveStartError.watchAppNotForeground.localizedDescription)
        }
        .alert(
            NSLocalizedString("linked_score_setup_exit_title", value: "退出同步计分？", comment: ""),
            isPresented: $showExitWhileSendingConfirm
        ) {
            Button(NSLocalizedString("linked_score_setup_exit_confirm", value: "退出", comment: ""), role: .destructive) {
                cancelWatchStart()
                onCancel?()
            }
            Button(NSLocalizedString("cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "linked_score_setup_exit_message",
                value: "现在正在等待手表确认。退出后将取消本次同步计分。",
                comment: ""
            ))
        }
        .onDisappear(perform: cancelWatchStart)
    }

    private var setupResult: SportsSetupResult {
        SportsSetupResult(
            team1Name: NSLocalizedString("shot_training_miss", value: "未中", comment: ""),
            team2Name: NSLocalizedString("shot_training_made", value: "命中", comment: ""),
            basketballTrainingScoringMode: mode.rawValue
        )
    }

    private func startOnWatch() {
        // 与通用 Setup 弹层同一口径：发起握手前再确认一次手表主控仍然可用，
        // 避免功能开关/设备能力在弹层打开期间变化后发送一个必然失败的请求。
        guard canStartOnWatch else {
            watchStartError = PhoneWatchLinkService.InteractiveStartError.watchUnavailable.localizedDescription
            return
        }
        watchStartError = nil
        var setup = setupResult
        watchStartTask = Task {
            defer { watchStartTask = nil }
            guard !Task.isCancelled else { return }
            do {
                setup.linkedWatchSessionId = try await SportsSetupWatchSessionLauncher.start(
                    gameType: .basketballTraining,
                    config: setup,
                    using: watchLinkService
                )
                guard !Task.isCancelled else { return }
                setup.startOnWatch = true
                watchStartTask = nil
                onConfirm?(setup)
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? PhoneWatchLinkService.InteractiveStartError,
                   case .watchAppNotForeground = error {
                    showWatchNotForeground = true
                } else {
                    watchStartError = error.localizedDescription
                }
            }
        }
    }

    private func cancel() {
        // 正在等待手表确认时先二次确认：中途退出会取消本次同步计分。
        guard watchStartTask == nil else {
            showExitWhileSendingConfirm = true
            return
        }
        onCancel?()
    }

    private func cancelWatchStart() {
        guard let task = watchStartTask else { return }
        watchStartTask = nil
        task.cancel()
        // 让手表侧也放弃这次 setup（服务端会 leaveSession 并回收会话）。
        watchLinkService.cancelPendingSetupHandshake()
    }

}
