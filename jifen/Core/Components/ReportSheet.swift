import SwiftUI

nonisolated struct ReportReasonOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// Reporting APIs use different length contracts. Keep their counting and
/// truncation policy explicit while sharing the same form presentation.
nonisolated enum ReportDetailLength: Equatable, Sendable {
    case characters
    case utf16

    func count(_ text: String) -> Int {
        self == .characters ? text.count : text.utf16.count
    }

    func limited(_ text: String, maximum: Int) -> String {
        if self == .characters { return String(text.prefix(maximum)) }
        var result = ""
        var length = 0
        for character in text {
            let next = String(character).utf16.count
            guard length + next <= maximum else { break }
            result.append(character)
            length += next
        }
        return result
    }
}

/// Shared sheet for group and feedback reports. Callers own permissions,
/// report status, API requests and successful dismissal.
struct ReportSheet: View {
    let title: String
    let reasonTitle: String
    let detailPlaceholder: String
    let submitTitle: String
    let reasons: [ReportReasonOption]
    @Binding var selectedReasonID: String?
    @Binding var detail: String
    var isSubmitting = false
    var canSubmit = true
    var errorMessage: String?
    var statusTitle: String?
    var statusDetail: String?
    var detailLimit = 500
    var detailLength = ReportDetailLength.characters
    var accessibilityPrefix = "report"
    var usesTopAction = false
    var receiptMode = false
    var extraContent: AnyView? = nil
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @State private var contentHeight: CGFloat = 0

    private var compactHeight: CGFloat {
        let estimatedBody = CGFloat(reasons.count) * 48 + 138 + (statusTitle == nil ? 0 : 110)
        return max(320, ceil((contentHeight > 0 ? contentHeight : estimatedBody) + 56 + (usesTopAction ? 0 : 80)))
    }

    private var submitEnabled: Bool {
        canSubmit && !isSubmitting && detailLength.count(detail) <= detailLimit
            && reasons.contains { $0.id == selectedReasonID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let statusTitle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(statusTitle).font(.subheadline.weight(.semibold))
                            if let statusDetail, !statusDetail.isEmpty {
                                Text(statusDetail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier(accessibilityPrefix + "_status")
                    }

                    if !receiptMode {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(reasons) { reason in
                            reasonRow(reason)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(reasonTitle)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField(detailPlaceholder, text: $detail, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .lineLimit(3...8)
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                            .background(Theme.inputFieldBackground, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier(accessibilityPrefix + "_detail")
                    }

                    } else if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    if let extraContent { extraContent }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.destructiveText)
                            .accessibilityIdentifier(accessibilityPrefix + "_error")
                    }
                }
                .padding(16)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(contentHeight - height) > 1 { contentHeight = height }
                }
                .disabled(isSubmitting)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.backgroundColor)
            .safeAreaInset(edge: .bottom, spacing: 0) { if !usesTopAction { actions } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton(action: onCancel).disabled(isSubmitting)
                }
                if usesTopAction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(submitTitle, action: onSubmit)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(submitEnabled ? Theme.primary : Theme.textSecondary)
                            .disabled(!submitEnabled).accessibilityIdentifier(accessibilityPrefix + "_submit")
                    }
                }
            }
        }
        .tint(Theme.primary)
        .presentationDetents(extraContent == nil ? [.height(compactHeight), .large] : [.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .onChange(of: detail) { _, value in
            let limited = detailLength.limited(value, maximum: detailLimit)
            if limited != value { detail = limited }
        }
    }

    private func reasonRow(_ reason: ReportReasonOption) -> some View {
        let selected = selectedReasonID == reason.id
        return Button { selectedReasonID = reason.id } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(selected ? Theme.primary : Theme.textSecondary)
                Text(reason.title).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityPrefix + "_reason_" + reason.id)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { cancelButton; submitButton }
            VStack(spacing: 10) { submitButton; cancelButton }
        }
        .padding(16)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(Theme.backgroundColor)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(receiptMode ? NSLocalizedString("group_report_close", value: "Close", comment: "") : NSLocalizedString("cancel", value: "取消", comment: ""))
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.inputFieldBackground, in: Capsule())
        }
        .buttonStyle(.plain).disabled(isSubmitting)
        .accessibilityIdentifier(accessibilityPrefix + "_cancel")
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(Theme.textOnPrimary) }
                Text(isSubmitting
                     ? NSLocalizedString("feedback_report_submitting", value: "提交中…", comment: "")
                     : submitTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textOnPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(.plain).disabled(!submitEnabled).opacity(submitEnabled || isSubmitting ? 1 : 0.5)
        .accessibilityIdentifier(accessibilityPrefix + "_submit")
    }
}
