//
//  MenuDialog.swift
//  jifen
//
//  Custom menu dialog - based on HarmonyOS design
//

import SwiftUI

struct MenuDialog: View {
    let isVisible: Bool
    let onClose: () -> Void
    let onMenuItemClick: (String) -> Void
    /// 是否显示「结束比赛」（足球、篮球等无计时终场时使用）
    var showEndGame: Bool = false

    var body: some View {
        if isVisible {
            ZStack {
                // Background overlay
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onClose()
                    }
                
                // Dialog content
                VStack(spacing: 0) {
                    // Title bar
                    HStack {
                        Text(NSLocalizedString("operations", comment: "Menu title"))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                        
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    
                    // Menu grid (2x3)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 8) {
                        // Whistle
                        MenuCard(
                            title: NSLocalizedString("menu_whistle", comment: "Whistle"),
                            icon: "bell.fill",
                            action: { onMenuItemClick("whistle") }
                        )

                        // Screenshot
                        MenuCard(
                            title: NSLocalizedString("menu_screenshot", comment: "Screenshot"),
                            icon: "camera.fill",
                            action: { onMenuItemClick("screenshot") }
                        )

                        // Exchange sides
                        MenuCard(
                            title: NSLocalizedString("menu_swap_sides", comment: "Exchange sides"),
                            icon: "arrow.left.arrow.right",
                            keepDialogOpen: true,
                            action: { onMenuItemClick("exchangeSide") }
                        )

                        // Reset
                        MenuCard(
                            title: NSLocalizedString("menu_reset", comment: "Reset"),
                            icon: "arrow.counterclockwise",
                            keepDialogOpen: true,
                            action: { onMenuItemClick("reset") }
                        )

                        // Undo
                        MenuCard(
                            title: NSLocalizedString("menu_undo", comment: "Undo"),
                            icon: "arrow.uturn.backward",
                            keepDialogOpen: true,
                            action: { onMenuItemClick("undo") }
                        )

                        // End game（仅足球、篮球显示）
                        if showEndGame {
                            MenuCard(
                                title: NSLocalizedString("menu_end_game", value: "结束比赛", comment: "End game"),
                                icon: "flag.checkered",
                                action: { onMenuItemClick("endGame") }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "1E1E1E").opacity(0.85))
                )
                .shadow(color: .black.opacity(0.12), radius: 32, x: 0, y: 12)
            }
        }
    }
}

struct MenuCard: View {
    let title: String
    var icon: String? = nil
    var customText: String? = nil
    var keepDialogOpen: Bool = false
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            action()
        }) {
            VStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                } else if let customText = customText {
                    Text(customText)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPressed ? Color.white.opacity(0.15) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

#Preview {
    MenuDialog(
        isVisible: true,
        onClose: {},
        onMenuItemClick: { action in
            #if DEBUG
            print("Menu item clicked: \(action)")
            #endif
        }
    )
}
