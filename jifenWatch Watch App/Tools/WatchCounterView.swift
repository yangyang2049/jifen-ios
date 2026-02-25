//
//  WatchCounterView.swift
//  jifenWatch Watch App
//
//  计数器：点击屏幕 +1，支持重置。与主应用/鸿蒙计数器对齐。
//

import SwiftUI

struct WatchCounterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var count: Int = 0
    @State private var showResetConfirm: Bool = false

    /// 杠铃布局：顶部 48、中间数字、底部 48（重置放在底部 48 里）
    private let barHeight: CGFloat = 48

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: barHeight)

                ZStack {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            count += 1
                            WatchHaptics.shared.play(.light)
                        }
                    Text("\(count)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(WatchTheme.primaryText)
                        .contentTransition(.numericText())
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ZStack {
                    Button {
                        showResetConfirm = true
                    } label: {
                        Text(NSLocalizedString("menu_reset", comment: "Reset"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WatchTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: barHeight)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(NSLocalizedString("game_counter", comment: "Counter"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(NSLocalizedString("menu_reset", comment: "Reset"), isPresented: $showResetConfirm) {
            Button(NSLocalizedString("menu_reset", comment: "Reset"), role: .destructive) {
                count = 0
                WatchHaptics.shared.play(.undo)
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("press_again_to_reset", comment: ""))
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }
}

#Preview {
    NavigationStack {
        WatchCounterView()
    }
}
