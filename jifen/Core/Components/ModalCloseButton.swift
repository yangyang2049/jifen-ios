import SwiftUI

/// Shared close affordance for sheets and dialogs whose dismissal does not
/// discard a pending business action.
struct ModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .foregroundColor(Theme.textPrimary)
        }
        .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
    }
}

/// Close affordance for dark, app-drawn scoreboard dialogs. The visible
/// circle stays 32pt while the hit target remains 44pt.
struct ScoreboardDialogCloseButton: View {
    let action: () -> Void
    var accessibilityIdentifier: String = "scoreboard_dialog_close_button"

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
