import SwiftUI

struct ToolsTab: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ToolsListPageView(onToolTap: { path.append($0) })
            .navigationDestination(for: ToolItem.self) { tool in
                tool.view
                    .navigationTitle(tool.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
    }
}

/// 工具列表内容页，无内层 NavigationStack，用于从首页 push 时避免嵌套导致自动退出。
struct ToolsListPageView: View {
    var onToolTap: ((ToolItem) -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Theme.lg) {
                ToolSectionView(
                    title: NSLocalizedString("match_tools", comment: "Match Tools"),
                    tools: ToolItem.competitionTools
                ) { tool in
                    onToolTap?(tool)
                }
                ToolSectionView(
                    title: NSLocalizedString("other_tools", comment: "Other Tools"),
                    tools: ToolItem.otherTools
                ) { tool in
                    onToolTap?(tool)
                }
            }
            .padding(Theme.lg)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("tools_title", comment: "Tools"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Remove duplicate ToolItem struct, it's now in ToolDefinitions.swift
// struct ToolItem: Identifiable, Hashable { ... } 

struct ToolSectionView: View {
    let title: String
    let tools: [ToolItem]
    let onToolClick: (ToolItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary.opacity(0.9))
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.md),
                GridItem(.flexible(), spacing: Theme.md),
                GridItem(.flexible(), spacing: Theme.md)
            ], spacing: Theme.md) {
                ForEach(tools, id: \.self) { tool in
                    ToolCardView(tool: tool) {
                        onToolClick(tool)
                    }
                }
            }
        }
    }
}

struct ToolCardView: View {
    let tool: ToolItem
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            VStack(spacing: 12) {
                Text(tool.emoji)
                    .font(.system(size: 48))
                
                Text(tool.title)
                    .font(.subheadline)
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.divider.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        ToolsTab()
    }
}
