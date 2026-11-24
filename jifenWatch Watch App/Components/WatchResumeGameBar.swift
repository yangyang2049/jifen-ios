import SwiftUI

struct WatchResumeGameBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmationDeadline: ContinuousClock.Instant?

    let session: WatchResumeSession
    let onResume: () -> Void
    let onDiscard: () -> Void

    private var isConfirming: Bool { confirmationDeadline != nil }

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        let closeSize: CGFloat = compact ? 30 : 36
        let spacing: CGFloat = compact ? 5 : 8

        resumeButton(compact: compact, spacing: spacing)
            .padding(.trailing, closeSize + spacing)
            .overlay(alignment: .trailing) {
                closeButton(size: closeSize, compact: compact)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.44), value: isConfirming)
            .padding(.leading, compact ? 8 : 10)
            .padding(.trailing, compact ? 5 : 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.resumeBar)
            .clipShape(RoundedRectangle(cornerRadius: WatchMetrics.pillRadius, style: .continuous))
            .task(id: confirmationDeadline) { [confirmationDeadline] in
                guard let confirmationDeadline else { return }
                do {
                    try await ContinuousClock().sleep(until: confirmationDeadline)
                } catch {
                    return
                }
                if self.confirmationDeadline == confirmationDeadline {
                    self.confirmationDeadline = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { confirmationDeadline = nil }
            }
            .onDisappear { confirmationDeadline = nil }
    }

    private func resumeButton(compact: Bool, spacing: CGFloat) -> some View {
        Button {
            confirmationDeadline = nil
            onResume()
        } label: {
            HStack(spacing: spacing) {
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
    }

    private func closeButton(size: CGFloat, compact: Bool) -> some View {
        let confirmTitle = NSLocalizedString("watch_resume_confirm_discard", value: "确认放弃", comment: "")

        return Button(action: handleClose) {
            ZStack {
                if isConfirming {
                    Text(confirmTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: isConfirming ? 64 : size)
            .frame(height: size)
            .background(isConfirming ? WatchTheme.dangerRed : Color.white.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isConfirming ? confirmTitle : session.discardActionTitle)
    }

    private func handleClose() {
        WatchHaptics.shared.play(.light)
        let now = ContinuousClock.now
        if let confirmationDeadline, now < confirmationDeadline {
            self.confirmationDeadline = nil
            onDiscard()
        } else {
            confirmationDeadline = now.advanced(by: .seconds(3))
        }
    }
}
