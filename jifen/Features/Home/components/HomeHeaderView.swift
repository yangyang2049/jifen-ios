//
//  HomeHeaderView.swift
//  jifen
//
//  Fixed home top bar. Layout mirrors HarmonyOS HomeHeader:
//  pinned above scroll content so it can later morph into a sync-scoring banner.
//

import SwiftUI

struct HomeHeaderView: View {
    let headerDate: String
    var onSyncTap: () -> Void

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

            Button(action: onSyncTap) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel(NSLocalizedString("sync_title", value: "局域网同步", comment: ""))
        }
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor)
    }
}
