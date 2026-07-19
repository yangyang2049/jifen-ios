import SwiftUI

/// Shared chrome for common-names / common-places management (aligned with HarmonyOS + RecordsTab menu).
enum CommonDataManagementChrome {
    static let listSpacing: CGFloat = 12
    static let floatingButtonHeight: CGFloat = 48
}

struct CommonDataSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .foregroundColor(Theme.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.md)
        .frame(height: 40)
        .background(Theme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct CommonDataCategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? .white : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selected ? Theme.accentColor : Theme.controlBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CommonDataFloatingAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: CommonDataManagementChrome.floatingButtonHeight)
                .background(Theme.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.md)
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.md)
        .background(
            Theme.backgroundColor
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct CommonDataBatchEditBar: View {
    let allSelected: Bool
    let selectedCount: Int
    let onToggleSelectAll: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleSelectAll) {
                Text(allSelected
                      ? NSLocalizedString("records_batch_deselect_all", value: "取消全选", comment: "")
                      : NSLocalizedString("records_batch_select_all", value: "全选", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accentColor)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: NSLocalizedString("records_batch_selected_n", value: "已选 %d 条", comment: ""), selectedCount))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button(action: onDelete) {
                Text(NSLocalizedString("delete", value: "删除", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(selectedCount > 0 ? Theme.destructiveText : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.md)
        .frame(height: 52)
        .background(Theme.cardBackground)
    }
}

struct CommonDataListCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func commonDataListCardStyle() -> some View {
        modifier(CommonDataListCardBackground())
    }
}
