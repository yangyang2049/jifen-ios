//
//  WatchPickleballScoreView.swift
//  jifenWatch Watch App
//

import ScoreCore
import SwiftUI

struct WatchPickleballScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchRallyScoreView(gameType: .pickleball, rules: .pickleball(maxSets: maxSets))
    }
}
