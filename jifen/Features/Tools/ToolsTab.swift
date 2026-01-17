import SwiftUI

struct ToolsTab: View {
    @State private var path = NavigationPath()
    var onOpenTool: ((ToolItem) -> Void)? = nil // Callback for opening a specific tool

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
                                onOpenTool?(tool) // Call the onOpenTool callback
                            }
                        )
                        
                        // Other Tools Section
                        ToolSectionView(
                            title: NSLocalizedString("other_tools", comment: "Other Tools section"),
                            tools: ToolItem.otherTools, // Use shared definition
                            onToolClick: { tool in
                                onOpenTool?(tool) // Call the onOpenTool callback
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
            // navigationDestination is no longer directly used for opening tool views modally,
            // but can be kept for other internal navigation if needed.
            // .navigationDestination(for: ToolItem.self) { tool in
            //    tool.view
            // }
            // Remove onChange(of: toolToOpen) as it's no longer needed
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
    ToolsTab() // No binding needed for preview anymore
}

