import SwiftUI

enum HomeToolsLayoutPolicy {
    static let maximumPadToolCount = 10
    static let minimumWideColumns = 4
    static let maximumWideColumns = 10
    static let wideItemMinimumWidth: CGFloat = 92
    static let wideColumnSpacing: CGFloat = 8

    private static let compactToolIDs = [
        "flip_coin", "dice", "whistle", "red_yellow_card",
        "points_table", "time", "aa_calculator", "ten_second"
    ]

    static func tools(isPad: Bool) -> [ToolItem] {
        if isPad {
            return Array(ToolItem.allTools.prefix(maximumPadToolCount))
        }

        let toolsByID = Dictionary(uniqueKeysWithValues: ToolItem.allTools.map { ($0.id, $0) })
        return compactToolIDs.compactMap { toolsByID[$0] }
    }

    static func wideColumnCount(forWidth width: CGFloat, toolCount: Int) -> Int {
        guard toolCount > 0 else { return 1 }

        let estimated = Int(
            (max(0, width) + wideColumnSpacing)
                / (wideItemMinimumWidth + wideColumnSpacing)
        )
        let minimum = min(minimumWideColumns, toolCount)
        return min(
            min(maximumWideColumns, toolCount),
            max(minimum, estimated)
        )
    }
}

// MARK: - ToolItemView
struct ToolItemView: View {
    let tool: ToolItem
    let iconColor: Color
    let isWide: Bool
    var isDarkTheme: Bool
    var onClickCallback: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onClickCallback?()
        }) {
            VStack(spacing: Theme.sm) {
                // Icon Container
                ZStack {
                    Text(tool.emoji)
                        .font(.system(size: 32))
                        .foregroundColor(iconColor)
                }
                .frame(width: 64, height: 64)
                .background(Theme.appCardBackground)
                .cornerRadius(Theme.cornerRadius)
                .shadow(color: isDarkTheme ? .clear : Color.black.opacity(0.05), radius: isDarkTheme ? 0 : 2, x: 0, y: isDarkTheme ? 0 : 1)

                // Label
                Text(tool.title)
                    .font(.system(size: Theme.fontBody2, weight: .bold))
                    .foregroundColor(isDarkTheme ? Theme.textSecondary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: isWide ? .infinity : nil)
            .frame(width: isWide ? nil : 84)
        }
        .buttonStyle(CardButtonStyle()) // Using the custom button style for animations
        .accessibilityIdentifier("home_tool_\(tool.id)")
        .accessibilityLabel(tool.title)
    }
}

// MARK: - ProToolsSectionView
struct ProToolsSectionView: View {
    var isPad: Bool = false
    var isWide: Bool = false
    var isDarkTheme: Bool = true
    var availableWidth: CGFloat = 0
    var onToolClick: ((ToolItem) -> Void)? = nil
    var onEnterToolsPage: (() -> Void)? = nil

    private let homeToolsText = NSLocalizedString("home_tools", comment: "Tools section title")

    init(
        isPad: Bool = false,
        isWide: Bool = false,
        isDarkTheme: Bool = true,
        availableWidth: CGFloat = 0,
        onToolClick: ((ToolItem) -> Void)? = nil,
        onEnterToolsPage: (() -> Void)? = nil
    ) {
        self.isPad = isPad
        self.isWide = isWide
        self.isDarkTheme = isDarkTheme
        self.availableWidth = availableWidth
        self.onToolClick = onToolClick
        self.onEnterToolsPage = onEnterToolsPage
    }

    private var tools: [ToolItem] {
        HomeToolsLayoutPolicy.tools(isPad: isPad)
    }

    private func iconColor(for tool: ToolItem) -> Color {
        tool.id == "whistle" ? Theme.toolWhistleRed : Theme.toolGray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: 标题 + 右侧 > 进入工具页
            HStack {
                Text(homeToolsText)
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if !isWide, let onEnterToolsPage = onEnterToolsPage {
                    Button(action: onEnterToolsPage) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home_all_tools_button")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.sectionContentSpacing)

            if isWide {
                let columnCount = HomeToolsLayoutPolicy.wideColumnCount(
                    forWidth: availableWidth,
                    toolCount: tools.count
                )
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: HomeToolsLayoutPolicy.wideColumnSpacing),
                        count: columnCount
                    ),
                    spacing: 20
                ) {
                    ForEach(tools) { tool in
                        ToolItemView(
                            tool: tool,
                            iconColor: iconColor(for: tool),
                            isWide: true,
                            isDarkTheme: isDarkTheme,
                            onClickCallback: {
                                onToolClick?(tool)
                            }
                        )
                    }
                }
            } else {
                // Mobile: Horizontal Scroll List
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) { // List({ space: 0 }), listDirection(Axis.Horizontal)
                        ForEach(tools) { tool in
                            ToolItemView(
                                tool: tool,
                                iconColor: iconColor(for: tool),
                                isWide: false,
                                isDarkTheme: isDarkTheme,
                                onClickCallback: {
                                    onToolClick?(tool)
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
