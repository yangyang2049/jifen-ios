//
//  ComingSoonPlaceholderView.swift
//  jifen
//
//  棋牌 / 简单计分 / 多人计分 占位页，后续接具体功能。
//

import SwiftUI

struct ComingSoonPlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: Theme.lg) {
            Text("🚧")
                .font(.system(size: 56))
            Text(title)
                .font(.system(size: Theme.fontH4, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(NSLocalizedString("feature_coming_soon", value: "敬请期待", comment: "Coming soon"))
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        ComingSoonPlaceholderView(title: GameType.doudizhu.displayName)
    }
}
