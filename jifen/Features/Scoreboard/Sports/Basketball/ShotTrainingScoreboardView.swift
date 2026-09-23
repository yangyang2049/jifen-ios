import RecordCore
import SwiftUI
import UIKit

nonisolated struct ShotTrainingShot: Codable, Equatable, Identifiable {
    let id: UUID
    let points: Int
    let made: Bool
    let timestamp: Date

    init(id: UUID = UUID(), points: Int, made: Bool, timestamp: Date = Date()) {
        self.id = id
        self.points = min(3, max(1, points))
        self.made = made
        self.timestamp = timestamp
    }
}

nonisolated struct ShotTrainingCounts: Codable, Equatable {
    var oneMade = 0
    var oneMiss = 0
    var twoMade = 0
    var twoMiss = 0
    var threeMade = 0
    var threeMiss = 0

    var made: Int { oneMade + twoMade + threeMade }
    var missed: Int { oneMiss + twoMiss + threeMiss }
    var attempts: Int { made + missed }
    var points: Int { oneMade + twoMade * 2 + threeMade * 3 }
    var rate: Int { attempts == 0 ? 0 : Int((Double(made) * 100 / Double(attempts)).rounded()) }

    func count(points: Int, made: Bool) -> Int {
        switch (points, made) {
        case (1, true): return oneMade
        case (1, false): return oneMiss
        case (2, true): return twoMade
        case (2, false): return twoMiss
        default: return made ? threeMade : threeMiss
        }
    }

    static func build(from shots: [ShotTrainingShot]) -> Self {
        shots.reduce(into: Self()) { result, shot in
            switch (shot.points, shot.made) {
            case (1, true): result.oneMade += 1
            case (1, false): result.oneMiss += 1
            case (2, true): result.twoMade += 1
            case (2, false): result.twoMiss += 1
            case (3, true): result.threeMade += 1
            default: result.threeMiss += 1
            }
        }
    }
}

nonisolated struct ShotTrainingResumeState: Codable, Equatable {
    var schemaVersion = 1
    var mode: ShotTrainingMode
    var shots: [ShotTrainingShot]
    var finished: Bool
}

/// 投篮训练配色唯一口径（对齐鸿蒙端 ShotTrainingScoreboard 常量）：页面底色 + 未中红、命中绿。
/// 手机端与投屏/跨设备显示端共用，只暴露十六进制，避免调用方受主线程隔离的 Color 初始化影响。
nonisolated enum ShotTrainingZonePalette {
    static let pageHex = "#0B0B0D"
    static let missHex = "#B93B3B"
    static let madeHex = "#2F9E4F"
    /// 自由模式入场提示层用半透明叠在分区上，色值与分区实色区分开。
    static let entryPromptMissHex = "#7E1818"
    static let entryPromptMadeHex = "#18712B"

    static func hex(made: Bool) -> String {
        made ? madeHex : missHex
    }

    static func entryPromptHex(made: Bool) -> String {
        made ? entryPromptMadeHex : entryPromptMissHex
    }
}

/// 手机端投篮训练记分页，1:1 对齐鸿蒙端 `ShotTrainingScoreboard.ets`。
/// 分区满屏铺满，没有标题栏和统计条：固定分值横屏「未中在左 / 命中在右」、竖屏上下；
/// 自由模式正好镜像（横屏上下、竖屏左右），每侧再切成 1/2/3 三格，分值徽标骑在红绿分区中心线上。
/// 页面操作集中在底部两颗浮动圆钮（左返回 / 右菜单）与左滑撤销手势；重置、结束训练在菜单里二次确认。
/// iOS 无法像鸿蒙那样直接转动窗口，「旋转方向」切换的是方向锁偏好，布局仍跟随实际窗口尺寸。
struct ShotTrainingScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    private static let landscapeLayoutKey = "basketball_training_use_landscape_layout"
    /// 鸿蒙端 FREE_ENTRY_SIDE_PROMPT_DURATION_MS
    private static let entrySidePromptDuration: TimeInterval = 2

    @State private var mode: ShotTrainingMode
    @State private var shots: [ShotTrainingShot]
    @State private var gameStartTime: Date
    @State private var recordID: String
    @State private var gameFinished: Bool
    @State private var showGameOver: Bool
    @State private var finalizedRecordID: String?
    @State private var previousIdleTimerDisabled: Bool?
    @State private var preferLandscape: Bool
    @State private var showMenu = false
    @State private var showEntrySidePrompt = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var exitConfirmDeadline: Date?
    @State private var showFinishedRecordDetail = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var entrySidePromptWork: DispatchWorkItem?

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        var restoredMode = ShotTrainingMode(rawValue: initialSetup?.basketballTrainingScoringMode ?? "") ?? .fixed1
        var restoredShots: [ShotTrainingShot] = []
        var restoredStart = Date()
        var restoredID = ScoreboardRecordIdentity.next(prefix: GameType.basketballTraining.canonicalScoreboardIdentifier)
        var restoredFinished = false

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId) {
            restoredStart = record.startTime
            restoredID = record.id
            if let data = record.stateSnapshot,
               let state = try? JSONDecoder().decode(ShotTrainingResumeState.self, from: data) {
                restoredMode = state.mode
                restoredShots = state.shots
                restoredFinished = state.finished
            } else if let rawMode = record.extraData?["basketballTrainingScoringMode"]?.value as? String {
                restoredMode = ShotTrainingMode(rawValue: rawMode) ?? .fixed1
            }
        }

        _mode = State(initialValue: restoredMode)
        _shots = State(initialValue: restoredShots)
        _gameStartTime = State(initialValue: restoredStart)
        _recordID = State(initialValue: restoredID)
        _gameFinished = State(initialValue: restoredFinished)
        _showGameOver = State(initialValue: restoredFinished)
        _finalizedRecordID = State(initialValue: restoredFinished ? restoredID : nil)
        let prefersLandscape = UserDefaults.standard.object(forKey: Self.landscapeLayoutKey) as? Bool ?? true
        _preferLandscape = State(initialValue: prefersLandscape)
    }

    private var counts: ShotTrainingCounts { .build(from: shots) }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack {
                Color(hex: ShotTrainingZonePalette.pageHex)

                scoringArea(isLandscape: isLandscape)

                if mode == .free {
                    freeCenterLabelsOverlay(isLandscape: isLandscape)
                        .allowsHitTesting(false)
                }

                if mode == .free, showEntrySidePrompt, !gameFinished, !showMenu {
                    entrySidePromptOverlay(isLandscape: isLandscape)
                        .allowsHitTesting(false)
                }

                if !gameFinished {
                    floatingChrome
                }

                if showGameOver {
                    gameOverDialog
                }

                if showToast {
                    ToastView(message: toastMessage)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(undoSwipeGesture)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .lockOrientation(preferLandscape ? .landscape : .portrait)
        .overlay {
            MenuDialog(
                isVisible: showMenu,
                onClose: {
                    menuConfirm.clear()
                    showMenu = false
                },
                onMenuItemClick: handleMenuAction,
                showEndGame: false,
                items: menuItems,
                analyticsGameType: .basketballTraining
            )
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOver)
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = PreferencesManager.shared.keepScoreboardScreenOn
            onSetupConsumed?()
            registerScoreboardSync()
            openEntrySidePrompt()
            saveRecord(finished: false)
        }
        .onChange(of: shots.count) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: gameFinished) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveRecord(finished: gameFinished) }
        }
        .onDisappear {
            clearEntrySidePromptTimer()
            saveRecord(finished: gameFinished)
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
        }
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: finalizedRecordID ?? recordID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
    }

    // MARK: - Scoring zones

    /// 鸿蒙端 build()：固定模式横屏左右、竖屏上下；自由模式镜像。未中永远在前（左 / 上）。
    @ViewBuilder
    private func scoringArea(isLandscape: Bool) -> some View {
        let madeOnRightHandSide = (mode == .free && !isLandscape) || (mode != .free && isLandscape)
        if madeOnRightHandSide {
            HStack(spacing: 0) {
                half(made: false, isLandscape: isLandscape)
                half(made: true, isLandscape: isLandscape)
            }
        } else {
            VStack(spacing: 0) {
                half(made: false, isLandscape: isLandscape)
                half(made: true, isLandscape: isLandscape)
            }
        }
    }

    @ViewBuilder
    private func half(made: Bool, isLandscape: Bool) -> some View {
        if mode == .free {
            freeZone(made: made, isLandscape: isLandscape)
        } else {
            fixedZone(made: made, isLandscape: isLandscape)
        }
    }

    /// 固定模式：数字与命中状态整体居中，不叠加分值徽标或说明。
    /// 大分数走普通记分板同一套 `ScoreboardTypographyResolver`（羽毛球等两端面板的 .twoSide 曲线），
    /// 随分区实测高度放大、按宽度收口；「未中/命中」小标签维持固定字号。
    private func fixedZone(made: Bool, isLandscape: Bool) -> some View {
        GeometryReader { proxy in
            let count = counts.count(points: mode.fixedPoints ?? 1, made: made)
            let labelHeight = (isLandscape ? 20 : 24) * 1.3 + 10
            let scoreSize = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .twoSide,
                    containerSize: proxy.size,
                    nameText: "",
                    scoreText: "\(count)",
                    preference: .default(font: .default),
                    horizontalPadding: 20,
                    reservedHeight: labelHeight,
                    isLargeScreen: Theme.usesPadLayout
                )
            ).scoreFontSize
            VStack(spacing: 10) {
                Text("\(count)")
                    .font(.system(size: scoreSize, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                Text(zoneLabel(made: made))
                    .font(.system(size: isLandscape ? 20 : 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(hex: ShotTrainingZonePalette.hex(made: made)))
        .contentShape(Rectangle())
        .onTapGesture {
            record(points: mode.fixedPoints ?? 1, made: made)
        }
    }

    /// 自由模式一侧：横屏 1/2/3 三列、竖屏 1/2/3 三行，整侧共用红/绿底色，格间 1vp 分隔线。
    private func freeZone(made: Bool, isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                HStack(spacing: 0) {
                    freeCell(points: 1, made: made)
                    freeDivider(vertical: true)
                    freeCell(points: 2, made: made)
                    freeDivider(vertical: true)
                    freeCell(points: 3, made: made)
                }
            } else {
                VStack(spacing: 0) {
                    freeCell(points: 1, made: made)
                    freeDivider(vertical: false)
                    freeCell(points: 2, made: made)
                    freeDivider(vertical: false)
                    freeCell(points: 3, made: made)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: ShotTrainingZonePalette.hex(made: made)))
    }

    private func freeDivider(vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }

    /// 自由模式单格：与斗地主格子同一条 `playerGrid` 曲线，随格子实测尺寸放大，
    /// 并对齐普通记分板的「大分数不超过半屏主分」收口。
    private func freeCell(points: Int, made: Bool) -> some View {
        GeometryReader { proxy in
            let count = counts.count(points: points, made: made)
            let scoreSize = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .doudizhu,
                    containerSize: proxy.size,
                    nameText: "",
                    scoreText: "\(count)",
                    preference: .default(font: .default),
                    horizontalPadding: 16,
                    scoreBaseScale: 0.85,
                    isLargeScreen: Theme.usesPadLayout
                )
            ).scoreFontSize
            Text("\(count)")
                .font(.system(size: scoreSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            record(points: points, made: made)
        }
    }

    /// 分值徽标压在红/绿分区中心线上：横屏是一条 38vp 高的横带，竖屏是一条 72vp 宽的竖带。
    @ViewBuilder
    private func freeCenterLabelsOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    freePointBadge(points, isLandscape: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 38)
        } else {
            VStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    freePointBadge(points, isLandscape: false)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 72)
        }
    }

    private func freePointBadge(_ points: Int, isLandscape: Bool) -> some View {
        Text(Self.pointLabel(points))
            .font(.system(size: isLandscape ? 15 : 17, weight: .semibold))
            .foregroundStyle(Color(hex: "#242428").opacity(0.72))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.76))
            )
    }

    /// 与鸿蒙/手表端一致：自由模式入场 2 秒内半透明覆盖两侧分区含义，提示层不拦截整格点击。
    @ViewBuilder
    private func entrySidePromptOverlay(isLandscape: Bool) -> some View {
        if isLandscape {
            VStack(spacing: 0) {
                entrySidePromptPanel(made: false, isLandscape: true)
                entrySidePromptPanel(made: true, isLandscape: true)
            }
        } else {
            HStack(spacing: 0) {
                entrySidePromptPanel(made: false, isLandscape: false)
                entrySidePromptPanel(made: true, isLandscape: false)
            }
        }
    }

    private func entrySidePromptPanel(made: Bool, isLandscape: Bool) -> some View {
        Text(zoneLabel(made: made))
            .font(.system(size: isLandscape ? 26 : 30, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: ShotTrainingZonePalette.entryPromptHex(made: made)).opacity(0.70))
    }

    private static func pointLabel(_ points: Int) -> String {
        switch points {
        case 1: return NSLocalizedString("shot_training_1pt", value: "1 分", comment: "")
        case 2: return NSLocalizedString("shot_training_2pt", value: "2 分", comment: "")
        default: return NSLocalizedString("shot_training_3pt", value: "3 分", comment: "")
        }
    }

    private func zoneLabel(made: Bool) -> String {
        made
            ? NSLocalizedString("shot_training_made", value: "命中", comment: "")
            : NSLocalizedString("shot_training_miss", value: "未中", comment: "")
    }

    // MARK: - Floating chrome + operation menu

    /// 页面上只有底部两颗浮动圆钮：左返回、右打开操作菜单。
    private var floatingChrome: some View {
        VStack {
            Spacer()
            HStack {
                chromeButton(systemName: "chevron.left", action: requestBack)
                    .modifier(ScoreboardBackButtonAccessibility(isBack: true))
                Spacer()
                chromeButton(systemName: "line.3.horizontal") {
                    showMenu = true
                }
                .accessibilityIdentifier("scoreboard_menu_button")
            }
        }
        .padding(ScoreboardConstants.buttonPadding)
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundStyle(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(Color.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    /// 鸿蒙端 getMenuItems：菜单只有这六项，不走 iOS 默认菜单（没有换边 / 样式 / 哨子）。
    private var menuItems: [ScoreboardMenuItem] {
        [
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_undo", comment: "Undo"),
                action: "undo",
                group: .match,
                icon: "arrow.uturn.backward"
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("scoreboard_rotate_orientation", value: "旋转方向", comment: ""),
                action: "layout",
                group: .match,
                icon: "rotate.left"
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_reset", comment: "Reset"),
                action: "reset",
                group: .match,
                icon: "arrow.counterclockwise",
                keepDialogOpen: true,
                confirming: menuConfirm.resetConfirming
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("shot_training_finish", value: "结束训练", comment: ""),
                action: "finish",
                group: .match,
                icon: "flag.checkered",
                keepDialogOpen: true,
                confirming: menuConfirm.finishConfirming
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_screenshot", comment: "Screenshot"),
                action: "screenshot",
                group: .tools,
                icon: "camera.fill"
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("scoreboard_usage_hint_menu", value: "使用说明", comment: ""),
                action: "usageHint",
                group: .tools,
                customText: "?",
                keepDialogOpen: true
            )
        ]
    }

    private func handleMenuAction(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            undoLastShot()
        case "layout":
            togglePreferredOrientation()
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                showMenu = false
                restartSession()
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.reset.localizedToast)
            }
        case "finish":
            if menuConfirm.armOrConfirm(.finish) {
                showMenu = false
                finishTraining()
            } else {
                showToastMessage(ScoreboardMenuConfirmAction.finish.localizedToast)
            }
        default:
            // 截图与使用说明由 MenuDialog 自身消费。
            break
        }
    }

    /// 鸿蒙端 PanGesture(direction: Left, distance: 50) → 撤销上一次记录。
    private var undoSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard !showMenu, !gameFinished,
                      value.translation.width < -50,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                undoLastShot()
            }
    }

    // MARK: - Training summary

    private var gameOverDialog: some View {
        GameOverDialog(
            winnerName: zoneLabel(made: true),
            gameType: .basketballTraining,
            leftName: zoneLabel(made: false),
            rightName: zoneLabel(made: true),
            leftScore: counts.missed,
            rightScore: counts.made,
            winnerIndices: [1],
            newGameLabel: NSLocalizedString("restart", value: "重新开始", comment: ""),
            onNewGame: { restartSession() },
            onRecords: {
                saveRecord(finished: true)
                // 不收起结束弹窗：查看记录是 fullScreenCover 盖在上面，关闭后仍停在弹窗上，
                // 否则页面已锁定为已结束态、底部圆钮也隐藏，用户回来就无从下手。
                showFinishedRecordDetail = true
            },
            onShare: { ScoreboardShareSupport.present(text: shareText) },
            onExit: {
                saveRecord(finished: true)
                performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
            }
        )
    }

    private var shareText: String {
        let currentCounts = counts
        return String(
            format: NSLocalizedString("shot_training_share", value: "投篮训练：命中 %d / %d，命中率 %d%%，得分 %d", comment: ""),
            currentCounts.made,
            currentCounts.attempts,
            currentCounts.rate,
            currentCounts.points
        )
    }

    // MARK: - Scoring actions

    private func record(points: Int, made: Bool) {
        guard !gameFinished else { return }
        hideEntrySidePrompt()
        shots.append(.init(points: points, made: made))
        saveRecord(finished: false)
        // 鸿蒙端 vibrate(made)：命中 40ms、未中 90ms，未中比命中更重。
        made ? VibrationManager.shared.vibrateLight() : VibrationManager.shared.vibrateMedium()
    }

    /// - Parameter made: 显示端只撤销指定一侧的最近一次出手；页面自身（菜单 / 左滑）撤销全局最后一次。
    private func undoLastShot(made: Bool? = nil) {
        guard !gameFinished else { return }
        let index: Int?
        if let made {
            index = shots.lastIndex { $0.made == made }
        } else {
            index = shots.isEmpty ? nil : shots.count - 1
        }
        guard let index else { return }
        shots.remove(at: index)
        saveRecord(finished: false)
        VibrationManager.shared.vibrateLight()
        if made == nil {
            showToastMessage(NSLocalizedString(
                "shot_training_undo_done",
                value: "已撤销上一次记录",
                comment: "Shot training undo done"
            ))
        }
    }

    private func openEntrySidePrompt() {
        guard mode == .free, shots.isEmpty, !gameFinished else { return }
        clearEntrySidePromptTimer()
        showEntrySidePrompt = true
        let work = DispatchWorkItem {
            entrySidePromptWork = nil
            showEntrySidePrompt = false
        }
        entrySidePromptWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.entrySidePromptDuration, execute: work)
    }

    private func clearEntrySidePromptTimer() {
        entrySidePromptWork?.cancel()
        entrySidePromptWork = nil
    }

    private func hideEntrySidePrompt() {
        clearEntrySidePromptTimer()
        showEntrySidePrompt = false
    }

    private func togglePreferredOrientation() {
        preferLandscape.toggle()
        UserDefaults.standard.set(preferLandscape, forKey: Self.landscapeLayoutKey)
    }

    private func finishTraining() {
        guard !gameFinished, !shots.isEmpty else { return }
        gameFinished = true
        showGameOver = true
        saveRecord(finished: true)
        VibrationManager.shared.vibrateMedium()
    }

    /// 重新开始：先把上一段落库为已结束，再清零。
    private func restartSession() {
        saveRecord(finished: true)
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.basketballTraining.canonicalScoreboardIdentifier)
        gameStartTime = Date()
        shots.removeAll()
        gameFinished = false
        showGameOver = false
        finalizedRecordID = nil
        menuConfirm.clear()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        openEntrySidePrompt()
    }

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToastMessage(NSLocalizedString(
                "press_again_to_exit",
                value: "再按一次退出",
                comment: ""
            ))
            return
        }

        exitConfirmDeadline = nil
        if !saveRecord(finished: gameFinished) { return }
        performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }

    // MARK: - Projection / cross-device display

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: { displaySnapshot() },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: false,
                    finished: gameFinished,
                    scoringLocked: false
                ) else { return }
                // 自由模式的分值只能由场上记录者决定，显示端只提供固定模式的加减。
                guard mode != .free else { return }
                let points = mode.fixedPoints ?? 1
                switch intent {
                case .addLeft: record(points: points, made: false)
                case .addRight: record(points: points, made: true)
                case .subtractLeft: undoLastShot(made: false)
                case .subtractRight: undoLastShot(made: true)
                case .undo: undoLastShot()
                case .exchangeSides, .requestSnapshot: break
                }
            }
        )
    }

    /// 显示端只有一个版式：横屏复刻记分分区（`shotTrainingGrid`）。固定模式左右两块为未中/命中总数，
    /// 自由模式上下分区、每侧 1/2/3 列，分项计数走 sportState。
    private func displaySnapshot() -> LocalScoreboardDisplayState {
        let currentCounts = counts
        let appearance = ScoreboardAppearanceSnapshot.current(
            styleID: ScoreboardStyleID(gameType: .basketballTraining)
        )
        var compact = LocalScoreboardDisplayState(
            gameID: GameType.basketballTraining.canonicalScoreboardIdentifier,
            title: "",
            leftName: zoneLabel(made: false),
            rightName: zoneLabel(made: true),
            leftScore: "\(currentCounts.missed)",
            rightScore: "\(currentCounts.made)",
            themeID: appearance.theme.rawValue,
            fontID: appearance.font.rawValue,
            finished: gameFinished,
            revision: 0
        )
        var external = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .shotTrainingGrid,
            sportState: [
                "trainingMode": .string(mode.rawValue),
                "trainingPoints": .integer(mode.fixedPoints ?? 0),
                "trainingOneMade": .integer(currentCounts.oneMade),
                "trainingOneMiss": .integer(currentCounts.oneMiss),
                "trainingTwoMade": .integer(currentCounts.twoMade),
                "trainingTwoMiss": .integer(currentCounts.twoMiss),
                "trainingThreeMade": .integer(currentCounts.threeMade),
                "trainingThreeMiss": .integer(currentCounts.threeMiss)
            ]
        )
        external.appearance = .init(snapshot: appearance)
        compact.externalState = external
        return compact
    }

    @discardableResult
    private func saveRecord(finished: Bool) -> Bool {
        let end = Date()
        let currentCounts = counts
        let isFinished = finished || gameFinished
        // 和羽毛球等计分页保持一致：刚进入后即使还是 0:0，也要留下 live
        // resume，用户退出后可以从首页的未完成比赛继续。空训练若被放弃，
        // ResumeSessionLifecycle 会直接清理，不会生成一条 0 次出手的历史记录。
        guard !shots.isEmpty || !isFinished else { return false }
        if isFinished, finalizedRecordID == recordID { return true }
        let snapshot = ShotTrainingResumeState(mode: mode, shots: shots, finished: isFinished)
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(snapshot)
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to encode shot training \(recordID)")
            return false
        }

        var runningMiss = 0
        var runningMade = 0
        let detailedActions = shots.map { shot -> DetailedScoreAction in
            if shot.made { runningMade += 1 } else { runningMiss += 1 }
            return DetailedScoreAction(
                type: .scoreChanged,
                epochMilliseconds: Int64(shot.timestamp.timeIntervalSince1970 * 1_000),
                team: shot.made ? .team2 : .team1,
                scores: [runningMiss, runningMade],
                scoreChange: 1,
                operationCode: "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
            )
        } + (isFinished ? [DetailedScoreAction(
            type: .matchFinished,
            epochMilliseconds: Int64(end.timeIntervalSince1970 * 1_000),
            scores: [currentCounts.missed, currentCounts.made],
            operationCode: "training_rate_\(currentCounts.rate)"
        )] : [])

        let modeValue = mode.fixedPoints.map { "\($0)pt" } ?? "free"
        var extraData: [String: AnyCodable] = [
            "type": AnyCodable(GameType.basketballTraining.rawValue),
            "gameMode": AnyCodable(modeValue),
            "basketballTrainingMode": AnyCodable(mode.fixedPoints == nil ? "mixed" : "fixed"),
            "basketballTrainingScoringMode": AnyCodable(mode.rawValue),
            "onePointMade": AnyCodable(currentCounts.oneMade),
            "onePointMiss": AnyCodable(currentCounts.oneMiss),
            "twoPointMade": AnyCodable(currentCounts.twoMade),
            "twoPointMiss": AnyCodable(currentCounts.twoMiss),
            "threePointMade": AnyCodable(currentCounts.threeMade),
            "threePointMiss": AnyCodable(currentCounts.threeMiss),
            "basketballTrainingMixed": AnyCodable([
                "onePointMade": currentCounts.oneMade,
                "onePointMiss": currentCounts.oneMiss,
                "twoPointMade": currentCounts.twoMade,
                "twoPointMiss": currentCounts.twoMiss,
                "threePointMade": currentCounts.threeMade,
                "threePointMiss": currentCounts.threeMiss
            ])
        ]
        if let fixedPoints = mode.fixedPoints { extraData["targetScore"] = AnyCodable(fixedPoints) }

        let actionLog = ["\(Int64(gameStartTime.timeIntervalSince1970 * 1_000))|training_start"]
            + shots.map { shot in
                "\(Int64(shot.timestamp.timeIntervalSince1970 * 1_000))|training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
            }
            + (isFinished ? ["\(Int64(end.timeIntervalSince1970 * 1_000))|training_rate_\(currentCounts.rate)"] : [])
        let record = ScoreboardRecord(
            id: recordID,
            gameType: .basketballTraining,
            startTime: gameStartTime,
            endTime: end,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: NSLocalizedString("shot_training_miss", value: "未中", comment: ""),
            team2Name: NSLocalizedString("shot_training_made", value: "命中", comment: ""),
            team1FinalScore: currentCounts.missed,
            team2FinalScore: currentCounts.made,
            actions: actionLog,
            detailedActions: detailedActions,
            totalScoreChanges: currentCounts.attempts,
            extraData: extraData,
            stateSnapshot: snapshotData,
            status: isFinished ? .finished : .draft
        )
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: isFinished)
            if isFinished {
                finalizedRecordID = recordID
                ScoreboardRecordsViewModel.shared.refreshRecords()
            }
            return true
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save shot training \(recordID)")
            return false
        }
    }
}
