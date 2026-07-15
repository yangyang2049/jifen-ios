//
//  ArcheryScoreboardView.swift
//  jifen
//
//  射箭计分板：使用标准 PVP 模板布局，保留射箭局分规则（先到 6 分胜、5:5 一箭决胜）。
//

import SwiftUI

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
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller = ArcheryScoreboardController()
    @State private var viewModel = ArcheryViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120

    @State private var showArrowPicker = false
    @State private var showSetEndOverlay = false
    @State private var pendingSetNumber = 0
    @State private var pendingSetLeftScore = 0
    @State private var pendingSetRightScore = 0

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
                            isEditMode: isEditMode
                        ))
                    }
                ),
                onBack: {
                    saveRecordIfNeeded()
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

            if viewModel.gameFinished {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text(viewModel.getWinnerDisplayText())
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.accentColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.5))
                .cornerRadius(14)
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(NSLocalizedString("project_archery", value: "Archery", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                onSetupConsumed?()
            }
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()

            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
        }
        .onDisappear {
            saveRecordIfNeeded()
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

    private var currentShooterName: String {
        viewModel.currentShooterIsLeft ? viewModel.leftTeam.name : viewModel.rightTeam.name
    }

    private func handleSetEnd(data: SetEndCallbackData) {
        pendingSetNumber = data.setNumber
        pendingSetLeftScore = data.finalLeftScore
        pendingSetRightScore = data.finalRightScore
        showSetEndOverlay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + archerySetEndOverlayDelay) {
            showSetEndOverlay = false
            data.continueUpdate()
        }
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let width = UIScreen.main.bounds.width
        if width <= 0 { return base }
        return min(240, max(base, base + (CGFloat(width) - 400) * 0.15))
    }

    private func saveRecordIfNeeded() {
        guard !controller.isRecordSaved(), !controller.getGameActions().isEmpty else { return }

        let winner: String? = (viewModel.leftTeam.sets ?? 0) > (viewModel.rightTeam.sets ?? 0)
            ? "left"
            : ((viewModel.rightTeam.sets ?? 0) > (viewModel.leftTeam.sets ?? 0) ? "right" : nil)

        let start = controller.getGameStartTime()
        let end = Date()
        controller.saveScoreboardRecord(
            id: "archery_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
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
                "arrowsPerSet": viewModel.arrowsPerSet
            ]
        )
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

private struct ArcheryStateSnapshot {
    let leftName: String
    let rightName: String
    let leftScore: Int
    let rightScore: Int
    let leftSetPoints: Int
    let rightSetPoints: Int
    let currentSet: Int
    let currentShooterIsLeft: Bool
    let arrowsLeftThisSet: Int
    let arrowsRightThisSet: Int
    let arrowsPerSet: Int
    let gameFinished: Bool
}

/// 需为 internal 以便 ScoreboardTemplate 通过 ScoreViewModelProtocol 派发调用 adjustSets（private 时协议走默认空实现，局分 +/- 不生效）
@Observable
class ArcheryViewModel: BaseScoreViewModel {
    var currentSet: Int = 1
    var currentShooterIsLeft: Bool = true
    var arrowsLeftThisSet: Int = 0
    var arrowsRightThisSet: Int = 0
    var arrowsPerSet: Int = archeryArrowsPerSetNormal

    private var snapshots: [ArcheryStateSnapshot] = []
    private var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.name = NSLocalizedString("watch_team_red", value: "红方", comment: "")
        rightTeam.name = NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        leftTeam.sets = 0
        rightTeam.sets = 0
    }

    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }

    func recordArrow(value: Int?) {
        let points = max(0, value ?? 0)
        addScore(isLeft: currentShooterIsLeft, points: points)
    }

    func adjustScore(isLeft: Bool, delta: Int) {
        saveSnapshot()
        if isLeft {
            leftTeam.score = max(0, leftTeam.score + delta)
        } else {
            rightTeam.score = max(0, rightTeam.score + delta)
        }
    }

    func adjustSetPoints(isLeft: Bool, delta: Int) {
        #if DEBUG
        let beforeLeft = leftTeam.sets ?? 0
        let beforeRight = rightTeam.sets ?? 0
        print("[ArcheryViewModel] adjustSetPoints isLeft=\(isLeft) delta=\(delta) before L=\(beforeLeft) R=\(beforeRight)")
        #endif
        saveSnapshot()
        if isLeft {
            leftTeam.sets = max(0, (leftTeam.sets ?? 0) + delta)
        } else {
            rightTeam.sets = max(0, (rightTeam.sets ?? 0) + delta)
        }
        #if DEBUG
        print("[ArcheryViewModel] adjustSetPoints after L=\(leftTeam.sets ?? 0) R=\(rightTeam.sets ?? 0)")
        #endif
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        #if DEBUG
        print("[ArcheryViewModel] adjustSets isLeft=\(isLeft) delta=\(delta)")
        #endif
        adjustSetPoints(isLeft: isLeft, delta: delta)
    }

    func getWinnerDisplayText() -> String {
        let leftSetPoints = leftTeam.sets ?? 0
        let rightSetPoints = rightTeam.sets ?? 0
        if leftSetPoints > rightSetPoints {
            return String(format: NSLocalizedString("winner_named_format", value: "%@ 获胜", comment: ""), leftTeam.name)
        }
        if rightSetPoints > leftSetPoints {
            return String(format: NSLocalizedString("winner_named_format", value: "%@ 获胜", comment: ""), rightTeam.name)
        }
        return NSLocalizedString("draw_result", value: "平局", comment: "")
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        if !editState.isEditMode {
            guard isLeft == currentShooterIsLeft else { return }
        }

        saveSnapshot()

        if isLeft {
            leftTeam.score += max(0, points)
            arrowsLeftThisSet += 1
        } else {
            rightTeam.score += max(0, points)
            arrowsRightThisSet += 1
        }

        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(max(0, points))")
        controller?.performVibration(type: .light)

        currentShooterIsLeft.toggle()

        if arrowsLeftThisSet >= arrowsPerSet && arrowsRightThisSet >= arrowsPerSet {
            finishCurrentSet()
        }
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveSnapshot()
        if isLeft {
            leftTeam.score = max(0, leftTeam.score - max(0, points))
        } else {
            rightTeam.score = max(0, rightTeam.score - max(0, points))
        }
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(max(0, points))")
        controller?.performVibration(type: .light)
    }

    override func undo() -> Bool {
        guard let snapshot = snapshots.popLast() else { return false }
        restoreSnapshot(snapshot)
        controller?.performVibration(type: .light)
        return true
    }

    override func exchangeSides() {
        guard !gameFinished else { return }

        saveSnapshot()

        let tempName = leftTeam.name
        let tempScore = leftTeam.score
        let tempSets = leftTeam.sets

        leftTeam.name = rightTeam.name
        leftTeam.score = rightTeam.score
        leftTeam.sets = rightTeam.sets

        rightTeam.name = tempName
        rightTeam.score = tempScore
        rightTeam.sets = tempSets

        currentShooterIsLeft.toggle()
        controller?.performVibration(type: .medium)
    }

    override func reset() {
        super.reset()
        currentSet = 1
        currentShooterIsLeft = true
        arrowsLeftThisSet = 0
        arrowsRightThisSet = 0
        arrowsPerSet = archeryArrowsPerSetNormal
        leftTeam.sets = 0
        rightTeam.sets = 0
        snapshots.removeAll()
    }

    private func finishCurrentSet() {
        let finalLeftScore = leftTeam.score
        let finalRightScore = rightTeam.score
        let setNumber = currentSet

        let newLeftSetPoints: Int
        let newRightSetPoints: Int
        let winnerName: String

        if finalLeftScore > finalRightScore {
            newLeftSetPoints = (leftTeam.sets ?? 0) + archerySetPointsWin
            newRightSetPoints = rightTeam.sets ?? 0
            winnerName = leftTeam.name
        } else if finalRightScore > finalLeftScore {
            newLeftSetPoints = leftTeam.sets ?? 0
            newRightSetPoints = (rightTeam.sets ?? 0) + archerySetPointsWin
            winnerName = rightTeam.name
        } else {
            newLeftSetPoints = (leftTeam.sets ?? 0) + archerySetPointsTie
            newRightSetPoints = (rightTeam.sets ?? 0) + archerySetPointsTie
            winnerName = NSLocalizedString("draw_result", value: "平局", comment: "")
        }

        let isMatchFinished = newLeftSetPoints >= archerySetPointsToWin || newRightSetPoints >= archerySetPointsToWin

        if let callback = onSetEndCallback {
            let data = SetEndCallbackData(
                finalLeftScore: finalLeftScore,
                finalRightScore: finalRightScore,
                winnerName: winnerName,
                setNumber: setNumber,
                leftSets: newLeftSetPoints,
                rightSets: newRightSetPoints,
                leftGames: nil,
                rightGames: nil,
                shouldChangeSides: false,
                isGameFinished: isMatchFinished,
                continueUpdate: {
                    self.applySetEnd(
                        newLeftSetPoints: newLeftSetPoints,
                        newRightSetPoints: newRightSetPoints,
                        isMatchFinished: isMatchFinished
                    )
                }
            )
            callback(data)
        } else {
            applySetEnd(
                newLeftSetPoints: newLeftSetPoints,
                newRightSetPoints: newRightSetPoints,
                isMatchFinished: isMatchFinished
            )
        }
    }

    private func applySetEnd(newLeftSetPoints: Int, newRightSetPoints: Int, isMatchFinished: Bool) {
        leftTeam.sets = newLeftSetPoints
        rightTeam.sets = newRightSetPoints

        if isMatchFinished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
            return
        }

        currentSet += 1
        leftTeam.score = 0
        rightTeam.score = 0
        arrowsLeftThisSet = 0
        arrowsRightThisSet = 0
        arrowsPerSet = (newLeftSetPoints == 5 && newRightSetPoints == 5)
            ? archeryArrowsPerSetShootoff
            : archeryArrowsPerSetNormal
        currentShooterIsLeft = true
    }

    private func saveSnapshot() {
        snapshots.append(ArcheryStateSnapshot(
            leftName: leftTeam.name,
            rightName: rightTeam.name,
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            leftSetPoints: leftTeam.sets ?? 0,
            rightSetPoints: rightTeam.sets ?? 0,
            currentSet: currentSet,
            currentShooterIsLeft: currentShooterIsLeft,
            arrowsLeftThisSet: arrowsLeftThisSet,
            arrowsRightThisSet: arrowsRightThisSet,
            arrowsPerSet: arrowsPerSet,
            gameFinished: gameFinished
        ))
        if snapshots.count > 100 {
            snapshots.removeFirst()
        }
    }

    private func restoreSnapshot(_ snapshot: ArcheryStateSnapshot) {
        leftTeam.name = snapshot.leftName
        rightTeam.name = snapshot.rightName
        leftTeam.score = snapshot.leftScore
        rightTeam.score = snapshot.rightScore
        leftTeam.sets = snapshot.leftSetPoints
        rightTeam.sets = snapshot.rightSetPoints
        currentSet = snapshot.currentSet
        currentShooterIsLeft = snapshot.currentShooterIsLeft
        arrowsLeftThisSet = snapshot.arrowsLeftThisSet
        arrowsRightThisSet = snapshot.arrowsRightThisSet
        arrowsPerSet = snapshot.arrowsPerSet
        gameFinished = snapshot.gameFinished
    }
}

/// 射箭中间层：发球箭头 + 左右半区点击，仅比左右半区高一层，由 Template 插在按钮与菜单之下；编辑模式下不显示、不响应，与羽毛球等共用模板行为一致
private struct ArcheryMiddleLayer: View {
    var viewModel: ArcheryViewModel
    @Binding var showArrowPicker: Bool
    var controller: ArcheryScoreboardController
    var isEditMode: Bool

    var body: some View {
        Group {
            if !isEditMode && !viewModel.gameFinished {
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
