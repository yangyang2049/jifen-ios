//
//  RedYellowCardView.swift
//  jifen
//
//  Red/Yellow card tool
//

import SwiftUI

struct RedYellowCardView: View {
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
                    Text("左右滑动切换")
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.bottom, 40)
                }
        }
        .navigationTitle("红黄牌")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RedYellowCardView()
}

