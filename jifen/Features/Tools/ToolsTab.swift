import SwiftUI

struct ToolsTab: View {
    @State private var path = NavigationPath()
    @Binding var toolToOpen: String? // New binding to open a specific tool

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
                                path.append(tool)
                            }
                        )
                        
                        // Other Tools Section
                        ToolSectionView(
                            title: NSLocalizedString("other_tools", comment: "Other Tools section"),
                            tools: ToolItem.otherTools, // Use shared definition
                            onToolClick: { tool in
                                path.append(tool)
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
            .navigationDestination(for: ToolItem.self) { tool in
                tool.view
            }
            .onChange(of: toolToOpen) { oldToolId, newToolId in // Add onChange observer
                if let newToolId = newToolId, let tool = ToolItem.allTools.first(where: { $0.id == newToolId }) {
                    path.append(tool)
                    toolToOpen = nil // Clear the binding after navigation
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
    ToolsTab(toolToOpen: .constant(nil)) // Provide a constant binding for preview
}

