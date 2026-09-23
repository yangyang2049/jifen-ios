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
        // Full-screen card color with a floating back button instead of a
        // navigation bar.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            FloatingBackButton(
                iconColor: currentIndex == 0 ? .black.opacity(0.75) : .white,
                circleColor: currentIndex == 0 ? Color.black.opacity(0.08) : Color.white.opacity(0.18)
            ) {
                dismiss()
            }
            .padding(.leading, 16)
            .padding(.top, 4)
        }
        .onChange(of: currentIndex) { _, value in
            AppAnalytics.track(.toolAction, parameters: [
                .itemID: .string("red_yellow_card"),
                .actionName: .string(value == 0 ? "show_yellow" : "show_red")
            ])
        }
    }
}

#Preview {
    RedYellowCardView()
}
