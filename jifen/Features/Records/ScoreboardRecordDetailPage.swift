import RecordCore
import ScoreCore
import SwiftUI

struct ScoreboardRecordDetailPage: View {
    let recordId: String
    @Environment(\.dismiss) private var dismiss

    private enum DetailMode: String, CaseIterable {
        case recap
        case timeline
    }

    private struct LaunchRequest: Identifiable, Hashable {
        let id = UUID()
        let gameType: GameType
        let setup: SportsSetupResult?
        let draftRecordId: String?
    }

    @State private var record: ScoreboardRecord?
    @State private var mode: DetailMode = .recap
    @State private var showingDeleteConfirm = false
    @State private var showingSetup = false
    @State private var launchRequest: LaunchRequest?
    @State private var explanation: String?
    @State private var shareFileURL: URL?
    @State private var showingShareSheet = false
    @State private var isPreparingShare = false

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            if let record {
                recordContent(record)
            } else {
                ContentUnavailableView(
                    NSLocalizedString("record_not_found", value: "记录不存在", comment: ""),
                    systemImage: "doc.questionmark",
                    description: Text(NSLocalizedString("record_may_deleted", value: "记录可能已被删除", comment: ""))
                )
            }
            if isPreparingShare {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .overlay { ProgressView(NSLocalizedString("share_preparing", value: "正在生成分享图片…", comment: "")).tint(.white).foregroundStyle(.white) }
            }
        }
        .navigationTitle(NSLocalizedString("match_detail", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: prepareShare) { Label(NSLocalizedString("share", comment: ""), systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { showingDeleteConfirm = true } label: { Label(NSLocalizedString("delete", comment: ""), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(record == nil)
            }
        }
        .onAppear(perform: loadRecord)
        .alert(NSLocalizedString("confirm_delete", comment: ""), isPresented: $showingDeleteConfirm) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", comment: ""), role: .destructive, action: deleteRecord)
        } message: { Text(NSLocalizedString("confirm_delete_record_message", comment: "")) }
        .alert(NSLocalizedString("record_unavailable", value: "无法继续", comment: ""), isPresented: Binding(get: { explanation != nil }, set: { if !$0 { explanation = nil } })) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {}
        } message: { Text(explanation ?? "") }
        .sheet(isPresented: $showingShareSheet, onDismiss: cleanupShareFile) {
            if let shareFileURL { ShareActivityView(activityItems: [shareFileURL]) }
        }
        .sheet(isPresented: $showingSetup) {
            if let record { replaySetupSheet(record) }
        }
        .navigationDestination(item: $launchRequest) { request in
            ScoreboardLaunchView(
                gameType: request.gameType,
                setupResult: request.setup,
                initialRecordId: request.draftRecordId,
                onBack: { launchRequest = nil }
            )
            .toolbar(.hidden, for: .tabBar)
        }
    }

    private func recordContent(_ record: ScoreboardRecord) -> some View {
        let presentation = ScoreboardRecordPresentation(record: record)
        return ScrollView {
            VStack(spacing: 16) {
                overviewCard(record)
                primaryActions(record, presentation: presentation)
                if !record.displayParticipants.isEmpty { rankingCard(record.displayParticipants) }
                if presentation.canShowTrend { trendCard(record: record, points: presentation.trend) }
                detailModePicker
                if mode == .recap {
                    recapCard(record: record, presentation: presentation)
                } else {
                    timelineCard(record: record, actions: presentation.actions)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func overviewCard(_ record: ScoreboardRecord) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(record.gameType.icon).font(.title)
                Text(record.gameType.displayName).font(.headline)
                Spacer()
                if record.isSyncedFromWatch {
                    Label(
                        NSLocalizedString(
                            "record_detail_synced_from_watch_badge",
                            value: "手表记录已同步",
                            comment: ""
                        ),
                        systemImage: "applewatch"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                Text(record.status == .draft ? NSLocalizedString("unfinished", value: "未结束", comment: "") : NSLocalizedString("finished", value: "已结束", comment: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.status == .draft ? .orange : .green)
            }
            if record.isSyncedFromWatch {
                Text(NSLocalizedString(
                    "record_detail_synced_from_watch_hint",
                    value: "这条记录已从手表同步到手机",
                    comment: ""
                ))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 12) {
                scoreSide(record.team1Name, score: record.team1FinalScore, isWinner: record.winner == "left")
                Text(":").font(.title.bold()).foregroundStyle(Theme.textSecondary)
                scoreSide(record.team2Name, score: record.team2FinalScore, isWinner: record.winner == "right")
            }
            if let left = record.team1SetScore, let right = record.team2SetScore {
                Text(String(format: NSLocalizedString("record_set_score_format", value: "局分 %d : %d", comment: ""), left, right))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if record.gameType == .tennis {
                Text("\(NSLocalizedString("tennis_format_label", value: "赛制", comment: ""))：\(tennisFormatDescription(record))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Divider()
            HStack {
                Label(formattedDate(record.startTime), systemImage: "calendar")
                Spacer()
                if let duration = record.duration { Label(formatScoreboardDuration(duration), systemImage: "clock") }
            }
            .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scoreSide(_ name: String, score: Int, isWinner: Bool) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.subheadline).lineLimit(1)
            Text("\(score)").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(isWinner ? .green : Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func primaryActions(_ record: ScoreboardRecord, presentation: ScoreboardRecordPresentation) -> some View {
        HStack(spacing: 10) {
            Button { handleReplay(record, presentation: presentation) } label: {
                Label(
                    record.status == .draft ? NSLocalizedString("continue_game", value: "继续比赛", comment: "") : NSLocalizedString("play_again", value: "再来一局", comment: ""),
                    systemImage: record.status == .draft ? "play.fill" : "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button(action: prepareShare) { Label(NSLocalizedString("share", comment: ""), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            Button(role: .destructive) { showingDeleteConfirm = true } label: { Image(systemName: "trash").frame(width: 28) }
                .buttonStyle(.bordered)
        }
    }

    private func rankingCard(_ participants: [ScoreboardRecordParticipant]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("record_final_ranking", value: "最终排名", comment: ""), systemImage: "list.number").font(.headline)
            ForEach(Array(participants.sorted { $0.score > $1.score }.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text("\(index + 1)").font(.headline).frame(width: 28)
                    Text(item.name)
                    Spacer()
                    Text("\(item.score)").font(.headline.monospacedDigit())
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func trendCard(record: ScoreboardRecord, points: [ScoreboardRecordTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(NSLocalizedString("score_trend", value: "比分趋势", comment: ""), systemImage: "chart.xyaxis.line").font(.headline)
            ScoreTrendChart(points: points, leftName: record.team1Name, rightName: record.team2Name)
                .frame(height: 190)
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detailModePicker: some View {
        Picker("", selection: $mode) {
            Text(NSLocalizedString("record_recap", value: "复盘", comment: "")).tag(DetailMode.recap)
            Text(NSLocalizedString("record_details", value: "明细", comment: "")).tag(DetailMode.timeline)
        }
        .pickerStyle(.segmented)
    }

    private func recapCard(record: ScoreboardRecord, presentation: ScoreboardRecordPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if presentation.recap.isEmpty {
                unavailableDetail
            } else {
                ForEach(presentation.recap) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.headline)
                        ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                            actionRow(action, index: index, record: record)
                        }
                    }
                    if section.id != presentation.recap.last?.id { Divider() }
                }
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func timelineCard(record: ScoreboardRecord, actions: [DetailedScoreAction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if actions.isEmpty { unavailableDetail }
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                actionRow(action, index: index, record: record)
                if index != actions.count - 1 { Divider().padding(.leading, 48) }
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var unavailableDetail: some View {
        Text(NSLocalizedString("record_detail_legacy_unavailable", value: "旧记录缺少可靠的分局或时间信息，已降级显示比赛总览。", comment: ""))
            .font(.subheadline).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRow(_ action: DetailedScoreAction, index: Int, record: ScoreboardRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(actionTime(action, index: index, start: record.startTime))
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 42, alignment: .leading)
            Text(actionTitle(action, record: record)).font(.subheadline)
            Spacer()
            if action.scores.count >= 2 {
                Text("\(action.scores[0]) : \(action.scores[1])").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.primary)
            }
        }
        .padding(.vertical, 6)
    }

    private func actionTitle(_ action: DetailedScoreAction, record: ScoreboardRecord) -> String {
        let sideName: String? = {
            switch action.team { case .team1: return record.team1Name; case .team2: return record.team2Name; default: return nil }
        }()
        switch action.type {
        case .matchStarted: return NSLocalizedString("game_started", comment: "")
        case .matchFinished: return NSLocalizedString("game_ended", comment: "")
        case .scoreChanged:
            if let sideName, let delta = action.scoreChange { return "\(sideName) \(delta >= 0 ? "+" : "")\(delta)" }
            return NSLocalizedString("record_score_changed", value: "比分变化", comment: "")
        case .setFinished: return NSLocalizedString("record_set_finished", value: "本局结束", comment: "")
        case .roundFinished: return NSLocalizedString("record_round_finished", value: "本回合结束", comment: "")
        case .periodFinished: return NSLocalizedString("record_period_finished", value: "本节结束", comment: "")
        case .undo: return NSLocalizedString("undo", value: "撤销", comment: "")
        case .reset: return NSLocalizedString("reset", value: "重置", comment: "")
        case .sideChanged: return NSLocalizedString("change_sides", value: "换边", comment: "")
        case .serveChanged: return NSLocalizedString("record_serve_changed", value: "交换发球", comment: "")
        case .foul: return NSLocalizedString("foul", value: "犯规", comment: "")
        case .timeout: return NSLocalizedString("timeout", value: "暂停", comment: "")
        case .stateChanged: return NSLocalizedString("record_state_changed", value: "状态变化", comment: "")
        }
    }

    private func actionTime(_ action: DetailedScoreAction, index: Int, start: Date) -> String {
        guard let milliseconds = action.epochMilliseconds else { return "#\(index + 1)" }
        let elapsed = max(0, Double(milliseconds) / 1_000 - start.timeIntervalSince1970)
        return String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    @ViewBuilder
    private func replaySetupSheet(_ record: ScoreboardRecord) -> some View {
        let setup = setupResult(from: record)
        NavigationStack {
            GeometryReader { proxy in
                let maxDialogHeight = max(280, proxy.size.height - 32)

                Group {
                    if record.gameType == .nineBall {
                        NineBallSetupDialogView(
                            initialSetup: setup,
                            maxDialogHeight: maxDialogHeight,
                            onConfirm: startReplay,
                            onCancel: { showingSetup = false }
                        )
                    } else if [.multiScoreboard, .doudizhu, .uno, .guandan, .shengji, .simpleScore].contains(record.gameType) {
                        MultiScoreSetupDialogView(
                            gameType: record.gameType,
                            defaultPlayerCount: setup.playerCount ?? 4,
                            initialPlayerNames: setup.playerNames ?? [],
                            defaultTeam1Name: setup.team1Name,
                            defaultTeam2Name: setup.team2Name,
                            initialTargetScore: setup.targetScore ?? 500,
                            titleEmoji: record.gameType.icon,
                            titleKey: localizationKey(for: record.gameType),
                            titleFallback: record.gameType.displayName,
                            maxDialogHeight: maxDialogHeight,
                            onConfirm: startReplay,
                            onCancel: { showingSetup = false }
                        )
                    } else {
                        SportsSetupDialogView(
                            gameType: record.gameType,
                            defaultTeam1Name: setup.team1Name,
                            defaultTeam2Name: setup.team2Name,
                            initialMaxSets: setup.maxSets,
                            initialPointsPerSet: setup.pointsPerSet,
                            initialTieBreakPoints: setup.tieBreakPoints,
                            initialSetup: setup,
                            maxDialogHeight: maxDialogHeight,
                            onConfirm: startReplay,
                            onCancel: { showingSetup = false }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .presentationDetents([.large])
    }

    private func handleReplay(_ record: ScoreboardRecord, presentation: ScoreboardRecordPresentation) {
        if record.status == .draft {
            guard record.stateSnapshot != nil else {
                explanation = NSLocalizedString("record_draft_cannot_restore", value: "这条旧草稿没有可恢复的状态快照。", comment: "")
                return
            }
            launchRequest = LaunchRequest(gameType: record.gameType, setup: nil, draftRecordId: record.id)
        } else {
            showingSetup = true
        }
    }

    private func startReplay(_ setup: SportsSetupResult) {
        guard let record else { return }
        showingSetup = false
        DispatchQueue.main.async {
            launchRequest = LaunchRequest(gameType: record.gameType, setup: setup, draftRecordId: nil)
        }
    }

    private func setupResult(from record: ScoreboardRecord) -> SportsSetupResult {
        let data = record.projectConfiguration ?? record.extraData ?? [:]
        var setup = SportsSetupResult(team1Name: record.team1Name, team2Name: record.team2Name)
        setup.maxSets = intValue(data["maxSets"])
        setup.pointsPerSet = intValue(data["pointsPerSet"] ?? data["targetScore"])
        setup.tieBreakPoints = intValue(data["tieBreakPoints"])
        setup.gamesPerSet = intValue(data["gamesPerSet"])
        setup.setScoringMode = stringValue(data["setScoringMode"])
        if let completion = stringValue(data["matchCompletionMode"]) {
            setup.matchCompletionMode = MatchCompletionMode(rawValue: completion)
        }
        setup.autoChangeSides = boolValue(data["autoChangeSides"])
        setup.isSingles = boolValue(data["isSingles"])
        setup.basketballMode = stringValue(data["basketballMode"])
        setup.basketballRuleSet = stringValue(data["basketballRuleSet"])
        setup.tennisDeuceMode = stringValue(data["tennisDeuceMode"])
        setup.servingSide = stringValue(data["servingSide"])
        setup.targetScore = intValue(data["targetScore"] ?? data["unoTargetScore"])
        setup.winByTwo = boolValue(data["winByTwo"])
        setup.scoreCap = intValue(data["scoreCap"])
        setup.useRallyScoring = boolValue(data["useRallyScoring"])
        setup.eightBallHandicapRacks = intValue(data["eightBallHandicapRacks"])
        setup.eightBallHandicapBeneficiary = stringValue(data["eightBallHandicapBeneficiary"])
        setup.playerNames = record.displayParticipants.map(\.name)
        setup.playerCount = setup.playerNames?.isEmpty == false ? setup.playerNames?.count : intValue(data["playerCount"])
        setup.nineBallBigGold = intValue(data["nineBallBigGold"])
        setup.nineBallSmallGold = intValue(data["nineBallSmallGold"])
        setup.nineBallGoldenNine = intValue(data["nineBallGoldenNine"])
        setup.nineBallNormalWin = intValue(data["nineBallNormalWin"])
        setup.nineBallBallInHand = intValue(data["nineBallBallInHand"])
        setup.nineBallFoul = intValue(data["nineBallFoul"])
        return setup
    }

    private func tennisFormatDescription(_ record: ScoreboardRecord) -> String {
        let data = record.projectConfiguration ?? record.extraData ?? [:]
        let tieBreakPoints = intValue(data["tieBreakPoints"]) == 10 ? 10 : 7
        if stringValue(data["setScoringMode"]) == "tiebreak_only" {
            return NSLocalizedString(
                tieBreakPoints == 10 ? "tennis_scoring_mode_tiebreak_10" : "tennis_scoring_mode_tiebreak_7",
                value: tieBreakPoints == 10 ? "一盘抢十" : "一盘抢七",
                comment: ""
            )
        }
        let games = intValue(data["gamesPerSet"]) == 4 ? 4 : 6
        let gamesLabel = NSLocalizedString(
            games == 4 ? "tennis_games_per_set_4" : "tennis_games_per_set_6",
            value: games == 4 ? "四局制" : "六局制",
            comment: ""
        )
        let tieBreakLabel = NSLocalizedString(
            tieBreakPoints == 10 ? "tennis_format_tiebreak_10" : "tennis_format_tiebreak_7",
            value: tieBreakPoints == 10 ? "盘内抢十" : "盘内抢七",
            comment: ""
        )
        return "\(NSLocalizedString("tennis_scoring_mode_regular", value: "传统赛制", comment: "")) · \(gamesLabel) · \(tieBreakLabel)"
    }

    private func intValue(_ value: AnyCodable?) -> Int? { (value?.value as? Int) ?? (value?.value as? Double).map(Int.init) ?? (value?.value as? String).flatMap(Int.init) }
    private func boolValue(_ value: AnyCodable?) -> Bool? { value?.value as? Bool }
    private func stringValue(_ value: AnyCodable?) -> String? { value?.value as? String }

    private func localizationKey(for gameType: GameType) -> String {
        switch gameType {
        case .doudizhu: return "game_doudizhu"
        case .uno: return "game_uno"
        case .guandan: return "game_guandan"
        case .shengji: return "game_shengji"
        case .simpleScore: return "game_simple_score"
        default: return "game_multi_scoreboard"
        }
    }

    private func loadRecord() { record = ScoreboardRecordManager.shared.getRecordById(recordId) }

    private func deleteRecord() {
        guard ScoreboardRecordManager.shared.deleteRecord(recordId) else { return }
        ScoreboardRecordsViewModel.shared.refreshRecords()
        dismiss()
    }

    private func prepareShare() {
        guard let record, !isPreparingShare else { return }
        isPreparingShare = true
        let renderer = ImageRenderer(content: RecordDetailShareCardView(record: record).frame(width: 600, height: 640))
        renderer.scale = UIScreen.main.scale
        guard let data = renderer.uiImage?.pngData() else { isPreparingShare = false; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share_record_\(record.id).png")
        do {
            try data.write(to: url, options: .atomic)
            shareFileURL = url
            showingShareSheet = true
        } catch { explanation = error.localizedDescription }
        isPreparingShare = false
    }

    private func cleanupShareFile() {
        if let shareFileURL { try? FileManager.default.removeItem(at: shareFileURL) }
        shareFileURL = nil
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ScoreTrendChart: View {
    let points: [ScoreboardRecordTrendPoint]
    let leftName: String
    let rightName: String

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let maxScore = max(1, points.flatMap { [$0.left, $0.right] }.max() ?? 1)
                draw(team: \.left, color: .red, maxScore: maxScore, context: &context, size: size)
                draw(team: \.right, color: .blue, maxScore: maxScore, context: &context, size: size)
            }
            HStack(spacing: 18) {
                Label(leftName, systemImage: "circle.fill").foregroundStyle(.red)
                Label(rightName, systemImage: "circle.fill").foregroundStyle(.blue)
            }.font(.caption)
        }
    }

    private func draw(team: KeyPath<ScoreboardRecordTrendPoint, Int>, color: Color, maxScore: Int, context: inout GraphicsContext, size: CGSize) {
        for segment in Set(points.map(\.segment)).sorted() {
            let values = points.filter { $0.segment == segment }
            guard values.count >= 2 else { continue }
            var path = Path()
            for (index, point) in values.enumerated() {
                let x = size.width * CGFloat(point.actionIndex) / CGFloat(max(1, (points.last?.actionIndex ?? 1)))
                let y = size.height - size.height * CGFloat(point[keyPath: team]) / CGFloat(maxScore)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color), lineWidth: 3)
        }
    }
}

private struct RecordDetailShareCardView: View {
    let record: ScoreboardRecord
    var body: some View {
        VStack(spacing: 24) {
            Text(record.gameType.icon).font(.system(size: 56))
            Text(record.gameType.displayName).font(.largeTitle.bold())
            Text(record.displayMatchTitle).font(.title3).multilineTextAlignment(.center)
            Text(record.displayScore()).font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
            if let duration = record.duration { Label(formatScoreboardDuration(duration), systemImage: "clock") }
            Spacer()
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "iScore").foregroundStyle(Theme.textSecondary)
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
        .foregroundStyle(Theme.textPrimary)
    }
}

private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
