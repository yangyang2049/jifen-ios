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
                            title: NSLocalizedString("match_tools", comment: "Match Tools section"),
                            tools: competitionTools,
                            selectedTool: $selectedTool
                        )
                        
                        // Other Tools Section
                        ToolSectionView(
                            title: NSLocalizedString("other_tools", comment: "Other Tools section"),
                            tools: otherTools,
                            selectedTool: $selectedTool
                        )
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(NSLocalizedString("tools_title", comment: "Tools title"))
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
            ToolItem(emoji: "🪙", title: NSLocalizedString("tool_flip_coin", comment: "Flip Coin"), view: AnyView(FlipCoinView())),
            ToolItem(emoji: "🎲", title: NSLocalizedString("tool_dice", comment: "Dice"), view: AnyView(DiceToolView())),
            ToolItem(emoji: "🔔", title: NSLocalizedString("tool_whistle", comment: "Whistle"), view: AnyView(WhistleToolView())),
            ToolItem(emoji: "👥", title: NSLocalizedString("tool_random_team", comment: "Random Team"), view: AnyView(RandomTeamView())),
            ToolItem(emoji: "🟨", title: NSLocalizedString("tool_red_yellow_card", comment: "Red Yellow Card"), view: AnyView(RedYellowCardView())),
            ToolItem(emoji: "📊", title: NSLocalizedString("tool_points_table", comment: "Points Table"), view: AnyView(PointsTableView()))
        ]
    }
    
    private var otherTools: [ToolItem] {
        [
            // ToolItem(emoji: "💬", title: NSLocalizedString("fullscreen_barrage", comment: "Fullscreen Barrage"), view: AnyView(FullscreenBarrageView())), // Temporarily hidden
            ToolItem(emoji: "🕐", title: NSLocalizedString("tool_time", comment: "Time Tool"), view: AnyView(DateTimeToolView())),
            ToolItem(emoji: "💰", title: NSLocalizedString("tool_aa_calculator", comment: "AA Calculator"), view: AnyView(AACalculatorView())),
            ToolItem(emoji: "⏱️", title: NSLocalizedString("tool_ten_second", comment: "Ten Second Challenge"), view: AnyView(TenSecondChallengeView()))
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

