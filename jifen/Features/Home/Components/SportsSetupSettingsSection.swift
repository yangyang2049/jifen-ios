import ScoreCore
import SwiftUI

struct SportsSetupSettingsSection: View {
    let gameType: GameType
    @Binding var draft: SportsSetupDraft
    var onCustomFieldFocus: (String?) -> Void = { _ in }
    @State private var completionModeExpanded = false
    @State private var requestedCustomField: CustomField?
    @State private var customFieldSelections: [CustomField: TextSelection] = [:]
    @FocusState private var focusedCustomField: CustomField?
    @Environment(\.layoutDirection) private var layoutDirection
    private let numberChipSize: CGFloat = 44
    private let customInputWidth: CGFloat = 64
    private let numberChipCornerRadius: CGFloat = 12

    private enum CustomField: String, Hashable {
        case sets
        case points
        case foosballScoreCap
        case pickleballTarget
        case basketballPeriod
        case basketballOvertime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            buildSettingsSection()
            // 「比赛功能」区：对齐安卓功能卡片矩阵，所有计分项目统一渲染。
            SportsSetupMatchFeaturesSection(gameType: gameType, draft: $draft)
        }
        .onChange(of: focusedCustomField) { oldField, newField in
            if let oldField, oldField != newField, requestedCustomField == oldField {
                requestedCustomField = nil
            }
            if let newField {
                requestedCustomField = newField
                let text = customFieldText(newField)
                customFieldSelections[newField] = TextSelection(range: text.startIndex..<text.endIndex)
            } else if let oldField {
                customFieldSelections[oldField] = nil
            }
            onCustomFieldFocus(newField.map { "setup_custom_\($0.rawValue)" })
        }
    }

    private func focusRequestedCustomField(_ field: CustomField) async {
        guard requestedCustomField == field else { return }
        // Start after this field is mounted, including cells in lazy grids.
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return
        }
        guard !Task.isCancelled, requestedCustomField == field else { return }
        focusedCustomField = field
    }

    private func dismissCustomFocus() {
        requestedCustomField = nil
        focusedCustomField = nil
        customFieldSelections = [:]
    }

    private func isEditingCustomField(_ field: CustomField) -> Bool {
        requestedCustomField == field || focusedCustomField == field
    }

    private func customFieldText(_ field: CustomField) -> String {
        switch field {
        case .sets: draft.customMaxSetsText
        case .points: draft.customPointsText
        case .foosballScoreCap: draft.customFoosballScoreCapText
        case .pickleballTarget: draft.customPickleballTargetText
        case .basketballPeriod: draft.basketballPeriodText
        case .basketballOvertime: draft.basketballOvertimeText
        }
    }

    private func isCustomValueActive(_ field: CustomField) -> Bool {
        isEditingCustomField(field) || !customFieldText(field).isEmpty
    }

    private func customTextSelection(_ field: CustomField) -> Binding<TextSelection?> {
        Binding(
            get: { customFieldSelections[field] },
            set: { customFieldSelections[field] = $0 }
        )
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
               gameType == .softTennis ||
               gameType == .padel ||
               gameType == .badminton ||
               gameType == .shuttlecock ||
               gameType == .squash ||
               gameType == .volleyball ||
               gameType == .beachVolleyball ||
               gameType == .airVolleyball ||
               gameType == .pickleball ||
               gameType == .foosball ||
               gameType == .eightBall ||
               gameType == .snooker
               || gameType == .football5v5
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
                } else if gameType == .tennis {
                    buildTennisSettings()
                } else if gameType == .softTennis {
                    buildSoftTennisSettings()
                } else if gameType == .padel {
                    buildPadelSettings()
                } else if gameType == .badminton {
                    buildMatchCompletionSection(useTennisWording: false)
                    buildPointsPerSetSection()
                } else if gameType == .pickleball {
                    buildPickleballSettings()
                } else if gameType == .shuttlecock {
                    buildPointsPerSetSection()
                } else if gameType == .squash {
                    buildMatchCompletionSection(useTennisWording: false)
                } else if gameType == .volleyball || gameType == .beachVolleyball || gameType == .airVolleyball {
                    // 比赛功能（自动换边/显示时间）由底部功能区统一渲染。
                } else if gameType == .foosball {
                    buildFoosballSettings()
                } else if gameType == .snooker {
                    buildSnookerSettings()
                } else if gameType == .eightBall {
                    buildEightBallSettings()
                } else if gameType == .football5v5 {
                    buildFootballSettings()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 对齐安卓 FootballHalfLengthSetup：居中布局，「−/＋」分列时长值左右两侧。
    @ViewBuilder
    private func buildFootballSettings() -> some View {
        let minutes = draft.footballHalfLengthSeconds / 60
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(NSLocalizedString("football_half_length", value: "每半场时长", comment: "Football half length"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                SystemHelpButton(
                    title: NSLocalizedString("football_half_length", value: "每半场时长", comment: "Football half length"),
                    message: NSLocalizedString(
                        "football_setup_hint",
                        value: "默认每半场 20 分钟；进入比赛后，点击顶部计时器开始或暂停。",
                        comment: "5x5 football timer setup hint"
                    ),
                    iconFontSize: 14,
                    accessibilityIdentifier: "football_half_length_help"
                )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                footballHalfLengthStepButton(
                    systemImage: "minus",
                    isDisabled: minutes <= 1,
                    action: { draft.footballHalfLengthSeconds = min(90, max(1, minutes - 1)) * 60 }
                )
                Text(String(
                    format: NSLocalizedString("minutes_format", value: "%d 分钟", comment: "Minutes"),
                    minutes
                ))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                footballHalfLengthStepButton(
                    systemImage: "plus",
                    isDisabled: minutes >= 90,
                    action: { draft.footballHalfLengthSeconds = min(90, max(1, minutes + 1)) * 60 }
                )
            }
            .accessibilityValue("\(minutes)")
        }
        .frame(maxWidth: .infinity)
    }

    /// 对齐安卓 HalfLengthStepButton：36pt 圆形按钮，边界处禁用并降透明度。
    private func footballHalfLengthStepButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.dialogControlBackground)
                .clipShape(Circle())
                .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func buildBasketballSettings() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("basketball_rule_set_label", value: "规则", comment: "Basketball rules"))
                .settingsLabelStyle()
            chipRow(options: ["fiba", "nba", "custom"], selection: $draft.basketballRuleSet) { value in
                value == "custom" ? NSLocalizedString("custom", comment: "") : value.uppercased()
            }
            if draft.basketballRuleSet == "custom" {
                VStack(spacing: 20) {
                    Text(NSLocalizedString("basketball_period_minutes", value: "每节时长（分钟）", comment: "")).settingsLabelStyle()
                    SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                        ForEach([10, 12, 15, 20], id: \.self) { value in
                            numberChip(value, selection: $draft.basketballPeriodMinutes, customField: .basketballPeriod) {
                                draft.basketballPeriodMinutes = value; draft.basketballPeriodText = ""; requestedCustomField = nil
                            }
                        }
                        customNumberChip(selection: $draft.basketballPeriodMinutes, text: $draft.basketballPeriodText, maxValue: 99, field: .basketballPeriod)
                    }
                    Text(NSLocalizedString("basketball_overtime_minutes", value: "加时时长（分钟）", comment: "")).settingsLabelStyle()
                    SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                        ForEach([3, 5, 10], id: \.self) { value in
                            numberChip(value, selection: $draft.basketballOvertimeMinutes, customField: .basketballOvertime) {
                                draft.basketballOvertimeMinutes = value; draft.basketballOvertimeText = ""; requestedCustomField = nil
                            }
                        }
                        customNumberChip(selection: $draft.basketballOvertimeMinutes, text: $draft.basketballOvertimeText, maxValue: 99, field: .basketballOvertime)
                    }
                }
            } else { Text(draft.basketballRuleSet == "nba"
                 ? NSLocalizedString("basketball_rule_nba_summary", value: "NBA：每节 12 分钟，常规赛 7 次暂停。", comment: "")
                 : NSLocalizedString("basketball_rule_fiba_summary", value: "FIBA：每节 10 分钟，上下半场分别计算暂停。", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func buildBoxingSettings() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("boxing_rounds", value: "回合数", comment: "Boxing rounds"))
                .settingsLabelStyle()
            SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                ForEach([3, 8, 10, 12], id: \.self) { rounds in
                    numberChip(rounds, selection: $draft.selectedMaxSets, customField: .sets) {
                        draft.customMaxSetsText = ""
                    }
                }
                customNumberChip(selection: $draft.selectedMaxSets, text: $draft.customMaxSetsText, maxValue: 99, field: .sets)
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
    }

    @ViewBuilder
    private func buildSoftTennisSettings() -> some View {
        Text(NSLocalizedString("soft_tennis_match_games", value: "整场局数", comment: "Soft tennis total match games"))
            .settingsLabelStyle()
        SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
            ForEach([7, 9], id: \.self) { games in
                numberChip(games, selection: $draft.softTennisMatchGames)
            }
        }
    }

    @ViewBuilder
    private func buildPadelSettings() -> some View {
        Text(NSLocalizedString("padel_deuce_mode", value: "平分规则", comment: "Padel deuce mode"))
            .settingsLabelStyle()
        SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
            ForEach(PadelDeuceMode.allCases, id: \.self) { mode in
                Button {
                    draft.padelDeuceMode = mode
                } label: {
                    Text(padelModeTitle(mode))
                        .font(.system(size: 14, weight: draft.padelDeuceMode == mode ? .medium : .regular))
                        .foregroundStyle(getChipTextColor(selected: draft.padelDeuceMode == mode))
                        .padding(.horizontal, 16)
                        .frame(minWidth: 64, minHeight: 40)
                        .background(getChipBackgroundColor(selected: draft.padelDeuceMode == mode))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func padelModeTitle(_ mode: PadelDeuceMode) -> String {
        switch mode {
        case .advantage: return NSLocalizedString("padel_advantage", value: "占先", comment: "")
        case .goldenPoint: return NSLocalizedString("padel_golden_point", value: "黄金分", comment: "")
        case .starPoint: return NSLocalizedString("padel_star_point", value: "星星分", comment: "")
        }
    }

    @ViewBuilder
    private func buildPointsPerSetSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("points_per_set", value: "每局分数", comment: "Points per set"))
                .settingsLabelStyle()
            customNumberChipGrid(
                presets: pointPresets,
                selection: $draft.selectedPointsPerSet,
                text: $draft.customPointsText,
                maxValue: 999,
                field: .points
            )
        }
    }

    @ViewBuilder
    private func buildPickleballSettings() -> some View {
        buildMatchCompletionSection(useTennisWording: false)
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("pickleball_target_score", value: "目标分", comment: ""))
                .settingsLabelStyle()
            // 安卓 3.4：目标分放开到 1–99。保留 11/15/21 快捷档位，
            // 其余整数走同文件已有的自定义数值输入（铅笔 chip → 数字键盘）。
            customNumberChipGrid(
                presets: SportsSetupDraft.pickleballTargetPresets,
                selection: $draft.pickleballTargetScore,
                text: $draft.customPickleballTargetText,
                maxValue: RallyRuleSet.pickleballTargetScoreRange.upperBound,
                minimumValue: RallyRuleSet.pickleballTargetScoreRange.lowerBound,
                field: .pickleballTarget
            )
        }
        .onChange(of: draft.pickleballTargetScore) { _, target in
            // 封顶分（scoreCap）只在目标分 11 时保留，其余目标分继续置 nil。
            if target != 11 { draft.pickleballScoreCap = nil }
        }
        if draft.pickleballTargetScore == 11 {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("pickleball_score_cap", value: "最高分上限", comment: ""))
                    .settingsLabelStyle()
                SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                    optionalNumberChip(nil, label: NSLocalizedString("pickleball_no_cap", value: "无", comment: ""), selection: $draft.pickleballScoreCap)
                    optionalNumberChip(13, label: "13", selection: $draft.pickleballScoreCap)
                    optionalNumberChip(15, label: "15", selection: $draft.pickleballScoreCap)
                }
            }
        }
        settingsToggle("pickleball_rally_scoring", fallback: "每球得分", value: $draft.pickleballUseRallyScoring)
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
                SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                    Button {
                        dismissCustomFocus()
                        draft.foosballScoreCap = nil
                        draft.customFoosballScoreCapText = ""
                    } label: {
                        Text(NSLocalizedString("pickleball_no_cap", value: "无", comment: ""))
                            .font(.system(size: 14, weight: draft.foosballScoreCap == nil && !isCustomValueActive(.foosballScoreCap) ? .medium : .regular))
                            .foregroundStyle(getChipTextColor(selected: draft.foosballScoreCap == nil && !isCustomValueActive(.foosballScoreCap)))
                            .padding(.horizontal, 8)
                            .frame(minWidth: numberChipSize, minHeight: numberChipSize)
                            .background(getChipBackgroundColor(selected: draft.foosballScoreCap == nil && !isCustomValueActive(.foosballScoreCap)))
                            .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    ForEach([8, 10], id: \.self) { value in
                        Button {
                            dismissCustomFocus()
                            draft.foosballScoreCap = value
                            draft.customFoosballScoreCapText = ""
                        } label: {
                            Text("\(value)")
                                .font(.system(size: 14, weight: draft.foosballScoreCap == value && !isCustomValueActive(.foosballScoreCap) ? .medium : .regular))
                                .foregroundStyle(getChipTextColor(selected: draft.foosballScoreCap == value && !isCustomValueActive(.foosballScoreCap)))
                                .frame(width: numberChipSize, height: numberChipSize)
                                .background(getChipBackgroundColor(selected: draft.foosballScoreCap == value && !isCustomValueActive(.foosballScoreCap)))
                                .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    customOptionalNumberChip(
                        selection: $draft.foosballScoreCap,
                        text: $draft.customFoosballScoreCapText,
                        maxValue: 99
                    )
                }
                // 封顶分越界不再红字拦截：开赛时由 SetupInputCorrection.scoreCap 夹到
                // [每局分数, 99]，与安卓一致。
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
                    SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
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
            customNumberChipGrid(
                presets: primaryPresets,
                selection: $draft.selectedMaxSets,
                text: $draft.customMaxSetsText,
                maxValue: 99,
                field: .sets
            )
        }
        settingsToggle("match_title", fallback: "比赛抬头", value: $draft.matchTitleEnabled)
        if draft.matchTitleEnabled {
            TextField(
                NSLocalizedString("match_title_placeholder", value: "例如：2026 城市公开赛", comment: "Snooker match title placeholder"),
                text: Binding(
                    get: { draft.matchTitle },
                    set: { draft.matchTitle = ScoreboardMatchTitlePolicy.limitInput($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("setup_snooker_match_title_input")
        }
    }

    @ViewBuilder
    private func buildSetCountSettings(title: String, presets: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).settingsLabelStyle()
            customNumberChipGrid(
                presets: presets,
                selection: $draft.selectedMaxSets,
                text: $draft.customMaxSetsText,
                maxValue: 99,
                field: .sets
            )
        }
    }

    /// Keep input fields mounted when the keyboard changes the scroll viewport.
    private func customNumberChipGrid(
        presets: [Int],
        selection: Binding<Int>,
        text: Binding<String>,
        maxValue: Int,
        minimumValue: Int = 0,
        field: CustomField
    ) -> some View {
        SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
            ForEach(presets, id: \.self) { value in
                numberChip(value, selection: selection, customField: field) {
                    text.wrappedValue = ""
                }
            }
            customNumberChip(
                selection: selection,
                text: text,
                maxValue: maxValue,
                minimumValue: minimumValue,
                field: field
            )
        }
    }

    private var pointPresets: [Int] {
        draft.pointPresets(for: gameType)
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
        customField: CustomField? = nil,
        onSelect: @escaping () -> Void = {}
    ) -> some View {
        let isSelected = selection.wrappedValue == value
            && !(customField.map { isCustomValueActive($0) } ?? false)
        return Button {
            dismissCustomFocus()
            selection.wrappedValue = value
            onSelect()
        } label: {
            Text("\(value)")
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(getChipTextColor(selected: isSelected))
                .frame(width: numberChipSize, height: numberChipSize)
                .background(getChipBackgroundColor(selected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customNumberChip(
        selection: Binding<Int>,
        text: Binding<String>,
        maxValue: Int,
        minimumValue: Int = 0,
        field: CustomField
    ) -> some View {
        if !text.wrappedValue.isEmpty || isEditingCustomField(field) {
            TextField(NSLocalizedString("custom", value: "自定义", comment: ""), text: Binding(
                get: { text.wrappedValue },
                set: { rawValue in
                    guard requestedCustomField == field else { return }
                    let limit = String(maxValue).count
                    let sanitized = normalizedDecimalDigits(rawValue, limit: limit)
                    text.wrappedValue = sanitized
                    selection.wrappedValue = max(minimumValue, min(maxValue, Int(sanitized) ?? 0))
                }
            ), selection: customTextSelection(field))
            .keyboardType(.numberPad)
            .focused($focusedCustomField, equals: field)
            .task(id: requestedCustomField) { await focusRequestedCustomField(field) }
            .multilineTextAlignment(.center)
            .font(.system(size: 14))
            .frame(width: customInputWidth, height: numberChipSize)
            .background(Theme.dialogControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
            .accessibilityIdentifier("setup_custom_\(field.rawValue)_field")
            .id("setup_custom_\(field.rawValue)")
        } else {
            Button {
                text.wrappedValue = selection.wrappedValue > 0
                    ? String(selection.wrappedValue)
                    : String(max(1, minimumValue))
                requestedCustomField = field
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: numberChipSize, height: numberChipSize)
                    .background(Theme.dialogControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("custom", value: "自定义", comment: ""))
            .accessibilityIdentifier("setup_custom_\(field.rawValue)_button")
        }
    }

    private func optionalNumberChip(
        _ value: Int?,
        label: String,
        selection: Binding<Int?>
    ) -> some View {
        Button {
            dismissCustomFocus()
            selection.wrappedValue = value
        } label: {
            Text(label)
                .font(.system(size: 14, weight: selection.wrappedValue == value ? .medium : .regular))
                .foregroundStyle(getChipTextColor(selected: selection.wrappedValue == value))
                .padding(.horizontal, value == nil ? 8 : 0)
                .frame(minWidth: numberChipSize, minHeight: numberChipSize)
                .background(getChipBackgroundColor(selected: selection.wrappedValue == value))
                .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customOptionalNumberChip(
        selection: Binding<Int?>,
        text: Binding<String>,
        maxValue: Int
    ) -> some View {
        let isCustomActive = isEditingCustomField(.foosballScoreCap) || !text.wrappedValue.isEmpty
            || (selection.wrappedValue != nil && selection.wrappedValue != 8 && selection.wrappedValue != 10)
        if isCustomActive {
            TextField(NSLocalizedString("custom", value: "自定义", comment: ""), text: Binding(
                get: { text.wrappedValue },
                set: { rawValue in
                    guard requestedCustomField == .foosballScoreCap else { return }
                    let limit = String(maxValue).count
                    let sanitized = normalizedDecimalDigits(rawValue, limit: limit)
                    text.wrappedValue = sanitized
                    if let value = Int(sanitized), value >= 1 {
                        selection.wrappedValue = min(maxValue, value)
                    } else {
                        selection.wrappedValue = nil
                    }
                }
            ), selection: customTextSelection(.foosballScoreCap))
            .keyboardType(.numberPad)
            .focused($focusedCustomField, equals: .foosballScoreCap)
            .task(id: requestedCustomField) { await focusRequestedCustomField(.foosballScoreCap) }
            .multilineTextAlignment(.center)
            .font(.system(size: 14))
            .frame(width: customInputWidth, height: numberChipSize)
            .background(Theme.dialogControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
            .accessibilityIdentifier("setup_custom_foosballScoreCap_field")
            .id("setup_custom_foosballScoreCap")
        } else {
            Button {
                let seed = selection.wrappedValue ?? 12
                text.wrappedValue = String(seed)
                selection.wrappedValue = seed
                requestedCustomField = .foosballScoreCap
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: numberChipSize, height: numberChipSize)
                    .background(Theme.dialogControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("custom", value: "自定义", comment: ""))
            .accessibilityIdentifier("setup_custom_foosballScoreCap_button")
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
        draft.matchCompletionPresets(for: gameType)
    }

    /// Presets used by the currently visible “局数/盘数” chips (not only classic best-of).
    private var frameCountPresets: [Int] {
        draft.frameCountPresets(for: gameType)
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
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
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
                                    .foregroundStyle(mode == draft.matchCompletionMode ? Theme.textOnPrimary : Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                Text(matchCompletionModeDescription(mode, useTennisWording: useTennisWording))
                                    .font(.system(size: 12))
                                    .foregroundStyle(mode == draft.matchCompletionMode ? Theme.textOnPrimary.opacity(0.88) : Theme.textSecondary)
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

            SetupNumberChoicesLayout(layoutDirection: layoutDirection) {
                ForEach(matchCompletionPresets, id: \.self) { sets in
                    let isSelected = draft.selectedMaxSets == sets && !isCustomValueActive(.sets)
                    Button(action: {
                        dismissCustomFocus()
                        draft.selectMatchCompletionPreset(sets, gameType: gameType)
                    }) {
                        Text("\(sets)")
                            .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                            .foregroundColor(getChipTextColor(selected: isSelected))
                            .frame(width: numberChipSize, height: numberChipSize)
                            .background(getChipBackgroundColor(selected: isSelected))
                            .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup_match_sets_\(sets)")
                }

                if !matchCompletionPresets.contains(draft.selectedMaxSets) || isCustomValueActive(.sets) {
                    TextField(NSLocalizedString("custom", value: "自定义", comment: ""), text: Binding(
                        get: { draft.customMaxSetsText },
                        set: { rawValue in
                            // A removed editor can send its final value after a preset is selected.
                            guard requestedCustomField == .sets else { return }
                            let sanitized = normalizedDecimalDigits(rawValue, limit: 2)
                            draft.customMaxSetsText = sanitized
                            draft.selectedMaxSets = Int(sanitized) ?? 0
                        }
                    ), selection: customTextSelection(.sets))
                    .keyboardType(.numberPad)
                    .focused($focusedCustomField, equals: .sets)
                    .task(id: requestedCustomField) { await focusRequestedCustomField(.sets) }
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .frame(width: customInputWidth, height: numberChipSize)
                    .background(Theme.dialogControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
                    .accessibilityIdentifier("custom_max_sets_field")
                    .id("setup_custom_sets")
                } else {
                    Button(action: {
                        draft.customMaxSetsText = String(max(1, draft.selectedMaxSets))
                        requestedCustomField = .sets
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: numberChipSize, height: numberChipSize)
                            .background(Theme.dialogControlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: numberChipCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("custom", value: "自定义", comment: ""))
                    .accessibilityIdentifier("custom_match_sets_button")
                }
            }

            // 偶数局不再红字拦截：开赛时自动 +1，并提示实际使用的局数（安卓 setup_auto_odd_sets）。
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

/// Wrap fixed-size choices without remounting the focused input when rows change.
struct SetupNumberChoicesLayout: Layout {
    var layoutDirection: LayoutDirection
    private let spacing: CGFloat = 8

    private func rows(for sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var rowWidth: CGFloat = 0
        for index in sizes.indices {
            let nextWidth = rowWidth + (row.isEmpty ? 0 : spacing) + sizes[index].width
            if !row.isEmpty && nextWidth > width {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            rowWidth += (row.isEmpty ? 0 : spacing) + sizes[index].width
            row.append(index)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(sizes.count - 1)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let rows = rows(for: sizes, width: width)
        let height = rows.reduce(CGFloat.zero) { height, row in
            height + (row.map { sizes[$0].height }.max() ?? 0)
        } + spacing * CGFloat(rows.count - 1)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(for: sizes, width: bounds.width) {
            let rowWidth = row.reduce(CGFloat.zero) { $0 + sizes[$1].width } + spacing * CGFloat(row.count - 1)
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = (bounds.width - rowWidth) / 2
            for index in row {
                let size = sizes[index]
                let originX = layoutDirection == .rightToLeft
                    ? bounds.maxX - x - size.width
                    : bounds.minX + x
                subviews[index].place(
                    at: CGPoint(x: originX, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
