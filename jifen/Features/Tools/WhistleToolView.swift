//
//  WhistleToolView.swift
//  jifen
//
//  Whistle tool - pixel perfect copy from HarmonyOS
//

import SwiftUI

enum WhistleLayoutPolicy {
    static let expandedLayoutThreshold: CGFloat = 600
    static let expandedContentMaxWidth: CGFloat = 800
    static let expandedOuterPadding: CGFloat = 32
    static let cardSpacing: CGFloat = 24
    static let compactCardSize: CGFloat = 240

    static func expandedCardSize(in containerSize: CGSize) -> CGFloat {
        let availableWidth = max(
            0,
            min(
                expandedContentMaxWidth,
                containerSize.width - expandedOuterPadding * 2
            )
        )
        let widthBasedSize = max(0, (availableWidth - cardSpacing) / 2)
        let heightBasedSize = max(0, containerSize.height - expandedOuterPadding * 2)
        return min(widthBasedSize, heightBasedSize)
    }
}

struct WhistleToolView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPlayingShort = false
    @State private var isPlayingLong = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                
                // Content based on device type
                if geometry.size.width > WhistleLayoutPolicy.expandedLayoutThreshold {
                    let cardSize = WhistleLayoutPolicy.expandedCardSize(in: geometry.size)

                    // Tablet: Horizontal layout
                    HStack(spacing: WhistleLayoutPolicy.cardSpacing) {
                        buildShortWhistleCard(cardSize: cardSize)
                        buildLongWhistleCard(cardSize: cardSize)
                    }
                    .frame(maxWidth: WhistleLayoutPolicy.expandedContentMaxWidth)
                    .padding(WhistleLayoutPolicy.expandedOuterPadding)
                } else {
                    // Phone: Vertical layout - centered cards
                    VStack(spacing: WhistleLayoutPolicy.cardSpacing) {
                        Spacer()
                        buildShortWhistleCard()
                        buildLongWhistleCard()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                }
            }
        }
        .navigationTitle(NSLocalizedString("whistle_title", comment: "Whistle title"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func buildShortWhistleCard(
        cardSize: CGFloat = WhistleLayoutPolicy.compactCardSize
    ) -> some View {
        Button(action: playShortWhistle) {
            VStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "4CAF50"))
                    .opacity(isPlayingShort ? 0.6 : 1.0)
                    .scaleEffect(isPlayingShort ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: isPlayingShort ? 0.2 : 0.3), value: isPlayingShort)

                Text(NSLocalizedString("short_whistle", comment: "Short whistle"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .frame(width: cardSize, height: cardSize)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isPlayingShort
                            ? Color(uiColor: .systemGreen).opacity(0.18)
                            : Theme.appCardBackground
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPlayingShort ? Color(hex: "4CAF50") : Color(hex: "4CAF50").opacity(0.3), lineWidth: isPlayingShort ? 3 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPlayingShort || isPlayingLong)
    }
    
    @ViewBuilder
    private func buildLongWhistleCard(
        cardSize: CGFloat = WhistleLayoutPolicy.compactCardSize
    ) -> some View {
        Button(action: playLongWhistle) {
            VStack(spacing: 12) {
                Text("📯")
                    .font(.system(size: 60))
                    .opacity(isPlayingLong ? 0.6 : 1.0)
                    .scaleEffect(isPlayingLong ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: isPlayingLong ? 1.0 : 0.3), value: isPlayingLong)

                Text(NSLocalizedString("long_whistle", comment: "Long whistle"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .frame(width: cardSize, height: cardSize)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isPlayingLong
                            ? Color(uiColor: .systemRed).opacity(0.18)
                            : Theme.appCardBackground
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isPlayingLong ? Color(hex: "F44336") : Color(hex: "F44336").opacity(0.3), lineWidth: isPlayingLong ? 3 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPlayingShort || isPlayingLong)
    }
    
    private func playShortWhistle() {
        guard !isPlayingShort && !isPlayingLong else { return }
        AppAnalytics.track(.toolAction, parameters: [
            .toolID: .string("whistle"),
            .actionName: .string("short_whistle")
        ])
        
        isPlayingShort = true
        VibrationManager.shared.vibrateLight()
        SoundManager.shared.playSound("whistle")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPlayingShort = false
        }
    }
    
    private func playLongWhistle() {
        guard !isPlayingShort && !isPlayingLong else { return }
        AppAnalytics.track(.toolAction, parameters: [
            .toolID: .string("whistle"),
            .actionName: .string("long_whistle")
        ])
        
        isPlayingLong = true
        VibrationManager.shared.vibrateHeavy()
        SoundManager.shared.playSound("buzzer")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isPlayingLong = false
        }
    }
}

#Preview {
    NavigationStack {
        WhistleToolView()
    }
}
