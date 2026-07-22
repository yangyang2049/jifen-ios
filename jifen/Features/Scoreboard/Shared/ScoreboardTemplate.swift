//
//  ScoreboardTemplate.swift
//  jifen
//
//  Scoreboard template - reusable UI component
//

import SwiftUI
import Photos // For PHPhotoLibrary
import UIKit

struct ScoreboardTemplate: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config: TemplateConfig
    var onBack: (() -> Void)? = nil

    init(config: TemplateConfig, onBack: (() -> Void)? = nil) {
        self._config = State(initialValue: config)
        self.onBack = onBack
    }
    @State private var showMenu: Bool = false
    @State private var isEditMode: Bool = false
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var hideButtonsForScreenshot: Bool = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var screenshotPreviewImage: UIImage? = nil // Screenshot preview image
    @State private var showScreenshotPreview: Bool = false // Show screenshot preview
    @State private var pendingTapSide: Bool?
    @State private var pendingTapAt: Date = .distantPast
    @State private var tapGeneration = 0
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var preferences = PreferencesManager.shared
    @State private var chromeButtonsVisible = true
    @State private var immersiveGeneration = 0
    @State private var previousIdleTimerDisabled: Bool?
    @State private var showDisplaySettings = false
    private let doubleTapWindow: TimeInterval = 0.24
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width >= geometry.size.height
            let panelSize = CGSize(
                width: isLandscape ? geometry.size.width / 2 : geometry.size.width,
                height: isLandscape ? geometry.size.height : geometry.size.height / 2
            )
            ZStack {
                // Background
                appearance.theme.palette.background.ignoresSafeArea(.all)
                
                // Main content adapts to landscape and portrait.
                let contentLayout = isLandscape
                    ? AnyLayout(HStackLayout(spacing: 0))
                    : AnyLayout(VStackLayout(spacing: 0))
                contentLayout {
                    // Left team
                    if let baseViewModel = config.viewModel as? BaseScoreViewModel {
                        TeamSection(
                            team: baseViewModel.leftTeam,
                            isLeft: true,
                            scoreFontSize: config.scoreFontSize,
                            scoreText: scoreText(for: baseViewModel.leftTeam, isLeft: true),
                            isEditMode: isEditMode,
                            editState: baseViewModel.editState,
                            scoreboardFont: appearance.font,
                            palette: appearance.theme.palette,
                            scoreMultiplier: scoreMultiplier,
                            nameMultiplier: nameMultiplier,
                            secondaryMultiplier: secondaryMultiplier,
                            fontRefreshTrigger: 0,
                            onScoreTap: { points in
                                config.viewModel.addScore(isLeft: true, points: points)
                            },
                            onScoreSubtract: { points in
                                config.viewModel.subtractScore(isLeft: true, points: points)
                            },
                            onScoreAdjust: { (isLeft, delta) in
                                if delta > 0 {
                                    config.viewModel.addScore(isLeft: isLeft, points: delta)
                                } else {
                                    config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                applySetsAdjust(viewModel: config.viewModel, isLeft: isLeft, delta: delta)
                            },
                            onGamesAdjust: nil,
                            onStartEditName: {
                                baseViewModel.startEditName(isLeft: true)
                            },
                            onUpdateInput: { value in
                                baseViewModel.updateInput(isLeft: true, value: value)
                            },
                            onConfirmEditName: {
                                baseViewModel.confirmEditName(isLeft: true)
                            },
                            gameType: config.gameType,
                            nameType: config.nameType,
                            isDoublesMode: config.isDoublesModeProvider?() ?? false,
                            scoringOptions: config.controller.getScoringOptions()
                        )
                        .frame(width: panelSize.width, height: panelSize.height, alignment: .leading)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isEditMode || true) // Allow hit testing for buttons in edit mode
                        .gesture(scoreTapGesture(isLeft: true, panelSize: panelSize))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                                    // Swipe left to undo
                                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                                        if !isEditMode {
                                            let success = config.viewModel.undo()
                                            if success {
                                                config.controller.performVibration(type: .light)
                                                showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
                                            }
                                        }
                                    }
                                }
                        )
                        
                        // Right team
                        TeamSection(
                            team: baseViewModel.rightTeam,
                            isLeft: false,
                            scoreFontSize: config.scoreFontSize,
                            scoreText: scoreText(for: baseViewModel.rightTeam, isLeft: false),
                            isEditMode: isEditMode,
                            editState: baseViewModel.editState,
                            scoreboardFont: appearance.font,
                            palette: appearance.theme.palette,
                            scoreMultiplier: scoreMultiplier,
                            nameMultiplier: nameMultiplier,
                            secondaryMultiplier: secondaryMultiplier,
                            fontRefreshTrigger: 0,
                            onScoreTap: { points in
                                config.viewModel.addScore(isLeft: false, points: points)
                            },
                            onScoreSubtract: { points in
                                config.viewModel.subtractScore(isLeft: false, points: points)
                            },
                            onScoreAdjust: { (isLeft, delta) in
                                if delta > 0 {
                                    config.viewModel.addScore(isLeft: isLeft, points: delta)
                                } else {
                                    config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                applySetsAdjust(viewModel: config.viewModel, isLeft: isLeft, delta: delta)
                            },
                            onGamesAdjust: nil,
                            onStartEditName: {
                                baseViewModel.startEditName(isLeft: false)
                            },
                            onUpdateInput: { value in
                                baseViewModel.updateInput(isLeft: false, value: value)
                            },
                            onConfirmEditName: {
                                baseViewModel.confirmEditName(isLeft: false)
                            },
                            gameType: config.gameType,
                            nameType: config.nameType,
                            isDoublesMode: config.isDoublesModeProvider?() ?? false,
                            scoringOptions: config.controller.getScoringOptions()
                        )
                        .frame(width: panelSize.width, height: panelSize.height, alignment: .leading)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isEditMode || true) // Allow hit testing for buttons in edit mode
                        .gesture(scoreTapGesture(isLeft: false, panelSize: panelSize))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                                    // Swipe left to undo
                                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                                        if !isEditMode {
                                            let success = config.viewModel.undo()
                                            if success {
                                                config.controller.performVibration(type: .light)
                                                showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
                                            }
                                        }
                                    }
                                }
                        )
                    }
                }
                
                // Edit button (top right) - close to screen edge
                if shouldShowChromeButtons {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                            if isEditMode {
                                // Exit edit mode - confirm any pending edits
                                if let baseViewModel = config.viewModel as? BaseScoreViewModel {
                                    let pendingName = baseViewModel.editState.currentInput
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !pendingName.isEmpty {
                                        Task {
                                            await CommonNamesManager.shared.recordUsage(pendingName, config.nameType)
                                        }
                                    }
                                    baseViewModel.confirmEditName(isLeft: true)
                                    baseViewModel.confirmEditName(isLeft: false)
                                }
                            }
                            isEditMode.toggle()
                            if let baseViewModel = config.viewModel as? BaseScoreViewModel {
                                baseViewModel.toggleEditMode()
                            }
                            config.controller.performVibration(type: .medium)
                            }) {
                                Image(systemName: isEditMode ? "checkmark" : "pencil")
                                .font(.system(size: ScoreboardConstants.buttonIconSize))
                                .foregroundColor(.white)
                                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                .background(
                                    Circle()
                                        .fill(isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.25))
                                )
                            }
                            .padding(.trailing, ScoreboardConstants.buttonPadding)
                            .padding(.top, ScoreboardConstants.buttonPadding)
                        }
                        Spacer()
                    }
                    .ignoresSafeArea(.all, edges: .top)
                }

                
                // Bottom buttons (back left, menu right) - only show when not in edit mode
                if !isEditMode && shouldShowChromeButtons {
                    VStack {
                        Spacer()
                        HStack {
                            // Back button always exists; immersive mode only toggles chrome visibility.
                            Button(action: {
                                config.controller.performVibration(type: .heavy)

                                // Handle double tap exit
                                if config.controller.handleExitClick() {
                                    OrientationLock.shared.unlock()
                                    performBack()
                                } else {
                                    toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
                                    showToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showToast = false
                                    }
                                    revealImmersiveChrome()
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundColor(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.25))
                                    )
                            }
                            .modifier(ScoreboardBackButtonAccessibility(isBack: true))
                            .padding(.leading, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)

                            Spacer()

                            // Menu button (bottom right)
                            Button(action: {
                                showMenu.toggle()
                                config.controller.performVibration(type: .medium)
                            }) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundColor(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.25))
                                    )
                            }
                            .padding(.trailing, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)

                        }
                }
                .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing]) // Full screen, not in safe area
                }

                // 中间层：仅比左右半区高一层，在编辑/底部按钮与菜单之下（如射箭的发球箭头+半区点击）；传入 isEditMode 以便编辑时隐藏/禁用
                if let provider = config.contentOverlayProvider {
                    provider(isEditMode)
                }

                if shouldShowImmersiveRevealZones {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }

                // Menu dialog
                MenuDialog(
                    isVisible: showMenu,
                    onClose: {
                        menuConfirm.clear()
                        showMenu = false
                    },
                    onMenuItemClick: { action in
                        handleMenuItemClick(action)
                    },
                    showEndGame: config.showEndGame
                        || config.gameType == .football
                        || config.gameType == .basketball
                        || config.gameType == .simpleScore,
                    resetConfirming: menuConfirm.resetConfirming,
                    items: ScoreboardMenuItemBuilder.defaultItems(
                        showEndGame: config.showEndGame
                            || config.gameType == .football
                            || config.gameType == .basketball
                            || config.gameType == .simpleScore,
                        showExchangeSide: true,
                        showSettleMatch: config.showSettleMatch,
                        resetConfirming: menuConfirm.resetConfirming,
                        exchangeConfirming: menuConfirm.exchangeConfirming,
                        finishConfirming: menuConfirm.finishConfirming,
                        settleConfirming: menuConfirm.settleConfirming,
                        extraItems: config.extraMenuItemsProvider?() ?? []
                    )
                )
                
                // Toast message
                if showToast {
                    ToastView(message: toastMessage)
                        .transition(.opacity.combined(with: .scale))
                        .allowsHitTesting(false)
                }
                
                // Screenshot preview (floating at bottom)
                if showScreenshotPreview, let previewImage = screenshotPreviewImage {
                    ScreenshotPreviewView(image: previewImage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.all) // Ignore safe area for entire ZStack
            .background(
                // Two-finger gesture detector
                TwoFingerSwipeDownView(
                    enabled: config.controller.swipeScreenshotEnabled && !isEditMode,
                    onSwipeDown: {
                        handleScreenshotGesture()
                    }
                )
            )
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.height < -50 && abs(value.translation.width) < 50 {
                            // Swipe up
                            showMenu.toggle()
                            config.controller.performVibration(type: .medium)
                        }
                    }
            )
        }
        .onChange(of: isEditMode) { _, newValue in
            config.onEditModeChange?(newValue)
            updateImmersiveChromeForBlockingState()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: showMenu) { _, isOpen in
            if !isOpen {
                menuConfirm.clear()
            }
            updateImmersiveChromeForBlockingState()
        }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveChromeForBlockingState() }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            applyScreenAwakePreference()
            updateImmersiveChromeForBlockingState()
        }
        .onAppear {
            config.onEditModeChange?(isEditMode)
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            applyScreenAwakePreference()
            revealImmersiveChrome()
            registerScoreboardSync()
        }
        .onDisappear {
            immersiveGeneration += 1
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
        }
        .scoreboardDisplaySettingsOverlay(isPresented: $showDisplaySettings, gameType: config.gameType)
        // Screenshot dialog removed - iOS auto-saves after permission is granted
    }
    
    // MARK: - Menu Item Handlers
    
    private func handleMenuItemClick(_ action: String) {
        config.controller.performVibration(type: .medium)
        menuConfirm.prepare(forMenuAction: action)

        switch action {
        case "whistle":
            // Sound is played by MenuDialog; this branch clears pending confirm.
            break

        case "screenshot":
            // Capture is handled by MenuDialog; this branch clears pending confirm.
            showMenu = false

        case "displaySettings":
            showMenu = false
            showDisplaySettings = true
            
        case "exchangeSide":
            if menuConfirm.armOrConfirm(.exchangeSide) {
                config.viewModel.exchangeSides()
                config.controller.recordScoreAction(action: "exchangeSide")
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
            }
            
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                config.viewModel.reset()
                config.controller.recordScoreAction(action: "reset")
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                showToastMessage(NSLocalizedString("has_been_reset", comment: ""))
                showMenu = false
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.reset.localizedToast)
            }
            
        case "undo":
            // Undo (keep dialog open)
            let success = config.viewModel.undo()
            if success {
                config.controller.recordScoreAction(action: "undo")
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
            } else {
                showToastMessage(NSLocalizedString("no_undo_available", comment: ""))
            }

        case "endGame":
            if menuConfirm.armOrConfirm(.finish) {
                if let onEndGame = config.onEndGame {
                    onEndGame()
                } else {
                    config.viewModel.endGame()
                }
                showMenu = false
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.finish.localizedToast)
            }

        case "settleMatch":
            if menuConfirm.armOrConfirm(.settleMatch) {
                if let onEndGame = config.onEndGame { onEndGame() }
                else { config.viewModel.endGame() }
                showMenu = false
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.settleMatch.localizedToast)
            }
            
        default:
            config.onMenuAction?(action)
        }
    }
    
    // MARK: - Screenshot Handlers
    
    private func handleScreenshotGesture() {
        guard !isEditMode && config.controller.swipeScreenshotEnabled else { return }
        
        config.controller.performVibration(type: .medium)
        
        // Hide buttons before screenshot
        hideButtonsForScreenshot = true
        
        // Wait for UI to update, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            captureScreenshot()
        }
    }
    
    private func captureScreenshot() {
        // Get the window to capture the screen
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            hideButtonsForScreenshot = false
            showToastMessage(NSLocalizedString("screenshot_failed", comment: ""))
            return
        }
        
        // Capture screenshot of the window directly
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        
        // Store preview image and show preview
        screenshotPreviewImage = image
        showScreenshotPreview = true
        
        // Check permission status before saving
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        if currentStatus == .authorized {
            // Permission already granted - show preview for 1500ms then save and show toast
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.hideButtonsForScreenshot = false
                self.saveScreenshot(image: image, fileName: self.config.controller.generateScreenshotFileName(), showPreview: false)
            }
        } else {
            // Permission not determined or denied - save and show preview until permission is granted/rejected
            hideButtonsForScreenshot = false
            saveScreenshot(image: image, fileName: config.controller.generateScreenshotFileName(), showPreview: true)
        }
    }
    
    private func saveScreenshot(image: UIImage, fileName: String, showPreview: Bool) {
        config.controller.saveScreenshotToPhotoLibrary(image) { success, error in
            if success {
                if showPreview {
                    // Hide preview after save success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            self.showScreenshotPreview = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.screenshotPreviewImage = nil
                        }
                    }
                } else {
                    // Hide preview immediately if already shown for 1500ms
                    withAnimation {
                        self.showScreenshotPreview = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.screenshotPreviewImage = nil
                    }
                }
                self.showToastMessage(NSLocalizedString("screenshot_saved", comment: ""))
            } else {
                let errorMessage = error?.localizedDescription ?? NSLocalizedString("unknown_error", comment: "")
                if errorMessage.contains("Settings") {
                    // Permission denied - hide preview after showing error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            self.showScreenshotPreview = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.screenshotPreviewImage = nil
                        }
                    }
                    self.showToastMessage(NSLocalizedString("please_allow_photo_access", comment: ""))
                } else {
                    // Other error - hide preview
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            self.showScreenshotPreview = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.screenshotPreviewImage = nil
                        }
                    }
                    self.showToastMessage(String(format: NSLocalizedString("save_failed", comment: ""), errorMessage))
                }
            }
        }
    }
    
    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }

    // MARK: - Score Display Helper

    private func scoreText(for team: TeamData, isLeft: Bool) -> String {
        if let provider = config.scoreTextProvider {
            return provider(isLeft, team)
        }
        return "\(team.score)"
    }

    private var shouldShowChromeButtons: Bool {
        !hideButtonsForScreenshot && (!appearance.immersiveMode || isEditMode || chromeButtonsVisible)
    }

    private var shouldShowImmersiveRevealZones: Bool {
        appearance.immersiveMode && !isEditMode && !showMenu && !showDisplaySettings && !chromeButtonsVisible
    }

    private var savedFontMultipliers: [String: Double] {
        PreferencesManager.shared.fontSizeMultipliers(for: config.gameType)
    }

    private var scoreMultiplier: Double { savedFontMultipliers[ScoreboardFontMetric.score.rawValue] ?? 1 }
    private var nameMultiplier: Double { savedFontMultipliers[ScoreboardFontMetric.name.rawValue] ?? 1 }
    private var secondaryMultiplier: Double { savedFontMultipliers[ScoreboardFontMetric.secondary.rawValue] ?? 1 }

    private func scoreTapGesture(isLeft: Bool, panelSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                guard !isEditMode, config.tapToAddEnabled, config.gameType != .boxing else { return }
                guard isScoreTouchAllowed(location: value.location, panelSize: panelSize) else { return }
                if let onScorePanelTap = config.onScorePanelTap {
                    pendingTapSide = nil
                    tapGeneration += 1
                    onScorePanelTap(isLeft)
                    revealImmersiveChrome()
                    return
                }
                let now = Date()
                if pendingTapSide == isLeft, now.timeIntervalSince(pendingTapAt) <= doubleTapWindow {
                    pendingTapSide = nil
                    tapGeneration += 1
                    if appearance.doubleTapSubtract {
                        config.viewModel.subtractScore(isLeft: isLeft, points: 1)
                    } else {
                        config.viewModel.addScore(isLeft: isLeft, points: 2)
                    }
                    LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                    revealImmersiveChrome()
                    return
                }

                if let previousSide = pendingTapSide, previousSide != isLeft {
                    config.viewModel.addScore(isLeft: previousSide, points: 1)
                    LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                }

                pendingTapSide = isLeft
                pendingTapAt = now
                tapGeneration += 1
                let generation = tapGeneration
                revealImmersiveChrome()
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) {
                    guard generation == tapGeneration, pendingTapSide == isLeft else { return }
                    pendingTapSide = nil
                    config.viewModel.addScore(isLeft: isLeft, points: 1)
                    LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                }
            }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: { makeSyncDisplayState() },
            handleIntent: { intent in
                switch intent {
                case .addLeft: config.viewModel.addScore(isLeft: true, points: 1)
                case .addRight: config.viewModel.addScore(isLeft: false, points: 1)
                case .subtractLeft: config.viewModel.subtractScore(isLeft: true, points: 1)
                case .subtractRight: config.viewModel.subtractScore(isLeft: false, points: 1)
                case .undo: _ = config.viewModel.undo()
                case .exchangeSides: config.viewModel.exchangeSides()
                case .requestSnapshot: break
                }
            }
        )
    }

    private func makeSyncDisplayState() -> LocalScoreboardDisplayState {
        let left = config.viewModel.leftTeam
        let right = config.viewModel.rightTeam
        return LocalScoreboardDisplayState(
            gameID: config.gameType.canonicalScoreboardIdentifier,
            title: config.gameType.displayName,
            leftName: left.name,
            rightName: right.name,
            leftScore: scoreText(for: left, isLeft: true),
            rightScore: scoreText(for: right, isLeft: false),
            leftDetail: syncDetail(for: left),
            rightDetail: syncDetail(for: right),
            themeID: appearance.theme.rawValue,
            fontID: appearance.font.rawValue,
            finished: config.viewModel.gameFinished,
            keyPoint: LocalScoreboardKeyPoint.syncValue(
                config.syncKeyPointProvider?(),
                finished: config.viewModel.gameFinished,
                isEditing: isEditMode
            ),
            revision: 0
        )
    }

    private func syncDetail(for team: TeamData) -> String? {
        let pieces = [
            team.sets.map { String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), $0) },
            team.games.map { String(format: NSLocalizedString("sync_games_format", value: "%d 盘", comment: ""), $0) }
        ].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private func isScoreTouchAllowed(location: CGPoint, panelSize: CGSize) -> Bool {
        guard appearance.touchGuard else { return true }
        return CGRect(
            x: panelSize.width * 0.2,
            y: panelSize.height * 0.2,
            width: panelSize.width * 0.6,
            height: panelSize.height * 0.6
        ).contains(location)
    }

    private func applyScreenAwakePreference() {
        UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
    }

    private func updateImmersiveChromeForBlockingState() {
        if isEditMode || showMenu || showDisplaySettings || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeButtonsVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private func revealImmersiveChrome() {
        chromeButtonsVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !isEditMode, !showMenu, !showDisplaySettings else { return }
        let hideDelay: TimeInterval
        if let remaining = config.controller.exitConfirmRemainingSeconds {
            hideDelay = remaining + 0.05
        } else {
            hideDelay = 1.5
        }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !isEditMode,
                  !showMenu,
                  !showDisplaySettings,
                  true else { return }
            if config.controller.exitConfirmRemainingSeconds != nil { return }
            chromeButtonsVisible = false
        }
    }

    private func performBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    /// 编辑模式下局分 ±：显式按具体 ViewModel 类型调用 adjustSets，避免协议默认实现被误派发导致局分不改（与射箭修复一致）。
    private func applySetsAdjust(viewModel: ScoreViewModelProtocol, isLeft: Bool, delta: Int) {
        if let vm = viewModel as? ArcheryViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else if let vm = viewModel as? BoxingViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else {
            viewModel.adjustSets(isLeft: isLeft, delta: delta)
        }
    }
}

// MARK: - Orientation Lock Extension

extension View {
    func lockOrientation(_ orientation: UIInterfaceOrientationMask) -> some View {
        self.onAppear {
            if UIDevice.current.userInterfaceIdiom == .pad,
               !PreferencesManager.shared.forceIPadLandscape {
                OrientationLock.shared.unlock()
            } else {
                OrientationLock.shared.lock(orientation)
            }
        }
        .onDisappear {
            OrientationLock.shared.unlock()
        }
    }
}

// MARK: - Team Section

struct TeamSection: View {
    var team: TeamData
    let isLeft: Bool
    let scoreFontSize: CGFloat
    let scoreText: String
    let isEditMode: Bool
    var editState: EditState
    let scoreboardFont: ScoreboardFont
    let palette: ScoreboardPalette
    let scoreMultiplier: Double
    let nameMultiplier: Double
    let secondaryMultiplier: Double
    let fontRefreshTrigger: Int // Used to trigger font refresh
    
    // Helper to get Font from font family name with bold weight
    private func getFont(size: CGFloat) -> Font {
        scoreboardFont.swiftUIFont(size: size)
    }
    let onScoreTap: (Int) -> Void
    let onScoreSubtract: (Int) -> Void
    let onScoreAdjust: ((Bool, Int) -> Void)?
    let onSetsAdjust: ((Bool, Int) -> Void)?
    let onGamesAdjust: ((Bool, Int) -> Void)?
    let onStartEditName: () -> Void
    let onUpdateInput: (String) -> Void
    let onConfirmEditName: () -> Void
    let gameType: GameType
    let nameType: NameType
    let isDoublesMode: Bool
    let scoringOptions: [Int]
    
    @FocusState private var isNameFocused: Bool
    @State private var showCommonNameSelector = false
    private let commonNamesManager = CommonNamesManager.shared

    private var isTablet: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// 编辑态队名输入框：缩短宽度并左右留白居中
    private var nameEditMaxWidth: CGFloat { isTablet ? 240 : 148 }
    private var nameEditSideInset: CGFloat { isTablet ? 40 : 28 }

    var body: some View {
        GeometryReader { geo in
            let halfH = geo.size.height
            let nameSize = ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: halfH) * nameMultiplier
            let doublesNameSize = (isTablet ? 28 : 22) * nameMultiplier
            let mainScoreSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: halfH) * scoreMultiplier
            // Prefer HOS curve; fall back to config size floor when caller passes a larger custom size.
            let effectiveScoreSize = max(mainScoreSize, scoreFontSize * scoreMultiplier * (isTablet ? min(1.5, 200 / max(scoreFontSize, 1)) : 1))
            let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: halfH) * secondaryMultiplier
            let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: halfH)
            let topPad = ScoreboardLayoutMetrics.nameTopPadding(panelHeight: halfH, isEditMode: isEditMode)

            ZStack {
                (isLeft ? palette.left : palette.right)
                    .ignoresSafeArea()

                // Centered main score + sets/games under it (HOS ScoreboardPageTemplate).
                VStack(spacing: mainToSet) {
                    scoreBlock(fontSize: effectiveScoreSize)
                    secondaryScoresBlock(fontSize: setSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Name pinned to top.
                VStack(spacing: 0) {
                    nameBlock(nameSize: nameSize, doublesNameSize: doublesNameSize)
                        .padding(.top, topPad)
                    Spacer(minLength: 0)
                }

                // Side controls pinned near bottom (HOS translateY: -72).
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !isEditMode && scoringOptions.count > 1 {
                        HStack(spacing: 12) {
                            ForEach(scoringOptions, id: \.self) { points in
                                Button(action: { onScoreTap(points) }) {
                                    Text("+\(points)")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(palette.foreground)
                                        .frame(width: 60, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(ScoreboardTheme.auxiliaryButtonBackground)
                                        )
                                }
                            }
                        }
                        .padding(.bottom, ScoreboardConstants.sideControlsBottomOffset)
                    }
                }
            }
            .foregroundStyle(palette.foreground)
        }
        .sheet(isPresented: $showCommonNameSelector) {
            CommonNameSelectorDialog(nameType: nameType) { selectedName in
                applyCommonName(selectedName)
            }
        }
    }

    @ViewBuilder
    private func nameBlock(nameSize: CGFloat, doublesNameSize: CGFloat) -> some View {
        if isEditMode {
            let isEditing = editState.editingSide == (isLeft ? .left : .right)
            HStack(spacing: 6) {
                TextField("", text: Binding(
                    get: {
                        if isEditing { return editState.currentInput }
                        return team.name
                    },
                    set: { newValue in
                        if isEditing {
                            onUpdateInput(newValue)
                        } else {
                            onStartEditName()
                            onUpdateInput(newValue)
                        }
                    }
                ))
                .font(.system(size: nameSize, weight: .bold))
                .foregroundColor(palette.foreground)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($isNameFocused)
                .onTapGesture {
                    onStartEditName()
                    isNameFocused = true
                }
                .onSubmit { confirmAndPersistName() }

                Button {
                    onStartEditName()
                    isNameFocused = false
                    showCommonNameSelector = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isTablet ? 20 : 16, weight: .semibold))
                        .foregroundColor(palette.foreground.opacity(0.9))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: nameEditMaxWidth)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, nameEditSideInset)
            .onChange(of: isEditMode) { _, newValue in
                if !newValue { confirmAndPersistName() }
            }
            .onChange(of: editState.editingSide) { _, newValue in
                isNameFocused = newValue == (isLeft ? .left : .right)
            }
        } else if let doublesNames = doublesDisplayNames {
            VStack(spacing: 2) {
                Text(doublesNames.0)
                    .font(.system(size: doublesNameSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(doublesNames.1)
                    .font(.system(size: doublesNameSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(palette.foreground)
            .padding(.horizontal, 8)
        } else {
            Text(team.name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundColor(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func scoreBlock(fontSize: CGFloat) -> some View {
        if isEditMode, let onScoreAdjust {
            HStack(spacing: 16) {
                adjustCircleButton(enabled: team.score > 0, systemName: "minus") {
                    if team.score > 0 { onScoreAdjust(isLeft, -1) }
                }
                Text(scoreText)
                    .font(getFont(size: fontSize))
                    .monospacedDigit()
                    .foregroundColor(palette.foreground)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                adjustCircleButton(enabled: true, systemName: "plus") {
                    onScoreAdjust(isLeft, 1)
                }
            }
        } else {
            Text(scoreText)
                .font(getFont(size: fontSize))
                .monospacedDigit()
                .foregroundColor(palette.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func secondaryScoresBlock(fontSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            if let sets = team.sets {
                secondaryValueRow(
                    value: sets,
                    fontSize: fontSize,
                    onAdjust: onSetsAdjust.map { adjust in { delta in adjust(isLeft, delta) } }
                )
            }
            if let games = team.games {
                secondaryValueRow(
                    value: games,
                    fontSize: fontSize,
                    onAdjust: onGamesAdjust.map { adjust in { delta in adjust(isLeft, delta) } }
                )
            }
        }
    }

    @ViewBuilder
    private func secondaryValueRow(value: Int, fontSize: CGFloat, onAdjust: ((Int) -> Void)?) -> some View {
        if isEditMode, let onAdjust {
            HStack(spacing: 16) {
                adjustCircleButton(enabled: value > 0, systemName: "minus") {
                    if value > 0 { onAdjust(-1) }
                }
                Text("\(value)")
                    .font(getFont(size: fontSize))
                    .monospacedDigit()
                    .foregroundColor(palette.secondary)
                adjustCircleButton(enabled: true, systemName: "plus") {
                    onAdjust(1)
                }
            }
        } else {
            Text("\(value)")
                .font(getFont(size: fontSize))
                .monospacedDigit()
                .foregroundColor(palette.secondary)
        }
    }

    private func adjustCircleButton(enabled: Bool, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(enabled ? palette.foreground.opacity(0.75) : palette.foreground.opacity(0.3))
                .frame(width: 50, height: 50)
                .background(Circle().fill(ScoreboardTheme.auxiliaryButtonBackgroundSubtle))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private func confirmAndPersistName() {
        let side: EditingSide = isLeft ? .left : .right
        guard editState.editingSide == side else {
            isNameFocused = false
            return
        }
        let trimmed = editState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Task {
                await commonNamesManager.recordUsage(trimmed, nameType)
            }
        }
        onConfirmEditName()
        isNameFocused = false
    }

    private func applyCommonName(_ selectedName: String) {
        onStartEditName()
        onUpdateInput(selectedName)
        Task {
            await commonNamesManager.recordUsage(selectedName, nameType)
        }
        onConfirmEditName()
        isNameFocused = false
    }

    private var doublesDisplayNames: (String, String)? {
        guard isDoublesMode else { return nil }
        guard gameType == .pingpong || gameType == .badminton || gameType == .tennis else { return nil }

        let separators = ["/", "／"]
        let raw = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        for separator in separators {
            let parts = raw
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return (parts[0], parts[1])
            }
        }
        return nil
    }
}

// MARK: - Two Finger Swipe Down View

struct TwoFingerSwipeDownView: UIViewRepresentable {
    let enabled: Bool
    let onSwipeDown: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing gesture recognizers
        uiView.gestureRecognizers?.forEach { uiView.removeGestureRecognizer($0) }
        
        guard enabled else { return }
        
        // Add two-finger pan gesture recognizer
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator
        uiView.addGestureRecognizer(panGesture)
        
        context.coordinator.onSwipeDown = onSwipeDown
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipeDown: (() -> Void)?
        private var hasTriggered = false
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.numberOfTouches == 2 else { return }
            
            let translation = gesture.translation(in: gesture.view)
            
            switch gesture.state {
            case .began:
                hasTriggered = false
            case .changed:
                // Check if it's a downward swipe
                if translation.y > 50 && abs(translation.x) < 50 && !hasTriggered {
                    hasTriggered = true
                    onSwipeDown?()
                }
            case .ended, .cancelled:
                hasTriggered = false
            default:
                break
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

// MARK: - UIView Extension for Finding Scoreboard View

extension UIView {
    func findScoreboardView() -> UIView? {
        // Look for a view with a specific identifier or tag
        // For now, we'll return self if it's large enough to be the main view
        if self.bounds.width > 500 && self.bounds.height > 300 {
            return self
        }
        
        for subview in subviews {
            if let found = subview.findScoreboardView() {
                return found
            }
        }
        
        return nil
    }
}

// MARK: - Screenshot Save Dialog

struct ScreenshotSaveDialog: View {
    let image: UIImage
    let fileName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var inputFileName: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                
                // File name input
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("screenshot_filename", value: "文件名", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    TextField("", text: $inputFileName)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Buttons
                HStack(spacing: 16) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        onCancel()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button(NSLocalizedString("save", comment: "")) {
                        let finalFileName = inputFileName.isEmpty ? fileName : inputFileName
                        onSave(finalFileName)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.black)
            .navigationTitle(NSLocalizedString("save_screenshot_title", value: "保存截图", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                inputFileName = fileName
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    /// Bottom offset so toast sits lower on scoreboards (above tab/safe area)
    private static let bottomPadding: CGFloat = 56

    var body: some View {
        VStack {
            Spacer()

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.bottom, Self.bottomPadding)
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

// MARK: - Screenshot Preview View

struct ScreenshotPreviewView: View {
    let image: UIImage
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                // Preview image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 80)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Spacer()
            }
            .padding(.bottom, 100) // Position above bottom buttons
        }
    }
}
