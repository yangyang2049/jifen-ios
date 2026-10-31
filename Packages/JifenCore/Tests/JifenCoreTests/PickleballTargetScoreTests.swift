import Foundation
import Testing
@testable import ScoreCore

/// 安卓 3.4 把匹克球目标分放开到 1–99（鸿蒙同语义），iOS 侧在 ScoreCore
/// 补 `normalizePickleballTargetScore` 并让 `RallyRuleSet.pickleball` 直接收口。
@Test func pickleballTargetScoreAcceptsOneToNinetyNine() {
    for target in [1, 7, 11, 15, 21, 42, 99] {
        #expect(RallyRuleSet.normalizePickleballTargetScore(target) == target)
        #expect(RallyRuleSet.pickleball(targetScore: target).pointsToWinSet == target)
        #expect(RallyRuleSet.pickleball(targetScore: target).sportProfile == .pickleball)
    }
}

@Test func pickleballTargetScoreFallsBackToElevenOnlyWhenOutOfRange() {
    #expect(RallyRuleSet.normalizePickleballTargetScore(nil) == 11)
    #expect(RallyRuleSet.normalizePickleballTargetScore(0) == 11)
    #expect(RallyRuleSet.normalizePickleballTargetScore(-3) == 11)
    #expect(RallyRuleSet.normalizePickleballTargetScore(100) == 11)
    #expect(RallyRuleSet.pickleball(maxSets: 3).pointsToWinSet == 11)
    #expect(RallyRuleSet.pickleball(targetScore: 250).pointsToWinSet == 11)
    #expect(RallyRuleSet.pickleballTargetScoreRange == 1...99)
}

@Test func pickleballTargetScoreKeepsLegacyDefaultsAndSetCount() {
    let legacy = RallyRuleSet.pickleball(maxSets: 3, matchCompletionMode: .bestOf)
    #expect(legacy.pointsToWinSet == 11)
    #expect(legacy.maxSets == 3)
    #expect(legacy.pointCap == nil)
    #expect(legacy.useRallyScoring == false)
    #expect(legacy.nextSetServerModel == .opening)

    let single = RallyRuleSet.pickleball(maxSets: 1, targetScore: 15, matchCompletionMode: .playAll)
    #expect(single.pointsToWinSet == 15)
    #expect(single.maxSets == 1)
    #expect(single.matchCompletionMode == .playAll)
}

@Test func pickleballCustomTargetDrivesSetCompletionAtAnyValue() {
    let reducer = RallyMatchReducer()
    for target in [5, 11, 13, 21, 33] {
        var state = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: RallyRuleSet.pickleball(maxSets: 1, targetScore: target)
        )
        for index in 0..<target {
            state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(index)).state
        }
        #expect(state.leftPoints == target)
        #expect(state.leftSets == 1)
        #expect(state.finished)
    }
}