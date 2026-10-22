import SwiftUI

/// Group text roles reuse the app's existing type scale; page/navigation titles stay native.
enum GroupTypography {
    static let section = Font.system(size: Theme.fontBody1, weight: .semibold)
    static let cardTitle = Font.system(size: Theme.fontBody1, weight: .medium)
    static let groupTitle = Font.system(size: Theme.fontH5, weight: .semibold)
    static let body = Font.system(size: Theme.fontBody2)
    static let input = Font.system(size: Theme.fontBody1)
    static let caption = Font.system(size: Theme.fontCaption)
}

enum GroupFieldSize {
    static let control: CGFloat = 48
    static let note: CGFloat = 100
    static let multipleNames: CGFloat = 140
}

/// Group fields use white surfaces in light mode and retain their existing dark palette.
enum GroupEditorColors {
    static let insetInput = Theme.dialogControlBackground
    static let avatar = Color(uiColor: .systemGray5)
    static let control = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemFill : .white
    })
    static let input = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1) : .white
    })
}

/// Shared field rhythm for the group editors; headings describe fields, not extra sections.
struct GroupAlignedField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(title).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GroupAlignedInput: ViewModifier {
    var minHeight: CGFloat
    var alignment: Alignment
    var font: Font
    func body(content: Content) -> some View {
        content.font(font).tint(Theme.primary)
            .padding(.horizontal, Theme.padding).padding(.vertical, Theme.spacing)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.divider.opacity(0.2), lineWidth: 0.5))
    }
}

extension View {
    func groupAlignedInput(minHeight: CGFloat = GroupFieldSize.control, alignment: Alignment = .leading, font: Font = GroupTypography.input) -> some View {
        modifier(GroupAlignedInput(minHeight: minHeight, alignment: alignment, font: font))
    }
}

struct GroupAlignedActionStyle: ButtonStyle {
    var secondary = false
    var destructive = false
    var secondaryForeground: Color? = nil
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: Theme.fontBody2, weight: .semibold))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(destructive ? Theme.destructiveText : secondary ? (secondaryForeground ?? Theme.primary) : Theme.textOnPrimary)
            .background(secondary || destructive ? GroupEditorColors.control : Theme.primary, in: RoundedRectangle(cornerRadius: 24))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

struct GroupAlignedFooter<Content: View>: View {
    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Theme.spacing) { content }
            .padding(.horizontal, Theme.padding).padding(.top, topPadding).padding(.bottom, bottomPadding)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
    }
}

struct GroupAlignedPolicyChoice: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: String
    var includesClosed = false
    private var values: [String] { includesClosed ? ["open", "approval", "closed"] : ["open", "approval"] }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.xs) { choices }
            VStack(spacing: Theme.xs) { choices }
        }.padding(Theme.xs).background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var choices: some View {
        ForEach(values, id: \.self) { value in
            Button { selection = value } label: {
                Text(groupText(value, value)).font(.system(size: Theme.fontBody2))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == value ? (colorScheme == .light ? Theme.textOnPrimary : Theme.primary) : Theme.textSecondary)
                    .background(selection == value ? (colorScheme == .light ? Theme.primary : Theme.cardBackground) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
        }
    }
}
