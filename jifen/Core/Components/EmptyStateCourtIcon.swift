import SwiftUI

struct EmptyStateCourtIcon: View {
    var size: CGFloat = 56
    var color: Color = Theme.textSecondary.opacity(0.7)

    var body: some View {
        Image("EmptyStateCourt")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(color)
            .accessibilityHidden(true)
    }
}
