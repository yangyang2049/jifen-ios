import SwiftUI

struct CommonDataSectionView: View {
    let onNamesTapped: () -> Void
    let onPlacesTapped: () -> Void

    var body: some View {
        // Measure the actual localized labels. Use full-width rows when two
        // cards would compress them, regardless of the selected language.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.gridSpacing) {
                entries(keepLabelsOnOneLine: true)
            }
            VStack(spacing: Theme.gridSpacing) {
                entries(keepLabelsOnOneLine: false)
            }
        }
    }

    @ViewBuilder
    private func entries(keepLabelsOnOneLine: Bool) -> some View {
        entry(
            title: NSLocalizedString("common_names_title", value: "已保存名称", comment: ""),
            subtitle: NSLocalizedString("home_common_names_desc", value: "队名、球员名", comment: ""),
            keepLabelsOnOneLine: keepLabelsOnOneLine,
            systemImage: "person.2",
            tint: Theme.accentColor,
            lightIconBackgroundOpacity: 0.16,
            action: onNamesTapped
        )
        entry(
            title: NSLocalizedString("common_places_title", value: "已保存地点", comment: ""),
            subtitle: NSLocalizedString("home_common_places_desc", value: "球馆、球场、地点", comment: ""),
            keepLabelsOnOneLine: keepLabelsOnOneLine,
            systemImage: "mappin.and.ellipse",
            tint: Color(hex: "4F46E5"),
            lightIconBackgroundOpacity: 0.14,
            action: onPlacesTapped
        )
    }

    private func entry(
        title: String,
        subtitle: String,
        keepLabelsOnOneLine: Bool,
        systemImage: String,
        tint: Color,
        lightIconBackgroundOpacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        Theme.tintedFill(tint, lightAlpha: lightIconBackgroundOpacity, darkAlpha: 0.30)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.homeNeutralCardTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.homeNeutralCardTextSecondary)
                }
                .fixedSize(horizontal: keepLabelsOnOneLine, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.compactCardPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.homeNeutralCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}
