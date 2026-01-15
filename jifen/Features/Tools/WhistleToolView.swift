//
//  WhistleToolView.swift
//  jifen
//
//  Whistle tool - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct WhistleToolView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPlayingShort = false
    @State private var isPlayingLong = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Content based on device type
                if geometry.size.width > 600 {
                    // Tablet: Horizontal layout
                    HStack(spacing: 24) {
                        buildShortWhistleCard()
                        buildLongWhistleCard()
                    }
                    .padding(32)
                } else {
                    // Phone: Vertical layout
                    VStack(spacing: 16) {
                        buildShortWhistleCard()
                        buildLongWhistleCard()
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("哨声")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private func buildShortWhistleCard() -> some View {
        Button(action: playShortWhistle) {
            VStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "4CAF50"))
                    .opacity(isPlayingShort ? 0.6 : 1.0)
                    .scaleEffect(isPlayingShort ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: isPlayingShort ? 0.2 : 0.3), value: isPlayingShort)
                
                Text("短哨")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(width: 300, height: 300)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isPlayingShort ? Color(hex: "4CAF50").opacity(0.3) : Color(hex: "4CAF50").opacity(0.1))
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
    private func buildLongWhistleCard() -> some View {
        Button(action: playLongWhistle) {
            VStack(spacing: 12) {
                Text("📯")
                    .font(.system(size: 60))
                    .opacity(isPlayingLong ? 0.6 : 1.0)
                    .scaleEffect(isPlayingLong ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: isPlayingLong ? 1.0 : 0.3), value: isPlayingLong)
                
                Text("长哨")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isPlayingLong ? Color(hex: "F44336").opacity(0.3) : Color(hex: "F44336").opacity(0.1))
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
        
        isPlayingShort = true
        VibrationManager.shared.vibrateLight()
        SoundManager.shared.playSound("whistle")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPlayingShort = false
        }
    }
    
    private func playLongWhistle() {
        guard !isPlayingShort && !isPlayingLong else { return }
        
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
