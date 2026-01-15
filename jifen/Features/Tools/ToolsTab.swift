//
//  ToolsTab.swift
//  jifen
//
//  Tools tab with liquid design
//

import SwiftUI

struct ToolsTab: View {
    @State private var selectedTool: ToolItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        // Competition Tools Section
                        ToolSectionView(
                            title: "比赛工具",
                            tools: competitionTools,
                            selectedTool: $selectedTool
                        )
                        
                        // Other Tools Section
                        ToolSectionView(
                            title: "其他工具",
                            tools: otherTools,
                            selectedTool: $selectedTool
                        )
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("工具")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .sheet(item: $selectedTool) { tool in
                NavigationStack {
                    tool.view
                }
            }
        }
    }
    
    private var competitionTools: [ToolItem] {
        [
            ToolItem(emoji: "🪙", title: "抛硬币", view: AnyView(FlipCoinView())),
            ToolItem(emoji: "🎲", title: "骰子", view: AnyView(DiceToolView())),
            ToolItem(emoji: "🔔", title: "哨声", view: AnyView(WhistleToolView())),
            ToolItem(emoji: "👥", title: "随机分组", view: AnyView(RandomTeamView())),
            ToolItem(emoji: "🟨", title: "红黄牌", view: AnyView(RedYellowCardView())),
            ToolItem(emoji: "📊", title: "积分表", view: AnyView(PointsTableView()))
        ]
    }
    
            private var otherTools: [ToolItem] {
                [
                    // ToolItem(emoji: "💬", title: "全屏弹幕", view: AnyView(FullscreenBarrageView())), // Temporarily hidden
                    ToolItem(emoji: "🕐", title: "时间工具", view: AnyView(DateTimeToolView())),
                    ToolItem(emoji: "💰", title: "AA计算器", view: AnyView(AACalculatorView())),
                    ToolItem(emoji: "⏱️", title: "十秒挑战", view: AnyView(TenSecondChallengeView()))
                ]
            }
}

struct ToolItem: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let view: AnyView
}

struct ToolSectionView: View {
    let title: String
    let tools: [ToolItem]
    @Binding var selectedTool: ToolItem?
    
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
                ForEach(tools) { tool in
                    ToolCardView(tool: tool) {
                        selectedTool = tool
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
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.cardBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ToolsTab()
}

