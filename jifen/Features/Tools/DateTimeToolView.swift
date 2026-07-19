//
//  DateTimeToolView.swift
//  jifen
//
//  Full-screen flip clock, aligned with the Android and HarmonyOS versions.
//

import SwiftUI

struct DateTimeToolView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let layout = FlipClockLayoutMetrics(
                size: geometry.size,
                isPad: UIDevice.current.userInterfaceIdiom == .pad
            )

            ZStack {
                Color(hex: "0D0D0D")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        FlipClockFace(date: context.date, layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear(perform: allowClockOrientations)
        .onDisappear {
            OrientationLock.shared.unlock()
        }
    }

    private var topBar: some View {
        HStack {
            clockToolbarButton(
                systemName: "chevron.left",
                accessibilityLabel: NSLocalizedString("back", value: "返回", comment: "Back")
            ) {
                dismiss()
            }

            Spacer()

            if UIDevice.current.userInterfaceIdiom == .phone {
                clockToolbarButton(
                    systemName: "rectangle.portrait.rotate",
                    accessibilityLabel: NSLocalizedString(
                        "rotate_display",
                        value: "旋转屏幕",
                        comment: "Rotate display"
                    )
                ) {
                    rotateScreen()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func clockToolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func allowClockOrientations() {
        OrientationLock.shared.lock(.allButUpsideDown)
        updateSupportedOrientations()
    }

    private func rotateScreen() {
        guard let windowScene = activeWindowScene else { return }

        let isPortrait = windowScene.interfaceOrientation.isPortrait
        let targetMask: UIInterfaceOrientationMask = isPortrait ? .landscapeRight : .portrait
        OrientationLock.shared.lock(targetMask)
        updateSupportedOrientations(in: windowScene)

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetMask)) { error in
            #if DEBUG
            print("[DateTimeToolView] Failed to rotate display: \(error.localizedDescription)")
            #endif
        }
    }

    private func updateSupportedOrientations(in scene: UIWindowScene? = nil) {
        let windowScene = scene ?? activeWindowScene
        windowScene?.windows.first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

private struct FlipClockFace: View {
    let date: Date
    let layout: FlipClockLayoutMetrics

    private var digits: [Int] {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        return [hour / 10, hour % 10, minute / 10, minute % 10, second / 10, second % 10]
    }

    var body: some View {
        Group {
            if layout.isHorizontal {
                HStack(spacing: layout.groupGap) {
                    digitPair(startingAt: 0)
                    digitPair(startingAt: 2)
                    digitPair(startingAt: 4)
                }
            } else {
                VStack(spacing: layout.groupGap) {
                    digitPair(startingAt: 0)
                    digitPair(startingAt: 2)
                    digitPair(startingAt: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTime)
    }

    private func digitPair(startingAt index: Int) -> some View {
        HStack(spacing: layout.digitGap) {
            FlipDigitView(
                digit: digits[index],
                cardWidth: layout.cardWidth,
                cardHeight: layout.cardHeight
            )
            FlipDigitView(
                digit: digits[index + 1],
                cardWidth: layout.cardWidth,
                cardHeight: layout.cardHeight
            )
        }
    }

    private var accessibilityTime: String {
        date.formatted(date: .omitted, time: .standard)
    }
}

private struct FlipDigitView: View {
    private static let seamHeight: CGFloat = 2.6
    private static let flipOutDuration: TimeInterval = 0.175
    private static let flipInDuration: TimeInterval = 0.215

    let digit: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @State private var displayDigit: Int
    @State private var topFlapDigit: Int
    @State private var bottomFlapDigit: Int
    @State private var topFlapAngle: Double = 0
    @State private var bottomFlapAngle: Double = 0
    @State private var topShadeOpacity: Double = 0
    @State private var bottomShadeOpacity: Double = 0
    @State private var bottomHighlightOpacity: Double = 0
    @State private var hingeShadowOpacity: Double = 0
    @State private var topFlapZIndex: Double = 3
    @State private var bottomFlapZIndex: Double = 2

    init(digit: Int, cardWidth: CGFloat, cardHeight: CGFloat) {
        let normalizedDigit = min(max(digit, 0), 9)
        self.digit = normalizedDigit
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        _displayDigit = State(initialValue: normalizedDigit)
        _topFlapDigit = State(initialValue: normalizedDigit)
        _bottomFlapDigit = State(initialValue: normalizedDigit)
    }

    var body: some View {
        ZStack(alignment: .top) {
            FlipDigitHalf(
                digit: displayDigit,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                half: .top
            )
            .zIndex(0)

            FlipDigitHalf(
                digit: displayDigit,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                half: .bottom
            )
            .offset(y: halfHeight)
            .zIndex(0)

            FlipDigitHalf(
                digit: topFlapDigit,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                half: .top,
                shadeOpacity: topShadeOpacity
            )
            .rotation3DEffect(
                .degrees(topFlapAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: perspective
            )
            .zIndex(topFlapZIndex)

            FlipDigitHalf(
                digit: bottomFlapDigit,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                half: .bottom,
                shadeOpacity: bottomShadeOpacity,
                highlightOpacity: bottomHighlightOpacity
            )
            .rotation3DEffect(
                .degrees(bottomFlapAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: perspective
            )
            .offset(y: halfHeight)
            .zIndex(bottomFlapZIndex)

            Color(hex: "0A0A0A")
                .frame(width: cardWidth, height: Self.seamHeight)
                .offset(y: halfHeight - Self.seamHeight / 2)
                .zIndex(10)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(
            color: .black.opacity(0.58 + hingeShadowOpacity * 0.22),
            radius: 6 + hingeShadowOpacity * 10,
            y: 3 + hingeShadowOpacity * 5
        )
        .task(id: digit) {
            await flip(to: digit)
        }
    }

    private var halfHeight: CGFloat {
        cardHeight / 2
    }

    private var perspective: CGFloat {
        1 / max(cardHeight * 3.2, 360)
    }

    @MainActor
    private func flip(to newDigit: Int) async {
        guard displayDigit != newDigit else { return }

        let oldDigit = displayDigit
        topFlapDigit = oldDigit
        bottomFlapDigit = newDigit
        topFlapAngle = 0
        bottomFlapAngle = 90
        topShadeOpacity = 0
        bottomShadeOpacity = 0.68
        bottomHighlightOpacity = 0.16
        hingeShadowOpacity = 0
        topFlapZIndex = 4
        bottomFlapZIndex = 2

        withAnimation(.timingCurve(0.55, 0.05, 0.85, 0.35, duration: Self.flipOutDuration)) {
            topFlapAngle = -90
            topShadeOpacity = 0.74
            hingeShadowOpacity = 0.32
        }

        do {
            try await Task.sleep(nanoseconds: UInt64(Self.flipOutDuration * 1_000_000_000))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        displayDigit = newDigit
        topFlapDigit = newDigit
        topFlapAngle = 0
        topShadeOpacity = 0
        topFlapZIndex = 2
        bottomFlapZIndex = 4

        withAnimation(.timingCurve(0.12, 0.75, 0.18, 1, duration: Self.flipInDuration)) {
            bottomFlapAngle = 0
            bottomShadeOpacity = 0
            bottomHighlightOpacity = 0
            hingeShadowOpacity = 0
        }

        do {
            try await Task.sleep(nanoseconds: UInt64(Self.flipInDuration * 1_000_000_000))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        topFlapZIndex = 3
        bottomFlapZIndex = 2
    }
}

private struct FlipDigitHalf: View {
    enum Half {
        case top
        case bottom
    }

    let digit: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let half: Half
    var shadeOpacity: Double = 0
    var highlightOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "181818")

            Canvas { context, size in
                let glyph = context.resolve(
                    Text(String(digit))
                        .font(.system(size: cardHeight * 0.72, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                )
                context.draw(
                    glyph,
                    at: CGPoint(
                        x: size.width / 2,
                        y: half == .top ? cardHeight / 2 : 0
                    ),
                    anchor: .center
                )
            }
            .frame(width: cardWidth, height: halfHeight)

            if shadeOpacity > 0 {
                Color.black.opacity(shadeOpacity)
            }

            if highlightOpacity > 0 {
                Color.white.opacity(highlightOpacity)
            }
        }
        .frame(width: cardWidth, height: halfHeight)
        .clipShape(halfShape)
    }

    private var halfHeight: CGFloat {
        cardHeight / 2
    }

    private var halfShape: UnevenRoundedRectangle {
        switch half {
        case .top:
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
        case .bottom:
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
        }
    }
}

private struct FlipClockLayoutMetrics {
    private static let landscapeCardAspect: CGFloat = 1.55

    let isHorizontal: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let digitGap: CGFloat
    let groupGap: CGFloat

    init(size: CGSize, isPad: Bool) {
        isHorizontal = isPad || size.width > size.height

        if isHorizontal {
            digitGap = 4
            groupGap = isPad ? 32 : 12

            let totalGroupSpacing = groupGap * 2
            let totalDigitSpacing = digitGap * 3
            let widthLimit = max((size.width - 48 - totalGroupSpacing - totalDigitSpacing) / 6, 1)
            let heightLimit = max((size.height - 80) * 0.88 / Self.landscapeCardAspect, 1)
            let platformMaximum: CGFloat = isPad ? 160 : .greatestFiniteMagnitude
            cardWidth = max(min(min(widthLimit, heightLimit), platformMaximum), 44)
            cardHeight = cardWidth * Self.landscapeCardAspect
        } else {
            digitGap = 6
            groupGap = 20

            let availableWidth = max(min(size.width - 64, 340), 1)
            cardWidth = availableWidth * 0.42
            let heightLimit = max((size.height - 120 - groupGap * 2) / 3, 1)
            cardHeight = max(min(heightLimit, cardWidth * 1.55), 112)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            DateTimeToolView()
        }
    }
#endif
