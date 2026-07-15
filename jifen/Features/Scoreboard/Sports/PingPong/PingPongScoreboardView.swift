import ScoreCore
import SwiftUI

struct PingPongScoreboardView: View {
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        RallyScoreboardView(
            leftName: initialSetup?.team1Name.isEmpty == false ? initialSetup!.team1Name : NSLocalizedString("red_team", value: "红方", comment: "Red team"),
            rightName: initialSetup?.team2Name.isEmpty == false ? initialSetup!.team2Name : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team"),
            gameType: .pingpong,
            rules: .pingPong(maxSets: initialSetup?.maxSets ?? 5),
            showBackButton: showBackButton,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }
}

#Preview {
    PingPongScoreboardView()
        .previewInterfaceOrientation(.landscapeLeft)
}
