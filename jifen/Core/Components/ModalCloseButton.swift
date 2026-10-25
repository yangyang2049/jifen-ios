import SwiftUI

/// Shared close affordance for sheets and dialogs. The caller retains its
/// existing dismissal, draft-discard confirmation and busy-state behavior.
struct ModalCloseButton: View {
    enum Placement { case toolbar, standalone }
    var placement: Placement = .toolbar
    /// 全屏相机等深色背景上的关闭按钮需要白色，其余场景沿用正文色。
    var tint: Color = Theme.textPrimary
    let action: () -> Void

    @ViewBuilder var body: some View {
        if placement == .standalone {
            closeButton.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
        } else {
            // The navigation toolbar supplies its own native background.
            closeButton
        }
    }

    private var closeButton: some View {
        Button(role: .cancel, action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
        }
        .tint(tint)
        .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
        .accessibilityIdentifier("modal_close_button")
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
