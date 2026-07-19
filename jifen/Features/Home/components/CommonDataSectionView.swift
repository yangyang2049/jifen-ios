import SwiftUI

struct CommonDataSectionView: View {
    let onNamesTapped: () -> Void
    let onPlacesTapped: () -> Void

    var body: some View {
        HStack(spacing: Theme.md) {
            entry(
                title: NSLocalizedString("common_names_title", value: "常用名称", comment: ""),
                subtitle: NSLocalizedString("home_common_names_desc", value: "队名、球员名", comment: ""),
                systemImage: "person.2",
                tint: Color(hex: "248A3D"),
                action: onNamesTapped
            )
            entry(
                title: NSLocalizedString("common_places_title", value: "常用地点", comment: ""),
                subtitle: NSLocalizedString("home_common_places_desc", value: "球馆、球场、地点", comment: ""),
                systemImage: "mappin.and.ellipse",
                tint: Color(hex: "4F46E5"),
                action: onPlacesTapped
            )
        }
    }

    private func entry(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Theme.homeCardTextPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.homeCardTextPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.homeCardTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background {
                LinearGradient(
                    colors: [tint.opacity(0.96), tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
