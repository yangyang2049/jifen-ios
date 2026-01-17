import SwiftUI

struct ToolsTab: View {
    @State private var path = NavigationPath()
    @Environment(\.colorScheme) var colorScheme

    enum NavigationDestination: Hashable {
        case tool(ToolItem)
    }

    init() {
        // Empty init since we removed the callback parameter
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        // Competition Tools Section
                        ToolSectionView(
                            title: NSLocalizedString("match_tools", comment: "Match Tools section"),
                            tools: ToolItem.competitionTools, // Use shared definition
                            onToolClick: { tool in
                                path.append(NavigationDestination.tool(tool))
                            }
                        )

                        // Other Tools Section
                        ToolSectionView(
                            title: NSLocalizedString("other_tools", comment: "Other Tools section"),
                            tools: ToolItem.otherTools, // Use shared definition
                            onToolClick: { tool in
                                path.append(NavigationDestination.tool(tool))
                            }
                        )
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(NSLocalizedString("tools_title", comment: "Tools title"))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .tool(let toolItem):
                    toolItem.view
                        .navigationTitle(toolItem.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .background(colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
    }
}

// Remove duplicate ToolItem struct, it's now in ToolDefinitions.swift
// struct ToolItem: Identifiable, Hashable { ... } 

struct ToolSectionView: View {
    let title: String
    let tools: [ToolItem]
    let onToolClick: (ToolItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary.opacity(0.9))
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.spacing),
                GridItem(.flexible(), spacing: Theme.spacing)
            ], spacing: Theme.spacing) {
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
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        ToolsTab()
    }
}
