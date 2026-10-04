import SwiftUI

struct BentoCardView: View {
    let title: String
    var subtitle: String = ""
    let gameType: GameType
    var gradientColors: [Color] = [Theme.surface, Theme.surface] // Default to Theme.surface
    var showDecorativeBars: Bool = false
    var artworkSize: CGFloat = 64
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                AppCatalogIcon(gameType: gameType, size: 36, artworkSize: artworkSize)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text(title)
                    .font(.system(size: Theme.fontH5, weight: .bold))
                    .foregroundColor(Theme.homeCardTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .cornerRadius(Theme.xxl)
        .shadow(color: Theme.homeButtonShadow, radius: 10, x: 0, y: 5)
    }
}

// Custom ButtonStyle to handle press feedback
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
