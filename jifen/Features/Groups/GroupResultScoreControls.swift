import SwiftUI

struct GroupResultScoreControls: View {
    @Binding var draft: GroupResultEntryDraft
    let rules: GroupMatchRules

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
        let quick = rules.maxSets <= 5 ? rules.overallScores : []
        if !quick.isEmpty {
            HStack(alignment: .top, spacing: Theme.sm) {
                quickColumn(groupText("entry_a_wins", "A wins"), scores: quick.filter { $0.a > $0.b }, tone: .red)
                quickColumn(groupText("entry_b_wins", "B wins"), scores: quick.filter { $0.b > $0.a }, tone: .blue)
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
            }
            ForEach(draft.sets.indices, id: \.self) { index in
                HStack {
                    Text("\(index + 1)").monospacedDigit()
                    GroupResultNumericField(text: $draft.sets[index].a, title: "\(groupText("set_details", "Set details")) \(index + 1) A", identifier: "group_detail_\(index)_A")
                    Text(":")
                    GroupResultNumericField(text: $draft.sets[index].b, title: "\(groupText("set_details", "Set details")) \(index + 1) B", identifier: "group_detail_\(index)_B")
                    if !draft.total.hasInput || draft.hasExcessDetailRows {
                        Button(role: .destructive) { draft.removeSet(at: index, rules: rules) } label: { Image(systemName: "minus.circle") }
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
        .onChange(of: draft.sets) { _, _ in draft.reconcileDetails(rules) }
    }
    private func disclosure(_ title: String, expanded: Binding<Bool>, identifier: String) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: Theme.sm) {
                Text(title).font(.system(size: Theme.fontBody2))
                Spacer(minLength: 8)
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.right").font(.system(size: Theme.fontBody2))
            }
            .padding(.horizontal, Theme.padding).padding(.vertical, Theme.sm).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Theme.textPrimary)
            .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
    private func quickColumn(_ title: String, scores: [GroupScore], tone: Color = Theme.textSecondary) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(title).font(.system(size: Theme.fontCaption, weight: .medium)).foregroundStyle(tone).frame(maxWidth: .infinity)
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                let chosen = draft.total.score == score
                Button { draft.selectTotal(score, rules: rules) } label: {
                    Text("\(score.a) : \(score.b)").font(.system(size: Theme.fontH5, weight: .medium)).monospacedDigit()
                        .padding(Theme.sm).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(chosen ? Theme.primary : Theme.textPrimary)
                        .background(chosen ? Theme.primary.opacity(0.12) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Theme.primary : Color(uiColor: .separator), lineWidth: chosen ? 1.5 : 1))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("group_quick_score_\(score.a)_\(score.b)")
            }
        }
        .padding(Theme.sm).frame(maxWidth: .infinity, alignment: .leading)
        .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
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
            .textFieldStyle(.plain).font(.system(size: Theme.fontBody2)).padding(.horizontal, Theme.sm).frame(minHeight: 44)
            .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
            .accessibilityLabel(title).accessibilityIdentifier(identifier)
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
        VStack(alignment: .leading, spacing: Theme.sm) {
            if !title.isEmpty { Text(title).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.sm)], alignment: .leading, spacing: Theme.sm) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Button { selection = value } label: {
                        Text(label(value)).font(.system(size: Theme.fontBody2)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).padding(Theme.sm).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selection == value ? Theme.primary : Theme.textPrimary)
                            .background(selection == value ? Theme.primary.opacity(0.12) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == value ? Theme.primary : Color(uiColor: .separator), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
        }.padding(Theme.sm).background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
    }
}
