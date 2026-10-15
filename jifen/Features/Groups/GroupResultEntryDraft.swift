import Foundation

/// Empty input is distinct from zero. This state is local to the open form, never persisted.
nonisolated struct GroupResultEntryDraft {
    struct Points: Equatable {
        var a = ""
        var b = ""
        var hasInput: Bool { !a.isEmpty || !b.isEmpty }
        var score: GroupScore? {
            guard let a = Self.number(a), let b = Self.number(b) else { return nil }
            return .init(a: a, b: b)
        }
        private static func number(_ text: String) -> Int? {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text), value <= 9999 else { return nil }
            return value
        }
    }
    var total = Points()
    var sets: [Points] = []
    var manualExpanded = false
    var detailsExpanded = false
    var victoryOrder: String?

    var hasDetailInput: Bool { sets.contains(where: \.hasInput) }
    var details: [GroupScore]? { hasDetailInput ? sets.compactMap(\.score) : nil }
    var score: GroupScore? {
        if total.hasInput { return total.score }
        guard hasDetailInput, sets.allSatisfy({ $0.score != nil }) else { return nil }
        return .init(a: sets.filter { $0.score!.a > $0.score!.b }.count,
                     b: sets.filter { $0.score!.b > $0.score!.a }.count)
    }
    func isValid(_ rules: GroupMatchRules) -> Bool {
        guard let score else { return false }
        if hasDetailInput {
            guard sets.allSatisfy({ $0.score != nil }) else { return false }
            if let victoryOrder, total.hasInput {
                let actual = sets.map { $0.score!.a > $0.score!.b ? "A" : "B" }.joined()
                guard actual == victoryOrder else { return false }
            }
        }
        return rules.validResult(score, sets: details)
    }
    mutating func selectTotal(_ value: GroupScore, rules: GroupMatchRules) {
        let next = Points(a: String(value.a), b: String(value.b))
        guard next != total else { return }
        total = next
        reconcileDetails(rules)
    }
    mutating func clearTotal() { total = Points(); victoryOrder = nil }
    mutating func clearDetails() { sets = []; victoryOrder = nil; detailsExpanded = false }
    mutating func reconcileDetails(_ rules: GroupMatchRules) {
        guard detailsExpanded, let score = total.score, rules.validResult(score, sets: nil) else { return }
        if hasDetailInput, sets.allSatisfy({ $0.score != nil }), rules.validResult(score, sets: details) {
            victoryOrder = sets.map { $0.score!.a > $0.score!.b ? "A" : "B" }.joined()
            return
        }
        let orders = Self.orders(rules, total: score)
        if let victoryOrder, orders.contains(victoryOrder), sets.count == score.a + score.b { return }
        victoryOrder = orders.count == 1 ? orders.first : nil
        // Retain entered points when changing a total; validation explains any mismatch.
        if !hasDetailInput {
            sets = Array(repeating: Points(), count: score.a + score.b)
        }
    }
    mutating func selectOrder(_ order: String, rules: GroupMatchRules) {
        guard Self.orders(rules, total: total.score).contains(order) else { return }
        let previous = Array(victoryOrder ?? "")
        let target = rules.sport == .tennis ? (rules.setScoringMode == "tiebreak_only" ? rules.tieBreakPoints : rules.gamesPerSet) : rules.pointsToWinSet
        sets = Array(order).enumerated().map { index, side in
            if index < previous.count, previous[index] == side, index < sets.count { return sets[index] }
            return side == "A" ? Points(a: String(target)) : Points(b: String(target))
        }
        victoryOrder = order
    }
    static func orders(_ rules: GroupMatchRules, total: GroupScore?) -> [String] {
        guard rules.maxSets <= 5, let total, rules.validResult(total, sets: nil) else { return [] }
        var result: [String] = []
        func visit(_ order: String, _ a: Int, _ b: Int) {
            if a == total.a && b == total.b { result.append(order); return }
            if rules.matchCompletionMode == "best_of", max(a, b) >= rules.maxSets / 2 + 1 { return }
            if a < total.a { visit(order + "A", a + 1, b) }
            if b < total.b { visit(order + "B", a, b + 1) }
        }
        visit("", 0, 0)
        return result
    }
}
