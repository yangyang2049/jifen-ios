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

struct ShotTrainingScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var mode: ShotTrainingMode
    @State private var shots: [ShotTrainingShot]
    @State private var gameStartTime: Date
    @State private var recordID: String
    @State private var gameFinished: Bool
    @State private var showSummary: Bool
    @State private var finalizedRecordID: String?
    @State private var previousIdleTimerDisabled: Bool?

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
        _showSummary = State(initialValue: restoredFinished)
        _finalizedRecordID = State(initialValue: restoredFinished ? restoredID : nil)
    }

    private var counts: ShotTrainingCounts { .build(from: shots) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea()
                VStack(spacing: 10) {
                    topBar
                    modeBar
                    statBar
                    if proxy.size.width > proxy.size.height {
                        HStack(spacing: 1) {
                            shotZone(made: false)
                            shotZone(made: true)
                        }
                    } else {
                        VStack(spacing: 1) {
                            shotZone(made: false)
                            shotZone(made: true)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

                if showSummary { summaryOverlay }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = PreferencesManager.shared.keepScoreboardScreenOn
            onSetupConsumed?()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveRecord(finished: gameFinished) }
        }
        .onDisappear {
            saveRecord(finished: gameFinished)
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: exitTraining) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
            }
            Text(NSLocalizedString("game_basketball_training", value: "投篮训练", comment: ""))
                .font(.system(size: 18, weight: .bold))
            Spacer()
            Button {
                guard !gameFinished, !shots.isEmpty else { return }
                shots.removeLast()
                saveRecord(finished: false)
                VibrationManager.shared.vibrateLight()
            } label: {
                Label(NSLocalizedString("undo", value: "撤销", comment: ""), systemImage: "arrow.uturn.backward")
            }
            .disabled(shots.isEmpty || gameFinished)
            Button {
                finishTraining()
            } label: {
                Text(NSLocalizedString("finish", value: "结束", comment: ""))
                    .fontWeight(.bold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .disabled(shots.isEmpty || gameFinished)
        }
        .foregroundStyle(.white)
        .frame(minHeight: 44)
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(ShotTrainingMode.allCases) { option in
                Button {
                    guard !gameFinished else { return }
                    mode = option
                    if !shots.isEmpty { saveRecord(finished: false) }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == option ? Color.black : Color.white.opacity(0.75))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(mode == option ? Color(red: 0.47, green: 0.84, blue: 0.56) : Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statBar: some View {
        HStack(spacing: 22) {
            stat(NSLocalizedString("shot_training_attempts", value: "出手", comment: ""), "\(counts.attempts)")
            stat(NSLocalizedString("shot_training_made", value: "命中", comment: ""), "\(counts.made)")
            stat(NSLocalizedString("shot_training_rate", value: "命中率", comment: ""), "\(counts.rate)%")
            stat(NSLocalizedString("shot_training_points", value: "得分", comment: ""), "\(counts.points)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
    }

    private func shotZone(made: Bool) -> some View {
        let color = made ? Color(red: 0.18, green: 0.62, blue: 0.31) : Color(red: 0.73, green: 0.23, blue: 0.23)
        return ZStack {
            RoundedRectangle(cornerRadius: 18).fill(color)
            VStack(spacing: 14) {
                Text(made
                    ? NSLocalizedString("shot_training_made", value: "命中", comment: "")
                    : NSLocalizedString("shot_training_miss", value: "未中", comment: ""))
                    .font(.system(size: 28, weight: .bold))
                Text("\(made ? counts.made : counts.missed)")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .monospacedDigit()
                if mode == .free {
                    HStack(spacing: 12) {
                        ForEach(1...3, id: \.self) { points in
                            Button("\(points)") { record(points: points, made: made) }
                                .buttonStyle(.plain)
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 58, height: 46)
                                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                } else {
                    Text(String(
                        format: NSLocalizedString("shot_training_tap_to_record", value: "点击记录 %d 分球", comment: ""),
                        mode.fixedPoints ?? 1
                    ))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard mode != .free else { return }
            record(points: mode.fixedPoints ?? 1, made: made)
        }
    }

    private var summaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(NSLocalizedString("shot_training_summary", value: "训练总结", comment: ""))
                    .font(.system(size: 26, weight: .bold))
                Text("\(counts.made) / \(counts.attempts)  ·  \(counts.rate)%")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(String(format: NSLocalizedString("shot_training_summary_points", value: "累计得分 %d", comment: ""), counts.points))
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 12) {
                    summaryButton(NSLocalizedString("records", value: "记录", comment: ""), action: exitTraining)
                    summaryButton(NSLocalizedString("restart", value: "重新开始", comment: ""), action: restart)
                    summaryButton(NSLocalizedString("share", value: "分享", comment: "")) {
                        ScoreboardShareSupport.present(text: shareText)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(30)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func summaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    private var shareText: String {
        String(
            format: NSLocalizedString("shot_training_share", value: "投篮训练：命中 %d / %d，命中率 %d%%，得分 %d", comment: ""),
            counts.made,
            counts.attempts,
            counts.rate,
            counts.points
        )
    }

    private func record(points: Int, made: Bool) {
        guard !gameFinished else { return }
        shots.append(.init(points: points, made: made))
        saveRecord(finished: false)
        made ? VibrationManager.shared.vibrateMedium() : VibrationManager.shared.vibrateLight()
    }

    private func finishTraining() {
        guard !gameFinished, !shots.isEmpty else { return }
        gameFinished = true
        showSummary = true
        saveRecord(finished: true)
        VibrationManager.shared.vibrateMedium()
    }

    private func restart() {
        saveRecord(finished: true)
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.basketballTraining.canonicalScoreboardIdentifier)
        gameStartTime = Date()
        shots.removeAll()
        gameFinished = false
        showSummary = false
        finalizedRecordID = nil
    }

    private func exitTraining() {
        saveRecord(finished: gameFinished)
        performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
    }

    private func saveRecord(finished: Bool) {
        guard !shots.isEmpty else { return }
        let end = Date()
        let currentCounts = counts
        let isFinished = finished || gameFinished
        if isFinished, finalizedRecordID == recordID { return }
        let snapshot = ShotTrainingResumeState(mode: mode, shots: shots, finished: isFinished)
        guard let snapshotData = try? JSONEncoder().encode(snapshot) else { return }

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
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save shot training \(recordID)")
        }
    }
}
