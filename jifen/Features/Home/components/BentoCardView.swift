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
            
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: Theme.fontH5, weight: .bold))
                            .foregroundColor(Theme.homeCardTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: Theme.fontCaption, weight: .medium))
                                .foregroundColor(Theme.homeCardTextSecondary)
                                .padding(.top, Theme.xs)
                                .textCase(.uppercase)
                        }
                    }
                    .layoutPriority(1)
                    Spacer()
                }

                Spacer()

                HStack {
                    Spacer()
                    Text(icon)
                        .font(.system(size: Theme.fontH3))
                        .padding(.trailing, Theme.sm)
                        .padding(.bottom, Theme.sm)
                }
            }
            .padding(Theme.md)
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
