import SwiftUI

struct ToolsTab: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ToolsListPageView(onToolTap: { path.append($0) })
            .navigationDestination(for: ToolItem.self) { tool in
                tool.view
                    .appAnalyticsScreen(AnalyticsScreen.tool(id: tool.id) ?? .toolsPage)
                    .navigationTitle(tool.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
    }
}

/// 工具列表内容页，无内层 NavigationStack，用于从首页 push 时避免嵌套导致自动退出。
/// 布局对齐计分 Tab：iPad 内容限宽 1080、分区标题带绿竖条、网格近正方形卡片。
struct ToolsListPageView: View {
    var onToolTap: ((ToolItem) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let usesPadLayout = Theme.usesPadLayout
            let availableWidth = max(
                0,
                min(proxy.size.width, usesPadLayout ? 1080 : .infinity) - Theme.pageHorizontalInset * 2
            )

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    ToolSectionView(
                        title: NSLocalizedString("match_tools", comment: "Match Tools"),
                        tools: ToolItem.competitionTools,
                        availableWidth: availableWidth,
                        usesPadLayout: usesPadLayout
                    ) { tool in
                        onToolTap?(tool)
                    }
                    ToolSectionView(
                        title: NSLocalizedString("other_tools", comment: "Other Tools"),
                        tools: ToolItem.otherTools,
                        availableWidth: availableWidth,
                        usesPadLayout: usesPadLayout
                    ) { tool in
                        onToolTap?(tool)
                    }
                }
                .frame(maxWidth: usesPadLayout ? 1080 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.pageHorizontalInset)
                .padding(.top, usesPadLayout ? Theme.lg : Theme.md)
                .padding(.bottom, Theme.tabContentBottomPadding)
            }
            .background(Theme.backgroundColor)
        }
        .navigationTitle(NSLocalizedString("tools_title", comment: "Tools"))
        .navigationBarTitleDisplayMode(.inline)
        .appAnalyticsScreen(.toolsPage)
    }
}

// Remove duplicate ToolItem struct, it's now in ToolDefinitions.swift
// struct ToolItem: Identifiable, Hashable { ... }

struct ToolSectionView: View {
    let title: String
    let tools: [ToolItem]
    let availableWidth: CGFloat
    let usesPadLayout: Bool
    let onToolClick: (ToolItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            SectionTitleView(title: title)

            LazyVGrid(columns: gridColumns, spacing: Theme.gridSpacing) {
                ForEach(tools, id: \.self) { tool in
                    ToolCardView(tool: tool) {
                        onToolClick(tool)
                    }
                }
            }
        }
    }

    /// 对齐计分 Tab：iPad 固定一行 4 个，窄屏（<360pt）2 列，其余 3 列。
    private var gridColumns: [GridItem] {
        let count = usesPadLayout ? 4 : (availableWidth + Theme.padding * 2 < 360 ? 2 : 3)
        return Array(
            repeating: GridItem(.flexible(), spacing: Theme.gridSpacing),
            count: count
        )
    }
}

struct ToolCardView: View {
    let tool: ToolItem
    let action: () -> Void

    var body: some View {
        Button(action: {
            VibrationManager.shared.vibrateLight()
            AppAnalytics.trackContentSelection(
                contentType: "tool",
                itemID: tool.id,
                entryPoint: .toolsPage
            )
            action()
        }) {
            VStack(spacing: 10) {
                Text(tool.emoji)
                    .font(.system(size: 40))

                Text(tool.title)
                    .font(.system(size: Theme.fontBody2))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Theme.cardPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .background(Theme.appCardBackground)
            .cornerRadius(Theme.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("tool_card_\(tool.id)")
        .accessibilityLabel(tool.title)
        .onAppear {
            // Preload the dice webview while the tile is on screen so pushing
            // the dice page doesn't stall the transition. The delay keeps the
            // webview creation out of the tools grid's own push animation.
            if tool.id == "dice" {
                DiceWebEngine.shared.warmUp(after: 0.5)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ToolsTab()
    }
}
