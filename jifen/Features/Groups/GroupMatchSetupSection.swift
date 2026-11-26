import ScoreCore
import SwiftUI

/// 小组活动「开始计分」的赛制桥接。
///
/// 活动排阵锁定的是席位与开赛权限，未开赛场次仍要能选规则，因此这里只在
/// 可编辑路径上把 `GroupMatchRules` 与 `SportsSetupDraft` 互相映射：
/// - 名称、席位、发球方继续由 `GroupMatchEditor` 负责，不进入草稿；
/// - 已开赛的冻结规则（`frozenRules`）与小组默认值不经过这条路径；
/// - 四项球类各自的赛制差异在这里收口，输出永远是可提交的合法规则。
enum GroupMatchSetupBridge {
    /// 用小组规则（默认值或已有设置）回填草稿，让「经典／打满」「局数」「分数」显示实际生效的规则。
    @MainActor
    static func draft(
        from rules: GroupMatchRules, format: GroupFormat, pointPresets: [Int]? = nil
    ) -> SportsSetupDraft {
        var draft = SportsSetupDraft()
        draft.initialize(
            gameType: rules.sport.gameType,
            initialSetup: rules.setup(format: format),
            initialMaxSets: rules.maxSets,
            initialPointsPerSet: rules.pointsToWinSet,
            initialTieBreakPoints: rules.tieBreakPoints,
            preferences: .shared
        )
        if let pointPresets, rules.sport == .badminton || rules.sport == .tableTennis {
            draft.customPointsText = pointPresets.contains(draft.selectedPointsPerSet)
                ? "" : String(draft.selectedPointsPerSet)
        }
        return draft
    }

    /// 草稿 → 小组规则。`base` 提供小组默认的计分方式与净胜两分等开关，
    /// 保证「保留小组默认值」：只有本场显式可变的字段才被草稿覆盖。
    @MainActor
    static func rules(from draft: SportsSetupDraft, sport: GroupSport, base: GroupMatchRules) -> GroupMatchRules {
        var rules = base
        rules.version = 1
        rules.sport = sport
        rules.matchCompletionMode = draft.matchCompletionMode == .playAll ? "play_all" : "best_of"
        rules.maxSets = draft.correctedMaxSets(for: sport.gameType)
        switch sport {
        case .badminton:
            // 目标分变更时按本机规则推导封顶，初始目标分保留小组设置。
            let points = SetupInputCorrection.pointsPerSet(
                positive(draft.selectedPointsPerSet), max: 999, fallback: 21
            )
            rules.pointsToWinSet = points
            if points != base.pointsToWinSet {
                rules.pointCap = RallyRuleSet.badmintonPointCap(for: points)
            }
        case .tableTennis:
            // 分数可编辑，计分方式与净胜两分沿用小组设置。
            rules.pointsToWinSet = SetupInputCorrection.pointsPerSet(
                positive(draft.selectedPointsPerSet), max: 999, fallback: 11
            )
            if let cap = base.pointCap, cap < rules.pointsToWinSet { rules.pointCap = nil }
        case .tennis:
            rules.gamesPerSet = draft.tennisGamesPerSet == 4 ? 4 : 6
            rules.usesNoAdScoring = draft.tennisDeuceMode == "no_ad"
            rules.pointCap = nil
            if draft.tennisSetScoringMode == "tiebreak_only" {
                // 抢七／抢十是独立的一局决胜局：盘数固定 1，经典赛制。
                rules.setScoringMode = "tiebreak_only"
                rules.maxSets = 1
                rules.matchCompletionMode = "best_of"
                rules.tieBreakPoints = draft.matchTieBreakPoints == 10 ? 10 : 7
                rules.pointsToWinSet = rules.tieBreakPoints
            } else {
                rules.setScoringMode = "regular"
                rules.tieBreakPoints = draft.regularTieBreakPoints == 10 ? 10 : 7
                rules.pointsToWinSet = rules.gamesPerSet
            }
        case .pickleball:
            // 目标分 1–99：11 分时才允许 13/15 封顶，其它目标分按 Setup 清空封顶，21 分可直接开赛。
            let target = SportsSetupDraft.pickleballTargetScore(draft.pickleballTargetScore)
            rules.pointsToWinSet = target
            rules.pointCap = target == 11 ? draft.pickleballScoreCap : nil
            rules.useRallyScoring = draft.pickleballUseRallyScoring
        case .billiards, .unsupported:
            break
        }
        return rules.isValid ? rules : base
    }

    private static func positive(_ value: Int) -> String? {
        value > 0 ? String(value) : nil
    }

    /// 居中规则摘要的第二行：计分方式 · 净胜两分 · 封顶，跟着选择即时变化。
    /// 网球常规不提示封顶，抢七／抢十的说明交给摘要首行。
    static func ruleLine(for rules: GroupMatchRules) -> String? {
        switch rules.sport {
        case .badminton, .tableTennis, .pickleball:
            var parts = [rules.useRallyScoring ? rallyScoringText : serverScoringText]
            if rules.winByTwo { parts.append(groupText("win_by_two", "Win by two")) }
            parts.append(scoreCapText(rules.pointCap))
            return parts.joined(separator: " · ")
        case .tennis, .billiards, .unsupported:
            return nil
        }
    }

    static var rallyScoringText: String { groupText("rally_scoring", "Rally scoring") }

    /// 三端共用文案：安卓 group_audit_result_sideout（仅发球方得分）的 iOS 对位键，
    /// 47 个语种都写了键以保持本地化键集一致；en / zh-Hans / zh-Hant 为人工译文，其余先按英文兜底。
    static var serverScoringText: String { groupText("side_out_scoring", "Server only") }

    /// 定稿写法：「30 分封顶」／「无封顶」。
    static func scoreCapText(_ cap: Int?) -> String {
        guard let cap else { return groupText("no_score_cap", "No cap") }
        return String(format: groupText("score_cap_format", "%d-point cap"), cap)
    }
}

/// 活动开赛的赛制区：定稿样式 = 居中规则摘要 + 本机 Setup 控件 + 推导出的封顶提示。
struct GroupMatchSetupSection: View {
    let rules: GroupMatchRules
    let sport: GroupSport
    @Binding var draft: SportsSetupDraft
    var pointPresets: [Int]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            summary
            SportsSetupSettingsSection(
                gameType: sport.gameType,
                draft: $draft,
                showsMatchFeatures: false,
                groupPointPresets: pointPresets,
                pickleballScoringControl: .choices
            )
            if let ruleLine {
                Text(ruleLine)
                    .font(.system(size: Theme.fontCaption))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("group_match_setup_rule_line")
            }
        }
    }

    private var summary: some View {
        VStack(spacing: Theme.xs) {
            Text(formatTitle)
                .font(.system(size: Theme.fontBody2, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(scoreTitle)
                .font(.system(size: Theme.fontCaption))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group_match_setup_summary")
    }

    private var formatTitle: String {
        // 抢七／抢十按「决胜局」表述，而不是「一盘赛」。
        if sport == .tennis, rules.setScoringMode == "tiebreak_only" {
            let points = rules.tieBreakPoints == 10 ? 10 : 7
            return NSLocalizedString(
                points == 10 ? "tennis_format_tiebreak_10" : "tennis_format_tiebreak_7",
                value: points == 10 ? "10-point tie-break" : "7-point tie-break",
                comment: "Tennis deciding tie-break"
            )
        }
        return rules.formatTitle
    }

    private var scoreTitle: String {
        switch sport {
        case .tennis:
            if rules.setScoringMode == "tiebreak_only" {
                return groupText("tie_break", "Tie-break points") + " \(rules.tieBreakPoints)"
            }
            return groupText("games_per_set", "Games per set") + " \(rules.gamesPerSet) · "
                + groupText("tie_break", "Tie-break points") + " \(rules.tieBreakPoints)"
        case .pickleball:
            return groupText("target_points", "Target score") + " \(rules.pointsToWinSet)"
        default:
            return NSLocalizedString("points_per_set", value: "Points per set", comment: "Points per set")
                + " \(rules.pointsToWinSet)"
        }
    }

    /// 封顶分对羽毛球是推导值、对匹克球只在 11 分时存在，所以单独提示一行。
    private var ruleLine: String? {
        GroupMatchSetupBridge.ruleLine(for: rules)
    }
}
