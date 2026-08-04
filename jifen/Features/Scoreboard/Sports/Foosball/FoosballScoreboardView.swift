import ScoreCore
import SwiftUI

/// 桌上足球：复用 Rally 抢分内核；2V2 正常计分时合并显示同队姓名，编辑时拆分为两位球员。
struct FoosballScoreboardView: View {
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        RallyScoreboardView(
            leftName: resolvedLeftName,
            rightName: resolvedRightName,
            gameType: isDoubles ? .foosballDoubles : .foosball,
            rules: rules,
            participants: isDoubles ? doublesParticipants(initialSetup) : nil,
            openingServer: Self.openingServer(for: initialSetup),
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement ?? false,
            initialResumeSessionId: initialResumeSessionId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        (initialSetup ?? SportsSetupResult(team1Name: "", team2Name: "")).foosballRules
    }

    static func openingServer(for setup: SportsSetupResult?) -> MatchSide {
        setup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }

    private var resolvedLeftName: String {
        if let name = initialSetup?.team1Name, !name.isEmpty { return name }
        return DefaultParticipantNames.resolve(
            for: .foosball,
            isSingles: initialSetup?.isSingles != false
        ).left
    }

    private var resolvedRightName: String {
        if let name = initialSetup?.team2Name, !name.isEmpty { return name }
        return DefaultParticipantNames.resolve(
            for: .foosball,
            isSingles: initialSetup?.isSingles != false
        ).right
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
