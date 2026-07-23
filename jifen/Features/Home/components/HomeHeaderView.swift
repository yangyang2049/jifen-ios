import SwiftUI

struct HomeHeaderView: View {
    let headerDate: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("app_name", comment: "App Name"))
                    .font(.system(size: Theme.fontH4, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.bottom, 2)
                    .lineLimit(1)

                Text(headerDate)
                    .font(.system(size: Theme.fontCaption, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()
        }
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor)
    }
}
