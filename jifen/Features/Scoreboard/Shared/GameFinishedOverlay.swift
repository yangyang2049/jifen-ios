//
//  GameFinishedOverlay.swift
//  jifen
//
//  Shared overlay for match end
//

import SwiftUI

struct GameFinishedOverlay: View {
    let winnerName: String
    var resultText: String? = nil
    
    var body: some View {
        VStack {
            VStack(spacing: 4) {
                Text(winnerName.isEmpty
                     ? NSLocalizedString("match_draw", value: "比赛平局", comment: "")
                     : String(format: NSLocalizedString("game_winner_format", comment: "Winner overlay"), winnerName))
                    .font(.system(size: 32, weight: .bold))
                if let resultText {
                    Text(resultText)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.5))
            )
        }
    }
}

#Preview {
    GameFinishedOverlay(winnerName: "红队")
}
