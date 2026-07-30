import SwiftUI

struct CommonDataSectionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onNamesTapped: () -> Void
    let onPlacesTapped: () -> Void

    var body: some View {
        HStack(spacing: Theme.gridSpacing) {
            entry(
                title: NSLocalizedString("common_names_title", value: "常用名称", comment: ""),
                subtitle: NSLocalizedString("home_common_names_desc", value: "队名、球员名", comment: ""),
                systemImage: "person.2",
                tint: Theme.accentColor,
                lightIconBackgroundOpacity: 0.16,
                action: onNamesTapped
            )
            entry(
                title: NSLocalizedString("common_places_title", value: "常用地点", comment: ""),
                subtitle: NSLocalizedString("home_common_places_desc", value: "球馆、球场、地点", comment: ""),
                systemImage: "mappin.and.ellipse",
                tint: Color(hex: "4F46E5"),
                lightIconBackgroundOpacity: 0.14,
                action: onPlacesTapped
            )
        }
    }

    private func entry(
        title: String,
        subtitle: String,
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
                        tint.opacity(colorScheme == .dark ? 0.30 : lightIconBackgroundOpacity)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.homeNeutralCardTextPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.homeNeutralCardTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.compactCardPadding)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.homeNeutralCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
