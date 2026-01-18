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
    @State private var showFontDialog: Bool = false
    @State private var resetClickCount: Int = 0
    @State private var fontRefreshTrigger: Int = 0 // Trigger to refresh font display
    @State private var screenshotPreviewImage: UIImage? = nil // Screenshot preview image
    @State private var showScreenshotPreview: Bool = false // Show screenshot preview
    
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
                            fontFamily: config.controller.getFontFamily(),
                            fontRefreshTrigger: fontRefreshTrigger,
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
                                } else {
                                    if delta > 0 {
                                        config.viewModel.addScore(isLeft: isLeft, points: delta)
                                    } else {
                                        config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                    }
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                if let pingPongViewModel = config.viewModel as? PingPongViewModel {
                                    pingPongViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                } else if let badmintonViewModel = config.viewModel as? BadmintonViewModel {
                                    badmintonViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                } else if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                }
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
                            scoringOptions: config.controller.getScoringOptions()
                        )
                        .frame(width: geometry.size.width / 2, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap to add score (only in normal mode)
                            if !isEditMode {
                                config.viewModel.addScore(isLeft: true, points: 1)
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
                            fontFamily: config.controller.getFontFamily(),
                            fontRefreshTrigger: fontRefreshTrigger,
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
                                } else {
                                    if delta > 0 {
                                        config.viewModel.addScore(isLeft: isLeft, points: delta)
                                    } else {
                                        config.viewModel.subtractScore(isLeft: isLeft, points: -delta)
                                    }
                                }
                            },
                            onSetsAdjust: { (isLeft, delta) in
                                if let pingPongViewModel = config.viewModel as? PingPongViewModel {
                                    pingPongViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                } else if let badmintonViewModel = config.viewModel as? BadmintonViewModel {
                                    badmintonViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                } else if let tennisViewModel = config.viewModel as? TennisViewModel {
                                    tennisViewModel.adjustSets(isLeft: isLeft, delta: delta)
                                }
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
                            scoringOptions: config.controller.getScoringOptions()
                        )
                        .frame(width: geometry.size.width / 2, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap to add score (only in normal mode)
                            if !isEditMode {
                                config.viewModel.addScore(isLeft: false, points: 1)
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
                                        // Can exit - unlock is handled by onDisappear
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
                
                // Menu dialog
                MenuDialog(
                    isVisible: showMenu,
                    onClose: {
                        showMenu = false
                    },
                    onMenuItemClick: { action in
                        handleMenuItemClick(action)
                    }
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
        .preferredColorScheme(.dark)
        // Screenshot dialog removed - iOS auto-saves after permission is granted
                .sheet(isPresented: $showFontDialog) {
                    FontSelectionDialog(
                        currentFont: config.controller.currentFont,
                        onFontSelected: { fontCode in
                            handleFontChange(fontCode: fontCode)
                        },
                        onCancel: {
                            showToastMessage("已撤销")
                        }
                    )
                }
    }
    
    // MARK: - Menu Item Handlers
    
    private func handleMenuItemClick(_ action: String) {
        config.controller.performVibration(type: .medium)
        
        switch action {
        case "whistle":
            // Play whistle sound
            SoundManager.shared.playSound("whistle")
            // Don't close dialog
            
        case "font":
            showMenu = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showFontDialog = true
            }
            
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
                showToastMessage("再次点击重置")
                // Reset count after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    resetClickCount = 0
                }
            } else if resetClickCount >= 2 {
                resetClickCount = 0
                // Don't close dialog - keep it open like other actions
                config.viewModel.reset()
                showToastMessage("已重置")
            }
            
        case "undo":
            // Undo (keep dialog open)
            let success = config.viewModel.undo()
            if !success {
                showToastMessage("没有可撤销的操作")
            }
            
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
            showToastMessage("截图失败")
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
                self.showToastMessage("截图已保存")
            } else {
                let errorMessage = error?.localizedDescription ?? "未知错误"
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
                    self.showToastMessage("请在设置中允许访问相册")
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
                    self.showToastMessage("保存失败: \(errorMessage)")
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
    
    // MARK: - Font Selection
    
    private func handleFontChange(fontCode: String) {
        // Update font in controller (this will also save to preferences)
        var updatedConfig = config
        updatedConfig.controller.currentFont = fontCode
        config = updatedConfig
        // Trigger UI refresh
        fontRefreshTrigger += 1
        showFontDialog = false
        showToastMessage("字体已更改")
        config.controller.performVibration(type: .medium)
    }
    
    // MARK: - Font Helper

    private func getFont(family: String, size: CGFloat) -> Font {
        // Map font codes to actual font families
        let mappedFamily: String
        switch family {
        case "digital":
            mappedFamily = "RobotoMono-Regular"
        case "seven_segment":
            mappedFamily = "7segment"
        case "harmony_digit":
            mappedFamily = "SF-Pro-Rounded" // Use SF Pro Rounded for harmony digit
        case "default":
            mappedFamily = "SF-Pro-Display"
        default:
            mappedFamily = family
        }

        // Try to use custom font first
        if let uiFont = UIFont(name: mappedFamily, size: size) {
            return Font(uiFont)
        }

        // Fallback to system fonts based on font code
        switch family {
        case "digital":
            return .system(size: size, design: .monospaced)
        case "seven_segment":
            return .system(size: size, design: .monospaced) // Fallback for seven-segment
        case "harmony_digit":
            return .system(size: size, design: .rounded)
        case "default", "SF Pro Display":
            return .system(size: size, design: .default)
        default:
            return .system(size: size)
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
    let scoringOptions: [Int]
    
    @FocusState private var isNameFocused: Bool
    
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
                    
                    TextField("", text: Binding(
                        get: {
                            // Always show currentInput when editing this side, otherwise show team name
                            if isEditing {
                                return editState.currentInput
                            } else {
                                return team.name
                            }
                        },
                        set: { newValue in
                            // Only update if we're editing this side
                            if isEditing {
                                onUpdateInput(newValue)
                            } else {
                                // If not editing, start editing when user types
                                onStartEditName()
                                onUpdateInput(newValue)
                            }
                        }
                    ))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                    .padding(.top, 20)
                    .focused($isNameFocused)
                    .onTapGesture {
                        onStartEditName()
                        isNameFocused = true
                    }
                    .onSubmit {
                        onConfirmEditName()
                        isNameFocused = false
                    }
                    .onChange(of: isEditMode) { oldValue, newValue in
                        if !newValue {
                            // Exit edit mode - confirm edit
                            onConfirmEditName()
                            isNameFocused = false
                        }
                    }
                    .onChange(of: editState.editingSide) { oldValue, newValue in
                        // When editing side changes, update focus
                        if newValue == (isLeft ? .left : .right) {
                            isNameFocused = true
                        } else {
                            isNameFocused = false
                        }
                    }
                } else {
                    Text(team.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // Score display - with -/+ buttons in edit mode
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
                            .font(getFont(family: fontFamily, size: scoreFontSize))
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
                            .font(getFont(family: fontFamily, size: scoreFontSize))
                            .foregroundColor(.white)
                }
                
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
                                .font(getFont(family: fontFamily, size: 48))
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
                            .font(getFont(family: fontFamily, size: 48))
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
                                .font(getFont(family: fontFamily, size: 48))
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
                            .font(getFont(family: fontFamily, size: 48))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                Spacer()
            }
        }
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
                    Text("文件名")
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
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("保存") {
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
            .navigationTitle("保存截图")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                inputFileName = fileName
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    
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
                .padding(.bottom, 100)
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
