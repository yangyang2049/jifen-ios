import SwiftUI

struct GroupResultScoreControls: View {
    @Binding var draft: GroupResultEntryDraft
    let rules: GroupMatchRules

    var body: some View {
        let quick = rules.maxSets <= 5 ? rules.overallScores : []
        if !quick.isEmpty {
            HStack(alignment: .top, spacing: Theme.sm) {
                quickColumn(groupText("entry_a_wins", "A wins"), scores: quick.filter { $0.a > $0.b })
                quickColumn(groupText("entry_b_wins", "B wins"), scores: quick.filter { $0.b > $0.a })
            }
            let draws = quick.filter { $0.a == $0.b }
            if !draws.isEmpty { quickColumn(groupText("result_draw", "Draw"), scores: draws) }
        }
        disclosure(groupText("entry_manual", "Manual entry"), expanded: $draft.manualExpanded, identifier: "group_result_manual")
        if draft.manualExpanded {
            HStack {
                GroupResultNumericField(text: $draft.total.a, title: groupText("overall_score", "Match score") + " A", identifier: "group_score_A")
                Text(":")
                GroupResultNumericField(text: $draft.total.b, title: groupText("overall_score", "Match score") + " B", identifier: "group_score_B")
            }
        }
        disclosure(groupText("set_details", "Set details"), expanded: $draft.detailsExpanded, identifier: "group_result_sets_toggle")
        if draft.detailsExpanded {
            if draft.total.hasInput {
                Button { draft.clearTotal() } label: {
                    Label(NSLocalizedString("clear", comment: "") + ": " + groupText("overall_score", "Match score"), systemImage: "xmark.circle")
                }.accessibilityIdentifier("group_result_clear_total")
                let orders = GroupResultEntryDraft.orders(rules, total: draft.total.score)
                if orders.count > 1 {
                    GroupRuleChoices(title: groupText("entry_set_winners", "Game winners"), values: orders,
                                     selection: Binding(get: { draft.victoryOrder ?? "" }, set: { draft.selectOrder($0, rules: rules) }), label: { $0.map(String.init).joined(separator: " › ") })
                }
            }
            ForEach(draft.sets.indices, id: \.self) { index in
                HStack {
                    Text("\(index + 1)").monospacedDigit()
                    GroupResultNumericField(text: $draft.sets[index].a, title: "\(groupText("set_details", "Set details")) \(index + 1) A", identifier: "group_detail_\(index)_A")
                    Text(":")
                    GroupResultNumericField(text: $draft.sets[index].b, title: "\(groupText("set_details", "Set details")) \(index + 1) B", identifier: "group_detail_\(index)_B")
                    if !draft.total.hasInput {
                        Button(role: .destructive) { draft.sets.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel(NSLocalizedString("delete", comment: ""))
                    }
                }
            }
            if !draft.total.hasInput {
                Button(groupText("add_set", "Add a game score")) { draft.sets.append(.init()) }
                    .disabled(draft.sets.count >= rules.maxSets).accessibilityIdentifier("group_result_add_set")
            }
            Button { draft.clearDetails() } label: {
                Label(NSLocalizedString("clear", comment: "") + ": " + groupText("set_details", "Set details"), systemImage: "xmark.circle")
            }.accessibilityIdentifier("group_result_clear_details")
        }
        if (draft.total.hasInput || draft.hasDetailInput) && !draft.isValid(rules) {
            GroupNotice(text: groupText("invalid_result", "The result must match the completed match and its rules."))
        }
    }
    private func disclosure(_ title: String, expanded: Binding<Bool>, identifier: String) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.caption)
            }.contentShape(Rectangle())
        }.accessibilityIdentifier(identifier)
    }
    private func quickColumn(_ title: String, scores: [GroupScore]) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                let chosen = draft.total.score == score
                Button { draft.selectTotal(score, rules: rules) } label: {
                    Text("\(score.a):\(score.b)").font(.subheadline).monospacedDigit().frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered).tint(chosen ? Theme.primary : Theme.textSecondary)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("group_quick_score_\(score.a)_\(score.b)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GroupResultNumericField: View {
    @Binding var text: String
    let title: String
    let identifier: String
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $text).keyboardType(.numberPad).multilineTextAlignment(.center)
            .focused($focused)
            .textFieldStyle(.roundedBorder).accessibilityLabel(title).accessibilityIdentifier(identifier)
            .onChange(of: text) { _, value in
                let cleaned = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                if cleaned != value { text = cleaned }
            }
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(NSLocalizedString("done", comment: "")) { focused = false }
                            .accessibilityIdentifier("group_result_keyboard_done")
                    }
                }
            }
    }
}

struct GroupRuleChoices<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Button { selection = value } label: {
                        Text(label(value)).font(.subheadline).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
                    }.buttonStyle(.bordered).tint(selection == value ? Theme.primary : Theme.textSecondary)
                        .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
        }.padding(10).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
