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
            VStack(spacing: Theme.sm) {
                // Icon Container
                ZStack {
                    Text(icon)
                        .font(.system(size: 32))
                        .foregroundColor(iconColor)
                }
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.cornerRadius)
                .shadow(color: isDarkTheme ? .clear : Color.black.opacity(0.05), radius: isDarkTheme ? 0 : 2, x: 0, y: isDarkTheme ? 0 : 1)

                // Label
                Text(name)
                    .font(.system(size: Theme.fontBody2, weight: .bold))
                    .foregroundColor(isDarkTheme ? Theme.textSecondary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 84)
        }
        .buttonStyle(CardButtonStyle()) // Using the custom button style for animations
    }
}

// MARK: - ProToolsSectionView
struct ProToolsSectionView: View {
    var isWide: Bool = false
    var isDarkTheme: Bool = true
    var onToolClick: ((String) -> Void)? = nil
    var onEnterToolsPage: (() -> Void)? = nil

    @State private var tools: [ToolDef] = []
    @State private var homeToolsText: String = NSLocalizedString("home_tools", comment: "Tools section title")

    init(isWide: Bool = false, isDarkTheme: Bool = true, onToolClick: ((String) -> Void)? = nil, onEnterToolsPage: (() -> Void)? = nil) {
        self.isWide = isWide
        self.isDarkTheme = isDarkTheme
        self.onToolClick = onToolClick
        self.onEnterToolsPage = onEnterToolsPage
        _tools = State(initialValue: Self.initialTools())
    }

    /// 按可用宽度计算列数 6～8，单格约 84pt + spacing，避免过疏或过密
    private static func columnCount(forWidth width: CGFloat) -> Int {
        let spacing = Theme.md
        let minCellWidth: CGFloat = 84
        let fit = Int((width + spacing) / (minCellWidth + spacing))
        return min(8, max(6, fit))
    }

    private static func initialTools() -> [ToolDef] {
        return [
            ToolDef(id: "flip_coin", name: NSLocalizedString("tool_flip_coin", comment: "Flip Coin"), icon: "🪙", color: Theme.toolGray),
            ToolDef(id: "dice", name: NSLocalizedString("tool_dice", comment: "Dice"), icon: "🎲", color: Theme.toolGray),
            ToolDef(id: "whistle", name: NSLocalizedString("home_tool_whistle", comment: "Whistle"), icon: "🔊", color: Theme.toolWhistleRed),
            ToolDef(id: "red_yellow_card", name: NSLocalizedString("tool_red_yellow_card", comment: "Red Yellow Card"), icon: "🟨", color: Theme.toolGray),
            ToolDef(id: "points_table", name: NSLocalizedString("points_table_title", value: "积分表", comment: ""), icon: "📊", color: Theme.toolGray),
            ToolDef(id: "stopwatch", name: NSLocalizedString("tool_stopwatch", value: "秒表", comment: "Stopwatch"), icon: "⏱️", color: Theme.toolGray),
            ToolDef(id: "time", name: NSLocalizedString("tool_time", value: "全屏时间", comment: "Fullscreen Time"), icon: "🕐", color: Theme.toolGray),
            ToolDef(id: "aa_calculator", name: NSLocalizedString("tool_aa_calculator", comment: "AA Calculator"), icon: "💰", color: Theme.toolGray),
            ToolDef(id: "ten_second", name: NSLocalizedString("tool_ten_second", comment: "Ten Second Challenge"), icon: "⏱️", color: Theme.toolGray),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: 标题 + 右侧 > 进入工具页
            HStack {
                Text(homeToolsText)
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if let onEnterToolsPage = onEnterToolsPage {
                    Button(action: onEnterToolsPage) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.md)

            if isWide {
                // Desktop/Tablet: 按宽度算列数 6～8，避免过疏或过密
                GeometryReader { geo in
                    let columns = Self.columnCount(forWidth: geo.size.width)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.md), count: columns), spacing: Theme.md) {
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
                }
                .frame(minHeight: 200)
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
                .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading) // alignItems(HorizontalAlign.Start)
    }
}
