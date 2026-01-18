import SwiftUI

// MARK: - ToolDef
struct ToolDef: Identifiable {
    let id: String
    var name: String // Will be localized
    let icon: String
    let color: Color
}

// MARK: - ToolItemView
struct ToolItemView: View {
    let name: String
    let icon: String
    let iconColor: Color
    var isDarkTheme: Bool
    var onClickCallback: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onClickCallback?()
        }) {
            VStack(spacing: Theme.sm) { // Column({ space: 8 })
                // Icon Container
                ZStack { // Column()
                    Text(icon)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor) // fontColor(this.iconColor)
                }
                .frame(width: 56, height: 56) // width(56), height(56)
                .background(.ultraThinMaterial) // Apply glassmorphism effect here
                .cornerRadius(Theme.cornerRadius) // borderRadius(BorderRadius.xl)
                .shadow(color: isDarkTheme ? .clear : Color.black.opacity(0.05), radius: isDarkTheme ? 0 : 2, x: 0, y: isDarkTheme ? 0 : 1) // shadow
                // .justifyContent(FlexAlign.Center), .alignItems(HorizontalAlign.Center) - handled by ZStack/modifiers

                // Label
                Text(name)
                    .font(.system(size: Theme.fontCaption, weight: .bold)) // FontSizes.overline, FontWeight.Bold
                    .foregroundColor(isDarkTheme ? Theme.textSecondary : Theme.textSecondary) // Colors.textTertiary : Colors.textSecondary
                    .lineLimit(1)
                    .truncationMode(.tail) // textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .frame(width: 72) // width(72) - Fixed width for snap alignment
        }
        .buttonStyle(CardButtonStyle()) // Using the custom button style for animations
    }
}

// MARK: - ProToolsSectionView
struct ProToolsSectionView: View {
    var isWide: Bool = false
    var isDarkTheme: Bool = true // Default to black UI
    var onToolClick: ((String) -> Void)? = nil

    @State private var tools: [ToolDef] = []
    @State private var homeToolsText: String = NSLocalizedString("home_tools", comment: "Tools section title")

    init(isWide: Bool = false, isDarkTheme: Bool = true, onToolClick: ((String) -> Void)? = nil) {
        self.isWide = isWide
        self.isDarkTheme = isDarkTheme
        self.onToolClick = onToolClick
        _tools = State(initialValue: Self.initialTools())
    }

    private static func initialTools() -> [ToolDef] {
        return [
            ToolDef(id: "whistle", name: NSLocalizedString("home_tool_whistle", comment: "Whistle tool name"), icon: "🔊", color: Theme.toolWhistleRed),
            ToolDef(id: "flip_coin", name: NSLocalizedString("home_tool_coin", comment: "Flip Coin tool name"), icon: "🪙", color: Theme.toolGray),
            ToolDef(id: "dice", name: NSLocalizedString("home_tool_dice", comment: "Dice tool name"), icon: "🎲", color: Theme.toolGray),
            ToolDef(id: "red_yellow_card", name: NSLocalizedString("tool_red_yellow_card", comment: "Red Yellow Card"), icon: "🟨", color: Theme.toolGray),
            ToolDef(id: "aa_calculator", name: NSLocalizedString("tool_aa_calculator", comment: "AA Calculator"), icon: "💰", color: Theme.toolGray),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Column()
            // Header
            HStack { // Row({ space: Spacing.sm })
                Text(homeToolsText)
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                
                Spacer() // Re-add Spacer to push text to left
            }
            .frame(maxWidth: .infinity) // justifyContent(FlexAlign.SpaceBetween), width('100%')
            .padding(.bottom, Theme.md) // margin({ bottom: Spacing.md })

            if isWide {
                // Desktop/Tablet: Grid - 6 columns in one row
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 0) {
                    ForEach(tools) { tool in
                        ToolItemView(
                            name: tool.name,
                            icon: tool.icon,
                            iconColor: tool.color,
                            isDarkTheme: isDarkTheme,
                            onClickCallback: {
                                onToolClick?(tool.id)
                            }
                        )
                    }
                }
                .padding(.leading, 0) // padding({ left: 0 })
            } else {
                // Mobile: Horizontal Scroll List
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) { // List({ space: 0 }), listDirection(Axis.Horizontal)
                        ForEach(tools) { tool in
                            ToolItemView(
                                name: tool.name,
                                icon: tool.icon,
                                iconColor: tool.color,
                                isDarkTheme: isDarkTheme,
                                onClickCallback: {
                                    onToolClick?(tool.id)
                                }
                            )
                        }
                    }
                    .padding(.leading, 0) // padding({ left: 0 })
                }
                .frame(height: 80) // height(80)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading) // alignItems(HorizontalAlign.Start)
    }
}
