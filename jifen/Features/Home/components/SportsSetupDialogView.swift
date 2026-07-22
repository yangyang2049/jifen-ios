import LinkCore
import ScoreCore
import SwiftUI

// MARK: - CommonNameSelectorDialog
// Sheet to pick a common team/player name (aligned with HarmonyOS common-name picker)

struct CommonNameSelectorDialog: View {
    @Environment(\.dismiss) var dismiss
    var nameType: NameType
    var onSelect: (String) -> Void

    private let commonNamesManager = CommonNamesManager.shared

    private var names: [String] {
        commonNamesManager.getNames(type: nameType)
    }

    var body: some View {
        NavigationView {
            Group {
                if names.isEmpty {
                    VStack(spacing: Theme.sm) {
                        EmptyStateCourtIcon(size: 44)
                        Text(NSLocalizedString("common_names_empty", value: "暂无常用名称", comment: ""))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textSecondary)
                        Text(NSLocalizedString("common_names_empty_hint", value: "在「设置」-「数据」-「常用名称管理」中添加队伍或选手名称，下次即可在此快速选择。", comment: "Hint when no common names"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.md)
                            .padding(.top, Theme.xs)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(names, id: \.self) { name in
                        Button(action: {
                            onSelect(name)
                            dismiss()
                        }) {
                            HStack {
                                Text(name)
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("common_names_title", value: "常用名称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(Theme.primary)
                }
            }
        }
    }
}

private extension View {
    func settingsLabelStyle() -> some View {
        font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct InlineCommonNameTextField: View {
    let placeholder: String
    @Binding var text: String
    var onChevronTap: () -> Void
    var font: Font = .system(size: 16)
    var textColor: Color = Theme.textPrimary
    var iconColor: Color = Theme.textSecondary
    var backgroundColor: Color = Theme.homeCardDark
    var height: CGFloat = 44
    var cornerRadius: CGFloat = Theme.sm

    var body: some View {
        HStack(spacing: Theme.xs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundColor(textColor)

            Button(action: onChevronTap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Theme.sm)
        .padding(.trailing, Theme.xs)
        .frame(height: height)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
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

    private enum NameInputTarget: String, Identifiable {
        case team1
        case team2
        case team1Player1
        case team1Player2
        case team2Player1
        case team2Player2

        var id: String { rawValue }
    }

    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var activeNameInputTarget: NameInputTarget? = nil
    @State private var selectedMaxSets: Int = 0
    @State private var selectedPointsPerSet: Int = 0
    @State private var regularTieBreakPoints: Int = 7
    @State private var matchTieBreakPoints: Int = 7
    @State private var tennisGamesPerSet: Int = 6
    @State private var tennisSetScoringMode: String = "regular"
    @State private var matchCompletionMode: MatchCompletionMode = .bestOf
    @State private var customMaxSetsText: String = ""
    @State private var customPointsText: String = ""
    @State private var completionModeExpanded = false
    @State private var autoChangeSides: Bool = true // 默认开启自动换边
    @State private var isSingles: Bool = true // 乒乓球/羽毛球/网球：单打/双打；足球机默认 2V2
    @State private var basketballRuleSet: String = "fiba"
    @State private var snookerShowMoreFrames = false
    @State private var customFoosballScoreCapText = ""
    @State private var customEightBallHandicapText = ""
    @State private var tennisDeuceMode: String = "advantage"
    @State private var servingSide: MatchSide = .left
    @State private var voiceAnnouncement = false
    @State private var pickleballTargetScore = 11
    @State private var pickleballScoreCap: Int? = nil
    @State private var pickleballUseRallyScoring = false
    @State private var foosballWinByTwo = false
    @State private var foosballScoreCap: Int? = nil
    @State private var eightBallHandicapMode = "none"
    @State private var eightBallHandicapRacks = 0
    @State private var isSendingSetupToWatch = false
    @State private var setupSendErrorText = ""
    @State private var team1Player1Name: String = ""
    @State private var team1Player2Name: String = ""
    @State private var team2Player1Name: String = ""
    @State private var team2Player2Name: String = ""

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
                    if shouldShowSinglesDoublesAtTop() {
                        buildSinglesDoublesSection()
                    }

                    if shouldUseDoublesPlayerInputs() {
                        buildDoublesNameInputs()
                    } else {
                        buildPrimaryNameInput()
                    }

                    if shouldShowServingSideSelector() {
                        buildServingSideSection()
                    }

                    buildSettingsSection()
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
        .onChange(of: isSingles) { _, newValue in
            guard shouldShowSinglesDoublesAtTop() else { return }
            if newValue {
                let firstLeft = team1Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstRight = team2Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstLeft.isEmpty { team1Name = firstLeft }
                if !firstRight.isEmpty { team2Name = firstRight }
            } else {
                applyDefaultsWhenSwitchingToDoubles()
            }
        }
        .onChange(of: matchCompletionMode) { _, newMode in
            if newMode == .bestOf, selectedMaxSets.isMultiple(of: 2) {
                selectedMaxSets = min(99, selectedMaxSets + 1)
            }
            customMaxSetsText = frameCountPresets.contains(selectedMaxSets) ? "" : (
                selectedMaxSets > 0 ? String(selectedMaxSets) : ""
            )
            syncPickleballTargetForSets()
        }
        .onChange(of: selectedMaxSets) { _, _ in
            syncPickleballTargetForSets()
            if gameType == .eightBall, selectedMaxSets <= 1 {
                eightBallHandicapMode = "none"
                eightBallHandicapRacks = 0
                customEightBallHandicapText = ""
            }
        }
        .sheet(item: $activeNameInputTarget) { target in
            CommonNameSelectorDialog(nameType: nameType(for: target)) { name in
                applySelectedName(name, to: target)
                activeNameInputTarget = nil
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
                Button(action: cancelDialog) {
                    Text(NSLocalizedString("cancel", comment: "Cancel button"))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 100, height: 44)
                        .background(Theme.controlBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSendingSetupToWatch)

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

    private func cancelDialog() {
        onCancel?()
    }

    private func initializeView() {
        let setup = initialSetup
        team1Name = setup?.team1Name ?? defaultTeam1Name
        team2Name = setup?.team2Name ?? defaultTeam2Name
        syncDoublesPlayerNamesFromTeamNames()

        selectedMaxSets = setup?.maxSets ?? initialMaxSets ?? getDefaultMaxSets() ?? 0
        customMaxSetsText = frameCountPresets.contains(selectedMaxSets) ? "" : (
            selectedMaxSets > 0 ? String(selectedMaxSets) : ""
        )
        selectedPointsPerSet = setup?.pointsPerSet ?? initialPointsPerSet ?? getDefaultPointsPerSet() ?? 0
        customPointsText = pointPresets.contains(selectedPointsPerSet) ? "" : String(selectedPointsPerSet)
        tennisGamesPerSet = setup?.gamesPerSet == 4 ? 4 : 6
        tennisSetScoringMode = setup?.setScoringMode == "tiebreak_only" ? "tiebreak_only" : "regular"
        let restoredTieBreakPoints = setup?.tieBreakPoints ?? initialTieBreakPoints ?? getDefaultTieBreakPoints() ?? 7
        if tennisSetScoringMode == "tiebreak_only" {
            matchTieBreakPoints = restoredTieBreakPoints == 10 ? 10 : 7
            regularTieBreakPoints = 7
        } else {
            regularTieBreakPoints = restoredTieBreakPoints == 10 ? 10 : 7
            matchTieBreakPoints = 7
        }
        matchCompletionMode = setup?.matchCompletionMode ?? .bestOf
        autoChangeSides = setup?.autoChangeSides ?? true
        basketballRuleSet = setup?.basketballRuleSet ?? "fiba"
        tennisDeuceMode = setup?.tennisDeuceMode ?? "advantage"
        servingSide = setup?.servingSide == "right" ? .right : .left
        voiceAnnouncement = setup?.voiceAnnouncement ?? false
        pickleballTargetScore = setup?.targetScore ?? 11
        pickleballScoreCap = setup?.scoreCap
        pickleballUseRallyScoring = setup?.useRallyScoring ?? false
        foosballWinByTwo = setup?.winByTwo ?? false
        foosballScoreCap = setup?.scoreCap
        customFoosballScoreCapText = ""
        eightBallHandicapMode = setup?.eightBallHandicapBeneficiary ?? "none"
        eightBallHandicapRacks = setup?.eightBallHandicapRacks ?? 0
        customEightBallHandicapText = ""
        snookerShowMoreFrames = false
        isSingles = setup?.isSingles ?? (gameType != .foosball)
        team1Player1Name = setup?.team1Player1Name ?? team1Player1Name
        team1Player2Name = setup?.team1Player2Name ?? team1Player2Name
        team2Player1Name = setup?.team2Player1Name ?? team2Player1Name
        team2Player2Name = setup?.team2Player2Name ?? team2Player2Name
        if gameType == .foosball && !isSingles {
            applyDefaultsWhenSwitchingToDoubles()
        }
        setupSendErrorText = ""
        syncPickleballTargetForSets()
    }

    private func syncPickleballTargetForSets() {
        guard gameType == .pickleball else { return }
        let next = selectedMaxSets == 1 ? 15 : 11
        pickleballTargetScore = next
        if next != 11 {
            pickleballScoreCap = nil
        }
    }

    private func getDefaultMaxSets() -> Int? {
        switch gameType {
        case .pingpong: return 5
        case .badminton, .pickleball, .boxing, .foosball: return 3
        case .tennis: return 3
        case .snooker: return 1
        case .eightBall: return 9
        default: return nil
        }
    }

    private func getDefaultPointsPerSet() -> Int? {
        switch gameType {
        case .pingpong: return 11
        case .badminton: return 21
        case .foosball: return 5
        default: return nil
        }
    }

    private func getDefaultTieBreakPoints() -> Int? {
        return gameType == .tennis ? 7 : nil
    }

    private func getTeamNameLabel(isTeam1 _: Bool) -> String {
        if shouldShowSinglesDoublesAtTop() {
            return isSingles
                ? NSLocalizedString("setup_player_name", value: "选手名称", comment: "Player name in setup")
                : NSLocalizedString("setup_team_name", value: "队伍名称", comment: "Team name in setup")
        }
        if isConfirmedPlayerSetupGame() {
            return NSLocalizedString("setup_player_name", value: "选手名称", comment: "Player name in setup")
        }
        if isConfirmedTeamSetupGame() {
            return NSLocalizedString("setup_team_name", value: "队伍名称", comment: "Team name in setup")
        }
        return NSLocalizedString("team_or_player_name", comment: "")
    }

    private func isConfirmedPlayerSetupGame() -> Bool {
        return gameType == .boxing || gameType == .archery
    }

    private func isConfirmedTeamSetupGame() -> Bool {
        return gameType == .football || gameType == .volleyball || gameType == .beachVolleyball ||
            gameType == .airVolleyball || gameType == .basketball || gameType == .threeBasketball
    }

    private func getTitle() -> String {
        switch gameType {
        case .football: return NSLocalizedString("football_setup_title", comment: "")
        case .basketball: return NSLocalizedString("basketball_setup_title", comment: "")
        case .volleyball: return NSLocalizedString("volleyball_setup_title", comment: "")
        case .pingpong: return NSLocalizedString("pingpong_setup_title", comment: "")
        case .badminton: return NSLocalizedString("badminton_setup_title", comment: "")
        case .tennis: return NSLocalizedString("tennis_setup_title", comment: "")
        default: return gameType.displayName + NSLocalizedString("setup_suffix", value: " 设置", comment: "")
        }
    }

    private func getProjectTitle() -> String {
        gameType.displayName
    }

    private func getEmoji() -> String {
        return gameType.icon // Using GameType.icon which is defined
    }

    private func getChipBackgroundColor(selected: Bool) -> Color {
        return selected ? Theme.primary : Theme.homeCardDark // Using homeCardDark as rgba(255,255,255,0.12)
    }

    private func getChipTextColor(selected: Bool) -> Color {
        return selected ? .white : Theme.textPrimary // Using Theme.textPrimary for dialog text color
    }
    
    private func shouldShowSettings() -> Bool {
        return gameType == .basketball ||
               gameType == .boxing ||
               gameType == .pingpong ||
               gameType == .tennis ||
               gameType == .badminton ||
               gameType == .volleyball ||
               gameType == .beachVolleyball ||
               gameType == .airVolleyball ||
               gameType == .pickleball ||
               gameType == .foosball ||
               gameType == .eightBall ||
               gameType == .snooker
    }

    private func shouldShowSinglesDoublesAtTop() -> Bool {
        return gameType == .pingpong || gameType == .badminton || gameType == .tennis || gameType == .pickleball || gameType == .foosball
    }

    private func shouldUseDoublesPlayerInputs() -> Bool {
        shouldShowSinglesDoublesAtTop() && !isSingles
    }

    private func shouldShowServingSideSelector() -> Bool {
        gameType == .pingpong ||
        gameType == .badminton ||
        gameType == .tennis ||
        gameType == .pickleball ||
        gameType == .volleyball ||
        gameType == .beachVolleyball ||
        gameType == .airVolleyball ||
        gameType == .snooker ||
        gameType == .archery
    }

    private var supportsWatchProject: Bool {
        AppFeatureFlags.isWatchLinkSupportedProject(gameType)
    }

    private var canStartOnWatch: Bool {
        AppFeatureFlags.watchLinkEntryEnabled
            && supportsWatchProject
            && watchLinkService.canStartInteractiveSession
    }

    @ViewBuilder
    private func buildServingSideSection() -> some View {
        HStack {
            servingSideButton(.left)
            Text(gameType == .snooker
                 ? NSLocalizedString("setup_opening_break_side", value: "首局开球方", comment: "First-frame breaker")
                 : (gameType == .archery
                    ? NSLocalizedString("setup_first_shooter", value: "首发选手", comment: "First archer")
                    : NSLocalizedString("setup_serving_side", value: "发球方", comment: "Opening serving side")))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
            servingSideButton(.right)
        }
        .padding(.vertical, 4)
    }

    private func servingSideButton(_ side: MatchSide) -> some View {
        let isSelected = side == servingSide

        return Button {
            servingSide = side
        } label: {
            Group {
                if gameType == .archery {
                    Image(systemName: "scope")
                        .font(.system(size: 22, weight: .medium))
                } else {
                    Image(servingIconAssetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            }
                .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary.opacity(0.72))
                .frame(width: 26, height: 26)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .left
            ? NSLocalizedString("setup_serving_left", value: "左侧发球", comment: "")
            : NSLocalizedString("setup_serving_right", value: "右侧发球", comment: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var servingIconAssetName: String {
        switch gameType {
        case .pingpong:
            return "ic_pingpong_serve"
        case .badminton:
            return "ic_badminton_serve"
        case .tennis, .pickleball:
            return "ic_tennis_serve"
        case .volleyball, .beachVolleyball, .airVolleyball:
            return "ic_volleyball_serve"
        case .snooker:
            return "ic_snooker_cue"
        default:
            return "ic_pingpong_serve"
        }
    }

    /// 名称区域：左右对半、中间 vs 隔开，无队伍/队员标题（对齐鸿蒙）
    @ViewBuilder
    private func buildPrimaryNameInput() -> some View {
        HStack(spacing: Theme.sm) {
            InlineCommonNameTextField(
                placeholder: defaultTeam1Name,
                text: $team1Name,
                onChevronTap: { activeNameInputTarget = .team1 }
            )
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            InlineCommonNameTextField(
                placeholder: defaultTeam2Name,
                text: $team2Name,
                onChevronTap: { activeNameInputTarget = .team2 }
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func buildDoublesNameInputs() -> some View {
        HStack(spacing: Theme.sm) {
            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("doubles_red_a", value: "红A", comment: ""),
                    text: $team1Player1Name,
                    onChevronTap: { activeNameInputTarget = .team1Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("doubles_red_b", value: "红B", comment: ""),
                    text: $team1Player2Name,
                    onChevronTap: { activeNameInputTarget = .team1Player2 }
                )
            }
            .frame(maxWidth: .infinity)

            Text(NSLocalizedString("vs_separator", value: " vs ", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            VStack(spacing: Theme.sm) {
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("doubles_blue_a", value: "蓝A", comment: ""),
                    text: $team2Player1Name,
                    onChevronTap: { activeNameInputTarget = .team2Player1 }
                )
                InlineCommonNameTextField(
                    placeholder: NSLocalizedString("doubles_blue_b", value: "蓝B", comment: ""),
                    text: $team2Player2Name,
                    onChevronTap: { activeNameInputTarget = .team2Player2 }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func buildSinglesDoublesSection() -> some View {
        Picker("", selection: $isSingles) {
            Text(singlesModeLabel)
                .tag(true)
                .accessibilityIdentifier("singles_option")
            Text(doublesModeLabel)
                .tag(false)
                .accessibilityIdentifier("doubles_option")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("singles_doubles_picker")
        .accessibilityValue(isSingles ? singlesModeLabel : doublesModeLabel)
    }

    private var singlesModeLabel: String {
        gameType == .foosball
            ? NSLocalizedString("foosball_mode_1v1", value: "1V1", comment: "")
            : NSLocalizedString("singles", value: "单打", comment: "")
    }

    private var doublesModeLabel: String {
        gameType == .foosball
            ? NSLocalizedString("foosball_mode_2v2", value: "2V2", comment: "")
            : NSLocalizedString("doubles", value: "双打", comment: "")
    }

    @ViewBuilder
    private func buildSettingsSection() -> some View {
        if shouldShowSettings() {
            VStack(alignment: .leading, spacing: 16) {
                if gameType == .basketball {
                    buildBasketballSettings()
                } else if gameType == .boxing {
                    buildBoxingSettings()
                } else if gameType == .pingpong {
                    buildMatchCompletionSection(useTennisWording: false)
                    buildPointsPerSetSection()
                    settingsToggle("pingpong_auto_change_sides", fallback: "自动换边", value: $autoChangeSides)
                    settingsToggle("voice_announcement", fallback: "语音播报", value: $voiceAnnouncement)
                } else if gameType == .tennis {
                    buildTennisSettings()
                } else if gameType == .badminton {
                    buildMatchCompletionSection(useTennisWording: false)
                    buildPointsPerSetSection()
                    settingsToggle("badminton_auto_change_sides", fallback: "自动换边", value: $autoChangeSides)
                    settingsToggle("voice_announcement", fallback: "语音播报", value: $voiceAnnouncement)
                } else if gameType == .pickleball {
                    buildPickleballSettings()
                } else if gameType == .volleyball || gameType == .beachVolleyball || gameType == .airVolleyball {
                    settingsToggle("volleyball_auto_change_sides", fallback: "自动换边", value: $autoChangeSides)
                } else if gameType == .foosball {
                    buildFoosballSettings()
                } else if gameType == .snooker {
                    buildSnookerSettings()
                } else if gameType == .eightBall {
                    buildEightBallSettings()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func buildBasketballSettings() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("basketball_rule_set_label", value: "规则", comment: "Basketball rules"))
                .settingsLabelStyle()
            chipRow(options: ["fiba", "nba"], selection: $basketballRuleSet) { value in
                value.uppercased()
            }
            Text(basketballRuleSet == "nba"
                 ? NSLocalizedString("basketball_rule_nba_summary", value: "NBA：每节 12 分钟，常规赛 7 次暂停。", comment: "")
                 : NSLocalizedString("basketball_rule_fiba_summary", value: "FIBA：每节 10 分钟，上下半场分别计算暂停。", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func buildBoxingSettings() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("boxing_rounds", value: "回合数", comment: "Boxing rounds"))
                .settingsLabelStyle()
            HStack(spacing: 8) {
                ForEach([3, 8, 10, 12], id: \.self) { rounds in
                    numberChip(rounds, selection: $selectedMaxSets) {
                        customMaxSetsText = ""
                    }
                }
                customNumberChip(selection: $selectedMaxSets, text: $customMaxSetsText, maxValue: 99)
            }
        }
    }

    @ViewBuilder
    private func buildTennisSettings() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("tennis_format_label", value: "赛制", comment: "Tennis format"))
                .settingsLabelStyle()
            HStack(spacing: 6) {
                ForEach(["regular", "tiebreak_7", "tiebreak_10"], id: \.self) { format in
                    let selected = format == "regular"
                        ? tennisSetScoringMode == "regular"
                        : tennisSetScoringMode == "tiebreak_only" && matchTieBreakPoints == (format == "tiebreak_10" ? 10 : 7)
                    Button {
                        if format == "regular" {
                            tennisSetScoringMode = "regular"
                        } else {
                            tennisSetScoringMode = "tiebreak_only"
                            matchTieBreakPoints = format == "tiebreak_10" ? 10 : 7
                        }
                    } label: {
                        Text(tennisFormatOptionText(format))
                            .font(.system(size: 13, weight: selected ? .medium : .regular))
                            .foregroundStyle(getChipTextColor(selected: selected))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(getChipBackgroundColor(selected: selected))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if tennisSetScoringMode == "regular" {
            buildMatchCompletionSection(useTennisWording: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tennis_games_per_set_label", value: "每盘局数", comment: "Games per tennis set"))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    ForEach([4, 6], id: \.self) { games in
                        Button {
                            tennisGamesPerSet = games
                        } label: {
                            Text(NSLocalizedString(games == 4 ? "tennis_games_per_set_4" : "tennis_games_per_set_6", value: games == 4 ? "四局制" : "六局制", comment: ""))
                                .font(.system(size: 14, weight: tennisGamesPerSet == games ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: tennisGamesPerSet == games))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(getChipBackgroundColor(selected: tennisGamesPerSet == games))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if tennisGamesPerSet == 4 {
                    Text(NSLocalizedString("tennis_short_set_help", value: "先到 4 局且领先 2 局，4-4 进入抢七", comment: "Short tennis set explanation"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tennis_set_tiebreak_label", value: "盘内抢分", comment: "In-set tiebreak"))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    ForEach([7, 10], id: \.self) { points in
                        Button {
                            regularTieBreakPoints = points
                        } label: {
                            Text(tennisTiebreakOptionText(points))
                                .font(.system(size: 14, weight: regularTieBreakPoints == points ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: regularTieBreakPoints == points))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(getChipBackgroundColor(selected: regularTieBreakPoints == points))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("tennis_deuce_mode", value: "40:40 规则", comment: "Tennis deuce mode"))
                    .settingsLabelStyle()
                chipRow(options: ["advantage", "no_ad"], selection: $tennisDeuceMode) { value in
                    value == "no_ad"
                        ? NSLocalizedString("tennis_deuce_option_no_ad", value: "金球", comment: "")
                        : NSLocalizedString("tennis_deuce_option_advantage", value: "占先", comment: "")
                }
            }
        }
        settingsToggle("tennis_auto_change_sides", fallback: "自动换边", value: $autoChangeSides)
        settingsToggle("voice_announcement", fallback: "语音播报", value: $voiceAnnouncement)
    }

    @ViewBuilder
    private func buildPointsPerSetSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("points_per_set", value: "每局分数", comment: "Points per set"))
                .settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(pointPresets, id: \.self) { points in
                    numberChip(points, selection: $selectedPointsPerSet) {
                        customPointsText = ""
                    }
                }
                customNumberChip(selection: $selectedPointsPerSet, text: $customPointsText, maxValue: 999)
            }
        }
    }

    @ViewBuilder
    private func buildPickleballSettings() -> some View {
        buildMatchCompletionSection(useTennisWording: false)
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("pickleball_target_score", value: "目标分", comment: ""))
                .settingsLabelStyle()
            HStack(spacing: 8) {
                ForEach([11, 15, 21], id: \.self) { points in
                    numberChip(points, selection: $pickleballTargetScore) {
                        if points != 11 { pickleballScoreCap = nil }
                    }
                }
            }
        }
        if pickleballTargetScore == 11 {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("pickleball_score_cap", value: "最高分上限", comment: ""))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    optionalNumberChip(nil, label: NSLocalizedString("pickleball_no_cap", value: "无", comment: ""), selection: $pickleballScoreCap)
                    optionalNumberChip(13, label: "13", selection: $pickleballScoreCap)
                    optionalNumberChip(15, label: "15", selection: $pickleballScoreCap)
                }
            }
        }
        settingsToggle("pickleball_rally_scoring", fallback: "每球得分", value: $pickleballUseRallyScoring)
        settingsToggle("pickleball_auto_change_sides", fallback: "自动换边", value: $autoChangeSides)
    }

    @ViewBuilder
    private func buildFoosballSettings() -> some View {
        buildMatchCompletionSection(useTennisWording: false)
        buildPointsPerSetSection()
        settingsToggle("foosball_final_win_by_two", fallback: "决胜局净胜 2 分", value: $foosballWinByTwo)
        if foosballWinByTwo {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("foosball_final_score_cap", value: "决胜局最高分上限", comment: ""))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    Button {
                        foosballScoreCap = nil
                        customFoosballScoreCapText = ""
                    } label: {
                        Text(NSLocalizedString("pickleball_no_cap", value: "无", comment: ""))
                            .font(.system(size: 14, weight: foosballScoreCap == nil && customFoosballScoreCapText.isEmpty ? .medium : .regular))
                            .foregroundStyle(getChipTextColor(selected: foosballScoreCap == nil && customFoosballScoreCapText.isEmpty))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(getChipBackgroundColor(selected: foosballScoreCap == nil && customFoosballScoreCapText.isEmpty))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    ForEach([8, 10], id: \.self) { value in
                        Button {
                            foosballScoreCap = value
                            customFoosballScoreCapText = ""
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 14, weight: foosballScoreCap == value && customFoosballScoreCapText.isEmpty ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: foosballScoreCap == value && customFoosballScoreCapText.isEmpty))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(getChipBackgroundColor(selected: foosballScoreCap == value && customFoosballScoreCapText.isEmpty))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    customOptionalNumberChip(
                        selection: $foosballScoreCap,
                        text: $customFoosballScoreCapText,
                        maxValue: 99
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func buildEightBallSettings() -> some View {
        buildSetCountSettings(
            title: NSLocalizedString("eight_ball_frames", value: "局数", comment: ""),
            presets: [1, 3, 5, 7, 9, 11]
        )
        if selectedMaxSets > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("eight_ball_handicap", value: "让局", comment: ""))
                    .settingsLabelStyle()
                chipRow(options: ["none", "team2", "team1"], selection: $eightBallHandicapMode) { value in
                    switch value {
                    case "team2":
                        return NSLocalizedString("eight_ball_left_lets_right", value: "左让右", comment: "")
                    case "team1":
                        return NSLocalizedString("eight_ball_right_lets_left", value: "右让左", comment: "")
                    default:
                        return NSLocalizedString("pickleball_no_cap", value: "无", comment: "")
                    }
                }
                if eightBallHandicapMode != "none" {
                    HStack(spacing: 8) {
                        ForEach([1, 2, 3], id: \.self) { racks in
                            numberChip(racks, selection: $eightBallHandicapRacks) {
                                customEightBallHandicapText = ""
                            }
                        }
                        customNumberChip(
                            selection: $eightBallHandicapRacks,
                            text: $customEightBallHandicapText,
                            maxValue: max(1, selectedMaxSets - 1)
                        )
                    }
                    .onAppear {
                        if eightBallHandicapRacks < 1 {
                            eightBallHandicapRacks = 1
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buildSnookerSettings() -> some View {
        let primaryPresets = [1, 3, 5, 7]
        let morePresets = [9, 11, 15, 17, 19, 25, 33, 35]
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("snooker_frames", value: "局数", comment: "")).settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(primaryPresets, id: \.self) { count in
                    numberChip(count, selection: $selectedMaxSets) {
                        customMaxSetsText = ""
                        snookerShowMoreFrames = false
                    }
                }
                Button {
                    snookerShowMoreFrames.toggle()
                } label: {
                    Text(NSLocalizedString("snooker_frames_more", value: "更多", comment: ""))
                        .font(.system(size: 14, weight: snookerShowMoreFrames ? .medium : .regular))
                        .foregroundStyle(getChipTextColor(selected: snookerShowMoreFrames))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(getChipBackgroundColor(selected: snookerShowMoreFrames))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                if snookerShowMoreFrames || morePresets.contains(selectedMaxSets) {
                    ForEach(morePresets, id: \.self) { count in
                        numberChip(count, selection: $selectedMaxSets) {
                            customMaxSetsText = ""
                            snookerShowMoreFrames = true
                        }
                    }
                }
                customNumberChip(selection: $selectedMaxSets, text: $customMaxSetsText, maxValue: 99)
            }
        }
    }

    @ViewBuilder
    private func buildSetCountSettings(title: String, presets: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presets, id: \.self) { count in
                    numberChip(count, selection: $selectedMaxSets) { customMaxSetsText = "" }
                }
                customNumberChip(selection: $selectedMaxSets, text: $customMaxSetsText, maxValue: 99)
            }
        }
    }

    private var pointPresets: [Int] {
        if gameType == .pingpong { return [5, 7, 9, 11, 15, 21] }
        if gameType == .foosball { return [5, 7, 8] }
        return [21, 15, 11]
    }

    private var hasValidPointsPerSet: Bool {
        guard gameType == .pingpong || gameType == .badminton || gameType == .foosball else { return true }
        let maximum = gameType == .foosball ? 99 : 999
        return (1...maximum).contains(selectedPointsPerSet)
    }

    private func chipRow(
        options: [String],
        selection: Binding<String>,
        label: @escaping (String) -> String
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 14, weight: selection.wrappedValue == option ? .medium : .regular))
                        .foregroundStyle(getChipTextColor(selected: selection.wrappedValue == option))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(getChipBackgroundColor(selected: selection.wrappedValue == option))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func numberChip(
        _ value: Int,
        selection: Binding<Int>,
        onSelect: @escaping () -> Void = {}
    ) -> some View {
        Button {
            selection.wrappedValue = value
            onSelect()
        } label: {
            Text("\(value)")
                .font(.system(size: 14, weight: selection.wrappedValue == value ? .medium : .regular))
                .foregroundStyle(getChipTextColor(selected: selection.wrappedValue == value))
                .frame(maxWidth: .infinity)
                .frame(minWidth: 38, minHeight: 36)
                .background(getChipBackgroundColor(selected: selection.wrappedValue == value))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customNumberChip(
        selection: Binding<Int>,
        text: Binding<String>,
        maxValue: Int
    ) -> some View {
        if !text.wrappedValue.isEmpty {
            TextField(NSLocalizedString("custom", value: "自定义", comment: ""), text: Binding(
                get: { text.wrappedValue },
                set: { rawValue in
                    let limit = String(maxValue).count
                    let sanitized = String(rawValue.filter(\.isNumber).prefix(limit))
                    text.wrappedValue = sanitized
                    selection.wrappedValue = min(maxValue, Int(sanitized) ?? 0)
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .frame(minWidth: 58, minHeight: 36)
            .background(Theme.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Button {
                text.wrappedValue = selection.wrappedValue > 0 ? String(selection.wrappedValue) : "1"
            } label: {
                Text(NSLocalizedString("custom", value: "自定义", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 58, minHeight: 36)
                    .background(Theme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func optionalNumberChip(
        _ value: Int?,
        label: String,
        selection: Binding<Int?>
    ) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            Text(label)
                .font(.system(size: 14, weight: selection.wrappedValue == value ? .medium : .regular))
                .foregroundStyle(getChipTextColor(selected: selection.wrappedValue == value))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(getChipBackgroundColor(selected: selection.wrappedValue == value))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customOptionalNumberChip(
        selection: Binding<Int?>,
        text: Binding<String>,
        maxValue: Int
    ) -> some View {
        let isCustomActive = !text.wrappedValue.isEmpty
            || (selection.wrappedValue != nil && selection.wrappedValue != 8 && selection.wrappedValue != 10)
        if isCustomActive {
            TextField(NSLocalizedString("custom", value: "自定义", comment: ""), text: Binding(
                get: { text.wrappedValue },
                set: { rawValue in
                    let limit = String(maxValue).count
                    let sanitized = String(rawValue.filter(\.isNumber).prefix(limit))
                    text.wrappedValue = sanitized
                    if let value = Int(sanitized), value >= 1 {
                        selection.wrappedValue = min(maxValue, value)
                    } else {
                        selection.wrappedValue = nil
                    }
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .frame(minWidth: 58, minHeight: 36)
            .background(Theme.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Button {
                let seed = selection.wrappedValue ?? 12
                text.wrappedValue = String(seed)
                selection.wrappedValue = seed
            } label: {
                Text(NSLocalizedString("custom", value: "自定义", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 58, minHeight: 36)
                    .background(Theme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsToggle(_ key: String, fallback: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(NSLocalizedString(key, value: fallback, comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.primary)
    }

    private var matchCompletionPresets: [Int] {
        matchCompletionMode == .playAll ? [1, 2, 3, 4, 5] : [1, 3, 5, 7]
    }

    /// Presets used by the currently visible “局数/盘数” chips (not only classic best-of).
    private var frameCountPresets: [Int] {
        switch gameType {
        case .eightBall:
            return [1, 3, 5, 7, 9, 11]
        case .snooker:
            return [1, 3, 5, 7, 9, 11, 15, 17, 19, 25, 33, 35]
        case .billiards:
            return [1, 3, 5, 7, 9, 11]
        default:
            return matchCompletionPresets
        }
    }

    private var hasValidMatchCompletionSets: Bool {
        guard selectedMaxSets >= 1, selectedMaxSets <= 99 else { return false }
        return matchCompletionMode == .playAll || !selectedMaxSets.isMultiple(of: 2)
    }

    @ViewBuilder
    private func buildMatchCompletionSection(useTennisWording: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Button(action: { completionModeExpanded.toggle() }) {
                HStack(spacing: Theme.xs) {
                    Text(useTennisWording
                         ? NSLocalizedString("match_completion_sets_tennis", value: "盘数", comment: "")
                         : NSLocalizedString("match_completion_sets", value: "局数", comment: ""))
                    Text("·")
                    Text(matchCompletionModeTitle(matchCompletionMode))
                    Image(systemName: completionModeExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("match_completion_mode_selector")
            .popover(isPresented: $completionModeExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                VStack(spacing: Theme.sm) {
                    ForEach(MatchCompletionMode.allCases, id: \.self) { mode in
                        Button(action: {
                            matchCompletionMode = mode
                            completionModeExpanded = false
                        }) {
                            VStack(spacing: 4) {
                                Text(matchCompletionModeTitle(mode))
                                    .font(.system(size: 16, weight: mode == matchCompletionMode ? .medium : .regular))
                                    .foregroundStyle(mode == matchCompletionMode ? Color.white : Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                Text(matchCompletionModeDescription(mode, useTennisWording: useTennisWording))
                                    .font(.system(size: 12))
                                    .foregroundStyle(mode == matchCompletionMode ? Color.white.opacity(0.88) : Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .padding(.horizontal, 14)
                            .background(mode == matchCompletionMode ? Theme.primary : Theme.controlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: useTennisWording ? 260 : 244)
                .presentationCompactAdaptation(.popover)
            }

            HStack(spacing: Theme.sm) {
                ForEach(matchCompletionPresets, id: \.self) { sets in
                    Button(action: {
                        selectedMaxSets = sets
                        customMaxSetsText = ""
                    }) {
                        Text("\(sets)")
                            .font(.system(size: 14, weight: selectedMaxSets == sets ? .medium : .regular))
                            .foregroundColor(getChipTextColor(selected: selectedMaxSets == sets))
                            .frame(maxWidth: .infinity)
                            .frame(minWidth: 38, minHeight: 36)
                            .background(getChipBackgroundColor(selected: selectedMaxSets == sets))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    if matchCompletionPresets.contains(selectedMaxSets) {
                        selectedMaxSets = 0
                        customMaxSetsText = ""
                    }
                }) {
                    Text(NSLocalizedString("custom", value: "自定义", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(getChipTextColor(selected: !matchCompletionPresets.contains(selectedMaxSets)))
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: 58, minHeight: 36)
                        .background(getChipBackgroundColor(selected: !matchCompletionPresets.contains(selectedMaxSets)))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom_match_sets_button")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if !matchCompletionPresets.contains(selectedMaxSets) {
                TextField(NSLocalizedString("match_completion_custom_placeholder", value: "输入 1-99", comment: ""), text: Binding(
                    get: { customMaxSetsText },
                    set: { rawValue in
                        let sanitized = String(rawValue.filter(\.isNumber).prefix(2))
                        customMaxSetsText = sanitized
                        selectedMaxSets = Int(sanitized) ?? 0
                    }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("custom_max_sets_field")
            }

            if !hasValidMatchCompletionSets {
                Text(NSLocalizedString(
                    "match_completion_invalid_sets",
                    value: "经典模式请输入 1-99 的奇数；打满模式请输入 1-99。",
                    comment: ""
                ))
                .font(.system(size: 12))
                .foregroundColor(.red)
            }
        }
    }

    private func matchCompletionModeTitle(_ mode: MatchCompletionMode) -> String {
        mode == .playAll
            ? NSLocalizedString("match_completion_play_all", value: "打满", comment: "")
            : NSLocalizedString("match_completion_classic", value: "经典", comment: "")
    }

    private func matchCompletionModeDescription(_ mode: MatchCompletionMode, useTennisWording: Bool) -> String {
        switch (mode, useTennisWording) {
        case (.bestOf, false):
            return NSLocalizedString("match_completion_classic_description", value: "如五局三胜，提前决出胜负", comment: "")
        case (.playAll, false):
            return NSLocalizedString("match_completion_play_all_description", value: "如五局全部打完，可能出现平局", comment: "")
        case (.bestOf, true):
            return NSLocalizedString("match_completion_classic_tennis_description", value: "如五盘三胜，提前决出胜负", comment: "")
        case (.playAll, true):
            return NSLocalizedString("match_completion_play_all_tennis_description", value: "如五盘全部打完，可能出现平局", comment: "")
        }
    }

    /// 切换到双打时：若两侧名称均不含 "/"，则自动填入默认双打名；否则按 "/" 拆分同步。
    private func applyDefaultsWhenSwitchingToDoubles() {
        let t1 = team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = team2Name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t1.contains("/"), !t2.contains("/") {
            if gameType == .foosball {
                // 对齐鸿蒙/安卓：红方A/红方B、蓝方A/蓝方B
                let red = splitDoublesTeamName(
                    NSLocalizedString("foosball_default_red_doubles", value: "红方A/红方B", comment: "")
                )
                let blue = splitDoublesTeamName(
                    NSLocalizedString("foosball_default_blue_doubles", value: "蓝方A/蓝方B", comment: "")
                )
                team1Player1Name = red.first
                team1Player2Name = red.second
                team2Player1Name = blue.first
                team2Player2Name = blue.second
            } else {
                team1Player1Name = NSLocalizedString("doubles_red_a", value: "红A", comment: "")
                team1Player2Name = NSLocalizedString("doubles_red_b", value: "红B", comment: "")
                team2Player1Name = NSLocalizedString("doubles_blue_a", value: "蓝A", comment: "")
                team2Player2Name = NSLocalizedString("doubles_blue_b", value: "蓝B", comment: "")
            }
        } else {
            syncDoublesPlayerNamesFromTeamNames()
        }
    }

    private func syncDoublesPlayerNamesFromTeamNames() {
        let left = splitDoublesTeamName(team1Name)
        let right = splitDoublesTeamName(team2Name)
        team1Player1Name = left.first
        team1Player2Name = left.second
        team2Player1Name = right.first
        team2Player2Name = right.second
    }

    private func splitDoublesTeamName(_ value: String) -> (first: String, second: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        let parts = trimmed
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        return (trimmed, "")
    }

    private func buildDoublesTeamName(_ player1: String, _ player2: String) -> String {
        let first = player1.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = player2.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty && !second.isEmpty {
            // 桌上足球对齐鸿蒙/安卓：`A/B`（无空格）；其他双打仍用 `A / B`
            if gameType == .foosball {
                return "\(first)/\(second)"
            }
            return "\(first) / \(second)"
        }
        return first.isEmpty ? second : first
    }

    private func nameType(for target: NameInputTarget) -> NameType {
        switch target {
        case .team1, .team2:
            if shouldShowSinglesDoublesAtTop() || usesPlayerCommonNames {
                return .player
            }
            return .team
        case .team1Player1, .team1Player2, .team2Player1, .team2Player2:
            return .player
        }
    }

    private var usesPlayerCommonNames: Bool {
        switch gameType {
        case .archery, .boxing, .billiards, .eightBall, .snooker:
            true
        default:
            false
        }
    }

    private func applySelectedName(_ value: String, to target: NameInputTarget) {
        switch target {
        case .team1:
            team1Name = value
        case .team2:
            team2Name = value
        case .team1Player1:
            team1Player1Name = value
        case .team1Player2:
            team1Player2Name = value
        case .team2Player1:
            team2Player1Name = value
        case .team2Player2:
            team2Player2Name = value
        }
    }

    private func pingpongSetOptionText(_ sets: Int) -> String {
        switch sets {
        case 3:
            return NSLocalizedString("pingpong_set_option_best_of_3", comment: "")
        case 5:
            return NSLocalizedString("pingpong_set_option_best_of_5", comment: "")
        case 7:
            return NSLocalizedString("pingpong_set_option_best_of_7", comment: "")
        default:
            return "Best of \(sets)"
        }
    }

    private func tennisSetOptionText(_ sets: Int) -> String {
        switch sets {
        case 3:
            return NSLocalizedString("tennis_set_option_best_of_3", comment: "")
        case 5:
            return NSLocalizedString("tennis_set_option_best_of_5", comment: "")
        default:
            return "Best of \(sets)"
        }
    }

    private func tennisTiebreakOptionText(_ points: Int) -> String {
        switch points {
        case 7:
            return NSLocalizedString("tennis_tiebreak_option_7", value: "抢七", comment: "")
        case 10:
            return NSLocalizedString("tennis_tiebreak_option_10", value: "抢十", comment: "")
        default:
            return "\(points)"
        }
    }

    private func tennisFormatOptionText(_ format: String) -> String {
        switch format {
        case "tiebreak_7":
            return NSLocalizedString("tennis_scoring_mode_tiebreak_7", value: "一盘抢七", comment: "")
        case "tiebreak_10":
            return NSLocalizedString("tennis_scoring_mode_tiebreak_10", value: "一盘抢十", comment: "")
        default:
            return NSLocalizedString("tennis_scoring_mode_regular", value: "传统赛制", comment: "")
        }
    }
    
    private func confirmSetup(startOnWatch: Bool = false) async {
        if supportsMatchCompletionMode, !hasValidMatchCompletionSets {
            return
        }
        if !hasValidPointsPerSet {
            return
        }
        let resolvedTeam1Name = shouldUseDoublesPlayerInputs()
            ? buildDoublesTeamName(team1Player1Name, team1Player2Name)
            : team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTeam2Name = shouldUseDoublesPlayerInputs()
            ? buildDoublesTeamName(team2Player1Name, team2Player2Name)
            : team2Name.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = SportsSetupResult(
            team1Name: resolvedTeam1Name,
            team2Name: resolvedTeam2Name,
            team1Player1Name: shouldUseDoublesPlayerInputs() ? team1Player1Name.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            team1Player2Name: shouldUseDoublesPlayerInputs() ? team1Player2Name.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            team2Player1Name: shouldUseDoublesPlayerInputs() ? team2Player1Name.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            team2Player2Name: shouldUseDoublesPlayerInputs() ? team2Player2Name.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        )

        if config.team1Name == config.team2Name && !config.team1Name.isEmpty {
            setupSendErrorText = NSLocalizedString(
                "duplicate_names_warning",
                value: "双方名称不能相同",
                comment: "Duplicate names warning"
            )
            return
        }
        
        var finalConfig = config

        if gameType == .basketball {
            finalConfig.basketballMode = "five_v_five"
            finalConfig.basketballRuleSet = basketballRuleSet
        } else if gameType == .boxing {
            finalConfig.maxRounds = selectedMaxSets > 0 ? selectedMaxSets : 3
        } else if gameType == .pingpong {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 5
            finalConfig.matchCompletionMode = matchCompletionMode
            finalConfig.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 11
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
            finalConfig.servingSide = servingSide.rawValue
            finalConfig.voiceAnnouncement = voiceAnnouncement
        } else if gameType == .tennis {
            finalConfig.maxSets = tennisSetScoringMode == "tiebreak_only" ? 1 : (selectedMaxSets > 0 ? selectedMaxSets : 3)
            finalConfig.matchCompletionMode = tennisSetScoringMode == "tiebreak_only" ? .bestOf : matchCompletionMode
            finalConfig.tieBreakPoints = tennisSetScoringMode == "tiebreak_only" ? matchTieBreakPoints : regularTieBreakPoints
            finalConfig.gamesPerSet = tennisGamesPerSet
            finalConfig.setScoringMode = tennisSetScoringMode
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
            finalConfig.tennisDeuceMode = tennisDeuceMode
            finalConfig.servingSide = servingSide.rawValue
            finalConfig.voiceAnnouncement = voiceAnnouncement
        } else if gameType == .badminton {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            finalConfig.matchCompletionMode = matchCompletionMode
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.isSingles = isSingles
            finalConfig.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 21
            finalConfig.servingSide = servingSide.rawValue
            finalConfig.voiceAnnouncement = voiceAnnouncement
        } else if gameType == .pickleball {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            finalConfig.matchCompletionMode = matchCompletionMode
            finalConfig.isSingles = isSingles
            finalConfig.targetScore = pickleballTargetScore
            finalConfig.winByTwo = true
            finalConfig.scoreCap = pickleballTargetScore == 11 ? pickleballScoreCap : nil
            finalConfig.useRallyScoring = pickleballUseRallyScoring
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.servingSide = servingSide.rawValue
        } else if gameType == .foosball {
            finalConfig.isSingles = isSingles
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            finalConfig.matchCompletionMode = matchCompletionMode
            finalConfig.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 5
            finalConfig.targetScore = finalConfig.pointsPerSet
            finalConfig.winByTwo = foosballWinByTwo
            finalConfig.scoreCap = foosballWinByTwo ? foosballScoreCap : nil
        } else if gameType == .volleyball || gameType == .beachVolleyball || gameType == .airVolleyball {
            finalConfig.autoChangeSides = autoChangeSides
            finalConfig.servingSide = servingSide.rawValue
        } else if gameType == .snooker {
            finalConfig.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 1
            finalConfig.servingSide = servingSide.rawValue
        } else if gameType == .eightBall {
            let target = selectedMaxSets > 0 ? selectedMaxSets : 9
            finalConfig.maxSets = target
            let handicap = eightBallHandicapMode == "none" ? 0 : min(eightBallHandicapRacks, max(0, target - 1))
            finalConfig.eightBallHandicapRacks = handicap
            finalConfig.eightBallHandicapBeneficiary = handicap > 0 ? eightBallHandicapMode : "none"
        } else if gameType == .archery {
            finalConfig.servingSide = servingSide.rawValue
        }

        if startOnWatch {
            guard canStartOnWatch else {
                setupSendErrorText = PhoneWatchLinkService.InteractiveStartError.watchUnavailable.localizedDescription
                return
            }
            isSendingSetupToWatch = true
            setupSendErrorText = ""
            do {
                finalConfig.linkedWatchSessionId = try await startLinkedWatchSession(for: finalConfig)
                finalConfig.startOnWatch = true
            } catch {
                isSendingSetupToWatch = false
                setupSendErrorText = error.localizedDescription
                return
            }
            isSendingSetupToWatch = false
        }
        
        if shouldUseDoublesPlayerInputs() {
            let playerNames = [
                team1Player1Name,
                team1Player2Name,
                team2Player1Name,
                team2Player2Name,
            ]
            for name in playerNames {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    await commonNamesManager.recordUsage(trimmed, .player)
                }
            }
        } else if shouldShowSinglesDoublesAtTop() {
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.recordUsage(finalConfig.team1Name, .player)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.recordUsage(finalConfig.team2Name, .player)
            }
        } else {
            let nameKind: NameType = usesPlayerCommonNames ? .player : .team
            if !finalConfig.team1Name.isEmpty && finalConfig.team1Name != defaultTeam1Name {
                await commonNamesManager.recordUsage(finalConfig.team1Name, nameKind)
            }
            if !finalConfig.team2Name.isEmpty && finalConfig.team2Name != defaultTeam2Name {
                await commonNamesManager.recordUsage(finalConfig.team2Name, nameKind)
            }
        }

        onConfirm?(finalConfig)
    }

    private func startLinkedWatchSession(for config: SportsSetupResult) async throws -> UUID {
        if gameType == .basketball {
            let mode: BasketballGameMode = config.basketballMode == "three_x_three" ? .threeXThree : .fiveVFive
            let ruleSet: BasketballRuleSet = config.basketballRuleSet == "nba" ? .nba : .fiba
            let state = BasketballMatchEngine.initial(
                leftName: config.team1Name,
                rightName: config.team2Name,
                gameMode: mode,
                ruleSet: ruleSet
            )
            return try await watchLinkService.startInteractiveOnWatch(state: state)
        }

        let coreGameType: ScoreCore.GameType
        let rules: RallyRuleSet
        switch gameType {
        case .pingpong:
            coreGameType = config.isSingles == false ? .pingpongDoubles : .pingpong
            var configured = RallyRuleSet.pingPong(
                maxSets: config.maxSets ?? 5,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf
            )
            let target = max(1, config.pointsPerSet ?? 11)
            configured.pointsToWinSet = target
            configured.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: coreGameType,
                pointsPerSet: target
            )
            configured.autoChangeSides = config.autoChangeSides ?? true
            rules = configured
        case .badminton:
            coreGameType = config.isSingles == false ? .badmintonDoubles : .badminton
            var configured = RallyRuleSet.badminton(
                maxSets: config.maxSets ?? 3,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf
            )
            let target = max(1, config.pointsPerSet ?? 21)
            configured.pointsToWinSet = target
            configured.pointCap = RallyRuleSet.badmintonPointCap(for: target)
            configured.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: coreGameType,
                pointsPerSet: target
            )
            configured.autoChangeSides = config.autoChangeSides ?? true
            rules = configured
        case .pickleball:
            coreGameType = config.isSingles == false ? .pickleballDoubles : .pickleball
            var configured = RallyRuleSet.pickleball(
                maxSets: config.maxSets ?? 3,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf
            )
            configured.pointsToWinSet = max(1, config.targetScore ?? 11)
            configured.pointCap = config.scoreCap
            configured.winByTwo = config.winByTwo ?? true
            configured.autoChangeSides = config.autoChangeSides ?? true
            configured.useRallyScoring = config.useRallyScoring ?? false
            configured.nextSetServerModel = config.isSingles == false ? .alternateFromOpening : .opening
            rules = configured
        case .tennis:
            let tennisType: ScoreCore.GameType = config.isSingles == false ? .tennisDoubles : .tennis
            let tennisRules = TennisRuleSet(
                maxSets: config.maxSets ?? 3,
                tieBreakPoints: config.tieBreakPoints == 10 ? 10 : 7,
                gamesPerSet: config.gamesPerSet ?? 6,
                setScoringMode: config.setScoringMode == "tiebreak_only" ? .tiebreakOnly : .regular,
                matchCompletionMode: config.matchCompletionMode ?? .bestOf,
                usesNoAdScoring: config.tennisDeuceMode == "no_ad",
                autoChangeSides: config.autoChangeSides ?? true
            )
            let opening: MatchSide = config.servingSide == MatchSide.right.rawValue ? .right : .left
            let tennisState = TennisMatchState(
                leftName: config.team1Name,
                rightName: config.team2Name,
                rules: tennisRules,
                openingServer: opening
            )
            return try await watchLinkService.startInteractiveOnWatch(gameType: tennisType, state: tennisState)
        case .archery:
            let archery = LinkedArcheryState(
                leftName: config.team1Name,
                rightName: config.team2Name,
                currentShooterIsLeft: config.servingSide != MatchSide.right.rawValue
            )
            return try await watchLinkService.startInteractiveOnWatch(
                snapshot: .archery(archery),
                gameType: .archeryDual
            )
        case .eightBall:
            let beneficiary: MatchSide? = config.eightBallHandicapBeneficiary == "team1" ? .left :
                (config.eightBallHandicapBeneficiary == "team2" ? .right : nil)
            let eight = EightBallState.initial(
                targetPoints: config.maxSets ?? 9,
                handicapRacks: config.eightBallHandicapRacks ?? 0,
                handicapBeneficiary: beneficiary
            )
            return try await watchLinkService.startInteractiveOnWatch(
                snapshot: .eightBall(eight),
                gameType: .eightBall
            )
        case .nineBall:
            let nineConfig = NineBallChaseConfig(
                bigGold: config.nineBallBigGold ?? 10,
                smallGold: config.nineBallSmallGold ?? 7,
                goldenNine: config.nineBallGoldenNine ?? 8,
                normalWin: config.nineBallNormalWin ?? 4,
                ballInHand: config.nineBallBallInHand ?? 1,
                foul: config.nineBallFoul ?? 1
            )
            let nine = NineBallChaseState.initial(config: nineConfig, playerCount: config.playerCount ?? 2)
            return try await watchLinkService.startInteractiveOnWatch(
                snapshot: .nineBall(nine),
                gameType: .nineBall
            )
        case .snooker:
            let snooker = SnookerState.initial(
                striker: config.servingSide == MatchSide.right.rawValue ? .right : .left,
                maxFrames: config.maxSets ?? 1
            )
            return try await watchLinkService.startInteractiveOnWatch(
                snapshot: .snooker(snooker),
                gameType: .snooker
            )
        default:
            throw PhoneWatchLinkService.InteractiveStartError.watchUnavailable
        }

        let openingServer: MatchSide = config.servingSide == MatchSide.right.rawValue ? .right : .left
        let state = RallyMatchEngine.initial(
            leftName: config.team1Name,
            rightName: config.team2Name,
            rules: rules,
            openingServer: openingServer,
            doubles: linkedDoublesState(for: coreGameType, config: config, openingServer: openingServer)
        )
        return try await watchLinkService.startInteractiveOnWatch(gameType: coreGameType, state: state)
    }

    private func linkedDoublesState(
        for gameType: ScoreCore.GameType,
        config: SportsSetupResult,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        guard config.isSingles == false else { return nil }
        let names = [
            config.team1Player1Name ?? "红A",
            config.team2Player1Name ?? "蓝A",
            config.team1Player2Name ?? "红B",
            config.team2Player2Name ?? "蓝B"
        ]
        switch gameType {
        case .pingpongDoubles:
            return .pingPong(
                playerNames: names,
                openingServerSlotIndex: openingServer == .left ? 0 : 1,
                openingReceiverSlotIndex: openingServer == .left ? 1 : 0
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        default:
            return nil
        }
    }

    private var supportsMatchCompletionMode: Bool {
        gameType == .pingpong || gameType == .badminton || gameType == .tennis ||
            gameType == .pickleball || gameType == .foosball
    }
}
