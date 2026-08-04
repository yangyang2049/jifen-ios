import ScoreCore
import SwiftUI

struct SportsSetupSettingsSection: View {
    let gameType: GameType
    @Binding var draft: SportsSetupDraft
    @State private var completionModeExpanded = false

    var body: some View {
        buildSettingsSection()
    }

    private func getChipBackgroundColor(selected: Bool) -> Color {
        return selected ? Theme.primary : Theme.dialogControlBackground
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
                    settingsToggle("pingpong_auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
                    settingsToggle("voice_announcement", fallback: "语音播报", value: $draft.voiceAnnouncement)
                } else if gameType == .tennis {
                    buildTennisSettings()
                } else if gameType == .badminton {
                    buildMatchCompletionSection(useTennisWording: false)
                    buildPointsPerSetSection()
                    settingsToggle("badminton_auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
                    settingsToggle("voice_announcement", fallback: "语音播报", value: $draft.voiceAnnouncement)
                } else if gameType == .pickleball {
                    buildPickleballSettings()
                } else if gameType == .volleyball || gameType == .beachVolleyball || gameType == .airVolleyball {
                    settingsToggle("volleyball_auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
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
            chipRow(options: ["fiba", "nba"], selection: $draft.basketballRuleSet) { value in
                value.uppercased()
            }
            Text(draft.basketballRuleSet == "nba"
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
                    numberChip(rounds, selection: $draft.selectedMaxSets) {
                        draft.customMaxSetsText = ""
                    }
                }
                customNumberChip(selection: $draft.selectedMaxSets, text: $draft.customMaxSetsText, maxValue: 99)
            }
        }
    }

    @ViewBuilder
    private func buildTennisSettings() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(["regular", "tiebreak_7", "tiebreak_10"], id: \.self) { format in
                    let selected = format == "regular"
                        ? draft.tennisSetScoringMode == "regular"
                        : draft.tennisSetScoringMode == "tiebreak_only" && draft.matchTieBreakPoints == (format == "tiebreak_10" ? 10 : 7)
                    Button {
                        if format == "regular" {
                            draft.tennisSetScoringMode = "regular"
                        } else {
                            draft.tennisSetScoringMode = "tiebreak_only"
                            draft.matchTieBreakPoints = format == "tiebreak_10" ? 10 : 7
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

        if draft.tennisSetScoringMode == "regular" {
            buildMatchCompletionSection(useTennisWording: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([4, 6], id: \.self) { games in
                        Button {
                            draft.tennisGamesPerSet = games
                        } label: {
                            Text(NSLocalizedString(games == 4 ? "tennis_games_per_set_4" : "tennis_games_per_set_6", value: games == 4 ? "四局制" : "六局制", comment: ""))
                                .font(.system(size: 14, weight: draft.tennisGamesPerSet == games ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: draft.tennisGamesPerSet == games))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(getChipBackgroundColor(selected: draft.tennisGamesPerSet == games))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if draft.tennisGamesPerSet == 4 {
                    Text(NSLocalizedString("tennis_short_set_help", value: "先胜 4 局且领先 2 局；4:4 时进行抢七决胜局", comment: "Short tennis set explanation"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([7, 10], id: \.self) { points in
                        Button {
                            draft.regularTieBreakPoints = points
                        } label: {
                            Text(tennisTiebreakOptionText(points))
                                .font(.system(size: 14, weight: draft.regularTieBreakPoints == points ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: draft.regularTieBreakPoints == points))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(getChipBackgroundColor(selected: draft.regularTieBreakPoints == points))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                chipRow(options: ["advantage", "no_ad"], selection: $draft.tennisDeuceMode) { value in
                    value == "no_ad"
                        ? NSLocalizedString("tennis_deuce_option_no_ad", value: "无占先", comment: "")
                        : NSLocalizedString("tennis_deuce_option_advantage", value: "占先", comment: "")
                }
            }
        }
        settingsToggle("tennis_auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
        settingsToggle("voice_announcement", fallback: "语音播报", value: $draft.voiceAnnouncement)
    }

    @ViewBuilder
    private func buildPointsPerSetSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("points_per_set", value: "每局分数", comment: "Points per set"))
                .settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(pointPresets, id: \.self) { points in
                    numberChip(points, selection: $draft.selectedPointsPerSet) {
                        draft.customPointsText = ""
                    }
                }
                customNumberChip(selection: $draft.selectedPointsPerSet, text: $draft.customPointsText, maxValue: 999)
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
                    numberChip(points, selection: $draft.pickleballTargetScore) {
                        if points != 11 { draft.pickleballScoreCap = nil }
                    }
                }
            }
        }
        if draft.pickleballTargetScore == 11 {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("pickleball_score_cap", value: "最高分上限", comment: ""))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    optionalNumberChip(nil, label: NSLocalizedString("pickleball_no_cap", value: "无", comment: ""), selection: $draft.pickleballScoreCap)
                    optionalNumberChip(13, label: "13", selection: $draft.pickleballScoreCap)
                    optionalNumberChip(15, label: "15", selection: $draft.pickleballScoreCap)
                }
            }
        }
        settingsToggle("pickleball_rally_scoring", fallback: "每球得分", value: $draft.pickleballUseRallyScoring)
        settingsToggle("pickleball_auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
        settingsToggle("voice_announcement", fallback: "语音播报", value: $draft.voiceAnnouncement)
    }

    @ViewBuilder
    private func buildFoosballSettings() -> some View {
        buildMatchCompletionSection(useTennisWording: false)
        buildPointsPerSetSection()
        settingsToggle("foosball_final_win_by_two", fallback: "决胜局净胜 2 分", value: $draft.foosballWinByTwo)
        if draft.foosballWinByTwo {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("foosball_final_score_cap", value: "决胜局最高分上限", comment: ""))
                    .settingsLabelStyle()
                HStack(spacing: 8) {
                    Button {
                        draft.foosballScoreCap = nil
                        draft.customFoosballScoreCapText = ""
                    } label: {
                        Text(NSLocalizedString("pickleball_no_cap", value: "无", comment: ""))
                            .font(.system(size: 14, weight: draft.foosballScoreCap == nil && draft.customFoosballScoreCapText.isEmpty ? .medium : .regular))
                            .foregroundStyle(getChipTextColor(selected: draft.foosballScoreCap == nil && draft.customFoosballScoreCapText.isEmpty))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(getChipBackgroundColor(selected: draft.foosballScoreCap == nil && draft.customFoosballScoreCapText.isEmpty))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    ForEach([8, 10], id: \.self) { value in
                        Button {
                            draft.foosballScoreCap = value
                            draft.customFoosballScoreCapText = ""
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 14, weight: draft.foosballScoreCap == value && draft.customFoosballScoreCapText.isEmpty ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: draft.foosballScoreCap == value && draft.customFoosballScoreCapText.isEmpty))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(getChipBackgroundColor(selected: draft.foosballScoreCap == value && draft.customFoosballScoreCapText.isEmpty))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    customOptionalNumberChip(
                        selection: $draft.foosballScoreCap,
                        text: $draft.customFoosballScoreCapText,
                        maxValue: 99
                    )
                }
                if !hasValidFoosballScoreCap {
                    Text(NSLocalizedString(
                        "setup_score_cap_below_target",
                        value: "封顶分不能低于每局分数。",
                        comment: "Foosball final-set score cap validation"
                    ))
                    .font(.system(size: 12))
                    .foregroundColor(.red)
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
        if draft.selectedMaxSets > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("eight_ball_handicap", value: "让局", comment: ""))
                    .settingsLabelStyle()
                chipRow(options: ["none", "team2", "team1"], selection: $draft.eightBallHandicapMode) { value in
                    switch value {
                    case "team2":
                        return NSLocalizedString("eight_ball_left_lets_right", value: "左让右", comment: "")
                    case "team1":
                        return NSLocalizedString("eight_ball_right_lets_left", value: "右让左", comment: "")
                    default:
                        return NSLocalizedString("pickleball_no_cap", value: "无", comment: "")
                    }
                }
                if draft.eightBallHandicapMode != "none" {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        ForEach(Array(1..<draft.selectedMaxSets), id: \.self) { racks in
                            numberChip(racks, selection: $draft.eightBallHandicapRacks)
                        }
                    }
                    .onAppear {
                        draft.eightBallHandicapRacks = min(max(1, draft.eightBallHandicapRacks), draft.selectedMaxSets - 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buildSnookerSettings() -> some View {
        let primaryPresets = [1, 3, 5, 7]
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("snooker_frames", value: "局数", comment: "")).settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(primaryPresets, id: \.self) { count in
                    numberChip(count, selection: $draft.selectedMaxSets) {
                        draft.customMaxSetsText = ""
                    }
                }
                customNumberChip(selection: $draft.selectedMaxSets, text: $draft.customMaxSetsText, maxValue: 99)
            }
        }
    }

    @ViewBuilder
    private func buildSetCountSettings(title: String, presets: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).settingsLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presets, id: \.self) { count in
                    numberChip(count, selection: $draft.selectedMaxSets) { draft.customMaxSetsText = "" }
                }
                customNumberChip(selection: $draft.selectedMaxSets, text: $draft.customMaxSetsText, maxValue: 99)
            }
        }
    }

    private var pointPresets: [Int] {
        draft.pointPresets(for: gameType)
    }

    private var hasValidPointsPerSet: Bool {
        draft.hasValidPointsPerSet(for: gameType)
    }

    private var hasValidFoosballScoreCap: Bool {
        draft.hasValidFoosballScoreCap(for: gameType)
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
            .background(Theme.dialogControlBackground)
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
                    .background(Theme.dialogControlBackground)
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
            .background(Theme.dialogControlBackground)
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
                    .background(Theme.dialogControlBackground)
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
        draft.matchCompletionPresets
    }

    /// Presets used by the currently visible “局数/盘数” chips (not only classic best-of).
    private var frameCountPresets: [Int] {
        draft.frameCountPresets(for: gameType)
    }

    private var hasValidMatchCompletionSets: Bool {
        draft.hasValidMatchCompletionSets
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
                    Text(matchCompletionModeTitle(draft.matchCompletionMode))
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
                            draft.matchCompletionMode = mode
                            completionModeExpanded = false
                        }) {
                            VStack(spacing: 4) {
                                Text(matchCompletionModeTitle(mode))
                                    .font(.system(size: 16, weight: mode == draft.matchCompletionMode ? .medium : .regular))
                                    .foregroundStyle(mode == draft.matchCompletionMode ? Color.white : Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                Text(matchCompletionModeDescription(mode, useTennisWording: useTennisWording))
                                    .font(.system(size: 12))
                                    .foregroundStyle(mode == draft.matchCompletionMode ? Color.white.opacity(0.88) : Theme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .padding(.horizontal, 14)
                            .background(mode == draft.matchCompletionMode ? Theme.primary : Theme.dialogControlBackground)
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
                        draft.selectedMaxSets = sets
                        draft.customMaxSetsText = ""
                    }) {
                        Text("\(sets)")
                            .font(.system(size: 14, weight: draft.selectedMaxSets == sets ? .medium : .regular))
                            .foregroundColor(getChipTextColor(selected: draft.selectedMaxSets == sets))
                            .frame(maxWidth: .infinity)
                            .frame(minWidth: 38, minHeight: 36)
                            .background(getChipBackgroundColor(selected: draft.selectedMaxSets == sets))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    if matchCompletionPresets.contains(draft.selectedMaxSets) {
                        draft.selectedMaxSets = 0
                        draft.customMaxSetsText = ""
                    }
                }) {
                    Text(NSLocalizedString("custom", value: "自定义", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(getChipTextColor(selected: !matchCompletionPresets.contains(draft.selectedMaxSets)))
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: 58, minHeight: 36)
                        .background(getChipBackgroundColor(selected: !matchCompletionPresets.contains(draft.selectedMaxSets)))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom_match_sets_button")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if !matchCompletionPresets.contains(draft.selectedMaxSets) {
                TextField(NSLocalizedString("match_completion_custom_placeholder", value: "输入 1-99", comment: ""), text: Binding(
                    get: { draft.customMaxSetsText },
                    set: { rawValue in
                        let sanitized = String(rawValue.filter(\.isNumber).prefix(2))
                        draft.customMaxSetsText = sanitized
                        draft.selectedMaxSets = Int(sanitized) ?? 0
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
    private var usesPlayerCommonNames: Bool {
        ScoreboardCommonNamePolicy.nameType(for: gameType) == .player
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
            return NSLocalizedString("tennis_scoring_mode_tiebreak_7", value: "抢七赛", comment: "")
        case "tiebreak_10":
            return NSLocalizedString("tennis_scoring_mode_tiebreak_10", value: "抢十赛", comment: "")
        default:
            return NSLocalizedString("tennis_scoring_mode_regular", value: "标准赛制", comment: "")
        }
    }
    
}
