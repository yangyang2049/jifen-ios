import SwiftUI

struct SportOptionView: View {
    let sport: GameType
    let isSelected: Bool
    var onClickOption: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onClickOption?()
        }) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let iconSize = max(24, min(56, side * 0.4))
                let fontSize = max(11, min(18, side * 0.12))
                VStack(spacing: Theme.sm) {
                    Text(getGameIcon(type: sport))
                        .font(.system(size: iconSize))
                    Text(getGameName(type: sport))
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.controlBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.homeEditButtonGreen : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(CardButtonStyle())
    }
}
