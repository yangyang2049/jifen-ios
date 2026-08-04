import LinkCore
import ScoreCore
import SwiftUI

enum LinkedScoreWatchStartGuidePolicy {
    static let showDelay: Duration = .milliseconds(120)
    static let visibleDuration: Duration = .milliseconds(4_800)
}

struct LinkedScoreWatchStartGuidePopover: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "applewatch")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text(NSLocalizedString(
                    "linked_score_watch_start_guide_title",
                    value: "手表主控计分",
                    comment: ""
                ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

                Spacer(minLength: 6)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.dialogControlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
                .accessibilityIdentifier("linked_score_watch_start_guide_close")
            }

            Text(NSLocalizedString(
                "linked_score_watch_start_guide_message",
                value: "点右侧手表按钮发送到手表，由手表主控；手机同步显示并保存记录。",
                comment: ""
            ))
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 268, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - SportsSetupDialogView

struct SportsSetupDialogView: View {
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    var gameType: GameType
    var defaultTeam1Name: String
    var defaultTeam2Name: String
    var initialMaxSets: Int?
    var initialPointsPerSet: Int?
    var initialTieBreakPoints: Int?
    var initialSetup: SportsSetupResult? = nil
    /// 整张 Setup 卡片的可用高度；标题、内容和操作区会分别测量。
    var maxDialogHeight: CGFloat = 680
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var draft = SportsSetupDraft()
    @State private var isSendingSetupToWatch = false
    @State private var setupSendErrorText = ""
    @State private var showExitWhileSendingConfirm = false
    @State private var showWatchNotForegroundAlert = false
    @State private var showWatchStartGuide = false
    // Managers
    private let commonNamesManager = CommonNamesManager.shared

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 6) {
                Text(getEmoji())
                    .font(.system(size: 20))
                Text(getProjectTitle())
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, Theme.md)
        } content: { maxContentHeight in
            AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight) {
                VStack(spacing: 20) {
                    SportsSetupParticipantSection(
                        gameType: gameType,
                        defaultTeam1Name: defaultTeam1Name,
                        defaultTeam2Name: defaultTeam2Name,
                        draft: $draft
                    )

                    SportsSetupSettingsSection(gameType: gameType, draft: $draft)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Theme.md)
            }
        } actions: {
            buildDialogActions()
        }
        .onAppear {
            initializeView()
        }
        .task(id: canStartOnWatch) {
            await presentWatchStartGuideIfNeeded()
        }
        .onChange(of: draft.isSingles) { _, newValue in
            guard shouldShowSinglesDoublesAtTop() else { return }
            if newValue {
                draft.applyDefaultsWhenSwitchingToSingles(gameType: gameType)
            } else {
                draft.applyDefaultsWhenSwitchingToDoubles(
                    gameType: gameType,
                    configuredLeftName: defaultTeam1Name,
                    configuredRightName: defaultTeam2Name
                )
            }
        }
        .onChange(of: draft.matchCompletionMode) { _, newMode in
            if newMode == .bestOf, draft.selectedMaxSets.isMultiple(of: 2) {
                draft.selectedMaxSets = min(99, draft.selectedMaxSets + 1)
            }
            draft.customMaxSetsText = draft.frameCountPresets(for: gameType).contains(draft.selectedMaxSets) ? "" : (
                draft.selectedMaxSets > 0 ? String(draft.selectedMaxSets) : ""
            )
            draft.syncPickleballTargetForSets(gameType: gameType)
        }
        .onChange(of: draft.selectedMaxSets) { _, newValue in
            draft.syncPickleballTargetForSets(gameType: gameType)
            if gameType == .eightBall {
                if newValue <= 1 {
                    draft.eightBallHandicapMode = "none"
                    draft.eightBallHandicapRacks = 0
                } else if draft.eightBallHandicapMode != "none" {
                    draft.eightBallHandicapRacks = min(max(1, draft.eightBallHandicapRacks), newValue - 1)
                }
            }
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
                Button(action: requestCancelDialog) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.dialogControlBackground)
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
                            dismissWatchStartGuide()
                            Task { await confirmSetup(startOnWatch: true) }
                        } label: {
                            Group {
                                if isSendingSetupToWatch {
                                    ProgressView()
                                        .tint(.white)
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
                            comment: "Start scoreboard on watch"
                        ))
                        .popover(
                            isPresented: $showWatchStartGuide,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .bottom
                        ) {
                            LinkedScoreWatchStartGuidePopover(
                                onDismiss: dismissWatchStartGuide
                            )
                        }
                        .alert(
                            NSLocalizedString(
                                "linked_score_watch_not_foreground_title",
                                value: "请打开手表 App",
                                comment: ""
                            ),
                            isPresented: $showWatchNotForegroundAlert
                        ) {
                            Button(NSLocalizedString(
                                "watch_sync_comm_failure_help_confirm",
                                value: "知道了",
                                comment: ""
                            ), role: .cancel) {}
                        } message: {
                            Text(PhoneWatchLinkService.InteractiveStartError.watchAppNotForeground.localizedDescription)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(Capsule())
                } else {
                    startButton(startOnWatch: false)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .alert(
            NSLocalizedString("linked_score_setup_exit_title", value: "退出同步计分？", comment: ""),
            isPresented: $showExitWhileSendingConfirm
        ) {
            Button(NSLocalizedString("linked_score_setup_exit_confirm", value: "退出", comment: ""), role: .destructive) {
                watchLinkService.cancelPendingSetupHandshake()
                isSendingSetupToWatch = false
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
    }

    private func dismissWatchStartGuide() {
        showWatchStartGuide = false
        PreferencesManager.shared.linkedScoreWatchStartGuideShown = true
    }

    @MainActor
    private func presentWatchStartGuideIfNeeded() async {
        guard canStartOnWatch else {
            showWatchStartGuide = false
            return
        }
        guard !PreferencesManager.shared.linkedScoreWatchStartGuideShown else {
            showWatchStartGuide = false
            return
        }

        do {
            try await Task.sleep(for: LinkedScoreWatchStartGuidePolicy.showDelay)
        } catch {
            return
        }
        guard !Task.isCancelled,
              canStartOnWatch,
              !PreferencesManager.shared.linkedScoreWatchStartGuideShown else { return }

        PreferencesManager.shared.linkedScoreWatchStartGuideShown = true
        showWatchStartGuide = true

        do {
            try await Task.sleep(for: LinkedScoreWatchStartGuidePolicy.visibleDuration)
        } catch {
            return
        }
        showWatchStartGuide = false
    }

    private func startButton(startOnWatch: Bool) -> some View {
        Button {
            Task { await confirmSetup(startOnWatch: startOnWatch) }
        } label: {
            Text(NSLocalizedString("start_game", comment: "Start Game button"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.primary)
        }
        .buttonStyle(.plain)
        .disabled(isSendingSetupToWatch)
        .opacity(isSendingSetupToWatch ? 0.7 : 1)
    }

    private func requestCancelDialog() {
        if isSendingSetupToWatch {
            showExitWhileSendingConfirm = true
        } else {
            onCancel?()
        }
    }

    private func cancelDialog() {
        onCancel?()
    }

    private func initializeView() {
        draft.initialize(
            gameType: gameType,
            initialSetup: initialSetup,
            initialMaxSets: initialMaxSets,
            initialPointsPerSet: initialPointsPerSet,
            initialTieBreakPoints: initialTieBreakPoints
        )
        setupSendErrorText = ""
    }

    private func getProjectTitle() -> String {
        gameType.displayName
    }

    private func getEmoji() -> String {
        return gameType.icon // Using GameType.icon which is defined
    }

    private func shouldShowSinglesDoublesAtTop() -> Bool {
        return gameType == .pingpong || gameType == .badminton || gameType == .tennis || gameType == .pickleball || gameType == .foosball
    }

    private func shouldUseDoublesPlayerInputs() -> Bool {
        shouldShowSinglesDoublesAtTop() && !draft.isSingles
    }

    private var supportsWatchProject: Bool {
        AppFeatureFlags.isWatchLinkSupportedSetup(
            gameType: gameType,
            isSingles: shouldShowSinglesDoublesAtTop() ? draft.isSingles : nil
        )
    }

    private var canStartOnWatch: Bool {
        AppFeatureFlags.watchLinkEntryEnabled
            && AppFeatureFlags.isWatchLinkSupportedOnCurrentDevice
            && supportsWatchProject
    }

    private func confirmSetup(startOnWatch: Bool = false) async {
        if supportsMatchCompletionMode, !draft.hasValidMatchCompletionSets {
            return
        }
        if !draft.hasValidPointsPerSet(for: gameType) {
            return
        }
        if !draft.hasValidFoosballScoreCap(for: gameType) {
            setupSendErrorText = NSLocalizedString(
                "setup_score_cap_below_target",
                value: "封顶分不能低于每局分数。",
                comment: "Foosball final-set score cap validation"
            )
            return
        }
        var finalConfig = draft.makeResult(
            gameType: gameType,
            usesDoublesPlayerInputs: shouldUseDoublesPlayerInputs()
        )

        if finalConfig.team1Name == finalConfig.team2Name && !finalConfig.team1Name.isEmpty {
            setupSendErrorText = NSLocalizedString(
                "duplicate_names_warning",
                value: "双方名称不能相同",
                comment: "Duplicate names warning"
            )
            return
        }

        if startOnWatch {
            guard canStartOnWatch else {
                setupSendErrorText = PhoneWatchLinkService.InteractiveStartError.watchUnavailable.localizedDescription
                return
            }
            isSendingSetupToWatch = true
            setupSendErrorText = ""
            do {
                finalConfig.linkedWatchSessionId = try await SportsSetupWatchSessionLauncher.start(
                    gameType: gameType,
                    config: finalConfig,
                    using: watchLinkService
                )
                finalConfig.startOnWatch = true
            } catch {
                isSendingSetupToWatch = false
                if let startError = error as? PhoneWatchLinkService.InteractiveStartError,
                   case .watchAppNotForeground = startError {
                    setupSendErrorText = ""
                    showWatchNotForegroundAlert = true
                } else {
                    setupSendErrorText = error.localizedDescription
                }
                return
            }
            isSendingSetupToWatch = false
        }
        
        if shouldUseDoublesPlayerInputs() {
            let playerNames = [
                draft.team1Player1Name,
                draft.team1Player2Name,
                draft.team2Player1Name,
                draft.team2Player2Name,
            ]
            for name in playerNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    await commonNamesManager.saveNameIfNeeded(trimmed, .player)
                }
            }
        } else if shouldShowSinglesDoublesAtTop() {
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.saveNameIfNeeded(finalConfig.team1Name, .player)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.saveNameIfNeeded(finalConfig.team2Name, .player)
            }
        } else {
            let nameKind = ScoreboardCommonNamePolicy.nameType(for: gameType)
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.saveNameIfNeeded(finalConfig.team1Name, nameKind)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.saveNameIfNeeded(finalConfig.team2Name, nameKind)
            }
        }

        onConfirm?(finalConfig)
    }


    private var supportsMatchCompletionMode: Bool {
        gameType == .pingpong || gameType == .badminton || gameType == .tennis ||
            gameType == .pickleball || gameType == .foosball
    }
}
