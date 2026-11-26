import XCTest
import ScoreCore
@testable import jifen

/// 小组活动排阵后开赛的四项球类赛制：复用本机 Setup 控件后的规则映射。
@MainActor
final class GroupMatchSetupRulesTests: XCTestCase {
    private func defaults(_ sport: GroupSport) -> GroupMatchRules {
        switch sport {
        case .badminton:
            return .init(sport: .badminton, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 21, pointCap: 30,
                         winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7,
                         setScoringMode: "regular", usesNoAdScoring: false)
        case .tableTennis:
            return .init(sport: .tableTennis, maxSets: 5, matchCompletionMode: "best_of", pointsToWinSet: 11, pointCap: nil,
                         winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7,
                         setScoringMode: "regular", usesNoAdScoring: false)
        case .tennis:
            return .init(sport: .tennis, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 6, pointCap: nil,
                         winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7,
                         setScoringMode: "regular", usesNoAdScoring: false)
        case .pickleball:
            return .init(sport: .pickleball, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 11, pointCap: 15,
                         winByTwo: true, useRallyScoring: true, gamesPerSet: 6, tieBreakPoints: 7,
                         setScoringMode: "regular", usesNoAdScoring: false)
        default:
            return .init(sport: sport, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 21, pointCap: nil,
                         winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7,
                         setScoringMode: "regular", usesNoAdScoring: false)
        }
    }

    private func draft(_ sport: GroupSport, format: GroupFormat = .doubles) -> SportsSetupDraft {
        GroupMatchSetupBridge.draft(from: defaults(sport), format: format)
    }

    /// 回填：四个球类 × 单双打都从小组实际规则起步，且默认值落成合法规则。
    func testSeededDraftKeepsGroupDefaultsForEverySportAndFormat() {
        for sport in GroupSport.racketSports {
            for format in GroupFormat.allCases {
                let base = defaults(sport)
                let seeded = GroupMatchSetupBridge.draft(from: base, format: format)
                let rules = GroupMatchSetupBridge.rules(from: seeded, sport: sport, base: base)
                XCTAssertTrue(rules.isValid, "\(sport)/\(format)")
                XCTAssertEqual(rules.maxSets, base.maxSets, "\(sport)/\(format)")
                XCTAssertEqual(rules.matchCompletionMode, base.matchCompletionMode, "\(sport)/\(format)")
                XCTAssertEqual(rules.pointsToWinSet, base.pointsToWinSet, "\(sport)/\(format)")
                XCTAssertEqual(rules.gamesPerSet, base.gamesPerSet, "\(sport)/\(format)")
                XCTAssertEqual(rules.tieBreakPoints, base.tieBreakPoints, "\(sport)/\(format)")
                switch sport {
                case .badminton:
                    XCTAssertEqual(rules.pointCap, 30)
                    XCTAssertEqual(rules.useRallyScoring, base.useRallyScoring)
                case .pickleball:
                    XCTAssertEqual(rules.pointCap, 15)
                    XCTAssertTrue(rules.useRallyScoring, "匹克球保留小组默认的每球得分")
                case .tennis:
                    XCTAssertEqual(rules.setScoringMode, "regular")
                    XCTAssertNil(rules.pointCap)
                default:
                    XCTAssertNil(rules.pointCap)
                    XCTAssertEqual(rules.pointsToWinSet, 11)
                    XCTAssertEqual(rules.useRallyScoring, base.useRallyScoring)
                }
            }
        }
    }

    /// 羽毛球：改目标分时推导封顶，保留小组的计分方式与净胜规则。
    func testBadmintonPreservesGroupScoringAndDerivesTheCap() {
        var base = defaults(.badminton)
        base.winByTwo = false
        for (points, expectedCap) in [(11, 15), (15, 21), (21, 30), (30, nil)] {
            var seeded = draft(.badminton)
            seeded.selectedPointsPerSet = points
            seeded.customPointsText = ""
            let rules = GroupMatchSetupBridge.rules(from: seeded, sport: .badminton, base: base)
            XCTAssertEqual(rules.pointsToWinSet, points)
            XCTAssertEqual(rules.pointCap, expectedCap, "points \(points)")
            XCTAssertFalse(rules.useRallyScoring)
            XCTAssertFalse(rules.winByTwo)
            XCTAssertTrue(rules.isValid, "points \(points)")
            // 计分板最终拿到的规则也必须是同一个封顶。
            let onCourt = rules.setup(format: .doubles).badmintonRules
            XCTAssertEqual(onCourt.pointCap, expectedCap)
            XCTAssertFalse(onCourt.useRallyScoring)
            XCTAssertFalse(onCourt.winByTwo)
        }
    }

    /// 乒乓球：沿用本机 Setup 的分数档（5/7/9/11），不封顶。
    func testTableTennisUsesTheSetupPointTiers() {
        let base = defaults(.tableTennis)
        for points in [5, 7, 9, 11, 15] {
            var seeded = draft(.tableTennis)
            seeded.selectedPointsPerSet = points
            seeded.customPointsText = ""
            let rules = GroupMatchSetupBridge.rules(from: seeded, sport: .tableTennis, base: base)
            XCTAssertEqual(rules.pointsToWinSet, points)
            XCTAssertNil(rules.pointCap)
            XCTAssertTrue(rules.isValid)
            XCTAssertEqual(rules.setup(format: .singles).pingPongRules.pointsToWinSet, points)
        }
    }

    func testDirectStartAppliesTheSameGroupRulesToTheScoreboard() {
        var base = defaults(.badminton)
        base.useRallyScoring = true
        base.winByTwo = false
        let seeded = GroupMatchSetupBridge.draft(from: base, format: .singles)
        XCTAssertEqual(seeded.customPointsText, "")
        var draft = seeded
        draft.selectedPointsPerSet = 15
        draft.voiceAnnouncement = true
        draft.servingSide = .right
        var setup = draft.makeResult(gameType: .badminton, usesDoublesPlayerInputs: false, voiceSupported: true)
        let rules = GroupMatchSetupBridge.rules(from: draft, sport: .badminton, base: base)

        rules.apply(to: &setup)

        XCTAssertEqual(GroupMatchRules(sport: .badminton, setup: setup), rules)
        XCTAssertTrue(setup.badmintonRules.useRallyScoring)
        XCTAssertFalse(setup.badmintonRules.winByTwo)
        XCTAssertEqual(setup.badmintonRules.pointsToWinSet, 15)
        XCTAssertEqual(setup.badmintonRules.pointCap, 21)
        XCTAssertEqual(setup.servingSide, "right")
        XCTAssertEqual(setup.voiceAnnouncement, true)
    }

    /// 网球常规：盘数、每盘局制、盘末抢分、占先/无占先各自独立。
    func testTennisRegularKeepsSetsGamesTieBreakAndDeuceIndependent() {
        let base = defaults(.tennis)
        var seeded = draft(.tennis)
        seeded.tennisSetScoringMode = "regular"
        seeded.selectedMaxSets = 5
        seeded.matchCompletionMode = .bestOf
        seeded.tennisGamesPerSet = 4
        seeded.regularTieBreakPoints = 10
        seeded.tennisDeuceMode = "no_ad"

        let rules = GroupMatchSetupBridge.rules(from: seeded, sport: .tennis, base: base)
        XCTAssertEqual(rules.maxSets, 5)
        XCTAssertEqual(rules.matchCompletionMode, "best_of")
        XCTAssertEqual(rules.gamesPerSet, 4)
        XCTAssertEqual(rules.tieBreakPoints, 10)
        XCTAssertTrue(rules.usesNoAdScoring)
        XCTAssertEqual(rules.setScoringMode, "regular")
        XCTAssertTrue(rules.isValid)
        let onCourt = rules.setup(format: .singles).tennisRules
        XCTAssertEqual(onCourt.maxSets, 5)
        XCTAssertEqual(onCourt.gamesPerSet, 4)
        XCTAssertEqual(onCourt.tieBreakPoints, 10)
        XCTAssertTrue(onCourt.usesNoAdScoring)
    }

    /// 网球抢七/抢十：独立开局，只打一局决胜，不再读盘数与每盘局制。
    func testTennisTieBreakOnlyIsOneIndependentDecidingGame() {
        let base = defaults(.tennis)
        for points in [7, 10] {
            var seeded = draft(.tennis)
            seeded.tennisSetScoringMode = "tiebreak_only"
            seeded.matchTieBreakPoints = points
            seeded.selectedMaxSets = 5
            seeded.tennisGamesPerSet = 4
            let rules = GroupMatchSetupBridge.rules(from: seeded, sport: .tennis, base: base)
            XCTAssertEqual(rules.setScoringMode, "tiebreak_only")
            XCTAssertEqual(rules.maxSets, 1)
            XCTAssertEqual(rules.matchCompletionMode, "best_of")
            XCTAssertEqual(rules.tieBreakPoints, points)
            XCTAssertTrue(rules.isValid, "tiebreak \(points)")
            XCTAssertEqual(rules.setup(format: .doubles).tennisRules.maxSets, 1)
            XCTAssertEqual(rules.setup(format: .doubles).tennisRules.tieBreakPoints, points)
        }
    }

    /// 匹克球：计分方式可选；11 分才有封顶（无/13/15），其它目标分清空封顶，21 分能开赛。
    func testPickleballCapOnlyAppliesToElevenAndTwentyOneCanStart() {
        let base = defaults(.pickleball)
        var seeded = draft(.pickleball)
        seeded.pickleballUseRallyScoring = false
        seeded.pickleballScoreCap = 13
        var rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: base)
        XCTAssertEqual(rules.pointsToWinSet, 11)
        XCTAssertEqual(rules.pointCap, 13)
        XCTAssertFalse(rules.useRallyScoring)
        XCTAssertTrue(rules.isValid)

        seeded.pickleballScoreCap = nil
        rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: base)
        XCTAssertNil(rules.pointCap, "11 分可以选「无」封顶")

        for target in [15, 21, 99] {
            var next = seeded
            next.pickleballTargetScore = target
            next.pickleballScoreCap = 15
            let value = GroupMatchSetupBridge.rules(from: next, sport: .pickleball, base: base)
            XCTAssertEqual(value.pointsToWinSet, target)
            XCTAssertNil(value.pointCap, "target \(target) 不给封顶")
            XCTAssertTrue(value.isValid, "target \(target) 必须可以开赛")
            XCTAssertEqual(value.setup(format: .doubles).pickleballRules.pointsToWinSet, target)
        }
    }

    /// 经典赛制偶数局在开赛时向上取奇数；打满保留原值。
    func testClassicEvenSetsAreCorrectedButPlayAllIsKept() {
        for sport in GroupSport.racketSports {
            var seeded = draft(sport)
            seeded.matchCompletionMode = .bestOf
            seeded.selectedMaxSets = 4
            let rules = GroupMatchSetupBridge.rules(from: seeded, sport: sport, base: defaults(sport))
            XCTAssertEqual(rules.maxSets, 5, "\(sport) 经典偶数局")
            XCTAssertTrue(rules.isValid)

            if sport != .tennis {
                seeded.matchCompletionMode = .playAll
                seeded.selectedMaxSets = 4
                let playAll = GroupMatchSetupBridge.rules(from: seeded, sport: sport, base: defaults(sport))
                XCTAssertEqual(playAll.maxSets, 4, "\(sport) 打满保留偶数局")
                XCTAssertEqual(playAll.matchCompletionMode, "play_all")
                XCTAssertTrue(playAll.isValid)
            }
        }
    }

    /// 居中规则摘要（第二行）必须带计分方式、净胜两分与封顶，并跟着选择变化。
    func testRuleLineCarriesScoringModeAndFollowsTheSelection() {
        let pickleballBase = defaults(.pickleball)
        var seeded = draft(.pickleball)
        seeded.pickleballUseRallyScoring = true
        seeded.pickleballScoreCap = 15
        var rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: pickleballBase)
        var line = GroupMatchSetupBridge.ruleLine(for: rules)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains(GroupMatchSetupBridge.rallyScoringText), line!)
        XCTAssertTrue(line!.contains(GroupMatchSetupBridge.scoreCapText(15)), line!)

        // 切到发球方得分：同一份摘要要立刻改写，且不再出现「每球得分」。
        seeded.pickleballUseRallyScoring = false
        rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: pickleballBase)
        line = GroupMatchSetupBridge.ruleLine(for: rules)
        XCTAssertTrue(line!.contains(GroupMatchSetupBridge.serverScoringText), line!)
        XCTAssertFalse(line!.contains(GroupMatchSetupBridge.rallyScoringText), line!)
        XCTAssertNotEqual(GroupMatchSetupBridge.rallyScoringText, GroupMatchSetupBridge.serverScoringText)

        // 封顶随目标分与 13/15 选择同步，21 分时显示无封顶。
        seeded.pickleballScoreCap = 13
        rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: pickleballBase)
        XCTAssertTrue(GroupMatchSetupBridge.ruleLine(for: rules)!.contains(GroupMatchSetupBridge.scoreCapText(13)))
        seeded.pickleballTargetScore = 21
        rules = GroupMatchSetupBridge.rules(from: seeded, sport: .pickleball, base: pickleballBase)
        XCTAssertTrue(GroupMatchSetupBridge.ruleLine(for: rules)!.contains(GroupMatchSetupBridge.scoreCapText(nil)))

        // 羽毛球按本机规则推导封顶，摘要始终是「每球得分」。
        for (points, cap) in [(11, 15), (15, 21), (21, 30), (30, nil)] {
            var badminton = draft(.badminton)
            badminton.selectedPointsPerSet = points
            let value = GroupMatchSetupBridge.rules(from: badminton, sport: .badminton, base: defaults(.badminton))
            let text = GroupMatchSetupBridge.ruleLine(for: value)!
            XCTAssertTrue(text.contains(GroupMatchSetupBridge.serverScoringText), text)
            XCTAssertTrue(text.contains(GroupMatchSetupBridge.scoreCapText(cap)), text)
        }

        // 乒乓球摘要同样是每球得分，无封顶。
        let pingpong = GroupMatchSetupBridge.rules(from: draft(.tableTennis), sport: .tableTennis, base: defaults(.tableTennis))
        let pingpongLine = GroupMatchSetupBridge.ruleLine(for: pingpong)!
        XCTAssertTrue(pingpongLine.contains(GroupMatchSetupBridge.serverScoringText), pingpongLine)
        XCTAssertTrue(pingpongLine.contains(GroupMatchSetupBridge.scoreCapText(nil)), pingpongLine)
        var straightPoints = pingpong
        straightPoints.winByTwo = false
        XCTAssertFalse(GroupMatchSetupBridge.ruleLine(for: straightPoints)!.contains(groupText("win_by_two", "Win by two")))

        // 网球常规不给封顶提示。
        XCTAssertNil(GroupMatchSetupBridge.ruleLine(for: GroupMatchSetupBridge.rules(from: draft(.tennis), sport: .tennis, base: defaults(.tennis))))
    }

    /// 小组未暴露的自定义输入也要夹到合法区间，避免提交时才报「规则不合法」。
    func testOutOfRangeInputsAreClampedIntoAValidRule() {
        var seeded = draft(.badminton)
        seeded.selectedPointsPerSet = 0
        seeded.selectedMaxSets = 0
        let rules = GroupMatchSetupBridge.rules(from: seeded, sport: .badminton, base: defaults(.badminton))
        XCTAssertTrue(rules.isValid)
        XCTAssertEqual(rules.pointsToWinSet, 21)
        XCTAssertEqual(rules.maxSets, 3)
    }
}
