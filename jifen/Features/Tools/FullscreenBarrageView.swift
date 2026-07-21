import SwiftUI
import UIKit

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
    @State private var fontSize: Double = UIDevice.current.userInterfaceIdiom == .pad ? 120 : 80
    @State private var speed: Double = 15
    @State private var textColor = Color.white
    @State private var backgroundColor = Color.black
    @State private var scrollStartedAt = Date()
    @State private var entryOrientation: UIInterfaceOrientationMask = .portrait

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
                            color: Color(hex: "2563EB"),
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

            overlayButton(systemName: "chevron.left", label: NSLocalizedString("back", value: "返回", comment: "")) {
                dismiss()
            }
            .padding(.leading, 16)
            .padding(.top, 10)
        }
        .accessibilityIdentifier("barrage_settings")
    }

    private var runningDisplay: some View {
        GeometryReader { geometry in
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
                } else {
                    scrollingText(width: geometry.size.width)
                }

                if showEditor {
                    runningEditor
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    runningOverlayButtons
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("barrage_running")
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

    private var runningOverlayButtons: some View {
        VStack {
            HStack {
                overlayButton(systemName: "chevron.left", label: NSLocalizedString("back", value: "返回", comment: "")) {
                    dismiss()
                }
                Spacer()
                if UIDevice.current.userInterfaceIdiom == .phone {
                    overlayButton(systemName: "rectangle.portrait.rotate", label: NSLocalizedString("rotate_display", value: "旋转屏幕", comment: "")) {
                        rotateScreen()
                    }
                }
                overlayButton(systemName: "pencil", label: NSLocalizedString("edit", value: "编辑", comment: "")) {
                    withAnimation(.easeInOut(duration: 0.2)) { showEditor = true }
                }
                overlayButton(systemName: "xmark", label: NSLocalizedString("close", value: "关闭", comment: "")) {
                    isRunning = false
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Spacer()
        }
    }

    private var runningEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField(NSLocalizedString("barrage_input_placeholder", value: "输入要展示的内容", comment: ""), text: $message)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color(hex: "374151").opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(NSLocalizedString("barrage_scroll_mode", value: "滚动", comment: "")) {
                    mode = .scroll
                    scrollStartedAt = Date()
                }
                .buttonStyle(BarrageModeButtonStyle(color: Color(hex: "2563EB")))

                Button(NSLocalizedString("barrage_static_mode", value: "静态", comment: "")) {
                    mode = .static
                }
                .buttonStyle(BarrageModeButtonStyle(color: Color(hex: "16A34A")))
            }

            HStack(spacing: 16) {
                compactSlider(title: NSLocalizedString("barrage_font_size", value: "字号", comment: ""), value: $fontSize, range: 20...200)
                compactSlider(title: NSLocalizedString("barrage_scroll_speed", value: "速度", comment: ""), value: $speed, range: 5...50)
            }

            HStack {
                compactColors(colors: textColors, selection: $textColor)
                Spacer(minLength: 16)
                compactColors(colors: backgroundColors, selection: $backgroundColor)
            }

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
        .background(Color(hex: "1F2937").opacity(0.96))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .frame(maxHeight: .infinity, alignment: .top)
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
            }
        }
    }

    private func compactSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(Int(value.wrappedValue))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Slider(value: value, in: range).tint(.blue)
        }
        .frame(maxWidth: 180)
    }

    private func compactColors(colors: [Color], selection: Binding<Color>) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(colors.prefix(6).enumerated()), id: \.offset) { _, color in
                colorButton(color: color, selected: colorsEqual(color, selection.wrappedValue), size: 28) {
                    selection.wrappedValue = color
                }
            }
        }
    }

    private func colorButton(color: Color, selected: Bool, size: CGFloat = 40, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(selected ? Theme.primary : Color.gray.opacity(0.45), lineWidth: selected ? 3 : 1))
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
    }

    private func colorsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
        UIColor(lhs).resolvedColor(with: .current).cgColor == UIColor(rhs).resolvedColor(with: .current).cgColor
    }

    private var colorSchemeForBackground: ColorScheme? {
        isRunning && colorsEqual(backgroundColor, .white) ? .light : nil
    }

    private func prepareOrientation() {
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
        let target: UIInterfaceOrientationMask = scene.interfaceOrientation.isPortrait ? .landscapeRight : .portrait
        OrientationLock.shared.lock(target)
        updateSupportedOrientations(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
            #if DEBUG
            print("[FullscreenBarrage] Rotation failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func restoreOrientation() {
        guard let scene = activeWindowScene else {
            OrientationLock.shared.unlock()
            return
        }
        OrientationLock.shared.lock(entryOrientation)
        updateSupportedOrientations(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: entryOrientation)) { error in
            #if DEBUG
            print("[FullscreenBarrage] Restore orientation failed: \(error.localizedDescription)")
            #endif
        }
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
}

private struct BarrageModeButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(color.opacity(configuration.isPressed ? 0.7 : 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    NavigationStack { FullscreenBarrageView() }
}
