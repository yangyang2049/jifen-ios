import LinkCore
import ScoreCore
import SwiftUI

private struct SetupFieldScrollTarget: Equatable {
    let fieldID: String?
    let viewportHeight: CGFloat
}

// MARK: - SportsSetupDialogView

struct SportsSetupDialogView: View {
    var gameType: GameType
    var defaultTeam1Name: String
    var defaultTeam2Name: String
    var initialMaxSets: Int?
    var initialPointsPerSet: Int?
    var initialTieBreakPoints: Int?
    var initialSetup: SportsSetupResult? = nil
    /// 整张 Setup 卡片的可用高度；标题、内容和操作区会分别测量。
    var showParticipants = true
    var maxDialogHeight: CGFloat = 680
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var draft = SportsSetupDraft()
    @State private var setupSendErrorText = ""
    @State private var focusedSetupFieldID: String?
    @State private var setupToastMessage: String?
    @State private var setupToastDismissTask: Task<Void, Never>?
    // Managers
    private let commonNamesManager = CommonNamesManager.shared

    var body: some View {
        AdaptiveSetupDialogLayout(maxHeight: maxDialogHeight) {
            HStack(spacing: 6) {
                AppCatalogIcon(gameType: gameType, size: 20)
                Text(getProjectTitle())
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .accessibilityIdentifier("sports_setup_title")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.horizontal, Theme.md)
        } content: { maxContentHeight in
            ScrollViewReader { scrollProxy in
                AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight) {
                    VStack(spacing: 20) {
                        if showParticipants {
                        SportsSetupParticipantSection(
                            gameType: gameType,
                            defaultTeam1Name: defaultTeam1Name,
                            defaultTeam2Name: defaultTeam2Name,
                            draft: $draft
                        )
                        }

                        SportsSetupSettingsSection(gameType: gameType, draft: $draft) {
                            focusedSetupFieldID = $0
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, Theme.md)
                }
                .task(id: SetupFieldScrollTarget(fieldID: focusedSetupFieldID, viewportHeight: maxContentHeight)) {
                    guard let fieldID = focusedSetupFieldID else { return }
                    // A keyboard resize can finish after the initial focus request.
                    // Restart when the viewport changes so the editor stays inside it.
                    do {
                        try await Task.sleep(for: .milliseconds(350))
                    } catch {
                        return
                    }
                    guard focusedSetupFieldID == fieldID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(fieldID, anchor: .center)
                    }
                }
            }
        } actions: {
            buildDialogActions()
        }
        .overlay(alignment: .bottom) {
            if let setupToastMessage {
                ToastView(message: setupToastMessage)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: setupToastMessage)
        .onAppear {
            initializeView()
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
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 100, height: 44)
                        .background(Theme.dialogControlBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                startButton()
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    private func startButton() -> some View {
        Button {
            Task { await confirmSetup() }
        } label: {
            Text(NSLocalizedString("start_game", comment: "Start Game button"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.primary)
        }
        .buttonStyle(.plain)
    }

    private func requestCancelDialog() {
        onCancel?()
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

    private func shouldShowSinglesDoublesAtTop() -> Bool {
        return gameType == .pingpong || gameType == .badminton || gameType == .tennis || gameType == .softTennis || gameType == .shuttlecock || gameType == .pickleball || gameType == .foosball
    }

    private func shouldUseDoublesPlayerInputs() -> Bool {
        if gameType == .padel { return true }
        if gameType == .shuttlecock {
            return [.doubles, .mixedDoubles].contains(draft.competitionFormat)
        }
        return shouldShowSinglesDoublesAtTop() && !draft.isSingles
    }

    private func confirmSetup() async {
        // 对齐安卓：数值类约束（局数/每局分数/封顶分/让局）在 makeResult 里静默夹到合法区间，
        // 个人项目允许不同选手同名，并在表单内提示；同一身份占多个席位仍需拦截。
        if let correction = draft.oddSetsCorrectionApplied(for: gameType) {
            showSetupToast(String(
                format: NSLocalizedString(
                    "setup_auto_odd_sets",
                    value: "Only odd numbers are allowed — using %d",
                    comment: "Setup odd-set autocorrection notice"
                ),
                correction.corrected
            ))
        }
        var finalConfig = draft.makeResult(
            gameType: gameType,
            usesDoublesPlayerInputs: shouldUseDoublesPlayerInputs()
        )

        if ParticipantIdentityRules.containsDuplicatePerson(Array((finalConfig.participantSelections ?? [:]).values)) {
            setupSendErrorText = identityText("already_playing", "你已在其他位置参赛")
            return
        }
        if !PersonalRecordAdapter.supportsPerson(gameType) && finalConfig.team1Name == finalConfig.team2Name && !finalConfig.team1Name.isEmpty {
            setupSendErrorText = NSLocalizedString(
                "duplicate_names_warning",
                value: "双方名称不能相同",
                comment: "Duplicate names warning"
            )
            return
        }

        if shouldUseDoublesPlayerInputs() || (gameType == .shuttlecock && draft.competitionFormat == .team) {
            let playerNames = [
                draft.team1Player1Name,
                draft.team1Player2Name,
                draft.team1Player3Name,
                draft.team2Player1Name,
                draft.team2Player2Name,
                draft.team2Player3Name,
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

        if ScoreboardMatchTimePolicy.includesSportsSetupValue(
            for: gameType,
            isSingles: draft.isSingles
        ) {
            PreferencesManager.shared.setScoreboardMatchTimeVisible(
                draft.showMatchTime,
                for: gameType
            )
        }

        onConfirm?(finalConfig)
    }

    /// Toast 与页面内其他一次性提示保持一致：2 秒后自动消失，新提示覆盖旧提示。
    private func showSetupToast(_ message: String) {
        setupToastDismissTask?.cancel()
        setupToastMessage = message
        setupToastDismissTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            setupToastMessage = nil
        }
    }

    private var supportsMatchCompletionMode: Bool {
        gameType == .pingpong || gameType == .badminton || gameType == .tennis ||
            gameType == .pickleball || gameType == .foosball
    }
}
