//
//  ArcheryScoreboardView.swift
//  jifen
//
//  射箭计分板：使用标准 PVP 模板布局，保留射箭局分规则（先到 6 分胜、5:5 一箭决胜）。
//

import LinkCore
import ScoreCore
import SwiftUI
import UIKit

private let archeryArrowsPerSetNormal = 3
private let archeryArrowsPerSetShootoff = 1
private let archerySetPointsToWin = 6
private let archerySetPointsWin = 2
private let archerySetPointsTie = 1
private let archerySetEndOverlayDelay: TimeInterval = 1.2

private let archeryScoreGrid: [[Int?]] = [
    [10, 9, 8, 7],
    [6, 5, 4, 3],
    [2, 1, 0, -1]
]

struct ArcheryScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller = ArcheryScoreboardController()
    @State private var viewModel = ArcheryViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var recordID: String
    @State private var watchSessionId: UUID?

    @State private var showArrowPicker = false
    @State private var showSetEndOverlay = false
    @State private var showClosestToCenter = false
    @State private var pendingSetNumber = 0
    @State private var pendingSetLeftScore = 0
    @State private var pendingSetRightScore = 0
    @State private var pendingContinueUpdate: (() -> Void)? = nil
    @State private var pendingClosestContinue: ((Bool) -> Void)? = nil

    private var scoringLocked: Bool { watchSessionId != nil && watchLinkService.isFollower }

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        _recordID = State(initialValue: initialRecordId ?? "archery_\(Int(Date().timeIntervalSince1970))")
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .archery,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" },
                    tapToAddEnabled: false,
                    contentOverlayProvider: { isEditMode in
                        AnyView(ArcheryMiddleLayer(
                            viewModel: viewModel,
                            showArrowPicker: $showArrowPicker,
                            controller: controller,
                            isEditMode: isEditMode,
                            scoringLocked: scoringLocked
                        ))
                    },
                    showEndGame: true,
                    extraMenuItemsProvider: {
                        WatchLinkMenuSupport.extraItems(
                            entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
                            sessionId: watchSessionId,
                            isFollower: watchLinkService.isFollower
                        )
                    },
                    onMenuAction: { action in
                        switch action {
                        case "takeover":
                            if let id = watchSessionId {
                                Task {
                                    try? await watchLinkService.takeover(sessionId: id)
                                    publishWatchIfNeeded()
                                }
                            }
                        case "endLink":
                            if let id = watchSessionId {
                                watchLinkService.leaveSession(id)
                                watchSessionId = nil
                            }
                        default:
                            break
                        }
                    }
                ),
                onBack: {
                    saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            VStack(spacing: 0) {
                archeryTopBadge
                    .padding(.top, ScoreboardConstants.buttonPadding + 2)
                Spacer()
            }

            if showArrowPicker {
                archeryScorePicker
            }

            if showSetEndOverlay {
                setEndOverlay
            }

            if showClosestToCenter {
                closestToCenterOverlay
            }

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: viewModel.getWinnerName(),
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.sets ?? 0,
                    rightScore: viewModel.rightTeam.sets ?? 0,
                    onNewGame: {
                        showGameOverDialog = false
                        viewModel.reset()
                        controller.recordScoreAction(action: "reset")
                    },
                    onRecords: {
                        saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        shareFinishedMatch()
                    },
                    onExit: {
                        saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                        onNavigationBack?()
                        dismiss()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
            }
        }
        .navigationTitle(NSLocalizedString("project_archery", value: "Archery", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            watchSessionId = initialSetup?.linkedWatchSessionId
            viewModel.controller = controller
            if let setup = initialSetup {
                let left = setup.team1Name.isEmpty
                    ? NSLocalizedString("watch_team_red", value: "红方", comment: "")
                    : setup.team1Name
                let right = setup.team2Name.isEmpty
                    ? NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
                    : setup.team2Name
                let openingIsLeft = setup.servingSide != MatchSide.right.rawValue
                viewModel.configureOpening(leftName: left, rightName: right, openingIsLeft: openingIsLeft)
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()

            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameOverDialog = true
                if !watchLinkService.isFollower {
                    saveGameRecordInRealTime(isGameFinished: true)
                }
                publishWatchIfNeeded(finished: true)
            }
        }
        .onChange(of: viewModel.leftTeam.score) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.rightTeam.score) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.leftTeam.sets) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.rightTeam.sets) { _, _ in publishWatchIfNeeded() }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId, let update, update.sessionId == watchSessionId,
                  let remote = update.snapshot.archeryState else { return }
            applyRemoteArchery(remote)
        }
        .onDisappear {
            if let watchSessionId { watchLinkService.endWatchSession(watchSessionId) }
            if !watchLinkService.isFollower {
                saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
            }
        }
    }

    private var archeryTopBadge: some View {
        VStack(spacing: 2) {
            Text(String(format: NSLocalizedString("watch_set_title_format", value: "第 %d 局", comment: ""), viewModel.currentSet))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("\(viewModel.leftTeam.sets ?? 0) - \(viewModel.rightTeam.sets ?? 0)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
        .cornerRadius(12)
    }

    private var centerShooterIndicator: some View {
        CenterLineServeIndicator(isLeftServing: viewModel.currentShooterIsLeft, triangleSize: 34)
    }

    private var archeryScorePicker: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showArrowPicker = false }

            VStack(spacing: 0) {
                // 标题栏与 X 按钮对齐羽毛球菜单（MenuDialog）：标题整体居中，X 在右侧圆底
                ZStack {
                    Text(currentShooterName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    HStack {
                        Spacer()
                        Button(action: { showArrowPicker = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .frame(height: 48)

                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { col in
                                let value = archeryScoreGrid[row][col]
                                Button {
                                    viewModel.recordArrow(value: value == -1 ? nil : value)
                                    showArrowPicker = false
                                } label: {
                                    Text(value == -1 ? "M" : "\(value ?? 0)")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(value == -1 ? .white : .black)
                                        .frame(width: 60, height: 60)
                                        .background(value == -1 ? Color.orange : Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 380)
            .background(Color.black.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.3), radius: 32, x: 0, y: 12)
            .onTapGesture { }
        }
    }

    private var setEndOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("watch_set_end_format", value: "第 %d 局结束", comment: ""), pendingSetNumber))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(viewModel.leftTeam.name)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "DC143C"))
                    Text("\(pendingSetLeftScore) - \(pendingSetRightScore)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(viewModel.rightTeam.name)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "1E90FF"))
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)
        }
    }

    private var closestToCenterOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(NSLocalizedString("archery_closest_title", value: "一箭决胜 · 近心", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text(String(
                    format: NSLocalizedString("archery_closest_message", value: "双方同环 %d，请选择更近心的一方", comment: ""),
                    pendingSetLeftScore
                ))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        showClosestToCenter = false
                        pendingClosestContinue?(true)
                        pendingClosestContinue = nil
                    } label: {
                        Text(viewModel.leftTeam.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(hex: "DC143C"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    Button {
                        showClosestToCenter = false
                        pendingClosestContinue?(false)
                        pendingClosestContinue = nil
                    } label: {
                        Text(viewModel.rightTeam.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(hex: "1E90FF"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 40)
        }
    }

    private var currentShooterName: String {
        viewModel.currentShooterIsLeft ? viewModel.leftTeam.name : viewModel.rightTeam.name
    }

    private func handleSetEnd(data: SetEndCallbackData) {
        pendingSetNumber = data.setNumber
        pendingSetLeftScore = data.finalLeftScore
        pendingSetRightScore = data.finalRightScore

        if viewModel.needsClosestToCenterDecision(
            leftArrowScore: data.finalLeftScore,
            rightArrowScore: data.finalRightScore
        ) {
            pendingClosestContinue = { leftWins in
                self.viewModel.applyClosestToCenter(leftWins: leftWins)
            }
            showClosestToCenter = true
            return
        }

        showSetEndOverlay = true
        pendingContinueUpdate = data.continueUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + archerySetEndOverlayDelay) {
            showSetEndOverlay = false
            pendingContinueUpdate?()
            pendingContinueUpdate = nil
        }
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let width = UIScreen.main.bounds.width
        if width <= 0 { return base }
        return min(240, max(base, base + (CGFloat(width) - 400) * 0.15))
    }

    private func restoreDraftIfNeeded() {
        guard let recordId = initialRecordId,
              let record = ScoreboardRecordManager.shared.getRecordById(recordId),
              record.status == .draft else {
            return
        }

        recordID = recordId
        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name

        if let leftRingScore = record.extraData?["leftRingScore"]?.value as? Int,
           let rightRingScore = record.extraData?["rightRingScore"]?.value as? Int {
            // keep names already set
            _ = leftRingScore
            _ = rightRingScore
        }
        viewModel.restoreMatchFields(
            leftRingScore: record.extraData?["leftRingScore"]?.value as? Int,
            rightRingScore: record.extraData?["rightRingScore"]?.value as? Int,
            leftSets: record.extraData?["leftSets"]?.value as? Int,
            rightSets: record.extraData?["rightSets"]?.value as? Int,
            currentSet: record.extraData?["currentSet"]?.value as? Int,
            arrowsPerSet: record.extraData?["arrowsPerSet"]?.value as? Int,
            arrowsLeftThisSet: record.extraData?["arrowsLeftThisSet"]?.value as? Int,
            arrowsRightThisSet: record.extraData?["arrowsRightThisSet"]?.value as? Int,
            currentShooterIsLeft: record.extraData?["currentShooterIsLeft"]?.value as? Bool,
            openingShooterIsLeft: record.extraData?["openingShooterIsLeft"]?.value as? Bool,
            sidesSwapped: record.extraData?["sidesSwapped"]?.value as? Bool
        )
    }

    private func publishWatchIfNeeded(finished: Bool = false) {
        guard let watchSessionId, watchLinkService.isController else { return }
        let snapshot = viewModel.linkedSnapshot(finished: finished)
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: .archeryDual,
            snapshot: .archery(snapshot)
        )
    }

    private func applyRemoteArchery(_ remote: LinkedArcheryState) {
        viewModel.applyRemote(remote)
        if remote.finished {
            showGameOverDialog = true
        }
    }

    private func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        let hasProgress = !controller.getGameActions().isEmpty
            || viewModel.leftTeam.score != 0
            || viewModel.rightTeam.score != 0
            || (viewModel.leftTeam.sets ?? 0) != 0
            || (viewModel.rightTeam.sets ?? 0) != 0
            || isGameFinished
            || viewModel.gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || viewModel.gameFinished
        let start = controller.getGameStartTime()
        let end = Date()

        var winner: String?
        if finished {
            let leftSets = viewModel.leftTeam.sets ?? 0
            let rightSets = viewModel.rightTeam.sets ?? 0
            if leftSets > rightSets {
                winner = TeamID.team0.rawValue
            } else if rightSets > leftSets {
                winner = TeamID.team1.rawValue
            }
        }

        controller.saveScoreboardRecord(
            id: recordID,
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.sets ?? 0,
            team2FinalScore: viewModel.rightTeam.sets ?? 0,
            team1SetScore: viewModel.leftTeam.sets,
            team2SetScore: viewModel.rightTeam.sets,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [
                "currentSet": viewModel.currentSet,
                "arrowsPerSet": viewModel.arrowsPerSet,
                "arrowsLeftThisSet": viewModel.arrowsLeftThisSet,
                "arrowsRightThisSet": viewModel.arrowsRightThisSet,
                "currentShooterIsLeft": viewModel.currentShooterIsLeft,
                "openingShooterIsLeft": viewModel.openingShooterIsLeft,
                "sidesSwapped": viewModel.match.sidesSwapped,
                "leftRingScore": viewModel.leftTeam.score,
                "rightRingScore": viewModel.rightTeam.score,
                "leftSets": viewModel.leftTeam.sets ?? 0,
                "rightSets": viewModel.rightTeam.sets ?? 0
            ],
            status: finished ? .finished : .draft
        )
    }

    private func shareFinishedMatch() {
        let text = "\(viewModel.leftTeam.name) \(viewModel.leftTeam.sets ?? 0) - \(viewModel.rightTeam.sets ?? 0) \(viewModel.rightTeam.name)"
        ScoreboardShareSupport.present(text: text)
    }
}

private class ArcheryScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .archery,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 80
        ))
    }

    override func getScoringOptions() -> [Int] {
        []
    }
}

/// 需为 internal 以便 ScoreboardTemplate 通过 ScoreViewModelProtocol 派发调用 adjustSets（private 时协议走默认空实现，局分 +/- 不生效）
@Observable
class ArcheryViewModel: BaseScoreViewModel {
    private let sessionStore: ArcherySessionStore
    private var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    private var lastEvents: [ArcheryMatchEvent] = []

    var match: ArcheryMatchState { sessionStore.state }
    var teamScreenLayout: TeamScreenLayout { sessionStore.teamScreenLayout }
    var sessionId: UUID { sessionStore.sessionId }

    var currentSet: Int { match.currentSet }
    var currentShooterIsLeft: Bool {
        get { match.currentShooterIsLeft }
        set { _ = apply(.selectShooter(isLeft: newValue), recordHistory: false) }
    }
    var openingShooterIsLeft: Bool { match.openingShooterIsLeft }
    var arrowsLeftThisSet: Int { match.arrowsLeftThisSet }
    var arrowsRightThisSet: Int { match.arrowsRightThisSet }
    var arrowsPerSet: Int { match.arrowsPerSet }

    override init(controller: BaseScoreboardController? = nil) {
        sessionStore = ArcherySessionStore(
            leftName: NSLocalizedString("watch_team_red", value: "红方", comment: ""),
            rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        )
        super.init(controller: controller)
        syncTeamsFromMatch()
    }

    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }

    func configureOpening(leftName: String, rightName: String, openingIsLeft: Bool) {
        sessionStore.configureOpening(leftName: leftName, rightName: rightName, openingIsLeft: openingIsLeft)
        syncTeamsFromMatch()
    }

    func applyRemote(_ remote: LinkedArcheryState) {
        var next = match
        remote.applying(to: &next)
        sessionStore.replaceDisplayedState(next)
        syncTeamsFromMatch()
    }

    func linkedSnapshot(finished: Bool = false) -> LinkedArcheryState {
        var snap = LinkedArcheryState(match: match)
        if finished { snap.finished = true }
        return snap
    }

    func recordArrow(value: Int?) {
        _ = apply(.recordArrow(side: nil, value: value))
        handlePostReduceUI()
    }

    override func adjustScore(isLeft: Bool, delta: Int) {
        _ = apply(.adjustArrowSum(side: isLeft ? .left : .right, delta: delta))
    }

    func adjustSetPoints(isLeft: Bool, delta: Int) {
        _ = apply(.adjustSetPoints(side: isLeft ? .left : .right, delta: delta))
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        adjustSetPoints(isLeft: isLeft, delta: delta)
    }

    func getWinnerDisplayText() -> String {
        let name = getWinnerName()
        if name.isEmpty {
            return NSLocalizedString("draw_result", value: "平局", comment: "")
        }
        return String(format: NSLocalizedString("winner_named_format", value: "%@ 获胜", comment: ""), name)
    }

    func getWinnerName() -> String {
        guard match.finished, let side = match.winnerSide else { return "" }
        return side == .left ? match.leftName : match.rightName
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !match.finished else { return }
        let side: MatchSide? = editState.isEditMode ? (isLeft ? .left : .right) : nil
        if !editState.isEditMode {
            guard isLeft == match.currentShooterIsLeft else { return }
        }
        _ = apply(.recordArrow(side: side, value: points))
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(max(0, points))")
        controller?.performVibration(type: .light)
        handlePostReduceUI()
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !match.finished else { return }
        _ = apply(.adjustArrowSum(side: isLeft ? .left : .right, delta: -max(0, points)))
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(max(0, points))")
        controller?.performVibration(type: .light)
    }

    override func undo() -> Bool {
        guard sessionStore.undo() else { return false }
        syncTeamsFromMatch()
        controller?.performVibration(type: .light)
        return true
    }

    override func exchangeSides() {
        guard !match.finished else { return }
        _ = apply(.exchangeSides)
        controller?.performVibration(type: .medium)
    }

    override func reset() {
        super.reset()
        _ = apply(.reset, recordHistory: false)
        sessionStore.clearHistory()
    }

    func needsClosestToCenterDecision(leftArrowScore: Int, rightArrowScore: Int) -> Bool {
        match.needsClosestToCenter
            && match.leftArrowSum == leftArrowScore
            && match.rightArrowSum == rightArrowScore
    }

    func applyClosestToCenter(leftWins: Bool) {
        _ = apply(.completeSet(closestToCenterWinner: leftWins ? .left : .right), recordHistory: false)
        if match.finished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        }
        syncTeamsFromMatch()
    }

    func continuePendingSetEnd() {
        guard match.setCompletionPending, !match.closestToCenterPending else { return }
        _ = apply(.completeSet(closestToCenterWinner: nil), recordHistory: false)
        if match.finished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        }
        syncTeamsFromMatch()
    }

    @discardableResult
    private func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> Bool {
        let result = sessionStore.apply(intent, recordHistory: recordHistory)
        guard result.accepted else { return false }
        lastEvents = result.events
        syncTeamsFromMatch()
        return true
    }

    private func handlePostReduceUI() {
        for event in lastEvents {
            switch event {
            case .closestToCenterRequired(let setNumber, _):
                let data = SetEndCallbackData(
                    finalLeftScore: match.leftArrowSum,
                    finalRightScore: match.rightArrowSum,
                    winnerName: NSLocalizedString("draw_result", value: "平局", comment: ""),
                    setNumber: setNumber,
                    leftSets: match.leftSetPoints,
                    rightSets: match.rightSetPoints,
                    leftGames: nil,
                    rightGames: nil,
                    shouldChangeSides: false,
                    isGameFinished: false,
                    continueUpdate: { [weak self] in
                        self?.applyClosestToCenter(leftWins: true)
                    }
                )
                onSetEndCallback?(data)
            case .setReady(let setNumber, let leftArrow, let rightArrow, let pendingLeft, let pendingRight):
                let winnerName: String
                if leftArrow > rightArrow {
                    winnerName = match.leftName
                } else if rightArrow > leftArrow {
                    winnerName = match.rightName
                } else {
                    winnerName = NSLocalizedString("draw_result", value: "平局", comment: "")
                }
                let isMatchFinished = pendingLeft >= match.rules.setPointsToWin || pendingRight >= match.rules.setPointsToWin
                let data = SetEndCallbackData(
                    finalLeftScore: leftArrow,
                    finalRightScore: rightArrow,
                    winnerName: winnerName,
                    setNumber: setNumber,
                    leftSets: pendingLeft,
                    rightSets: pendingRight,
                    leftGames: nil,
                    rightGames: nil,
                    shouldChangeSides: false,
                    isGameFinished: isMatchFinished,
                    continueUpdate: { [weak self] in
                        self?.continuePendingSetEnd()
                    }
                )
                onSetEndCallback?(data)
            case .matchFinished:
                gameFinished = true
                controller?.performVibration(type: .heavy)
            default:
                break
            }
        }
    }

    private func syncTeamsFromMatch() {
        leftTeam.name = match.leftName
        rightTeam.name = match.rightName
        leftTeam.score = match.leftArrowSum
        rightTeam.score = match.rightArrowSum
        leftTeam.sets = match.leftSetPoints
        rightTeam.sets = match.rightSetPoints
        gameFinished = match.finished
    }

    func restoreMatchFields(
        leftRingScore: Int?,
        rightRingScore: Int?,
        leftSets: Int?,
        rightSets: Int?,
        currentSet: Int?,
        arrowsPerSet: Int?,
        arrowsLeftThisSet: Int?,
        arrowsRightThisSet: Int?,
        currentShooterIsLeft: Bool?,
        openingShooterIsLeft: Bool?,
        sidesSwapped: Bool? = nil
    ) {
        var next = match
        if let leftRingScore { next.leftArrowSum = leftRingScore }
        if let rightRingScore { next.rightArrowSum = rightRingScore }
        if let leftSets { next.leftSetPoints = leftSets }
        if let rightSets { next.rightSetPoints = rightSets }
        if let currentSet { next.currentSet = max(1, currentSet) }
        if let arrowsPerSet { next.arrowsPerSet = max(1, arrowsPerSet) }
        if let arrowsLeftThisSet { next.arrowsLeftThisSet = max(0, arrowsLeftThisSet) }
        if let arrowsRightThisSet { next.arrowsRightThisSet = max(0, arrowsRightThisSet) }
        if let currentShooterIsLeft { next.currentShooterIsLeft = currentShooterIsLeft }
        if let openingShooterIsLeft { next.openingShooterIsLeft = openingShooterIsLeft }
        if let sidesSwapped { next.sidesSwapped = sidesSwapped }
        sessionStore.replaceDisplayedState(next)
        sessionStore.persistSnapshot()
        syncTeamsFromMatch()
    }
}

/// 射箭中间层：发球箭头 + 左右半区点击，仅比左右半区高一层，由 Template 插在按钮与菜单之下；编辑模式下不显示、不响应，与羽毛球等共用模板行为一致
private struct ArcheryMiddleLayer: View {
    var viewModel: ArcheryViewModel
    @Binding var showArrowPicker: Bool
    var controller: ArcheryScoreboardController
    var isEditMode: Bool
    var scoringLocked: Bool = false

    var body: some View {
        Group {
            if !isEditMode && !viewModel.gameFinished && !scoringLocked {
                CenterLineServeIndicator(isLeftServing: viewModel.currentShooterIsLeft, triangleSize: 34)
                    .allowsHitTesting(false)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: geo.size.width / 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.currentShooterIsLeft = true
                                showArrowPicker = true
                                controller.performVibration(type: .light)
                            }
                        Color.clear
                            .frame(width: geo.size.width / 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.currentShooterIsLeft = false
                                showArrowPicker = true
                                controller.performVibration(type: .light)
                            }
                    }
                }
                .padding(.top, 80)
                .padding(.bottom, 88)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ArcheryScoreboardView()
    }
}
