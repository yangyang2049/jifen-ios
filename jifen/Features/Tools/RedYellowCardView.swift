//
//  RedYellowCardView.swift
//  jifen
//
//  Red/Yellow card tool
//

import SwiftUI

struct RedYellowCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $currentIndex) {
                    // Yellow Card
                    Color(hex: "FFEB3B")
                        .ignoresSafeArea()
                        .tag(0)
                    
                    // Red Card
                    Color(hex: "F44336")
                        .ignoresSafeArea()
                        .tag(1)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                
                // Hint
                VStack {
                    Spacer()
                    Text(NSLocalizedString("swipe_to_switch", comment: "Swipe to switch"))
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.bottom, 40)
                }
        }
        .navigationTitle(NSLocalizedString("red_yellow_card_title", comment: "Red Yellow Card title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RedYellowCardView()
}
