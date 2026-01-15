import SwiftUI

struct WatchTennisScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchScoreboardView(rules: WatchTennisRules(maxSets: maxSets))
            .navigationBarHidden(true)
    }
}
