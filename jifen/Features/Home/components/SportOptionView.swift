import SwiftUI

struct SportOptionView: View {
    let sport: GameType
    let isSelected: Bool
    var isDarkTheme: Bool
    var onClickOption: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onClickOption?()
        }) {
            VStack(spacing: Theme.sm) { // Column({ space: 8 })
                Text(getGameIcon(type: sport)) // getGameIcon(this.sport)
                    .font(.system(size: 24))
                
                Text(getGameName(type: sport)) // getGameName(this.sport)
                    .font(.system(size: 11, weight: .medium)) // fontSize(11), fontWeight(FontWeight.Medium)
                    .foregroundColor(isDarkTheme ? Theme.textPrimary : .black) // fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // width('100%'), height('100%')
            // .justifyContent(FlexAlign.Center) .alignItems(HorizontalAlign.Center)
            .aspectRatio(1, contentMode: .fit) // aspectRatio(1)
            .background(isDarkTheme ? Theme.homeOverlayBorder : Theme.homeBackgroundLight) // backgroundColor
            .cornerRadius(16) // borderRadius(16)
            .overlay( // border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.homeEditButtonGreen : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(CardButtonStyle()) // Using custom button style for animations
    }
}
