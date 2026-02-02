//
//  GameFinishedOverlay.swift
//  jifen
//
//  Shared overlay for match end
//

import SwiftUI

struct GameFinishedOverlay: View {
    let winnerName: String
    
    var body: some View {
        VStack {
            Text(String(format: NSLocalizedString("game_winner_format", comment: "Winner overlay"), winnerName))
                .font(.system(size: 32, weight: .bold))
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
