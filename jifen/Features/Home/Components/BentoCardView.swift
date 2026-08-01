import SwiftUI

struct BentoCardView: View {
    let title: String
    var subtitle: String = ""
    let icon: String
    var gradientColors: [Color] = [Theme.surface, Theme.surface] // Default to Theme.surface
    var showDecorativeBars: Bool = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(icon)
                    .font(.system(size: 36))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text(title)
                    .font(.system(size: Theme.fontH5, weight: .bold))
                    .foregroundColor(Theme.homeCardTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .cornerRadius(Theme.xxl)
        .shadow(color: Theme.homeButtonShadow, radius: 10, x: 0, y: 5)
        .buttonStyle(CardButtonStyle())
    }
}

// Custom ButtonStyle to handle press feedback
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
