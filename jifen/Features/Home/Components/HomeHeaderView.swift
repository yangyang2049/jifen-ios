import SwiftUI

struct HomeHeaderView: View {
    let headerDate: String
    var onCastTapped: () -> Void = {}
    @ObservedObject private var externalDisplay = ExternalDisplayCoordinator.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("app_name", comment: "App Name"))
                    .font(.system(size: Theme.fontH4, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.bottom, 2)
                    .lineLimit(1)

                Text(headerDate)
                    .font(.system(size: Theme.fontCaption, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            Button(action: onCastTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(externalDisplay.status == .dedicated
                         ? NSLocalizedString("cast_active", value: "投屏中", comment: "")
                         : NSLocalizedString("cast_title", value: "投屏", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(externalDisplay.status == .dedicated ? Color.white : Theme.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    externalDisplay.status == .dedicated
                        ? Theme.primary
                        : Theme.primary.opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_cast_button")
            .accessibilityLabel(NSLocalizedString("cast_title", value: "投屏", comment: ""))
        }
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor)
    }
}
