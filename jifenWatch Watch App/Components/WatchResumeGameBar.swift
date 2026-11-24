import SwiftUI

struct WatchResumeGameBar: View {
    let session: WatchResumeSession
    let onResume: () -> Void
    let onClose: () -> Void

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        HStack(spacing: compact ? 5 : 8) {
            Button(action: onResume) {
                HStack(spacing: compact ? 5 : 8) {
                    if let gameType = session.payload.gameType {
                        WatchCatalogIcon(gameType: gameType, size: compact ? 18 : 20)
                            .frame(width: compact ? 22 : 30, height: compact ? 32 : 36)
                    } else {
                        Text(session.emoji)
                            .font(.system(size: compact ? 19 : 22))
                            .frame(width: compact ? 22 : 30, height: compact ? 32 : 36)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.scoreLine)
                            .font(.system(size: compact ? 15 : 18, weight: .bold))
                            .foregroundStyle(WatchTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        HStack(spacing: 2) {
                            Text(session.resumeActionTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WatchTheme.primaryText.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.resumeActionTitle)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(WatchTheme.primaryText)
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.discardActionTitle)
        }
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, compact ? 5 : 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.resumeBar)
        .clipShape(RoundedRectangle(cornerRadius: WatchMetrics.pillRadius, style: .continuous))
    }
}
