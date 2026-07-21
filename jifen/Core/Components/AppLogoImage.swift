import SwiftUI

/// In-app App Icon with iOS-style continuous rounded corners (~22.4%).
struct AppLogoImage: View {
    var size: CGFloat = 72

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}
