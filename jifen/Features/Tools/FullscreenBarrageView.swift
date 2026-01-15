//
//  FullscreenBarrageView.swift
//  jifen
//
//  Fullscreen barrage tool
//

import SwiftUI

struct FullscreenBarrageView: View {
    @State private var message = ""
    @State private var showInput = true
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            if showInput {
                inputView
            } else {
                barrageView
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var inputView: some View {
        VStack(spacing: 20) {
            Text("全屏弹幕")
                .font(.largeTitle)
                .foregroundColor(Theme.textPrimary)
            
            TextField("输入弹幕内容", text: $message)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            Button(action: { showInput = false }) {
                Text("显示")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .fill(Theme.accentColor)
                    )
            }
            .padding(.horizontal, Theme.padding)
            .disabled(message.isEmpty)
        }
        .padding()
    }
    
    private var barrageView: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            Text(message.isEmpty ? "弹幕内容" : message)
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
                .onTapGesture {
                    showInput = true
                }
        }
    }
}

#Preview {
    FullscreenBarrageView()
}

