import ScoreCore
import SwiftUI


// MARK: - CommonNameSelectorDialog
// Sheet to pick a common team/player name (aligned with HarmonyOS common-name picker)

struct CommonNameSelectorDialog: View {
    @Environment(\.dismiss) var dismiss
    var nameType: NameType
    var onSelect: (String) -> Void
    var unavailablePeople: Set<ParticipantPersonRef> = []
    var onParticipantSelect: ((ParticipantSelection) -> Void)?

    init(nameType: NameType, unavailablePeople: Set<ParticipantPersonRef> = [],
         onParticipantSelect: ((ParticipantSelection) -> Void)? = nil,
         onSelect: @escaping (String) -> Void) {
        self.nameType = nameType; self.unavailablePeople = unavailablePeople
        self.onParticipantSelect = onParticipantSelect; self.onSelect = onSelect
    }

    @State private var identity = ParticipantIdentityStore.shared

    private let commonNamesManager = CommonNamesManager.shared

    private var names: [String] {
        commonNamesManager.getNames(type: nameType)
    }
    private var providesIdentity: Bool { nameType == .player && onParticipantSelect != nil }

    var body: some View {
        NavigationView {
            Group {
                if names.isEmpty && !providesIdentity {
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
                    List {
                        if providesIdentity {
                            Section {
                                ForEach(identity.pickerSelections, id: \.name) { selection in
                                    Button {
                                        onSelect(selection.name); onParticipantSelect?(selection); dismiss()
                                    } label: {
                                        HStack(spacing: 10) {
                                            IdentitySelfAvatar(size: 32)
                                            Text(selection.name); Text(identityText("self", "我")).font(.caption).foregroundStyle(Theme.accentColor)
                                            Spacer()
                                        }.frame(minHeight: 44)
                                    }.disabled(selection.personRef.map { unavailablePeople.contains($0) } ?? false)
                                }
                            } footer: {
                                if unavailablePeople.contains(identity.person) {
                                    Text(identityText("already_playing", "你已在其他位置参赛"))
                                }
                            }
                        }
                        ForEach(names.filter { name in !providesIdentity || !identity.pickerSelections.contains(where: { ParticipantIdentityRules.normalizedName($0.name) == ParticipantIdentityRules.normalizedName(name) }) }, id: \.self) { name in
                        Button(action: {
                            onSelect(name)
                            onParticipantSelect?(.init(name: name))
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
                        NavigationLink(identityText("manage_common_names", "管理常用名称")) {
                            CommonNamesManagementView()
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
    }
}

extension View {
    /// Setup 对话框区块小标题：14pt、常规字重、次要色，包含换行文字的居中对齐。
    func settingsLabelStyle() -> some View {
        font(.system(size: 14, weight: .regular))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
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
    var leadingLabel: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let leadingLabel {
                Text(leadingLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: height)
                    .background(Theme.primary.opacity(0.5))
            }

            HStack(spacing: Theme.xs) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundColor(textColor)

                // 对齐安卓 NameInput：尾部箭头是铺满字段高度的 44pt 热区，而不是只包住 24pt 图标。
                // 图标向右偏移 8.4pt，补偿原图右侧透明区，让可见右距约为 12pt。
                Button(action: onChevronTap) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                        .offset(x: 8.4)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common_names_title", value: "Saved Names", comment: ""))
            }
            .padding(.leading, Theme.sm)
        }
        // 有尾部操作时由它的热区覆盖到右边缘，不再额外留白（对齐安卓 SetupNameField）。
        .padding(.trailing, 0)
        .frame(height: height)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
    }
}
