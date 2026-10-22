import SwiftUI

/// Shared gold VIP mark for the bottom trailing corner of an avatar.
struct AvatarVIPBadge: View {
    let avatarSize: CGFloat

    var body: some View {
        let badgeSize: CGFloat = avatarSize >= 44 ? 15 : avatarSize >= 36 ? 13 : 8
        let glyphSize: CGFloat = avatarSize >= 36 ? 9 : 6
        Text("v")
            .font(.system(size: glyphSize, weight: .medium).italic())
            .foregroundColor(Color(hex: "422006"))
            .frame(width: badgeSize, height: badgeSize)
            .background(Circle().fill(Color(hex: "FBBF24")))
            .offset(x: 0.4, y: -0.2)
            .accessibilityLabel("VIP")
    }
}
