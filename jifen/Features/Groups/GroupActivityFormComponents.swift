import SwiftUI

/// Compact controls shared only by the activity, lineup and registration editors.
struct GroupActivitySurface<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.padding) { content }
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GroupActivityChoices<Value: Hashable>: View {
    @Binding var selection: Value
    var values: [Value]
    var title: (Value) -> String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { options }
            VStack(spacing: 0) { options }
        }
        .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider.opacity(0.45), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var options: some View {
        ForEach(values, id: \.self) { value in
            Button { selection = value } label: {
                Text(title(value)).font(.system(size: Theme.fontBody2, weight: .medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.sm).padding(.vertical, Theme.sm)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == value ? Theme.textOnPrimary : Theme.textPrimary)
                    .background(selection == value ? Theme.primary : .clear)
            }.buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
        }
    }
}

struct GroupActivityDateField: View {
    var title = ""
    @Binding var selection: Date
    var components: DatePickerComponents = [.date, .hourAndMinute]
    var minimum: Date? = nil
    var maximum: Date? = nil
    var compact = false
    var allowsTimeSelection = false
    var initiallySelectsTime = false
    var summary: String? = nil
    var inlineTitle = false
    private var offersTimeSelection: Bool { allowsTimeSelection || components == [.date, .hourAndMinute] }
    @State private var selectingTime = false
    private var pickerComponents: DatePickerComponents { offersTimeSelection ? (selectingTime ? .hourAndMinute : .date) : components }
    @State private var presented = false
    @State private var pending = Date()

    private var value: String {
        if let summary { return summary }
        if components == .date { return selection.formatted(date: .numeric, time: .omitted) }
        if components == .hourAndMinute { return selection.formatted(date: .omitted, time: .shortened) }
        return selection.formatted(date: .abbreviated, time: .shortened)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            if !inlineTitle && !title.isEmpty { Text(title).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary) }
            Button { pending = selection; selectingTime = initiallySelectsTime || components == .hourAndMinute; presented = true } label: {
                HStack(spacing: Theme.sm) {
                    if inlineTitle {
                        Text(title).font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 4)
                    }
                    Text(value).lineLimit(1).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    if !inlineTitle { Spacer(minLength: 4) }
                    Image(systemName: "chevron.right").font(.system(size: Theme.fontCaption))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(GroupTypography.input).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.padding).padding(.vertical, Theme.sm)
                .frame(maxWidth: .infinity, minHeight: compact ? 44 : 48, alignment: .leading)
                .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityLabel(title.isEmpty ? value : title)
        }
        .sheet(isPresented: $presented) {
            NavigationStack {
                VStack(spacing: Theme.spacing) {
                    if offersTimeSelection {
                        Picker(title, selection: $selectingTime) {
                            Text(NSLocalizedString("date", value: "Date", comment: "")).tag(false)
                            Text(NSLocalizedString("time_filter", value: "Time", comment: "")).tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("group_date_time_mode")
                    }
                    if pickerComponents == .hourAndMinute { picker.datePickerStyle(.wheel) }
                    else { picker.datePickerStyle(.graphical) }
                    Spacer(minLength: 0)
                }
                .labelsHidden().tint(Theme.primary).padding(Theme.padding)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ModalCloseButton { presented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("done", value: "Done", comment: "")) {
                            selection = min(max(pending, minimum ?? .distantPast), maximum ?? .distantFuture)
                            presented = false
                        }
                    }
                }
            }.presentationDetents(offersTimeSelection ? [.height(560), .large] : [.medium, .large])
        }
    }
    @ViewBuilder private var picker: some View {
        if let minimum, let maximum {
            DatePicker(title, selection: $pending, in: min(minimum, maximum)...maximum, displayedComponents: pickerComponents)
        } else if let minimum {
            DatePicker(title, selection: $pending, in: minimum..., displayedComponents: pickerComponents)
        } else if let maximum {
            DatePicker(title, selection: $pending, in: ...maximum, displayedComponents: pickerComponents)
        } else {
            DatePicker(title, selection: $pending, displayedComponents: pickerComponents)
        }
    }
}

struct GroupActivityLineupHeading: View {
    var count: Int
    var body: some View {
        HStack(spacing: Theme.sm) {
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.primary).frame(width: 3, height: 14)
            Text(groupText("activity_lineup_section_matches", "Match arrangement"))
                .font(.system(size: Theme.fontBody1, weight: .medium))
            Spacer()
            Text(String(format: groupText("activity_lineup_match_count", "%d matches"), count))
                .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
        }
    }
}
