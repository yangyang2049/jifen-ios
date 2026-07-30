import SwiftUI
import UIKit

struct FullscreenBarrageOverlayPadding: Equatable {
    let top: CGFloat
    let leading: CGFloat
    let trailing: CGFloat
}

enum FullscreenBarrageOverlayLayout {
    /// Keep the controls just clear of the system safe area without creating
    /// an oversized empty band around the full-screen content.
    static let extraClearance: CGFloat = 6
    static let minimumHorizontalPadding: CGFloat = 16

    static func padding(
        for safeAreaInsets: UIEdgeInsets,
        rotatesContentClockwise: Bool
    ) -> FullscreenBarrageOverlayPadding {
        // When the display surface is rotated clockwise inside a resizable
        // iPad window, its logical top/leading/trailing edges map to the
        // window's right/top/bottom edges respectively.
        let logicalTop = rotatesContentClockwise ? safeAreaInsets.right : safeAreaInsets.top
        let logicalLeading = rotatesContentClockwise ? safeAreaInsets.top : safeAreaInsets.left
        let logicalTrailing = rotatesContentClockwise ? safeAreaInsets.bottom : safeAreaInsets.right

        return FullscreenBarrageOverlayPadding(
            top: max(0, logicalTop) + extraClearance,
            leading: max(minimumHorizontalPadding, max(0, logicalLeading) + extraClearance),
            trailing: max(minimumHorizontalPadding, max(0, logicalTrailing) + extraClearance)
        )
    }
}

struct FullscreenBarrageView: View {
    private enum DisplayMode: String, CaseIterable {
        case scroll
        case `static`
    }

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var mode: DisplayMode = .scroll
    @State private var isRunning = false
    @State private var showEditor = false
    @State private var fontSize: Double = Theme.usesPadLayout ? 120 : 80
    @State private var speed: Double = 15
    @State private var textColor = Color.white
    @State private var backgroundColor = Color.black
    @State private var scrollStartedAt = Date()
    @State private var entryOrientation: UIInterfaceOrientationMask = .portrait
    /// iPad windowed modes (Stage Manager / resizable windows) reject scene
    /// orientation requests. Rotate the full display surface in that case so
    /// the user-facing rotate action still works for both barrage modes.
    @State private var usesContentRotationFallback = false
    /// Invalidates UIKit geometry callbacks after another rotate request or
    /// after this screen begins restoring its entry orientation.
    @State private var orientationRequestGeneration = 0

    private let textColors: [Color] = [
        .white, Color(hex: "FF3B30"), Color(hex: "FFD60A"), Color(hex: "30D158"),
        Color(hex: "0A84FF"), Color(hex: "EC4899"), Color(hex: "00FFFF")
    ]
    private let backgroundColors: [Color] = [
        .black, .white, Color(hex: "808080"), Color(hex: "3F3F3F"),
        Color(hex: "007AFF"), Color(hex: "34C759"), Color(hex: "FF3B30"), Color(hex: "8B6914")
    ]

    var body: some View {
        ZStack {
            if isRunning {
                runningDisplay
            } else {
                settingsPage
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: prepareOrientation)
        .onDisappear(perform: restoreOrientation)
        .preferredColorScheme(colorSchemeForBackground)
    }

    private var settingsPage: some View {
        ZStack(alignment: .topLeading) {
            Theme.backgroundColor.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(NSLocalizedString("barrage_text_label", value: "弹幕文字", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)

                    TextField(
                        NSLocalizedString("barrage_input_placeholder", value: "输入要展示的内容", comment: ""),
                        text: $message,
                        axis: .vertical
                    )
                    .accessibilityIdentifier("barrage_message_field")
                    .font(.system(size: 18))
                    .padding(14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    sliderRow(
                        title: NSLocalizedString("barrage_font_size", value: "字体大小", comment: ""),
                        value: $fontSize,
                        range: 20...200,
                        step: 5
                    )

                    sliderRow(
                        title: NSLocalizedString("barrage_scroll_speed", value: "滚动速度", comment: ""),
                        value: $speed,
                        range: 5...50,
                        step: 1
                    )

                    colorPickerRow(
                        title: NSLocalizedString("barrage_text_color", value: "文字颜色", comment: ""),
                        colors: textColors,
                        selection: $textColor
                    )
                    colorPickerRow(
                        title: NSLocalizedString("barrage_bg_color", value: "背景颜色", comment: ""),
                        colors: backgroundColors,
                        selection: $backgroundColor
                    )

                    HStack(spacing: 12) {
                        displayButton(
                            NSLocalizedString("barrage_scroll_display", value: "滚动显示", comment: ""),
                            color: Theme.primary,
                            mode: .scroll
                        )
                        displayButton(
                            NSLocalizedString("barrage_static_display", value: "静态显示", comment: ""),
                            color: Color(hex: "16A34A"),
                            mode: .static
                        )
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, Theme.padding)
                .padding(.top, 76)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }

            VStack {
                HStack {
                    overlayButton(systemName: "chevron.left", label: NSLocalizedString("back", value: "返回", comment: "")) {
                        dismiss()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .accessibilityIdentifier("barrage_settings")
    }

    private var runningDisplay: some View {
        GeometryReader { container in
            let displaySize = usesContentRotationFallback
                ? CGSize(width: container.size.height, height: container.size.width)
                : container.size
            let overlayPadding = FullscreenBarrageOverlayLayout.padding(
                for: activeWindowSafeAreaInsets,
                rotatesContentClockwise: usesContentRotationFallback
            )

            runningDisplaySurface(width: displaySize.width, overlayPadding: overlayPadding)
                .frame(width: displaySize.width, height: displaySize.height)
                .rotationEffect(.degrees(usesContentRotationFallback ? 90 : 0))
                .position(x: container.size.width / 2, y: container.size.height / 2)
                .animation(.easeInOut(duration: 0.25), value: usesContentRotationFallback)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("barrage_running")
        .accessibilityValue(usesContentRotationFallback ? "content_rotated" : "window_orientation")
    }

    private func runningDisplaySurface(
        width: CGFloat,
        overlayPadding: FullscreenBarrageOverlayPadding
    ) -> some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if mode == .static {
                Text(message)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.2)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                scrollingText(width: width)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if showEditor {
                    runningEditor
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    runningOverlayButtons(padding: overlayPadding)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func scrollingText(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let estimatedTextWidth = max(fontSize * max(1, Double(message.count)) * 0.72, Double(width))
            let distance = Double(width) + estimatedTextWidth
            let duration = max(2.0, 20.0 / max(1, speed))
            let elapsed = context.date.timeIntervalSince(scrollStartedAt)
            let phase = elapsed.truncatingRemainder(dividingBy: duration) / duration
            let offset = Double(width) - distance * phase

            Text(message)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func runningOverlayButtons(padding: FullscreenBarrageOverlayPadding) -> some View {
        HStack(spacing: 12) {
            overlayButton(systemName: "chevron.left", label: NSLocalizedString("back", value: "返回", comment: "")) {
                // Exit fullscreen display back to settings (replaces removed close button).
                AppAnalytics.track(.toolAction, parameters: [
                    .toolID: .string("fullscreen_barrage"),
                    .actionName: .string("stop_display"),
                    .displayMode: .string(mode.rawValue)
                ])
                invalidateOrientationRequests()
                isRunning = false
                showEditor = false
            }
            .accessibilityIdentifier("barrage_running_back")
            Spacer(minLength: 8)
            overlayButton(systemName: "rectangle.portrait.rotate", label: NSLocalizedString("rotate_display", value: "旋转屏幕", comment: "")) {
                rotateScreen()
            }
            .accessibilityIdentifier("barrage_running_rotate")
            overlayButton(systemName: "pencil", label: NSLocalizedString("edit", value: "编辑", comment: "")) {
                withAnimation(.easeInOut(duration: 0.2)) { showEditor = true }
            }
            .accessibilityIdentifier("barrage_running_edit")
        }
        .padding(.leading, padding.leading)
        .padding(.trailing, padding.trailing)
        .padding(.top, padding.top)
    }

    private var runningEditor: some View {
        VStack(spacing: 12) {
            TextField(NSLocalizedString("barrage_input_placeholder", value: "输入要展示的内容", comment: ""), text: $message)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(Color(hex: "374151").opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                Button(NSLocalizedString("barrage_scroll_mode", value: "滚动", comment: "")) {
                    mode = .scroll
                    scrollStartedAt = Date()
                }
                .buttonStyle(BarrageModeButtonStyle(color: Theme.primary))
                .frame(maxWidth: .infinity)

                Button(NSLocalizedString("barrage_static_mode", value: "静态", comment: "")) {
                    mode = .static
                }
                .buttonStyle(BarrageModeButtonStyle(color: Color(hex: "16A34A")))
                .frame(maxWidth: .infinity)
            }

            compactSlider(title: NSLocalizedString("barrage_font_size", value: "字号", comment: ""), value: $fontSize, range: 20...200)
            compactSlider(title: NSLocalizedString("barrage_scroll_speed", value: "速度", comment: ""), value: $speed, range: 5...50)

            compactColors(colors: textColors, selection: $textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            compactColors(colors: backgroundColors, selection: $backgroundColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showEditor = false }
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 44, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(hex: "1F2937").opacity(0.96))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(Theme.textPrimary)
            }
            .font(.subheadline.weight(.medium))
            Slider(value: value, in: range, step: step).tint(Theme.primary)
        }
    }

    private func colorPickerRow(title: String, colors: [Color], selection: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        colorButton(color: color, selected: colorsEqual(color, selection.wrappedValue)) {
                            selection.wrappedValue = color
                        }
                    }
                }
                // Leave room for the selection stroke so it isn't clipped by the scroll view.
                .padding(.vertical, 4)
            }
        }
    }

    private func compactSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(Int(value.wrappedValue))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Slider(value: value, in: range).tint(Theme.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func compactColors(colors: [Color], selection: Binding<Color>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    colorButton(color: color, selected: colorsEqual(color, selection.wrappedValue), size: 28) {
                        selection.wrappedValue = color
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func colorButton(color: Color, selected: Bool, size: CGFloat = 40, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(selected ? Theme.primary : Color.gray.opacity(0.45), lineWidth: selected ? 3 : 1)
                )
                // Always pad for the thicker selection stroke so layout doesn't jump.
                .padding(3)
        }
        .buttonStyle(.plain)
    }

    private func displayButton(_ title: String, color: Color, mode: DisplayMode) -> some View {
        let isDisabled = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            start(mode)
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(isDisabled ? Theme.textSecondary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(isDisabled ? Theme.controlBackground : color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode == .scroll ? "barrage_start_scroll" : "barrage_start_static")
        .disabled(isDisabled)
    }

    private func overlayButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func start(_ newMode: DisplayMode) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        message = trimmed
        mode = newMode
        scrollStartedAt = Date()
        showEditor = false
        isRunning = true
        AppAnalytics.track(.toolAction, parameters: [
            .toolID: .string("fullscreen_barrage"),
            .actionName: .string("start_display"),
            .displayMode: .string(newMode.rawValue)
        ])
    }

    private func colorsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
        UIColor(lhs).resolvedColor(with: .current).cgColor == UIColor(rhs).resolvedColor(with: .current).cgColor
    }

    private var colorSchemeForBackground: ColorScheme? {
        isRunning && colorsEqual(backgroundColor, .white) ? .light : nil
    }

    private func prepareOrientation() {
        invalidateOrientationRequests()
        if let scene = activeWindowScene {
            entryOrientation = scene.interfaceOrientation.isLandscape
                ? (scene.interfaceOrientation == .landscapeLeft ? .landscapeLeft : .landscapeRight)
                : .portrait
        }
        OrientationLock.shared.lock(.allButUpsideDown)
        updateSupportedOrientations()
    }

    private func rotateScreen() {
        guard let scene = activeWindowScene else { return }
        let requestGeneration = nextOrientationRequestGeneration()

        if usesContentRotationFallback {
            usesContentRotationFallback = false
            return
        }

        // A resizable iPad window cannot change the scene's interface
        // orientation programmatically. Swapping and rotating the complete
        // display surface produces the same result without issuing a request
        // that the system is guaranteed to reject.
        if Theme.usesPadLayout, !scene.isFullScreen {
            OrientationLock.shared.lock(.all)
            updateSupportedOrientations(in: scene)
            usesContentRotationFallback = true
            return
        }

        let target: UIInterfaceOrientationMask = scene.interfaceOrientation.isPortrait ? .landscapeRight : .portrait
        OrientationLock.shared.lock(target)
        updateSupportedOrientations(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
            // Windowing state can change between the button tap and UIKit
            // handling the request. Fall back to rotating the content instead
            // of leaving the button with no visible effect.
            DispatchQueue.main.async {
                guard orientationRequestGeneration == requestGeneration, isRunning else { return }
                OrientationLock.shared.lock(
                    Theme.usesPadLayout ? .all : .allButUpsideDown
                )
                updateSupportedOrientations(in: scene)
                usesContentRotationFallback = true
            }
        }
    }

    private func restoreOrientation() {
        let requestGeneration = nextOrientationRequestGeneration()
        usesContentRotationFallback = false
        guard let scene = activeWindowScene else {
            OrientationLock.shared.unlock()
            return
        }

        if Theme.usesPadLayout, !scene.isFullScreen {
            OrientationLock.shared.unlock()
            updateSupportedOrientations(in: scene)
            return
        }

        OrientationLock.shared.lock(entryOrientation)
        updateSupportedOrientations(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: entryOrientation)) { _ in
            DispatchQueue.main.async {
                guard orientationRequestGeneration == requestGeneration else { return }
                OrientationLock.shared.unlock()
                updateSupportedOrientations(in: scene)
            }
        }
    }

    @discardableResult
    private func nextOrientationRequestGeneration() -> Int {
        orientationRequestGeneration &+= 1
        return orientationRequestGeneration
    }

    private func invalidateOrientationRequests() {
        orientationRequestGeneration &+= 1
    }

    private func updateSupportedOrientations(in scene: UIWindowScene? = nil) {
        (scene ?? activeWindowScene)?.windows.first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private var activeWindowSafeAreaInsets: UIEdgeInsets {
        activeWindowScene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }
}

private struct BarrageModeButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(color.opacity(configuration.isPressed ? 0.7 : 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    NavigationStack { FullscreenBarrageView() }
}
