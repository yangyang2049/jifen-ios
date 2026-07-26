import SwiftUI

struct WatchResumeGameBar: View {
    let session: WatchResumeSession
    let onResume: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onResume) {
                HStack(spacing: 8) {
                    Text(session.emoji)
                        .font(.system(size: 22))
                        .frame(width: 30, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.scoreLine)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WatchTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 2) {
                            Text(NSLocalizedString(
                                "watch_continue_match",
                                value: "继续比赛",
                                comment: ""
                            ))
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
            .accessibilityLabel(NSLocalizedString(
                "watch_continue_match",
                value: "继续比赛",
                comment: ""
            ))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WatchTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString(
                "watch_resume_discard",
                value: "放弃未完成比赛",
                comment: ""
            ))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.resumeBar)
        .clipShape(RoundedRectangle(cornerRadius: WatchMetrics.pillRadius, style: .continuous))
    }
}
