//
//  RestCountdownOverlay.swift
//  jifen
//
//  Shared rest countdown overlay
//

import SwiftUI
import Foundation

struct RestCountdownOverlay: View {
    let message: String
    let remainingSeconds: Int
    var onClose: (() -> Void)? = nil
    /// 撤销回调；非空时显示「撤销」按钮（局间休息/局中休息等与 Watch、鸿蒙一致）
    var onUndo: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { onClose?() }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Text(message)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)

                Text(formatTime(remainingSeconds))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "39FF14"))

                if let onUndo = onUndo {
                    Button(action: onUndo) {
                        Text("撤销")
                            .frame(width: 160, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
            )
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

#Preview {
    RestCountdownOverlay(message: "局间休息", remainingSeconds: 90)
}
