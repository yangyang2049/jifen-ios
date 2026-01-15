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
            Text("\(winnerName) 获胜")
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
