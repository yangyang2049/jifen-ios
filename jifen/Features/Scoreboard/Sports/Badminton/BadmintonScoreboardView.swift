import ScoreCore
import SwiftUI

struct BadmintonScoreboardView: View {
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        RallyScoreboardView(
            leftName: initialSetup?.team1Name.isEmpty == false ? initialSetup!.team1Name : NSLocalizedString("red_team", value: "红方", comment: "Red team"),
            rightName: initialSetup?.team2Name.isEmpty == false ? initialSetup!.team2Name : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team"),
            gameType: isDoubles ? .badmintonDoubles : .badminton,
            rules: rules,
            participants: rallyParticipants,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement == true,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            initialRecordId: initialRecordId,
            showBackButton: showBackButton,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        var rules = RallyRuleSet.badminton(
            maxSets: initialSetup?.maxSets ?? 3,
            matchCompletionMode: initialSetup?.matchCompletionMode ?? .bestOf
        )
        rules.autoChangeSides = initialSetup?.autoChangeSides ?? true
        let target = max(1, initialSetup?.pointsPerSet ?? 21)
        let coreType: ScoreCore.GameType = initialSetup?.isSingles == false ? .badmintonDoubles : .badminton
        rules.pointsToWinSet = target
        rules.pointCap = RallyRuleSet.badmintonPointCap(for: target)
        rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(for: coreType, pointsPerSet: target)
        return rules
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }

    private var rallyParticipants: [SessionParticipant]? {
        initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil
    }
}
