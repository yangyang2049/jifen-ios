import SwiftUI

struct BentoCardView: View {
    let title: String
    var subtitle: String = ""
    let icon: String
    var gradientColors: [Color] = [Theme.surface, Theme.surface] // Default to Theme.surface
    var isDarkText: Bool = false
    var onClickCard: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) { // Corresponds to Stack({ alignContent: Alignment.TopStart })
            // Content
            VStack(spacing: 0) { // No explicit spacing in HarmonyOS Column, set to 0
                HStack(alignment: .top) { // Corresponds to Row()
                    VStack(alignment: .leading, spacing: 0) { // Corresponds to Column()
                        Text(title)
                            .font(.system(size: Theme.fontH5, weight: .bold)) // FontSizes.h5, FontWeight.Bold
                            .foregroundColor(isDarkText ? .black : Theme.textPrimary) // Colors.black : Colors.textPrimary
                            .lineLimit(1)
                            .truncationMode(.tail) // textOverflow({ overflow: TextOverflow.Ellipsis })

                        if !subtitle.isEmpty { // if (this.subtitle)
                            Text(subtitle)
                                .font(.system(size: Theme.fontCaption, weight: .medium)) // FontSizes.overline (approximated to fontCaption), FontWeight.Medium
                                .foregroundColor(isDarkText ? Theme.textSecondary : Theme.textSecondary) // Colors.textTertiary : Colors.textSecondary (HarmonyOS had textTertiary, using textSecondary for now)
                                .padding(.top, Theme.xs) // margin({ top: Spacing.xs })
                                .textCase(.uppercase) // textCase(TextCase.UpperCase)
                        }
                    }
                    .layoutPriority(1) // layoutWeight(1)

                    Text(icon)
                        .font(.system(size: Theme.fontH3)) // FontSizes.h3
                }
                .frame(maxWidth: .infinity, alignment: .top) // width('100%'), alignItems(VerticalAlign.Top)
                .padding(.top, Theme.md) // Adjusted for visual balance if needed, HarmonyOS has md padding for whole column.

                // Decorative Bars (only if subtitle exists and not simple background)
                if !subtitle.isEmpty && gradientColors[0] != Theme.surface && gradientColors[0] != .white {
                    Spacer() // Blank()
                    HStack(spacing: 2) { // Row({ space: 2 })
                        DecorativeBar(height: 16)
                        DecorativeBar(height: 28)
                        DecorativeBar(height: 20)
                        DecorativeBar(height: 40)
                        DecorativeBar(height: 24)
                    }
                    .frame(height: 48) // height(48)
                    .opacity(0.3)
                    .frame(maxWidth: .infinity, alignment: .leading) // alignSelf(ItemAlign.Start)
                } else {
                    Spacer() // To push content to top if no decorative bars
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // width('100%'), height('100%')
            .padding(Theme.md) // padding(Spacing.md)
            // .justifyContent(FlexAlign.SpaceBetween) // Managed by Spacer()

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // width('100%'), height('100%')
        .background(
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading, // angle: 135 (approximated to topLeading)
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(Theme.xxl) // borderRadius(BorderRadius.xxl)
        .shadow(color: Theme.homeButtonShadow, radius: 10, x: 0, y: 5) // shadow({ radius: 10, color: Colors.homeButtonShadow, offsetY: 5 })
        .buttonStyle(CardButtonStyle()) // Using a custom button style to handle pressed state
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
