import SwiftUI


// MARK: - CommonNameSelectorDialog
// Sheet to pick a common team/player name (aligned with HarmonyOS common-name picker)

struct CommonNameSelectorDialog: View {
    @Environment(\.dismiss) var dismiss
    var nameType: NameType
    var onSelect: (String) -> Void

    private let commonNamesManager = CommonNamesManager.shared

    private var names: [String] {
        commonNamesManager.getNames(type: nameType)
    }

    var body: some View {
        NavigationView {
            Group {
                if names.isEmpty {
                    VStack(spacing: Theme.sm) {
                        EmptyStateCourtIcon(size: 44)
                        Text(NSLocalizedString("common_names_empty", value: "暂无常用名称", comment: ""))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textSecondary)
                        Text(NSLocalizedString("common_names_empty_hint", value: "在「设置」-「数据」-「常用名称管理」中添加队伍或选手名称，下次即可在此快速选择。", comment: "Hint when no common names"))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.md)
                            .padding(.top, Theme.xs)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(names, id: \.self) { name in
                        Button(action: {
                            onSelect(name)
                            dismiss()
                        }) {
                            HStack {
                                Text(name)
                                    .font(.system(size: 16))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.dialogSurfaceBackground)
            .navigationTitle(NSLocalizedString("common_names_title", value: "常用名称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        // Scoreboards use very large display fonts. A presented sheet inherits
        // the environment from its presenter, so reset it at the sheet root to
        // keep all system-provided navigation text at a normal dialog size.
        .environment(\.font, .body)
        .presentationBackground(Theme.dialogSurfaceBackground)
    }
}

extension View {
    func settingsLabelStyle() -> some View {
        font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct InlineCommonNameTextField: View {
    let placeholder: String
    @Binding var text: String
    var onChevronTap: () -> Void
    var font: Font = .system(size: 16)
    var textColor: Color = Theme.textPrimary
    var iconColor: Color = Theme.textSecondary
    var backgroundColor: Color = Theme.dialogControlBackground
    var height: CGFloat = 44
    var cornerRadius: CGFloat = Theme.sm

    var body: some View {
        HStack(spacing: Theme.xs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundColor(textColor)

            Button(action: onChevronTap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Theme.sm)
        .padding(.trailing, Theme.xs)
        .frame(height: height)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
    }
}

