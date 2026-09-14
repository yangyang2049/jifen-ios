import LinkCore
import ScoreCore
import SwiftUI

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
    var maxDialogHeight: CGFloat = 680
    var onConfirm: ((SportsSetupResult) -> Void)?
    var onCancel: (() -> Void)?

    @State private var draft = SportsSetupDraft()
    @State private var setupSendErrorText = ""
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
                .foregroundStyle(.white)
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

    private func getEmoji() -> String {
        return gameType.icon // Using GameType.icon which is defined
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


    private var supportsMatchCompletionMode: Bool {
        gameType == .pingpong || gameType == .badminton || gameType == .tennis ||
            gameType == .pickleball || gameType == .foosball
    }
}
