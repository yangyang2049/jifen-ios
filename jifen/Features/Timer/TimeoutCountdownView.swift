import SwiftUI
import UIKit

private enum CountdownMode: String, CaseIterable {
    case quick
    case sports

    var title: String {
        switch self {
        case .quick:
            return NSLocalizedString("timer_countdown_mode_quick", value: "快捷", comment: "Quick countdown mode")
        case .sports:
            return NSLocalizedString("timer_countdown_mode_sports", value: "比赛", comment: "Sports countdown mode")
        }
    }
}

private struct CountdownPreset: Identifiable {
    let id: String
    let titleKey: String
    let fallbackTitle: String
    let seconds: Int

    var title: String { NSLocalizedString(titleKey, value: fallbackTitle, comment: "Countdown preset") }
}

private struct CountdownSport: Identifiable {
    let id: String
    let titleKey: String
    let fallbackTitle: String
    let presets: [CountdownPreset]

    var title: String { NSLocalizedString(titleKey, value: fallbackTitle, comment: "Countdown sport") }
}

struct TimeoutCountdownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var state = TimerToolStateStore.loadCountdown()
    @State private var displayRemainingMilliseconds: Double = 30_000
    @State private var timer: Timer?
    @State private var mode: CountdownMode = .quick
    @State private var selectedSportID = "ping_pong"
    @State private var customMinutes = 0
    @State private var customSeconds = 30
    @State private var showsCustomEditor = false
    @State private var lastBackTap: Date?
    @State private var showsExitHint = false
    @State private var exitHintTask: Task<Void, Never>?
    @State private var previousSecondBoundary = -1
    @State private var previousIdleTimerDisabled: Bool?

    private let quickPresets = [30, 60, 180, 300, 600]

    private var sports: [CountdownSport] {
        [
            CountdownSport(
                id: "ping_pong",
                titleKey: "timer_sport_tab_ping_pong",
                fallbackTitle: "乒乓球",
                presets: [
                    preset("ping_timeout", "timer_sport_preset_timeout", "暂停", 60),
                    preset("ping_break", "timer_sport_preset_break", "局间", 60)
                ]
            ),
            CountdownSport(
                id: "badminton",
                titleKey: "timer_sport_tab_badminton",
                fallbackTitle: "羽毛球",
                presets: [
                    preset("badminton_interval", "timer_sport_preset_interval", "间歇", 60),
                    preset("badminton_between", "timer_sport_preset_between_games", "局间", 120)
                ]
            ),
            CountdownSport(
                id: "tennis",
                titleKey: "timer_sport_tab_tennis",
                fallbackTitle: "网球",
                presets: [
                    preset("tennis_game", "timer_sport_preset_tennis_game_break", "局间休息", 90),
                    preset("tennis_set", "timer_sport_preset_tennis_set_break", "盘间休息", 120),
                    preset("tennis_medical", "timer_sport_preset_tennis_medical", "医疗暂停", 180)
                ]
            ),
            CountdownSport(
                id: "volleyball",
                titleKey: "timer_sport_tab_volleyball",
                fallbackTitle: "排球",
                presets: [
                    preset("volleyball_timeout", "timer_sport_preset_timeout", "暂停", 30),
                    preset("volleyball_technical", "timer_sport_preset_technical", "技术暂停", 60),
                    preset("volleyball_between", "timer_sport_preset_between_sets", "局间", 180)
                ]
            ),
            CountdownSport(
                id: "basketball",
                titleKey: "timer_sport_tab_basketball",
                fallbackTitle: "篮球",
                presets: [
                    preset("basketball_timeout", "timer_sport_preset_timeout", "暂停", 60),
                    preset("basketball_short", "timer_sport_preset_short_break", "节间", 120),
                    preset("basketball_half", "timer_sport_preset_halftime", "中场", 900)
                ]
            )
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let compactLandscape = UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    VStack(spacing: compactLandscape ? 4 : 10) {
                        Spacer(minLength: compactLandscape ? 0 : 12)

                        Text(formatCountdown(displayRemainingMilliseconds))
                            .font(.system(size: timerFontSize(for: geometry.size), weight: .bold, design: .monospaced))
                            .foregroundStyle(timeColor)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)

                        Text(compactDuration(state.durationSeconds))
                            .font(.system(size: compactLandscape ? 14 : 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))

                        Spacer(minLength: compactLandscape ? 4 : 16)

                        if shouldShowPresets(compactLandscape: compactLandscape) {
                            presetArea
                                .frame(maxWidth: 720)
                                .padding(.horizontal, 16)

                            modePicker
                                .frame(maxWidth: 360)
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                        }

                        Spacer(minLength: compactLandscape ? 4 : 18)

                        controls
                            .padding(.bottom, compactLandscape ? 8 : 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showsExitHint {
                    Text(NSLocalizedString("tap_again_to_exit", value: "再次轻触退出", comment: "Tap again to exit"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.78), in: Capsule())
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsCustomEditor) {
            customEditor
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshCountdown()
            if state.phase == .running { startTicker() }
        }
    }

    private var topBar: some View {
        HStack {
            toolbarCircleButton(systemName: "chevron.left", action: handleBack)
            Spacer()
            if UIDevice.current.userInterfaceIdiom == .phone {
                toolbarCircleButton(systemName: "rectangle.portrait.rotate", action: rotateScreen)
            } else {
                Color.clear.frame(width: 60, height: 60)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func toolbarCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var presetArea: some View {
        if mode == .quick {
            quickPresetGrid
        } else {
            sportsPresetArea
        }
    }

    private var quickPresetGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(quickPresets.prefix(3)), id: \.self) { seconds in
                    quickPresetButton(seconds)
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(quickPresets.suffix(2)), id: \.self) { seconds in
                    quickPresetButton(seconds)
                }
                presetButton(
                    title: NSLocalizedString("timer_countdown_edit_time", value: "编辑时间", comment: "Edit countdown time"),
                    subtitle: nil,
                    selected: !quickPresets.contains(state.durationSeconds)
                ) {
                    syncCustomFields()
                    showsCustomEditor = true
                }
            }
        }
    }

    private func quickPresetButton(_ seconds: Int) -> some View {
        let title: String
        switch seconds {
        case 30: title = NSLocalizedString("timer_countdown_chip_30s", value: "30 秒", comment: "30 seconds")
        case 60: title = NSLocalizedString("timer_countdown_chip_1m", value: "1 分钟", comment: "1 minute")
        case 180: title = NSLocalizedString("timer_countdown_chip_3m", value: "3 分钟", comment: "3 minutes")
        case 300: title = NSLocalizedString("timer_countdown_chip_5m", value: "5 分钟", comment: "5 minutes")
        default: title = NSLocalizedString("timer_countdown_chip_10m", value: "10 分钟", comment: "10 minutes")
        }
        return presetButton(title: title, subtitle: nil, selected: state.durationSeconds == seconds) {
            applyDuration(seconds)
        }
    }

    private var sportsPresetArea: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sports) { sport in
                        Button {
                            selectedSportID = sport.id
                            VibrationManager.shared.vibrateLight()
                        } label: {
                            Text(sport.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selectedSportID == sport.id ? Theme.textOnPrimary : .white.opacity(0.65))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(selectedSportID == sport.id ? Theme.primary : .white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(selectedSport.presets) { item in
                    presetButton(
                        title: item.title,
                        subtitle: formatCountdown(Double(item.seconds) * 1_000),
                        selected: state.durationSeconds == item.seconds
                    ) {
                        applyDuration(item.seconds)
                    }
                }
            }
        }
    }

    private func presetButton(
        title: String,
        subtitle: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: subtitle == nil ? 0 : 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .opacity(0.72)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(selected ? Color.white.opacity(0.22) : Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Theme.primary : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CountdownMode.allCases, id: \.rawValue) { item in
                Button {
                    mode = item
                    VibrationManager.shared.vibrateLight()
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mode == item ? Theme.textOnPrimary : .white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(mode == item ? Theme.primary : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private var controls: some View {
        HStack {
            Button(action: resetCountdown) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.black.opacity(0.2), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                    .opacity(resetDisabled ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(resetDisabled)

            Spacer().frame(maxWidth: 56)

            Button(action: mainAction) {
                Image(systemName: state.phase == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 90, height: 90)
                    .background(.white.opacity(0.13), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Spacer().frame(maxWidth: 56)

            Color.clear.frame(width: 60, height: 60)
        }
        .frame(maxWidth: 322)
    }

    private var customEditor: some View {
        ZStack {
            Color(hex: "151515").ignoresSafeArea()
            VStack(spacing: 22) {
                Text(NSLocalizedString("timer_countdown_edit_time", value: "编辑时间", comment: "Edit countdown time"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(NSLocalizedString("timer_custom_duration", value: "自定义", comment: "Custom duration"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))

                customValueRow(
                    title: NSLocalizedString("timer_custom_minutes", value: "分钟", comment: "Minutes"),
                    value: customMinutes,
                    decrease: { adjustCustom(minutes: -1, seconds: 0) },
                    increase: { adjustCustom(minutes: 1, seconds: 0) }
                )

                customValueRow(
                    title: NSLocalizedString("timer_custom_seconds", value: "秒", comment: "Seconds"),
                    value: customSeconds,
                    decrease: { adjustCustom(minutes: 0, seconds: -1) },
                    increase: { adjustCustom(minutes: 0, seconds: 1) }
                )
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    private func customValueRow(
        title: String,
        value: Int,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 56, alignment: .leading)

            valueButton(systemName: "minus", action: decrease)

            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            valueButton(systemName: "plus", action: increase)
        }
    }

    private func valueButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var selectedSport: CountdownSport {
        sports.first(where: { $0.id == selectedSportID }) ?? sports[0]
    }

    private var resetDisabled: Bool {
        state.phase == .idle && state.durationSeconds == state.lastDurationSeconds
    }

    private var timeColor: Color {
        let seconds = Int(ceil(displayRemainingMilliseconds / 1_000))
        guard state.phase == .running else { return .white }
        if seconds <= 3 { return Color(hex: "FF453A") }
        if seconds <= 10 { return Color(hex: "FF9F0A") }
        return .white
    }

    private func shouldShowPresets(compactLandscape: Bool) -> Bool {
        (state.phase == .idle || state.phase == .ended) && !compactLandscape
    }

    private func timerFontSize(for size: CGSize) -> CGFloat {
        let compactLandscape = UIDevice.current.userInterfaceIdiom == .phone && size.width > size.height
        if compactLandscape { return min(112, size.height * 0.28) }
        if UIDevice.current.userInterfaceIdiom == .pad { return 128 }
        return min(88, size.width * 0.22)
    }

    private func preset(_ id: String, _ key: String, _ title: String, _ seconds: Int) -> CountdownPreset {
        CountdownPreset(id: id, titleKey: key, fallbackTitle: title, seconds: seconds)
    }

    private func appear() {
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        allowCountdownOrientations()
        state = TimerToolStateStore.loadCountdown()
        syncCustomFields()
        refreshCountdown()
        if state.phase == .running { startTicker() }
    }

    private func disappear() {
        stopTicker()
        TimerToolStateStore.saveCountdown(state)
        exitHintTask?.cancel()
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
        OrientationLock.shared.unlock()
    }

    private func applyDuration(_ seconds: Int) {
        guard state.phase == .idle || state.phase == .ended else { return }
        let clamped = min(86_400, max(1, seconds))
        state = CountdownPersistedState(
            phase: .idle,
            durationSeconds: clamped,
            lastDurationSeconds: clamped,
            endAt: 0,
            remainingMilliseconds: 0
        )
        displayRemainingMilliseconds = Double(clamped) * 1_000
        TimerToolStateStore.saveCountdown(state)
        VibrationManager.shared.vibrateLight()
    }

    private func mainAction() {
        switch state.phase {
        case .running:
            pauseCountdown()
        case .idle, .paused:
            startOrResumeCountdown()
        case .ended:
            state.phase = .idle
            state.durationSeconds = state.lastDurationSeconds
            state.remainingMilliseconds = 0
            startOrResumeCountdown()
        }
    }

    private func startOrResumeCountdown() {
        let remaining: Double
        if state.phase == .paused {
            remaining = max(1, state.remainingMilliseconds)
        } else {
            remaining = Double(state.durationSeconds) * 1_000
            state.lastDurationSeconds = state.durationSeconds
        }
        state.phase = .running
        state.endAt = Date().timeIntervalSince1970 + remaining / 1_000
        state.remainingMilliseconds = 0
        displayRemainingMilliseconds = remaining
        previousSecondBoundary = -1
        TimerToolStateStore.saveCountdown(state)
        CountdownNotificationManager.shared.schedule(after: remaining / 1_000)
        startTicker()
        VibrationManager.shared.vibrateMedium()
    }

    private func pauseCountdown() {
        state.remainingMilliseconds = state.remainingMilliseconds(at: Date())
        state.endAt = 0
        state.phase = .paused
        displayRemainingMilliseconds = state.remainingMilliseconds
        stopTicker()
        CountdownNotificationManager.shared.cancel()
        TimerToolStateStore.saveCountdown(state)
        VibrationManager.shared.vibrateMedium()
    }

    private func resetCountdown() {
        guard !resetDisabled else { return }
        stopTicker()
        CountdownNotificationManager.shared.cancel()
        state = CountdownPersistedState(
            phase: .idle,
            durationSeconds: state.lastDurationSeconds,
            lastDurationSeconds: state.lastDurationSeconds,
            endAt: 0,
            remainingMilliseconds: 0
        )
        displayRemainingMilliseconds = Double(state.durationSeconds) * 1_000
        previousSecondBoundary = -1
        TimerToolStateStore.saveCountdown(state)
        VibrationManager.shared.vibrateMedium()
    }

    private func startTicker() {
        stopTicker()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            refreshCountdown()
        }
        if let timer { RunLoop.current.add(timer, forMode: .common) }
    }

    private func stopTicker() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshCountdown() {
        guard state.phase == .running else {
            displayRemainingMilliseconds = state.remainingMilliseconds()
            return
        }
        let remaining = state.remainingMilliseconds(at: Date())
        displayRemainingMilliseconds = remaining
        guard remaining > 0 else {
            finishCountdown()
            return
        }
        let secondBoundary = Int(ceil(remaining / 1_000))
        if secondBoundary != previousSecondBoundary {
            previousSecondBoundary = secondBoundary
            warnIfNeeded(secondBoundary)
        }
    }

    private func finishCountdown() {
        stopTicker()
        CountdownNotificationManager.shared.cancel()
        state = CountdownPersistedState(
            phase: .ended,
            durationSeconds: state.durationSeconds,
            lastDurationSeconds: state.durationSeconds,
            endAt: 0,
            remainingMilliseconds: 0
        )
        displayRemainingMilliseconds = 0
        TimerToolStateStore.saveCountdown(state)
        // Harmony CountdownPage plays timeout.mp3 (locale-aware); fall back to buzzer if missing.
        BoardTimerVoiceAnnouncer.shared.playTimeout()
        VibrationManager.shared.vibrateHeavy()
    }

    private func warnIfNeeded(_ seconds: Int) {
        guard warningThresholds(for: state.durationSeconds).contains(seconds) else { return }
        if seconds <= 3 {
            VibrationManager.shared.vibrateMedium()
        } else {
            VibrationManager.shared.vibrateLight()
        }
    }

    private func warningThresholds(for duration: Int) -> Set<Int> {
        if duration >= 300 { return [60, 30, 10, 5, 3, 2, 1] }
        if duration >= 120 { return [30, 10, 5, 3, 2, 1] }
        if duration >= 60 { return [10, 5, 3, 2, 1] }
        if duration >= 30 { return [10, 5, 3, 1] }
        return [5, 3, 1]
    }

    private func syncCustomFields() {
        customMinutes = state.durationSeconds / 60
        customSeconds = state.durationSeconds % 60
    }

    private func adjustCustom(minutes minuteDelta: Int, seconds secondDelta: Int) {
        customMinutes = min(1_439, max(0, customMinutes + minuteDelta))
        customSeconds = min(59, max(0, customSeconds + secondDelta))
        let total = max(1, customMinutes * 60 + customSeconds)
        customMinutes = total / 60
        customSeconds = total % 60
        applyDuration(total)
    }

    private func handleBack() {
        let now = Date()
        if let lastBackTap, now.timeIntervalSince(lastBackTap) <= 2 {
            exitHintTask?.cancel()
            rotateToPortraitIfNeeded()
            dismiss()
            return
        }
        lastBackTap = now
        withAnimation(.easeOut(duration: 0.18)) { showsExitHint = true }
        exitHintTask?.cancel()
        exitHintTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.18)) { showsExitHint = false }
            }
        }
    }

    private func formatCountdown(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(ceil(milliseconds / 1_000)))
        if seconds >= 3_600 {
            return String(format: "%02d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func compactDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = seconds / 60 % 60
        let remainder = seconds % 60
        if hours > 0, minutes > 0 {
            return String(format: NSLocalizedString("countdown_compact_hm", value: "%d h %d min", comment: "Hours and minutes"), hours, minutes)
        }
        if hours > 0 {
            return String(format: NSLocalizedString("countdown_compact_h", value: "%d h", comment: "Hours"), hours)
        }
        if minutes > 0, remainder > 0 {
            return String(format: NSLocalizedString("countdown_compact_ms", value: "%d min %d s", comment: "Minutes and seconds"), minutes, remainder)
        }
        if minutes > 0 {
            return String(format: NSLocalizedString("countdown_compact_m", value: "%d min", comment: "Minutes"), minutes)
        }
        return String(format: NSLocalizedString("countdown_compact_s", value: "%d s", comment: "Seconds"), remainder)
    }

    private func allowCountdownOrientations() {
        OrientationLock.shared.lock(.allButUpsideDown)
        updateSupportedOrientations()
    }

    private func rotateScreen() {
        guard let windowScene = activeWindowScene else { return }
        let target: UIInterfaceOrientationMask = windowScene.interfaceOrientation.isPortrait ? .landscapeRight : .portrait
        requestOrientation(target, scene: windowScene)
    }

    private func rotateToPortraitIfNeeded() {
        guard let scene = activeWindowScene, scene.interfaceOrientation.isLandscape else { return }
        requestOrientation(.portrait, scene: scene)
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask, scene: UIWindowScene) {
        OrientationLock.shared.lock(mask)
        updateSupportedOrientations(in: scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            #if DEBUG
            print("[TimeoutCountdownView] Failed to rotate: \(error.localizedDescription)")
            #endif
        }
    }

    private func updateSupportedOrientations(in scene: UIWindowScene? = nil) {
        (scene ?? activeWindowScene)?.windows.first(where: \.isKeyWindow)?
            .rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

#Preview {
    NavigationStack { TimeoutCountdownView() }
}
