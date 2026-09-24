import SwiftUI
import UIKit

struct CommonDataSectionView: View {
    let onNamesTapped: () -> Void
    let onPlacesTapped: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let namesTitle = NSLocalizedString("common_names_title", value: "常用名称", comment: "")
            let placesTitle = NSLocalizedString("common_places_title", value: "常用地点", comment: "")
            let cardTextWidth = (geometry.size.width - Theme.gridSpacing) / 2
                - 2 * Theme.compactCardPadding - 36 - Theme.sm
            let titleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let titleWidth = max(
                (namesTitle as NSString).size(withAttributes: [.font: titleFont]).width,
                (placesTitle as NSString).size(withAttributes: [.font: titleFont]).width
            )
            let compactEnglish = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
                && cardTextWidth < titleWidth + 4

            HStack(spacing: Theme.gridSpacing) {
                entry(
                    title: namesTitle,
                    subtitle: compactEnglish ? nil : NSLocalizedString("home_common_names_desc", value: "队名、球员名", comment: ""),
                    compactTitle: compactEnglish,
                    systemImage: "person.2",
                    tint: Theme.accentColor,
                    lightIconBackgroundOpacity: 0.16,
                    action: onNamesTapped
                )
                entry(
                    title: placesTitle,
                    subtitle: compactEnglish ? nil : NSLocalizedString("home_common_places_desc", value: "球馆、球场、地点", comment: ""),
                    compactTitle: compactEnglish,
                    systemImage: "mappin.and.ellipse",
                    tint: Color(hex: "4F46E5"),
                    lightIconBackgroundOpacity: 0.14,
                    action: onPlacesTapped
                )
            }
        }
        .frame(height: 76)
    }

    private func entry(
        title: String,
        subtitle: String?,
        compactTitle: Bool,
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
                        .lineLimit(compactTitle ? 2 : 1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.homeNeutralCardTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.compactCardPadding)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.homeNeutralCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
