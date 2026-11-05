import SwiftUI

/// Bounded reels keep the initial animation at 1.2 s, even for large totals.
struct RollingRecordStatistic: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from = 0
    @State private var to = 0
    @State private var progress = 1.0
    @State private var first = true
    @State private var hasShownNonZero = false

    var body: some View {
        RecordStatisticReels(from: from, to: to, progress: progress, first: first)
            .font(.title2)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(max(0, value))))
            .task(id: value) {
                let target = max(0, value)
                guard target != to else {
                    // A task can be cancelled during its first layout pass when leaving the page.
                    if progress < 1 {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { progress = 1 }
                    }
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    from = to
                    to = target
                    first = !hasShownNonZero
                    hasShownNonZero = hasShownNonZero || target > 0
                    progress = reduceMotion ? 1 : 0
                }
                guard !reduceMotion else { return }
                // Give the zero-position reels a layout pass before moving them.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: first ? 1.2 : 0.35)) { progress = 1 }
            }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { progress = 1 }
                }
            }
    }
}

private struct RecordStatisticReels: View, Animatable {
    let from: Int
    let to: Int
    var progress: Double
    let first: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var width: Int { String(max(from, to)).count }
    private func digits(_ value: Int) -> [Int] {
        Array((String(repeating: "0", count: width - String(value).count) + String(value))).map { $0.wholeNumberValue ?? 0 }
    }

    var body: some View {
        if progress >= 1 {
            Text(String(to))
        } else {
            let a = digits(from)
            let b = digits(to)
            let direction = to >= from ? 1 : -1
            HStack(spacing: 0) {
                ForEach(0..<width, id: \.self) { index in
                    let steps = ((b[index] - a[index]) * direction + 10) % 10 + (first ? 10 : 0)
                    let duration = first ? 1.2 : 0.35
                    let delay = first ? Double(index) * 0.022 : 0
                    let phase = min(1, max(0, (progress * duration - delay) / (duration - delay)))
                    let eased = 1 - pow(1 - phase, 3)
                    Text("0").hidden().overlay(alignment: .top) {
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                ForEach(0...steps, id: \.self) { step in
                                    Text(String((a[index] + direction * step + 100) % 10))
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }
                            .frame(height: geometry.size.height * CGFloat(steps + 1), alignment: .top)
                            .offset(y: -eased * Double(steps) * geometry.size.height)
                        }
                    }.clipped()
                }
            }
        }
    }
}
