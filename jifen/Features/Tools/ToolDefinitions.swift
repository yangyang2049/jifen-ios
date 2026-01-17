import SwiftUI

// MARK: - ToolItem Definition
struct ToolItem: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let view: AnyView
    
    static func == (lhs: ToolItem, rhs: ToolItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tool Definitions
extension ToolItem {
    static let competitionTools: [ToolItem] = [
        ToolItem(id: "flip_coin", emoji: "🪙", title: NSLocalizedString("tool_flip_coin", comment: "Flip Coin"), view: AnyView(FlipCoinView())),
        ToolItem(id: "dice", emoji: "🎲", title: NSLocalizedString("tool_dice", comment: "Dice"), view: AnyView(DiceToolView())),
        ToolItem(id: "whistle", emoji: "🔔", title: NSLocalizedString("tool_whistle", comment: "Whistle"), view: AnyView(WhistleToolView())),
        ToolItem(id: "random_team", emoji: "👥", title: NSLocalizedString("tool_random_team", comment: "Random Team"), view: AnyView(RandomTeamView())),
        ToolItem(id: "red_yellow_card", emoji: "🟨", title: NSLocalizedString("tool_red_yellow_card", comment: "Red Yellow Card"), view: AnyView(RedYellowCardView()))
    ]
    
    static let otherTools: [ToolItem] = [
        // ToolItem(id: "fullscreen_barrage", emoji: "💬", title: NSLocalizedString("fullscreen_barrage", comment: "Fullscreen Barrage"), view: AnyView(FullscreenBarrageView())), // Temporarily hidden
        ToolItem(id: "time", emoji: "🕐", title: NSLocalizedString("tool_time", comment: "Time Tool"), view: AnyView(DateTimeToolView())),
        ToolItem(id: "aa_calculator", emoji: "💰", title: NSLocalizedString("tool_aa_calculator", comment: "AA Calculator"), view: AnyView(AACalculatorView())),
        ToolItem(id: "ten_second", emoji: "⏱️", title: NSLocalizedString("tool_ten_second", comment: "Ten Second Challenge"), view: AnyView(TenSecondChallengeView()))
    ]

    static let allTools: [ToolItem] = competitionTools + otherTools
}
