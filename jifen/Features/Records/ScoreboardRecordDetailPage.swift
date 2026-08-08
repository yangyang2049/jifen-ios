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
    @State private var didTrackRecordView = false
    @State private var selectedTrendTabID: String?
    @State private var selectedDetailSectionID: String?

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
        .onAppear(perform: loadRecord)
        .alert(NSLocalizedString("confirm_delete", comment: ""), isPresented: $showingDeleteConfirm) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", comment: ""), role: .destructive, action: deleteRecord)
        } message: { Text(NSLocalizedString("confirm_delete_record_message", comment: "")) }
        .alert(NSLocalizedString("record_unavailable", value: "无法继续", comment: ""), isPresented: Binding(get: { explanation != nil }, set: { if !$0 { explanation = nil } })) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {}
        } message: { Text(explanation ?? "") }
        .sheet(isPresented: $showingShareSheet, onDismiss: cleanupShareFile) {
            if let shareFileURL { AnalyticsActivityView(activityItems: [shareFileURL], contentType: "score_record") }
        }
        .sheet(isPresented: $showingSetup) {
            if let record { replaySetupSheet(record) }
        }
        .navigationDestination(item: $launchRequest) { request in
            ScoreboardLaunchView(
                gameType: request.gameType,
                setupResult: request.setup,
                automaticallyShowsUsageHint: false,
                analyticsEntryPoint: .recordReplay,
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
                if !record.displayParticipants.isEmpty { rankingCard(record) }
                switch presentation.detailLayout {
                case .standard:
                    if presentation.canShowTrend {
                        trendCard(record: record, tabs: presentation.trendTabs)
                    }
                    detailModePicker
                    recordSectionPicker(presentation.recap)
                    if mode == .recap {
                        recapCard(
                            record: record,
                            sections: visibleRecordSections(presentation.recap)
                        )
                    } else {
                        timelineCard(
                            record: record,
                            sections: visibleRecordSections(presentation.timelineSections)
                        )
                    }
                case .multiScoreTimeline:
                    multiScoreTimelineCard(
                        record: record,
                        rows: presentation.multiScoreTimelineRows
                    )
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
                Text(record.competitionDisplayName).font(.headline)
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
                if record.status == .finished {
                    Text(NSLocalizedString("finished", value: "已结束", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text(NSLocalizedString("record_unfinished", value: "未完成", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
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
            let score = record.primaryScore
            HStack(alignment: .center, spacing: 12) {
                scoreSide(
                    record.team1Name,
                    score: score.left,
                    isWinner: record.resolvedWinnerRecordTeam == .team1
                )
                Text(":").font(.title.bold()).foregroundStyle(Theme.textSecondary)
                scoreSide(
                    record.team2Name,
                    score: score.right,
                    isWinner: record.resolvedWinnerRecordTeam == .team2
                )
            }
            if let format = recordFormatDescription(record) {
                Text(format)
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
        HStack(spacing: 16) {
            Button { handleReplay(record, presentation: presentation) } label: {
                Label(
                    NSLocalizedString("play_again", value: "再来一场", comment: ""),
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: ScoreboardConstants.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            Button(action: prepareShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(
                        width: ScoreboardConstants.minimumTouchTarget + 8,
                        height: ScoreboardConstants.minimumTouchTarget + 8
                    )
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("share", comment: ""))
            Button(role: .destructive) { showingDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(
                        width: ScoreboardConstants.minimumTouchTarget + 8,
                        height: ScoreboardConstants.minimumTouchTarget + 8
                    )
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("delete", comment: ""))
        }
    }

    private func rankingCard(_ record: ScoreboardRecord) -> some View {
        let rankedParticipants = record.displayParticipants.enumerated().sorted {
            if $0.element.score != $1.element.score {
                return $0.element.score > $1.element.score
            }
            return $0.offset < $1.offset
        }
        return VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("record_final_ranking", value: "最终排名", comment: ""), systemImage: "list.number").font(.headline)
            ForEach(Array(rankedParticipants.enumerated()), id: \.element.offset) { rank, entry in
                let isWinner = record.resolvedWinnerIdentity == .participant(index: entry.offset)
                HStack {
                    Text("\(rank + 1)").font(.headline).frame(width: 28)
                    Text(entry.element.name)
                    if isWinner {
                        Image(systemName: "trophy.fill")
                            .accessibilityLabel(NSLocalizedString("winner", value: "赢家", comment: ""))
                    }
                    Spacer()
                    Text("\(entry.element.score)").font(.headline.monospacedDigit())
                }
                .foregroundStyle(isWinner ? Color.green : Theme.textPrimary)
                .padding(.vertical, 4)
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func trendCard(
        record: ScoreboardRecord,
        tabs: [ScoreboardRecordTrendTab]
    ) -> some View {
        let selectedTab = tabs.first { $0.id == selectedTrendTabID } ?? tabs.first
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(NSLocalizedString("score_trend", value: "比分趋势", comment: ""), systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                if tabs.count > 1, let selectedTab {
                    Picker(
                        "",
                        selection: Binding(
                            get: { selectedTab.id },
                            set: { selectedTrendTabID = $0 }
                        )
                    ) {
                        ForEach(tabs) { tab in
                            Text(tab.title).tag(tab.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("score_trend_tab_picker")
                }
            }
            if let selectedTab {
                ScoreTrendChart(
                    tab: selectedTab,
                    leftName: record.team1Name,
                    rightName: record.team2Name
                )
                .frame(height: 190)
                .accessibilityIdentifier("score_trend_chart_\(selectedTab.id)")
                .accessibilityValue("\(selectedTab.title), \(selectedTab.points.count)")
            }
        }
        .onAppear {
            if !tabs.contains(where: { $0.id == selectedTrendTabID }) {
                selectedTrendTabID = tabs.first?.id
            }
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

    @ViewBuilder
    private func recordSectionPicker(_ sections: [ScoreboardRecordRecapSection]) -> some View {
        if sections.count > 1 {
            if Theme.usesPadLayout {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112, maximum: 180), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    recordSectionButtons(sections)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        recordSectionButtons(sections)
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    @ViewBuilder
    private func recordSectionButtons(_ sections: [ScoreboardRecordRecapSection]) -> some View {
        recordSectionButton(
            title: NSLocalizedString("record_recap_full_match", value: "全场", comment: ""),
            sectionID: nil
        )
        ForEach(sections) { section in
            recordSectionButton(title: section.title, sectionID: section.id)
        }
    }

    private func recordSectionButton(title: String, sectionID: String?) -> some View {
        let selected = selectedDetailSectionID == sectionID
        return Button {
            selectedDetailSectionID = sectionID
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: Theme.usesPadLayout ? .infinity : nil)
                .padding(.horizontal, 14)
                .frame(minHeight: ScoreboardConstants.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : Theme.textPrimary)
        .background(selected ? Theme.accentColor : Theme.surface)
        .clipShape(Capsule())
        .accessibilityIdentifier(
            sectionID.map { "record_detail_section_\($0)" } ?? "record_detail_section_all"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func visibleRecordSections(
        _ sections: [ScoreboardRecordRecapSection]
    ) -> [ScoreboardRecordRecapSection] {
        guard let selectedDetailSectionID else { return sections }
        return sections.filter { $0.id == selectedDetailSectionID }
    }

    private func recapCard(
        record: ScoreboardRecord,
        sections: [ScoreboardRecordRecapSection]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if sections.isEmpty {
                unavailableDetail
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.headline)
                        if let result = section.result, !result.scores.isEmpty {
                            recapResultRow(result)
                        }
                        ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                            actionRow(action, index: index, record: record)
                        }
                        if section.actions.isEmpty && section.result == nil {
                            unavailableDetail
                        }
                    }
                    if section.id != sections.last?.id { Divider() }
                }
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recapResultRow(_ result: RecordSetResult) -> some View {
        HStack {
            Spacer()
            Text(result.scores.map(String.init).joined(separator: " : "))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.primary)
        }
        .padding(.vertical, 2)
    }

    private func timelineCard(
        record: ScoreboardRecord,
        sections: [ScoreboardRecordRecapSection]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if sections.isEmpty {
                unavailableDetail
            } else {
                ForEach(sections) { section in
                    if section.number != nil || sections.count > 1 {
                        Text(section.title)
                            .font(.headline)
                            .padding(.vertical, 6)
                    }
                    if section.actions.isEmpty {
                        unavailableDetail
                    } else {
                        ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                            actionRow(action, index: index, record: record)
                            if index != section.actions.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    if section.id != sections.last?.id { Divider() }
                }
            }
        }
        .padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func multiScoreTimelineCard(
        record: ScoreboardRecord,
        rows: [MultiScoreRecordDetailRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                Text(NSLocalizedString("multi_score_record_actions", value: "分数变化记录", comment: ""))
                    .accessibilityIdentifier("multi_score_record_actions")
            }
            .font(.headline)
            .padding(.bottom, 6)

            if rows.isEmpty {
                Text(NSLocalizedString(
                    "multi_score_record_no_actions",
                    value: "暂无分数变化记录",
                    comment: ""
                ))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityIdentifier("multi_score_record_no_actions")
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    multiScoreTimelineRow(row, index: index, record: record)
                    if index != rows.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func multiScoreTimelineRow(
        _ row: MultiScoreRecordDetailRow,
        index: Int,
        record: ScoreboardRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(relativeActionTime(
                epochMilliseconds: row.epochMilliseconds,
                index: index,
                start: record.startTime
            ))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 42, alignment: .leading)

            Text(multiScoreActionTitle(row.event))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func multiScoreActionTitle(_ event: MultiScoreRecordDetailEvent) -> String {
        switch event {
        case .scoreAdjustment(let participantName, let delta):
            guard let participantName, let delta else {
                return NSLocalizedString("record_score_changed", value: "比分变化", comment: "")
            }
            let signedDelta = delta > 0 ? "+\(delta)" : "\(delta)"
            return String(
                format: NSLocalizedString(
                    "multi_score_record_adjustment_format",
                    value: "%@ %@",
                    comment: ""
                ),
                participantName,
                signedDelta
            )
        case .matchStarted:
            return NSLocalizedString("game_started", comment: "")
        case .matchFinished:
            return NSLocalizedString("game_ended", comment: "")
        case .reset:
            return NSLocalizedString("reset", value: "重置", comment: "")
        case .undo:
            return NSLocalizedString("undo", value: "撤销", comment: "")
        case .stateChanged:
            return NSLocalizedString("record_state_changed", value: "状态变化", comment: "")
        }
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
        relativeActionTime(
            epochMilliseconds: action.epochMilliseconds,
            index: index,
            start: start
        )
    }

    private func relativeActionTime(
        epochMilliseconds: Int64?,
        index: Int,
        start: Date
    ) -> String {
        guard let milliseconds = epochMilliseconds else { return "#\(index + 1)" }
        let elapsed = max(0, Double(milliseconds) / 1_000 - start.timeIntervalSince1970)
        return String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    @ViewBuilder
    private func replaySetupSheet(_ record: ScoreboardRecord) -> some View {
        let setup = ScoreboardRecordConfiguration.setup(from: record)
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
                            initialSetup: setup,
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
        AppAnalytics.track(.scoreboardMenuAction, parameters: [
            .gameType: .string(record.gameType.analyticsIdentifier),
            .actionName: .string("play_again"),
            .entryPoint: .string(AnalyticsEntryPoint.recordReplay.rawValue)
        ])
        showingSetup = true
    }

    private func startReplay(_ setup: SportsSetupResult) {
        guard let record else { return }
        showingSetup = false
        DispatchQueue.main.async {
            launchRequest = LaunchRequest(
                gameType: record.gameType,
                setup: setup
            )
        }
    }

    private func recordFormatDescription(_ record: ScoreboardRecord) -> String? {
        switch record.gameType {
        case .tennis:
            return tennisFormatDescription(record)
        case .pingpong, .badminton:
            return rallyFormatDescription(record)
        case .pickleball:
            return pickleballFormatDescription(record)
        default:
            return nil
        }
    }

    /// 网球：赛制从大到小 = 三盘两胜/打满 · 每盘局数 · 抢七/抢十；tiebreak-only 仅显示抢七。
    private func tennisFormatDescription(_ record: ScoreboardRecord) -> String {
        let data = record.mergedProjectConfiguration
        let tieBreakPoints = record.tennisTieBreakPoints == 10 ? 10 : 7
        if record.isTennisTiebreakOnly {
            return NSLocalizedString(
                tieBreakPoints == 10 ? "tennis_scoring_mode_tiebreak_10" : "tennis_scoring_mode_tiebreak_7",
                comment: ""
            )
        }
        let games = intValue(data["gamesPerSet"]) == 4 ? 4 : 6
        let gamesLabel = NSLocalizedString(
            games == 4 ? "tennis_games_per_set_4" : "tennis_games_per_set_6",
            comment: ""
        )
        let tieBreakLabel = NSLocalizedString(
            tieBreakPoints == 10 ? "tennis_format_tiebreak_10" : "tennis_format_tiebreak_7",
            comment: ""
        )
        return "\(tennisSetsLabel(record)) · \(gamesLabel) · \(tieBreakLabel)"
    }

    private func tennisSetsLabel(_ record: ScoreboardRecord) -> String {
        let data = record.mergedProjectConfiguration
        let maxSets = intValue(data["maxSets"]) ?? 3
        if stringValue(data["matchCompletionMode"]) == "play_all" {
            return String(format: NSLocalizedString("record_format_sets_play_all_tennis", comment: ""), maxSets)
        }
        switch maxSets {
        case 1: return NSLocalizedString("tennis_set_option_best_of_1", comment: "")
        case 3: return NSLocalizedString("tennis_set_option_best_of_3", comment: "")
        case 5: return NSLocalizedString("tennis_set_option_best_of_5", comment: "")
        default: return "\(maxSets)"
        }
    }

    /// 乒乓球/羽毛球：赛制 = 三局两胜/打满 · 每局分数（从大到小）
    private func rallyFormatDescription(_ record: ScoreboardRecord) -> String? {
        let data = record.mergedProjectConfiguration
        let defaultMaxSets = record.gameType == .pingpong ? 5 : 3
        let maxSets = intValue(data["maxSets"]) ?? defaultMaxSets
        let defaultPoints = record.gameType == .pingpong ? 11 : 21
        let points = intValue(data["pointsPerSet"]) ?? defaultPoints
        let sets = genericSetsLabel(maxSets: maxSets, completionMode: stringValue(data["matchCompletionMode"]))
        let pointsLabel = String(
            format: NSLocalizedString("record_format_points_per_set", comment: ""),
            points
        )
        return "\(sets) · \(pointsLabel)"
    }

    /// 匹克球：赛制 = 三局两胜/打满 · 目标分（从大到小）
    private func pickleballFormatDescription(_ record: ScoreboardRecord) -> String? {
        let data = record.mergedProjectConfiguration
        let maxSets = intValue(data["maxSets"]) ?? 3
        let targetScore = intValue(data["targetScore"]) ?? 11
        let sets = genericSetsLabel(maxSets: maxSets, completionMode: stringValue(data["matchCompletionMode"]))
        let scoreLabel = String(
            format: NSLocalizedString("record_format_pickleball_score", comment: ""),
            targetScore
        )
        return "\(sets) · \(scoreLabel)"
    }

    private func genericSetsLabel(maxSets: Int, completionMode: String?) -> String {
        if completionMode == "play_all" {
            return String(format: NSLocalizedString("record_format_sets_play_all", comment: ""), maxSets)
        }
        switch maxSets {
        case 1: return NSLocalizedString("pingpong_set_option_best_of_1", comment: "")
        case 3: return NSLocalizedString("pingpong_set_option_best_of_3", comment: "")
        case 5: return NSLocalizedString("pingpong_set_option_best_of_5", comment: "")
        case 7: return NSLocalizedString("pingpong_set_option_best_of_7", comment: "")
        default: return "\(maxSets)"
        }
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

    private func loadRecord() {
        selectedTrendTabID = nil
        selectedDetailSectionID = nil
        record = ScoreboardRecordManager.shared.getRecordById(recordId)
        guard let record, !didTrackRecordView else { return }
        didTrackRecordView = true
        let screen: AnalyticsScreen = record.gameType == .multiScoreboard ? .multiscoreRecordDetail : .sportsRecordDetail
        AppAnalytics.screenView(screen, source: .recordsTab)
        AppAnalytics.track(.recordView, parameters: [
            .recordType: .string(record.gameType == .multiScoreboard ? "multiscore" : "scoreboard"),
            .gameType: .string(record.gameType.analyticsIdentifier),
            .sourceSurface: .string(record.isSyncedFromWatch ? AnalyticsSourceSurface.watch.rawValue : AnalyticsSourceSurface.phone.rawValue)
        ])
    }

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
            AppAnalytics.track(.shareStart, parameters: [
                .contentType: .string("score_record"),
                .gameType: .string(record.gameType.analyticsIdentifier),
                .sourcePage: .string(record.gameType == .multiScoreboard ? AnalyticsScreen.multiscoreRecordDetail.rawValue : AnalyticsScreen.sportsRecordDetail.rawValue)
            ])
            showingShareSheet = true
        } catch {
            AppAnalytics.track(.shareResult, parameters: [
                .contentType: .string("score_record"),
                .result: .string(AnalyticsResult.failed.rawValue)
            ])
            explanation = error.localizedDescription
        }
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
    let tab: ScoreboardRecordTrendTab
    let leftName: String
    let rightName: String

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let points = tab.points
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
        let points = tab.points
        let xPositions = ScoreboardTrendChartGeometry.xPositions(
            pointCount: points.count,
            width: size.width
        )
        guard points.count >= 2, xPositions.count == points.count else { return }

        var path = Path()
        var plottedPoints: [CGPoint] = []
        for (index, point) in points.enumerated() {
            let score = max(0, min(point[keyPath: team], maxScore))
            let plotted = CGPoint(
                x: xPositions[index],
                y: size.height - size.height * CGFloat(score) / CGFloat(maxScore)
            )
            plottedPoints.append(plotted)
            if index == 0 {
                path.move(to: plotted)
            } else {
                path.addLine(to: plotted)
            }
        }
        context.stroke(path, with: .color(color), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        for point in plottedPoints {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                with: .color(color)
            )
        }
    }
}

private struct RecordDetailShareCardView: View {
    let record: ScoreboardRecord
    var body: some View {
        VStack(spacing: 24) {
            Text(record.gameType.icon).font(.system(size: 56))
            Text(record.competitionDisplayName).font(.largeTitle.bold())
            Text(record.displayMatchTitle).font(.title3).multilineTextAlignment(.center)
            let score = record.primaryScore
            Text("\(score.left) : \(score.right)").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
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
