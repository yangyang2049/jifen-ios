import SwiftUI

struct WatchRandomNumberView: View {
    @State private var fingerScale: CGFloat = 1
    @State private var randomNumber: Int = 0
    @State private var showNumber: Bool = false
    @State private var numberScale: CGFloat = 0
    @State private var numberOpacity: Double = 0
    @State private var history: [Int] = []
    @State private var showHistoryOverlay: Bool = false

    private let historyRowHeight: CGFloat = 34

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: historyRowHeight)

                Spacer()

                if !showNumber {
                    Text("👆")
                        .font(.system(size: 40))
                        .scaleEffect(fingerScale)
                } else {
                    Text("\(randomNumber)")
                        .font(.system(size: 84, weight: .bold))
                        .foregroundColor(WatchTheme.accent)
                        .scaleEffect(numberScale)
                        .opacity(numberOpacity)
                }

                Spacer()

                historyRow
                    .frame(height: historyRowHeight)
            }

            if showHistoryOverlay {
                historyOverlay
            }
        }
        .onTapGesture {
            guard !showHistoryOverlay else { return }
            generateNumber()
        }
    }

    private var recentHistory: [Int] {
        Array(history.suffix(4))
    }

    private var historyRow: some View {
        Group {
            if !showHistoryOverlay, !history.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recentHistory, id: \.self) { value in
                        historyBubble(text: "\(value)")
                    }
                    if history.count > 4 {
                        historyBubble(text: "···")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showHistoryOverlay = true
                }
            } else {
                Color.clear
            }
        }
    }

    private func historyBubble(text: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 26, height: 26)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: 0xD0D0D0))
        }
    }

    private var historyOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    showHistoryOverlay = false
                }

            VStack(spacing: 8) {
                Text("记录")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.indices.reversed(), id: \.self) { idx in
                            let num = history[idx]
                            HStack {
                                Text("#\(history.count - idx)")
                                    .font(.system(size: 12))
                                    .foregroundColor(WatchTheme.secondaryText)
                                    .frame(width: 40, alignment: .leading)

                                Text("\(num)")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(WatchTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)

                            if idx != history.indices.first {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }

            }
            .frame(width: 140, height: 170)
            .background(WatchTheme.card)
            .cornerRadius(16)
        }
    }

    private func generateNumber() {
        triggerFingerFeedback()
        WatchHaptics.shared.play(.light)
        randomNumber = Int.random(in: 1...100)
        showNumber = true
        numberScale = 0
        numberOpacity = 0

        withAnimation(.easeOut(duration: 0.3)) {
            numberScale = 1
            numberOpacity = 1
        }

        history.append(randomNumber)
        if history.count > 20 {
            history = Array(history.suffix(20))
        }
    }

    private func triggerFingerFeedback() {
        withAnimation(.easeOut(duration: WatchAnimations.fingerFeedback)) {
            fingerScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + WatchAnimations.delayStart) {
            withAnimation(.easeOut(duration: WatchAnimations.fingerFeedback)) {
                fingerScale = 1.0
            }
        }
    }
}
