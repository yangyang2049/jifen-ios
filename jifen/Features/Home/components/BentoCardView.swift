import SwiftUI

struct BentoCardView: View {
    let title: String
    var subtitle: String = ""
    let icon: String
    var gradientColors: [Color] = [Theme.surface, Theme.surface] // Default to Theme.surface
    var isDarkText: Bool = false
    var showDecorativeBars: Bool = true // New parameter, default to true
    
    var body: some View {
        ZStack { // Overall ZStack for the card
            LinearGradient( // Background gradient
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading) { // Main content VStack
                HStack(alignment: .top) { // Top row: title/subtitle and emoji
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: Theme.fontH5, weight: .bold))
                            .foregroundColor(isDarkText ? .black : Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: Theme.fontCaption, weight: .medium))
                                .foregroundColor(isDarkText ? Theme.textSecondary : Theme.textSecondary)
                                .padding(.top, Theme.xs)
                                .textCase(.uppercase)
                        }
                    }
                    .layoutPriority(1) // Allows title to take available width
                    
                    Spacer() // Pushes the icon to the right
                    
                    Text(icon) // Emoji at top right
                        .font(.system(size: Theme.fontH3))
                }
                // Removed .padding(.top, Theme.md) from HStack, rely on overall padding
                
                // Decorative Bars or Spacer
                if showDecorativeBars && !subtitle.isEmpty && gradientColors[0] != Theme.surface && gradientColors[0] != .white {
                    Spacer()
                    HStack(spacing: 2) {
                        DecorativeBar(height: 16)
                        DecorativeBar(height: 28)
                        DecorativeBar(height: 20)
                        DecorativeBar(height: 40)
                        DecorativeBar(height: 24)
                    }
                    .frame(height: 48)
                    .opacity(0.3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }
            .padding(Theme.md) // Revert padding to Theme.md
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Align content within card
        }
        .cornerRadius(Theme.xxl)
        .shadow(color: Theme.homeButtonShadow, radius: 10, x: 0, y: 5)
        .buttonStyle(CardButtonStyle())
    }
    
    // Decorative Bar sub-component
    private func DecorativeBar(height: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.textOnPrimary) // backgroundColor(Colors.textOnPrimary)
            .frame(width: 4, height: height) // width(4), height(height)
            .cornerRadius(2) // borderRadius(2)
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
