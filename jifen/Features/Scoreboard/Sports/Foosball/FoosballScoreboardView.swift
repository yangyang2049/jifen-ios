import ScoreCore
import SwiftUI

/// 桌上足球：复用 Rally 抢分内核；2V2 使用四角球员布局且无发球轮转。
struct FoosballScoreboardView: View {
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        RallyScoreboardView(
            leftName: resolvedLeftName,
            rightName: resolvedRightName,
            gameType: isDoubles ? .foosballDoubles : .foosball,
            rules: rules,
            participants: isDoubles ? doublesParticipants(initialSetup) : nil,
            openingServer: .left,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement ?? false,
            initialRecordId: initialRecordId,
            showBackButton: showBackButton,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        (initialSetup ?? SportsSetupResult(team1Name: "", team2Name: "")).foosballRules
    }

    private var resolvedLeftName: String {
        if let name = initialSetup?.team1Name, !name.isEmpty { return name }
        if initialSetup?.isSingles == false {
            return NSLocalizedString("foosball_default_red_doubles", value: "红方A/红方B", comment: "")
        }
        return NSLocalizedString("player_a", value: "选手A", comment: "")
    }

    private var resolvedRightName: String {
        if let name = initialSetup?.team2Name, !name.isEmpty { return name }
        if initialSetup?.isSingles == false {
            return NSLocalizedString("foosball_default_blue_doubles", value: "蓝方A/蓝方B", comment: "")
        }
        return NSLocalizedString("player_b", value: "选手B", comment: "")
    }

    static func joinFoosballNames(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty && !b.isEmpty { return "\(a)/\(b)" }
        return a.isEmpty ? b : a
    }
}

#Preview(traits: .landscapeLeft) {
    FoosballScoreboardView()
}
