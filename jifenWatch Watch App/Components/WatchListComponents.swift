import SwiftUI

struct WatchListHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(WatchTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: WatchMetrics.navBarHeight)
    }
}

struct WatchPillRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var trailingIcon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(WatchTheme.primaryText)
                    .lineLimit(trailingIcon == nil ? 1 : 2)
                    .minimumScaleFactor(trailingIcon == nil ? 0.75 : 1)
                    .multilineTextAlignment(.leading)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(WatchTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            .padding(.trailing, trailingIcon == nil ? 0 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingIcon {
                Text(trailingIcon)
                    .font(.system(size: 14))
            }
        }
        .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.listItemBackground)
        .cornerRadius(WatchMetrics.pillRadius)
    }
}

struct WatchPillButton: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WatchPillRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

struct WatchToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
    }
}
