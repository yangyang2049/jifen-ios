//
//  FullscreenBarrageView.swift
//  jifen
//
//  Fullscreen barrage tool
//

import SwiftUI

struct FullscreenBarrageView: View {
    @Environment(\.dismiss) private var dismiss
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
        .navigationTitle(NSLocalizedString("fullscreen_barrage", comment: "Fullscreen Barrage title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var inputView: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("fullscreen_barrage", comment: "Fullscreen Barrage"))
                .font(.largeTitle)
                .foregroundColor(Theme.textPrimary)
            
            TextField(NSLocalizedString("enter_barrage_content", comment: "Enter barrage content"), text: $message)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            Button(action: { showInput = false }) {
                Text(NSLocalizedString("show", comment: "Show"))
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
            
            Text(message.isEmpty ? NSLocalizedString("barrage_content", comment: "Barrage Content") : message)
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

