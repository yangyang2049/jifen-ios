import LinkCore
import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

enum TwoSideScoreboardText {
    static var linkedNewGameOnWatch: String {
        NSLocalizedString(
            "game_over_new_game_on_watch",
            value: "再来一场\n（请在手表端操作）",
            comment: ""
        )
    }
}

/// Two-side 50/50 scaffold aligned with the HOS boards for eight-ball, shengji, and guandan.
struct TwoSideScoreboardScaffold<Center: View>: View {
    let gameType: GameType
    let leftName: String
    let rightName: String
    let leftScore: String
    let rightScore: String
    let leftDetail: String?
    let rightDetail: String?
    let finished: Bool
    let onLeftTap: () -> Void
    let onRightTap: () -> Void
    let onUndo: () -> Bool
    let onReset: () -> Void
    let onExchange: (() -> Void)?
    let onBack: () -> Void
    var showEndGame: Bool = false
    var onEndGame: (() -> Void)? = nil
    var onEditCommit: ((String, String, String, String) -> Void)? = nil
    /// Defaults to the shared game policy so a new two-side scoreboard
    /// cannot silently read the wrong common-name collection.
    var nameType: NameType? = nil
    var editingEnabled: Bool = true
    var scoringEnabled: Bool = true
    /// Optional step-based editor used by rank/score boards that mirror the
    /// badminton singles edit layout instead of accepting raw score text.
    var onEditAdjust: ((Bool, Int) -> Void)? = nil
    var extraMenuItems: [ScoreboardMenuItem] = []
    var onMenuAction: ((String) -> Void)? = nil
    /// Optional overlay between the halves (e.g. serve triangle). Drawn above panels.
    var seamOverlay: (() -> AnyView)? = nil
    /// Optional controls rendered directly below each side's main score.
    var panelAccessory: ((Bool) -> AnyView)? = nil
    /// Optional floating bottom dock (e.g. snooker balls).
    var bottomBar: (() -> AnyView)? = nil
    /// Optional top-center pill.
    var topCenter: ((ScoreboardTypographyPreference, CGSize) -> AnyView)? = nil
    var onEditModeChange: ((Bool) -> Void)? = nil
    var onTypographyChange: ((ScoreboardTypographyPreference) -> Void)? = nil
    /// Stable team color placement; supplied values are already screen ordered.
    var sidesSwapped = false
    let center: (ScoreboardTypographyPreference, CGSize) -> Center

    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(rawValue: "unconfigured")
    )
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var showMenu = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editLeftScore = ""
    @State private var editRightScore = ""
    @State private var exitConfirmDeadline: Date?
    @State private var showToast = false
    @State private var toastMessage = ""

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showDisplaySettings || showMenu
    }

    private var resolvedNameType: NameType {
        nameType ?? ScoreboardCommonNamePolicy.nameType(for: gameType)
    }

    var body: some View {
        GeometryReader { proxy in
            let halfH = proxy.size.height
            ZStack {
                appearance.theme.palette.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    scorePanel(
                        isLeft: true,
                        name: leftName,
                        score: leftScore,
                        detail: leftDetail,
                        color: sidesSwapped ? appearance.theme.palette.right : appearance.theme.palette.left,
                        panelSize: CGSize(width: proxy.size.width / 2, height: halfH),
                        accessory: panelAccessory?(true),
                        action: onLeftTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)
                    .accessibilityIdentifier("scoreboard_left_panel")

                    scorePanel(
                        isLeft: false,
                        name: rightName,
                        score: rightScore,
                        detail: rightDetail,
                        color: sidesSwapped ? appearance.theme.palette.left : appearance.theme.palette.right,
                        panelSize: CGSize(width: proxy.size.width / 2, height: halfH),
                        accessory: panelAccessory?(false),
                        action: onRightTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)
                    .accessibilityIdentifier("scoreboard_right_panel")
                }

                if !isEditMode, !finished, let seamOverlay {
                    seamOverlay()
                }

                if !isEditMode, let topCenter {
                    VStack {
                        topCenter(typographySession.effectivePreference, proxy.size)
                            .padding(.top, ScoreboardConstants.buttonPadding)
                        Spacer()
                    }
                }

                // Compact center hints (target text etc.) sit mid-bottom above optional bottom bar.
                if !isEditMode {
                    VStack {
                        Spacer()
                        center(typographySession.effectivePreference, proxy.size)
                            .padding(.bottom, bottomBar == nil ? 72 : 90)
                    }
                    .allowsHitTesting(false)
                }

                if !isEditMode, let bottomBar {
                    VStack {
                        Spacer()
                        bottomBar()
                    }
                    .zIndex(20)
                }

                if shouldShowChrome {
                    chromeOverlay
                }

                if appearance.immersiveMode && !chromeVisible {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }

                if showToast {
                    ToastView(message: toastMessage)
                        .transition(.opacity.combined(with: .scale))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard !isEditMode else { return }
                showMenu = true
                revealImmersiveChrome()
            })
            .simultaneousGesture(DragGesture(minimumDistance: 36).onEnded { value in
                guard scoringEnabled,
                      !isEditMode,
                      value.translation.width < -60,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                if onUndo() {
                    showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: ""))
                } else {
                    showToastMessage(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
                }
            })
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.primary)
        .lockOrientation(.landscape)
        .onAppear {
            typographySession.switchStyleID(ScoreboardStyleID(gameType: gameType))
            onTypographyChange?(typographySession.effectivePreference)
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: showMenu) { _, isOpen in
            if !isOpen { menuConfirm.clear() }
            updateImmersiveForBlocking()
        }
        .onChange(of: showDisplaySettings) { _, presented in
            updateImmersiveForBlocking()
            if !presented {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        }
        .onChange(of: typographySession.effectivePreference) { _, preference in
            onTypographyChange?(preference)
        }
        .onDisappear {
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .overlay {
            MenuDialog(
                isVisible: showMenu,
                onClose: {
                    menuConfirm.clear()
                    showMenu = false
                },
                onMenuItemClick: { action in
                    menuConfirm.prepare(forMenuAction: action)
                    switch action {
                    case "undo":
                        if onUndo() {
                            showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
                        } else {
                            showToastMessage(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
                        }
                    case "reset":
                        if menuConfirm.armOrConfirm(.reset) {
                            onReset()
                            showToastMessage(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                            showMenu = false
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.reset.localizedToast)
                        }
                    case ScoreboardMenuActionID.exchangeSide.rawValue:
                        if menuConfirm.armOrConfirm(.exchangeSide) {
                            onExchange?()
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
                        }
                    case "endGame":
                        if menuConfirm.armOrConfirm(.finish) {
                            onEndGame?()
                            showMenu = false
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.finish.localizedToast)
                        }
                    case "displaySettings": showDisplaySettings = true; showMenu = false
                    default: onMenuAction?(action)
                    }
                },
                showEndGame: showEndGame,
                showExchangeSide: onExchange != nil,
                items: ScoreboardMenuItemBuilder.defaultItems(
                    showEndGame: showEndGame,
                    showExchangeSide: onExchange != nil,
                    showWhistle: true,
                    showScreenshot: true,
                    resetConfirming: menuConfirm.resetConfirming,
                    exchangeConfirming: menuConfirm.exchangeConfirming,
                    finishConfirming: menuConfirm.finishConfirming,
                    scoringEnabled: scoringEnabled,
                    extraItems: extraMenuItems
                ),
                analyticsGameType: gameType
            )
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: leftDetail == nil && rightDetail == nil
                ? [.name, .score]
                : ScoreboardTypographyProfile.twoSide.adjustableMetrics
        )
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !showDisplaySettings, !showMenu else { return }
        let hideDelay: TimeInterval
        if let exitConfirmDeadline, Date() <= exitConfirmDeadline {
            hideDelay = max(exitConfirmDeadline.timeIntervalSinceNow, 0) + 0.05
        } else {
            hideDelay = 1.5
        }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !showDisplaySettings,
                  !showMenu else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private var chromeOverlay: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    if onEditCommit != nil, editingEnabled {
                        chromeButton(isEditMode ? "checkmark" : "pencil") { toggleEditMode() }
                    }
                }
                Spacer()
            }
            .padding(ScoreboardConstants.buttonPadding)

            if !isEditMode {
                VStack {
                    Spacer()
                    HStack {
                        chromeButton("chevron.left", action: requestBack)
                        Spacer()
                        chromeButton("line.3.horizontal") { showMenu = true }
                    }
                }
                .padding(ScoreboardConstants.buttonPadding)
            }
        }
    }

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToastMessage(NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: ""))
            VibrationManager.shared.vibrateHeavy()
            revealImmersiveChrome()
            return
        }
        exitConfirmDeadline = nil
        OrientationLock.shared.unlock()
        onBack()
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }

    private func chromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        let background = systemName == "checkmark" ? Theme.primary : Color.black.opacity(0.25)
        return Button(action: {
            action()
            revealImmersiveChrome()
        }) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: systemName))
        .modifier(ScoreboardBackButtonAccessibility(isBack: systemName == "chevron.left"))
    }

    private func accessibilityIdentifier(for systemName: String) -> String {
        switch systemName {
        case "chevron.left":
            return ScoreboardConstants.backButtonAccessibilityID
        case "line.3.horizontal":
            return "scoreboard_menu_button"
        case "pencil", "checkmark":
            return "scoreboard_edit_button"
        default:
            return "scoreboard_chrome_\(systemName.replacingOccurrences(of: ".", with: "_"))"
        }
    }

    private func scorePanel(
        isLeft: Bool,
        name: String,
        score: String,
        detail: String?,
        color: Color,
        panelSize: CGSize,
        accessory: AnyView?,
        action: @escaping () -> Void
    ) -> some View {
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .twoSide,
                containerSize: panelSize,
                nameText: name,
                scoreText: score,
                secondaryText: detail ?? "",
                preference: typographySession.effectivePreference,
                horizontalPadding: 20,
                reservedHeight: accessory == nil ? 0 : 44,
                scoreBaseScale: isEditMode
                    ? 1
                    : ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: score),
                isLargeScreen: Theme.usesPadLayout
            )
        )
        let mainSize = typography.scoreFontSize
        let nameSize = typography.nameFontSize
        let topPad = ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height)
        let setSize = typography.secondaryFontSize
        let mainToDetailSpacing = ScoreboardLayoutMetrics.mainToSetSpacing(
            halfViewportHeight: panelSize.height
        )
        let editOffset = isEditMode
            ? ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: panelSize.height)
            : 0

        return ZStack {
            color

            if isEditMode {
                VStack(spacing: typography.nameToScoreSpacing) {
                    if let onEditAdjust {
                        HStack(spacing: 16) {
                            editCircleButton(systemName: "minus") { onEditAdjust(isLeft, -1) }
                            Text(score)
                                .font(typographySession.effectivePreference.font.swiftUIFont(
                                    size: ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: mainSize)
                                ))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            editCircleButton(systemName: "plus") { onEditAdjust(isLeft, 1) }
                        }
                    } else {
                        TextField(
                            "0",
                            text: isLeft ? $editLeftScore : $editRightScore
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .font(typographySession.effectivePreference.font.swiftUIFont(
                            size: ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: mainSize)
                        ))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: editOffset)

                VStack {
                    ScoreboardNameEditorField(
                        placeholder: resolvedNameType == .player
                            ? NSLocalizedString("setup_player_name", value: "选手名称", comment: "")
                            : NSLocalizedString("setup_team_name", value: "队伍名称", comment: ""),
                        text: isLeft ? $editLeftName : $editRightName,
                        nameType: resolvedNameType,
                        scoreboardFont: typographySession.effectivePreference.font
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, topPad)
                    .offset(y: editOffset)
                    Spacer()
                }
            } else {
                // Keep the complete label/score/detail cluster centered. This
                // matches the rally and standard templates and prevents a
                // top-pinned name from making the main score look too high.
                VStack(spacing: 0) {
                    Text(name)
                        .font(typographySession.effectivePreference.font.swiftUIFont(
                            size: nameSize,
                            weight: .bold
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)

                    Spacer().frame(height: typography.nameToScoreSpacing)

                    Text(score)
                        .font(typographySession.effectivePreference.font.swiftUIFont(size: mainSize))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)

                    if let accessory {
                        accessory
                            .padding(.top, 8)
                    }

                    if let detail {
                        Spacer().frame(height: mainToDetailSpacing)
                        Text(detail)
                            .font(typographySession.effectivePreference.font.swiftUIFont(size: setSize))
                            .foregroundStyle(appearance.theme.palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !finished else { return }
            action()
        }
    }

    private func editCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(appearance.theme.palette.foreground.opacity(0.75))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func toggleEditMode() {
        if isEditMode {
            onEditCommit?(
                editLeftName.trimmingCharacters(in: .whitespacesAndNewlines),
                editRightName.trimmingCharacters(in: .whitespacesAndNewlines),
                editLeftScore.trimmingCharacters(in: .whitespacesAndNewlines),
                editRightScore.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isEditMode = false
            onEditModeChange?(false)
        } else {
            editLeftName = leftName
            editRightName = rightName
            editLeftScore = leftScore
            editRightScore = rightScore
            isEditMode = true
            onEditModeChange?(true)
        }
    }
}

/// Compact per-side action used by the card scoreboards. Dimensions and
/// translucent treatment mirror the HarmonyOS auxiliary buttons.
@ViewBuilder
func scoreboardCardActionButton(
    _ title: String,
    width: CGFloat? = nil,
    action: @escaping () -> Void
) -> some View {
    let size: CGFloat = Theme.usesPadLayout ? 64 : 56
    Button(action: action) {
        Text(title)
            .font(.system(size: Theme.usesPadLayout ? 20 : 16, weight: .bold))
            .foregroundStyle(ScoreboardAppearanceSnapshot.current().theme.palette.foreground)
            .frame(width: width ?? size, height: size)
            .background(Capsule().fill(ScoreboardTheme.auxiliaryButtonBackgroundSubtle))
    }
    .buttonStyle(.plain)
}
