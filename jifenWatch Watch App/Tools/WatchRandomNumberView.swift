import SwiftUI

struct WatchRandomNumberView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fingerScale: CGFloat = 1
    @State private var tapHintPulse: CGFloat = 1.0
    @State private var randomNumber: Int = 0
    @State private var showNumber: Bool = false
    @State private var numberScale: CGFloat = 0
    @State private var numberOpacity: Double = 0
    @State private var history: [Int] = []
    @State private var showHistoryOverlay: Bool = false
    /// 随机数范围上限：1–10 或 1–100（对齐鸿蒙 WatchRandomNumber 的双档）。
    /// 默认沿用 iOS 既有的 1–100，不静默改变老用户的结果分布。
    @AppStorage("watch_random_number_range_max") private var rangeMax: Int = 100

    private let historyRowHeight: CGFloat = 34

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                rangePicker
                    .frame(height: historyRowHeight)

                Spacer()

                if !showNumber {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(WatchTheme.accent)
                        .scaleEffect(fingerScale * tapHintPulse)
                        .accessibilityHidden(true)
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
        .onAppear {
            startTapHintPulse()
        }
        .onChange(of: showNumber) { _, isShowingNumber in
            if !isShowingNumber {
                startTapHintPulse()
            } else {
                tapHintPulse = 1.0
            }
        }
        .navigationTitle(
            showHistoryOverlay
                ? ""
                : NSLocalizedString("tool_random_number", comment: "Random Number")
        )
        .navigationBarTitleDisplayMode(.inline)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    private func startTapHintPulse() {
        tapHintPulse = 1.0
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            tapHintPulse = 1.15
        }
    }

    /// 两段式胶囊开关：直接展示 1–10 与 1–100，消除隐藏切换入口的可发现性问题。
    private var rangePicker: some View {
        let compact = WatchLayout.isCompactScreen
        return HStack(spacing: 2) {
            rangeOptionButton(max: 10, compact: compact)
            rangeOptionButton(max: 100, compact: compact)
        }
        .padding(2)
        .background(Color.white.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch_random_number_range")
    }

    private func rangeOptionButton(max: Int, compact: Bool) -> some View {
        let selected = rangeMax == max
        return Button {
            guard rangeMax != max else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                rangeMax = max
            }
            WatchHaptics.shared.play(.light)
        } label: {
            Text("1–\(max)")
                .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : WatchTheme.secondaryText)
                .padding(.horizontal, compact ? 9 : 11)
                .frame(height: compact ? 22 : 24)
                .background(
                    selected ? Color.white.opacity(0.26) : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch_random_number_range_\(max)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var recentHistory: [Int] {
        Array(history.suffix(4))
    }

    private var historyRow: some View {
        Group {
            if !showHistoryOverlay, !history.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(recentHistory.enumerated()), id: \.offset) { _, value in
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
        let compact = WatchLayout.isCompactScreen
        return ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture {
                    showHistoryOverlay = false
                }

            VStack(spacing: 0) {
                WatchDialogHeader(
                    title: NSLocalizedString("records", comment: "Records"),
                    onClose: { showHistoryOverlay = false }
                )
                .padding(.bottom, compact ? 6 : 10)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.indices.reversed(), id: \.self) { idx in
                            let num = history[idx]
                            HStack {
                                Text("#\(history.count - idx)")
                                    .font(.system(size: 12))
                                    .foregroundColor(WatchTheme.secondaryText)
                                    .frame(width: 38, alignment: .leading)

                                Text("\(num)")
                                    .font(.system(size: compact ? 18 : 20, weight: .medium))
                                    .foregroundColor(WatchTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: compact ? 38 : 42)

                            if idx != history.indices.first {
                                Rectangle()
                                    .fill(WatchTheme.subtleFill)
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, compact ? 8 : 10)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 152 : 186)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.top, compact ? 22 : 26)
            .padding(.bottom, compact ? 4 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func generateNumber() {
        triggerFingerFeedback()
        WatchHaptics.shared.play(.light)
        randomNumber = Int.random(in: 1...max(2, rangeMax))
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
