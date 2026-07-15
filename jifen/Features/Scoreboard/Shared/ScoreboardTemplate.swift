//
//  ScoreboardTemplate.swift
//  jifen
//
//  Scoreboard template - reusable UI component
//

import SwiftUI
import Photos // For PHPhotoLibrary

struct ScoreboardTemplate: View {
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
    @State private var resetClickCount: Int = 0
    @State private var screenshotPreviewImage: UIImage? = nil // Screenshot preview image
    @State private var showScreenshotPreview: Bool = false // Show screenshot preview
    @State private var lastTapTime: Date = Date.distantPast
    private let tapDebounceInterval: TimeInterval = 0.15 // 150ms debounce for tap gestures
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea(.all)
                
                // Main content - Landscape layout (horizontal)
                HStack(spacing: 0) {
                    // Left team
                    if let baseViewModel = config.viewModel as? BaseScoreViewModel {
                        TeamSection(
                            team: baseViewModel.leftTeam,
                            isLeft: true,
                            scoreFontSize: config.scoreFontSize,
                            scoreText: scoreText(for: baseViewModel.leftTeam, isLeft: true),
                            isEditMode: isEditMode,
                            editState: baseViewModel.editState,
                            fontFamily: "SF Pro Display",
                            fontRefreshTrigger: 0,
                            onScoreTap: { points in
                                config.viewModel.addScore(isLeft: true, points: points)
                            },
                            onScoreSubtract: { points in
                                config.viewModel.subtractScore(isLeft: true, points: points)
                            },
                            onScoreAdjust: { (isLeft, delta) in
                                if let pingPongViewModel = config.viewModel as? PingPongViewModel {
                                    pingPongViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let badmintonViewModel = config.viewModel as? BadmintonViewModel {
                                    badmintonViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let pickleballViewModel = config.viewModel as? PickleballViewModel {
                                    pickleballViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else {
                                    if delta > 0 {
                                        config.viewModel.addScore(isLeft: isLeft, points: delta)
                                    } else {
                                        config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                    }
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                applySetsAdjust(viewModel: config.viewModel, isLeft: isLeft, delta: delta)
                            },
                            onGamesAdjust: { (isLeft, delta) in
                                if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustGames(isLeft: isLeft, delta: delta)
                                }
                            },
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
                        .frame(width: geometry.size.width / 2, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap to add score (only in normal mode) with debouncing; 拳击不通过点击加分
                            if !isEditMode && config.tapToAddEnabled && config.gameType != .boxing {
                                let currentTime = Date()
                                if currentTime.timeIntervalSince(lastTapTime) >= tapDebounceInterval {
                                    lastTapTime = currentTime
                                    config.viewModel.addScore(isLeft: true, points: 1)
                                }
                            }
                        }
                        .allowsHitTesting(!isEditMode || true) // Allow hit testing for buttons in edit mode
                        .gesture(
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
                            fontFamily: "SF Pro Display",
                            fontRefreshTrigger: 0,
                            onScoreTap: { points in
                                config.viewModel.addScore(isLeft: false, points: points)
                            },
                            onScoreSubtract: { points in
                                config.viewModel.subtractScore(isLeft: false, points: points)
                            },
                            onScoreAdjust: { (isLeft, delta) in
                                if let pingPongViewModel = config.viewModel as? PingPongViewModel {
                                    pingPongViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let badmintonViewModel = config.viewModel as? BadmintonViewModel {
                                    badmintonViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else if let pickleballViewModel = config.viewModel as? PickleballViewModel {
                                    pickleballViewModel.adjustScore(isLeft: isLeft, delta: delta)
                                } else {
                                    if delta > 0 {
                                        config.viewModel.addScore(isLeft: isLeft, points: delta)
                                    } else {
                                        config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                    }
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                applySetsAdjust(viewModel: config.viewModel, isLeft: isLeft, delta: delta)
                            },
                            onGamesAdjust: { (isLeft, delta) in
                                if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustGames(isLeft: isLeft, delta: delta)
                                }
                            },
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
                        .frame(width: geometry.size.width / 2, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap to add score (only in normal mode) with debouncing; 拳击不通过点击加分
                            if !isEditMode && config.tapToAddEnabled && config.gameType != .boxing {
                                let currentTime = Date()
                                if currentTime.timeIntervalSince(lastTapTime) >= tapDebounceInterval {
                                    lastTapTime = currentTime
                                    config.viewModel.addScore(isLeft: false, points: 1)
                                }
                            }
                        }
                        .allowsHitTesting(!isEditMode || true) // Allow hit testing for buttons in edit mode
                        .gesture(
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
                .ignoresSafeArea(.all, edges: .top) // Full screen, not in safe area

                
                // Bottom buttons (back left, menu right) - only show when not in edit mode
                if !isEditMode {
                    VStack {
                        Spacer()
                        HStack {
                            // Back button (bottom left) - left margin = bottom margin, full screen
                            if let onBack = onBack {
                                Button(action: {
                                    config.controller.performVibration(type: .heavy)

                                    // Handle double tap exit
                                    if config.controller.handleExitClick() {
                                        // Can exit
                                        OrientationLock.shared.unlock()
                                        onBack()
                                    } else {
                                        // Need to tap again - show toast
                                        toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
                                        showToast = true
                                        // Auto hide toast after 2 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            showToast = false
                                        }
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
                                .padding(.leading, ScoreboardConstants.buttonPadding)
                                .padding(.bottom, ScoreboardConstants.buttonPadding)
                            }

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

                // Menu dialog
                MenuDialog(
                    isVisible: showMenu,
                    onClose: {
                        showMenu = false
                    },
                    onMenuItemClick: { action in
                        handleMenuItemClick(action)
                    },
                    showEndGame: config.gameType == .football || config.gameType == .basketball
                )
                
                // Toast message
                if showToast {
                    ToastView(message: toastMessage)
                        .transition(.opacity.combined(with: .scale))
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
        }
        .onAppear {
            config.onEditModeChange?(isEditMode)
        }
        // Screenshot dialog removed - iOS auto-saves after permission is granted
    }
    
    // MARK: - Menu Item Handlers
    
    private func handleMenuItemClick(_ action: String) {
        config.controller.performVibration(type: .medium)
        
        switch action {
        case "whistle":
            // Play whistle sound
            SoundManager.shared.playSound("whistle")
            // Don't close dialog

        case "screenshot":
            showMenu = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                handleScreenshotGesture()
            }
            
        case "exchangeSide":
            // Exchange sides (keep dialog open)
            config.viewModel.exchangeSides()
            
        case "reset":
            // Double tap to reset
            resetClickCount += 1
            if resetClickCount == 1 {
                showToastMessage(NSLocalizedString("press_again_to_reset", comment: ""))
                // Reset count after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    resetClickCount = 0
                }
            } else if resetClickCount >= 2 {
                resetClickCount = 0
                // Don't close dialog - keep it open like other actions
                config.viewModel.reset()
                showToastMessage(NSLocalizedString("has_been_reset", comment: ""))
            }
            
        case "undo":
            // Undo (keep dialog open)
            let success = config.viewModel.undo()
            if success {
                showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
            } else {
                showToastMessage(NSLocalizedString("no_undo_available", comment: ""))
            }

        case "endGame":
            // 结束比赛（足球/篮球）：设置 gameFinished，关闭菜单，overlay 由 onChange(gameFinished) 显示
            config.viewModel.endGame()
            showMenu = false
            
        default:
            break
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

    /// 编辑模式下局分 ±：显式按具体 ViewModel 类型调用 adjustSets，避免协议默认实现被误派发导致局分不改（与射箭修复一致）。
    private func applySetsAdjust(viewModel: ScoreViewModelProtocol, isLeft: Bool, delta: Int) {
        if let vm = viewModel as? ArcheryViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else if let vm = viewModel as? PingPongViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else if let vm = viewModel as? BadmintonViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else if let vm = viewModel as? TennisViewModel {
            vm.adjustSets(isLeft: isLeft, delta: delta)
        } else if let vm = viewModel as? PickleballViewModel {
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
            OrientationLock.shared.lock(orientation)
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
    let fontFamily: String
    let fontRefreshTrigger: Int // Used to trigger font refresh
    
    // Helper to get Font from font family name with bold weight
    private func getFont(family: String, size: CGFloat) -> Font {
        // Try to use custom font first with bold weight
        if let uiFont = UIFont(name: family, size: size) {
            // Try to get bold variant
            if let boldDescriptor = uiFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                let boldFont = UIFont(descriptor: boldDescriptor, size: size)
                return Font(boldFont)
            }
            // If bold variant not available, use regular with bold weight modifier
            return Font(uiFont).weight(.bold)
        }
        
        // Fallback to system fonts with bold weight
        switch family {
        case "Menlo":
            return .system(size: size, weight: .bold, design: .monospaced)
        case "SF Pro Display", "default":
            return .system(size: size, weight: .bold)
        default:
            return .system(size: size, weight: .bold)
        }
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
    private var nameFontSize: CGFloat { isTablet ? 44 : 32 }
    private var doublesNameFontSize: CGFloat { isTablet ? 28 : 22 }
    private var nameTopPadding: CGFloat { isTablet ? 36 : 28 }
    /// 大分数（主比分）在大屏上放大，更充分利用空间
    private var effectiveScoreFontSize: CGFloat { isTablet ? min(scoreFontSize * 1.5, 200) : scoreFontSize }
    /// 局分/盘分数字在大屏上放大
    private var setsGamesFontSize: CGFloat { isTablet ? 80 : 48 }
    /// 台球仅总分、无局分/加分按钮，分数需纵向居中
    private var centerScoreVertically: Bool { gameType == .billiards }
    
    var body: some View {
        ZStack {
            // Background color (red for left, blue for right)
            (isLeft ? Color(hex: "DC143C") : Color(hex: "1E90FF"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Team name - editable in edit mode
                if isEditMode {
                    let isEditing = editState.editingSide == (isLeft ? .left : .right)
                    
                    HStack(spacing: 8) {
                        TextField("", text: Binding(
                            get: {
                                if isEditing {
                                    return editState.currentInput
                                } else {
                                    return team.name
                                }
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
                        .font(.system(size: nameFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .onTapGesture {
                            onStartEditName()
                            isNameFocused = true
                        }
                        .onSubmit {
                            confirmAndPersistName()
                        }

                        Button {
                            onStartEditName()
                            isNameFocused = false
                            showCommonNameSelector = true
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: isTablet ? 22 : 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                    .padding(.top, nameTopPadding)
                    .onChange(of: isEditMode) { _, newValue in
                        if !newValue {
                            confirmAndPersistName()
                        }
                    }
                    .onChange(of: editState.editingSide) { _, newValue in
                        isNameFocused = newValue == (isLeft ? .left : .right)
                    }
                } else {
                    if let doublesNames = doublesDisplayNames {
                        VStack(spacing: 2) {
                            Text(doublesNames.0)
                                .font(.system(size: doublesNameFontSize, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(doublesNames.1)
                                .font(.system(size: doublesNameFontSize, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.top, nameTopPadding)
                        .padding(.horizontal, 8)
                    } else {
                        Text(team.name)
                            .font(.system(size: nameFontSize, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, nameTopPadding)
                    }
                }
                
                Spacer()
                
                // Score display - 台球时用 ZStack 占满剩余高度使分数纵向居中
                ZStack {
                    if isEditMode, let onScoreAdjust = onScoreAdjust {
                        HStack(spacing: 16) {
                            Button(action: {
                                if team.score > 0 {
                                    onScoreAdjust(isLeft, -1)
                                }
                            }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(team.score > 0 ? .white.opacity(0.75) : .white.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .disabled(team.score <= 0)
                            
                            Text(scoreText)
                                .font(getFont(family: fontFamily, size: effectiveScoreFontSize))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            
                            Button(action: {
                                onScoreAdjust(isLeft, 1)
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                        }
                    } else {
                        Text(scoreText)
                            .font(getFont(family: fontFamily, size: effectiveScoreFontSize))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: centerScoreVertically ? .infinity : nil)
                
                // Sets display - with -/+ buttons in edit mode
                if let sets = team.sets {
                    if isEditMode, let onSetsAdjust = onSetsAdjust {
                        HStack(spacing: 16) {
                            Button(action: {
                                if sets > 0 {
                                    onSetsAdjust(isLeft, -1)
                                }
                            }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(sets > 0 ? .white.opacity(0.75) : .white.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .disabled(sets <= 0)
                            
                            Text("\(sets)")
                                .font(getFont(family: fontFamily, size: setsGamesFontSize))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.9))
                            
                            Button(action: {
                                onSetsAdjust(isLeft, 1)
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                        }
                    } else {
                        Text("\(sets)")
                            .font(getFont(family: fontFamily, size: setsGamesFontSize))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                // Games display (if available, for tennis) - just number, larger
                if let games = team.games {
                    if isEditMode, let onGamesAdjust = onGamesAdjust {
                        HStack(spacing: 16) {
                            Button(action: {
                                if games > 0 {
                                    onGamesAdjust(isLeft, -1)
                                }
                            }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(games > 0 ? .white.opacity(0.75) : .white.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .disabled(games <= 0)

                            Text("\(games)")
                                .font(getFont(family: fontFamily, size: setsGamesFontSize))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.9))

                            Button(action: {
                                onGamesAdjust(isLeft, 1)
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                        }
                    } else {
                        Text("\(games)")
                            .font(getFont(family: fontFamily, size: setsGamesFontSize))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                // Scoring buttons - only show when there are multiple options and not in edit mode
                if !isEditMode && scoringOptions.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(scoringOptions, id: \.self) { points in
                            Button(action: {
                                onScoreTap(points)
                            }) {
                                Text("+\(points)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.15))
                                    )
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showCommonNameSelector) {
            CommonNameSelectorDialog(nameType: nameType) { selectedName in
                applyCommonName(selectedName)
            }
        }
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
