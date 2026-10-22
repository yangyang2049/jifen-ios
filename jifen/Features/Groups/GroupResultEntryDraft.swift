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

    var hasDetailInput: Bool { sets.contains(where: \.hasInput) }
    var hasExcessDetailRows: Bool { total.score.map { sets.count > $0.a + $0.b } ?? false }
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
        }
        return rules.validResult(score, sets: details)
    }
    mutating func selectTotal(_ value: GroupScore, rules: GroupMatchRules) {
        let next = Points(a: String(value.a), b: String(value.b))
        guard next != total else { return }
        total = next
        reconcileDetails(rules)
    }
    mutating func clearTotal() { total = Points() }
    mutating func clearDetails() { sets = []; detailsExpanded = false }
    mutating func reconcileDetails(_ rules: GroupMatchRules) {
        guard detailsExpanded, let score = total.score, rules.validResult(score, sets: nil) else { return }
        let count = score.a + score.b
        // Append blank rows on growth and reclaim only unused trailing placeholders on shrink.
        // Entered scores remain until the user explicitly removes a row or clears its contents.
        while sets.count < count { sets.append(.init()) }
        while sets.count > count, sets.last?.hasInput == false { sets.removeLast() }
    }
    mutating func removeSet(at index: Int, rules: GroupMatchRules) {
        guard sets.indices.contains(index), !total.hasInput || hasExcessDetailRows else { return }
        sets.remove(at: index)
        reconcileDetails(rules)
    }
}
