import CoreImage.CIFilterBuiltins
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

    /// 「再来一场」Setup 请求：与首页/计分 Tab 一致，用居中 Setup Dialog 呈现。
    private struct ReplaySetupRequest: Identifiable {
        let id = UUID()
        let record: ScoreboardRecord
    }

    @State private var record: ScoreboardRecord?
    @State private var mode: DetailMode = .recap
    @State private var showingDeleteConfirm = false
    @State private var replaySetupRequest: ReplaySetupRequest?
    @State private var launchRequest: LaunchRequest?
    @State private var explanation: String?
    @State private var shareFileURL: URL?
    @State private var showingShareSheet = false
    @State private var isPreparingShare = false
    @State private var didTrackRecordView = false
    @State private var selectedTrendTabID: String?
    @State private var selectedDetailSectionID: String?
    @State private var noteSheetMode: RecordNoteSheetMode = .none
    @State private var recordNoteToast: String?
    @State private var showingScoreCorrection = false
    @State private var correctionTeam1Text = ""
    @State private var correctionTeam2Text = ""
    @State private var correctionSet1Text = ""
    @State private var correctionSet2Text = ""
    @State private var correctionError: String?

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
        .navigationTitle(record?.gameType.recordDetailTitle ?? GameType.defaultRecordDetailTitle)
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
        .sheet(isPresented: $showingScoreCorrection) {
            if let record { scoreCorrectionSheet(record) }
        }
        .overlay {
            // 与首页/计分 Tab 同款居中 Setup Dialog（CenteredSetupDialogPresenter），不再用 Bottom Sheet。
            CenteredSetupDialogPresenter(item: $replaySetupRequest) { request, dismiss, maxDialogHeight in
                replaySetupDialog(
                    for: request.record,
                    maxDialogHeight: maxDialogHeight,
                    onCancel: dismiss
                )
            }
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
                RecordNotesSectionView(
                    recordId: record.id,
                    note: record.note,
                    voiceNote: record.voiceNote,
                    sheetMode: $noteSheetMode,
                    onNotesChanged: { loadRecord() },
                    onToast: { recordNoteToast = $0 }
                )
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
        // 笔记 sheet 挂详情页顶层：没有笔记卡片时"笔记"按钮也要能弹出菜单。
        .sheet(isPresented: Binding(
            get: { noteSheetMode != .none },
            set: { if !$0 { noteSheetMode = .none } }
        )) {
            RecordNoteSheet(
                recordId: record.id,
                note: record.note,
                sheetMode: $noteSheetMode,
                onNotesChanged: { loadRecord() },
                onToast: { recordNoteToast = $0 }
            )
        }
        .overlay(alignment: .bottom) {
            if let recordNoteToast {
                Text(recordNoteToast)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        self.recordNoteToast = nil
                    }
            }
        }
    }

    private func overviewCard(_ record: ScoreboardRecord) -> some View {
        overviewContent(record, dateText: formattedDate(record.startTime))
            .padding(18)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 概览卡内容（与安卓 GameInfoCard 对齐），详情页与分享卡共用。
    private func overviewContent(_ record: ScoreboardRecord, dateText: String) -> some View {
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
            if let matchTitle = record.configuredMatchTitle {
                Text(matchTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("record_match_title")
            }
            if record.gameType == .doudizhu, record.displayParticipants.count >= 3 {
                let participants = Array(record.displayParticipants.prefix(4))
                HStack(alignment: .center, spacing: 8) {
                    ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                        if index > 0 {
                            Text("/").font(.title.bold()).foregroundStyle(Theme.textSecondary)
                        }
                        scoreSide(
                            participant.name,
                            score: participant.score,
                            isWinner: record.resolvedWinnerIdentity == .participant(index: index)
                        )
                    }
                }
            } else {
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
                if record.status == .finished && record.displayParticipants.isEmpty {
                    HStack {
                        Spacer()
                        Button { openScoreCorrection(record) } label: {
                            Label(
                                NSLocalizedString("record_score_correction", value: "纠错", comment: ""),
                                systemImage: "pencil.line"
                            )
                            .font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                }
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
    }

    private func scoreSide(_ name: String, score: Int, isWinner: Bool) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.subheadline).lineLimit(1)
            Text("\(score)").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(isWinner ? .green : Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func primaryActions(_ record: ScoreboardRecord, presentation: ScoreboardRecordPresentation) -> some View {
        HStack(spacing: 12) {
            Button { handleReplay(record, presentation: presentation) } label: {
                Label(
                    NSLocalizedString("play_again", value: "再来一场", comment: ""),
                    systemImage: "arrow.clockwise"
                )
                .font(.system(size: 17, weight: .semibold))
                .imageScale(.medium)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            Button { noteSheetMode = .menu } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("record_note_action", value: "笔记", comment: ""))
            Button(action: prepareShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("share", comment: ""))
            Button(role: .destructive) { showingDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("delete", comment: ""))
        }
    }

    private func openScoreCorrection(_ record: ScoreboardRecord) {
        correctionTeam1Text = "\(record.team1FinalScore)"
        correctionTeam2Text = "\(record.team2FinalScore)"
        correctionSet1Text = record.team1SetScore.map(String.init) ?? ""
        correctionSet2Text = record.team2SetScore.map(String.init) ?? ""
        correctionError = nil
        showingScoreCorrection = true
    }

    private var correctionTeam1Value: Int? { Int(correctionTeam1Text.trimmingCharacters(in: .whitespaces)) }
    private var correctionTeam2Value: Int? { Int(correctionTeam2Text.trimmingCharacters(in: .whitespaces)) }
    private var correctionSet1Value: Int? { Int(correctionSet1Text.trimmingCharacters(in: .whitespaces)) }
    private var correctionSet2Value: Int? { Int(correctionSet2Text.trimmingCharacters(in: .whitespaces)) }

    private func scoreCorrectionSheet(_ record: ScoreboardRecord) -> some View {
        NavigationStack {
            Form {
                if record.team1SetScore != nil || record.team2SetScore != nil {
                    Section(NSLocalizedString("record_correction_set_score", value: "局分 / 盘分", comment: "")) {
                        TextField(record.team1Name, text: $correctionSet1Text)
                            .keyboardType(.numberPad)
                        TextField(record.team2Name, text: $correctionSet2Text)
                            .keyboardType(.numberPad)
                    }
                }
                Section(NSLocalizedString("record_correction_final_score", value: "当局分 / 总分", comment: "")) {
                    TextField(record.team1Name, text: $correctionTeam1Text)
                        .keyboardType(.numberPad)
                    TextField(record.team2Name, text: $correctionTeam2Text)
                        .keyboardType(.numberPad)
                }
                Section {
                    Text(NSLocalizedString(
                        "record_correction_hint",
                        value: "保存后胜者将按新比分重算；原始比分保留在记录中，不影响回放。",
                        comment: ""
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let correctionError {
                    Text(correctionError).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle(NSLocalizedString("record_score_correction", value: "纠错", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) { showingScoreCorrection = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save", value: "保存", comment: "")) { submitScoreCorrection(record) }
                        .disabled(correctionTeam1Value == nil || correctionTeam2Value == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func submitScoreCorrection(_ record: ScoreboardRecord) {
        guard let team1 = correctionTeam1Value, let team2 = correctionTeam2Value else { return }
        let set1 = correctionSet1Value ?? record.team1SetScore
        let set2 = correctionSet2Value ?? record.team2SetScore
        if (set1 == nil) != (set2 == nil) {
            correctionError = NSLocalizedString(
                "record_correction_set_mismatch",
                value: "局分需要两侧同时填写",
                comment: ""
            )
            return
        }
        do {
            try ScoreboardRecordManager.shared.updateRecordFinalScores(
                id: record.id,
                team1FinalScore: team1,
                team2FinalScore: team2,
                team1SetScore: set1,
                team2SetScore: set2
            )
            showingScoreCorrection = false
            loadRecord()
        } catch {
            correctionError = error.localizedDescription
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
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.primary)
                        .frame(width: 3, height: 16)
                    Text(NSLocalizedString("score_trend", value: "比分趋势", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                }
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
                            recapResultRow(result, record: record)
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

    private func recapResultRow(_ result: RecordSetResult, record: ScoreboardRecord) -> some View {
        HStack {
            Spacer()
            Text(
                record.gameType == .doudizhu
                    ? DoudizhuRecordDetailPolicy.scoreLine(scores: result.scores)
                        ?? result.scores.map(String.init).joined(separator: " : ")
                    : result.scores.map(String.init).joined(separator: " : ")
            )
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
        let doudizhuDetails = DoudizhuRecordDetailPolicy.scoreDetails(for: action, record: record)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(actionTime(action, index: index, start: record.startTime))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 42, alignment: .leading)
                Text(actionTitle(action, record: record)).font(.subheadline)
                Spacer()
                if let scoreText = actionScoreText(action, record: record) {
                    Text(scoreText).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.primary)
                }
            }
            if !doudizhuDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(doudizhuDetails.enumerated()), id: \.offset) { _, detail in
                        HStack(spacing: 8) {
                            Text(doudizhuPlayerRoleText(detail))
                            Spacer()
                            if let change = detail.scoreChange {
                                Text(DoudizhuRecordDetailPolicy.signedScore(change))
                                    .font(.subheadline.bold().monospacedDigit())
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(detail.isWinner ? Color.green : Theme.textSecondary)
                    }
                }
                .padding(.leading, 52)
            }
        }
        .padding(.vertical, 6)
    }

    private func actionScoreText(_ action: DetailedScoreAction, record: ScoreboardRecord) -> String? {
        if record.gameType == .doudizhu {
            return DoudizhuRecordDetailPolicy.scoreLine(for: action)
        }
        guard action.scores.count >= 2 else { return nil }
        return "\(action.scores[0]) : \(action.scores[1])"
    }

    private func doudizhuPlayerRoleText(_ detail: DoudizhuRecordScoreDetail) -> String {
        let role: String?
        switch detail.role {
        case .landlord:
            role = NSLocalizedString("doudizhu_role_landlord", value: "地主", comment: "")
        case .farmer:
            role = NSLocalizedString("doudizhu_role_farmer", value: "农民", comment: "")
        case nil:
            role = nil
        }
        guard let role else { return detail.playerName }
        return String.localizedStringWithFormat(
            NSLocalizedString("doudizhu_player_role_format", value: "%@（%@）", comment: ""),
            detail.playerName,
            role
        )
    }

    private func actionTitle(_ action: DetailedScoreAction, record: ScoreboardRecord) -> String {
        if record.gameType == .doudizhu {
            let winnerNames = DoudizhuRecordDetailPolicy.winnerNames(for: action, record: record)
            if !winnerNames.isEmpty {
                let separator = NSLocalizedString("doudizhu_winner_separator", value: "、", comment: "")
                return String.localizedStringWithFormat(
                    NSLocalizedString("winner_named_format", value: "%@ 获胜", comment: ""),
                    winnerNames.joined(separator: separator)
                )
            }
        }
        let sideName: String? = {
            switch action.team { case .team1: return record.team1Name; case .team2: return record.team2Name; default: return nil }
        }()
        if let title = ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
            operationCode: action.operationCode,
            teamName: sideName
        ) {
            return title
        }
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
    private func replaySetupDialog(
        for record: ScoreboardRecord,
        maxDialogHeight: CGFloat,
        onCancel: @escaping () -> Void
    ) -> some View {
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        Group {
            if record.gameType == .basketballTraining {
                ShotTrainingSetupDialogView(
                    maxDialogHeight: maxDialogHeight,
                    initialMode: ShotTrainingMode(rawValue: setup.basketballTrainingScoringMode ?? "") ?? .fixed1,
                    onConfirm: startReplay,
                    onCancel: onCancel
                )
            } else if record.gameType == .nineBall {
                NineBallSetupDialogView(
                    initialSetup: setup,
                    maxDialogHeight: maxDialogHeight,
                    onConfirm: startReplay,
                    onCancel: onCancel
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
                    onCancel: onCancel
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
                    onCancel: onCancel
                )
            }
        }
    }

    private func handleReplay(_ record: ScoreboardRecord, presentation: ScoreboardRecordPresentation) {
        AppAnalytics.track(.scoreboardMenuAction, parameters: [
            .gameType: .string(record.gameType.analyticsIdentifier),
            .actionName: .string("play_again"),
            .entryPoint: .string(AnalyticsEntryPoint.recordReplay.rawValue)
        ])
        replaySetupRequest = ReplaySetupRequest(record: record)
    }

    private func startReplay(_ setup: SportsSetupResult) {
        guard let record else { return }
        replaySetupRequest = nil
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
        // 对齐安卓 shareScoreboardRecord：渲染 GameInfoCard（含品牌页脚）位图。
        let content = overviewContent(record, dateText: formattedDate(record.startTime))
        let renderer = ImageRenderer(
            content: RecordDetailShareCardView(content: content)
                .frame(width: 328)
                .fixedSize(horizontal: false, vertical: true)
        )
        renderer.scale = AppScreen.scale
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

    // Mirrors Android RecordTrendChart colors: home=red, away=blue.
    // 蓝色直接取 systemBlue（浅 #007AFF / 深 #0A84FF），与安卓双值一致，无需手写分支。
    private var trendRed: Color { Color(red: 1, green: 0x3B / 255, blue: 0x30 / 255) }
    private var trendBlue: Color { Color(uiColor: .systemBlue) }

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let points = tab.points
                let maxScore = max(1, points.flatMap { [$0.left, $0.right] }.max() ?? 1)
                draw(team: \.left, color: trendRed, maxScore: maxScore, context: &context, size: size)
                draw(team: \.right, color: trendBlue, maxScore: maxScore, context: &context, size: size)
            }
            HStack(spacing: 18) {
                Label(leftName, systemImage: "circle.fill").foregroundStyle(trendRed)
                Label(rightName, systemImage: "circle.fill").foregroundStyle(trendBlue)
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

        var previous: CGPoint?
        for (index, point) in points.enumerated() {
            let score = max(0, min(point[keyPath: team], maxScore))
            let plotted = CGPoint(
                x: xPositions[index],
                y: size.height - size.height * CGFloat(score) / CGFloat(maxScore)
            )
            if let previous {
                // 对齐安卓 drawSeries：逐段 drawLine + 圆头，保证直线段与斜线段粗细一致。
                var segment = Path()
                segment.move(to: previous)
                segment.addLine(to: plotted)
                context.stroke(segment, with: .color(color), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            previous = plotted
        }
    }
}

/// 分享卡 = 概览内容 + 虚线分隔 + 品牌页脚（应用图标 + 名称 + 下载二维码），1:1 对齐安卓。
private struct RecordDetailShareCardView<Content: View>: View {
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 18)
                .padding(.top, 18)
            dashedDivider
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            brandFooter
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(16)
        .background(Theme.backgroundColor)
    }

    private var dashedDivider: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(
                path,
                with: .color(Theme.divider),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }
        .frame(height: 1)
    }

    private var brandFooter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                appIcon
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(appDisplayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            qrImage
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(Color.white)
                .padding(4)
        }
        .frame(height: 60)
    }

    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? "iScore"
    }

    private var appIcon: Image {
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let image = UIImage(named: last) {
            return Image(uiImage: image)
        }
        if let image = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") {
            return Image(uiImage: image)
        }
        return Image(systemName: "square.grid.2x2")
    }

    private var qrImage: Image {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("https://jifenqi.com/download".utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
           let cgImage = CIContext().createCGImage(output, from: output.extent) {
            return Image(uiImage: UIImage(cgImage: cgImage))
        }
        return Image(systemName: "qrcode")
    }
}
