import RecordCore
import SwiftUI

struct WatchRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recordID: String
    @State private var record: WatchScoreboardRecord? = nil
    @State private var loading = true
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loading {
                    ProgressView()
                        .tint(WatchTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let record = record {
                    titleHeader
                    gameInfoCard(record)
                    if let details = record.basketballTrainingDetails {
                        basketballDetailsCard(details)
                    }
                    if record.doublesTeamNames == nil,
                       let participants = record.participants,
                       participants.count > 2 {
                        participantsCard(participants)
                    }
                    actionsCard(record)
                    deleteButton
                } else {
                    VStack(spacing: 8) {
                        Text("❌")
                            .font(.system(size: 32))
                        Text(NSLocalizedString("record_not_found", comment: "Record not found"))
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .onAppear {
            loadRecord()
        }
        .alert(NSLocalizedString("confirm_deletion", comment: "Confirm Deletion"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("delete", comment: "Delete"), role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text(NSLocalizedString("cannot_be_recovered_after_deletion", comment: "Cannot be recovered after deletion"))
        }
        .navigationTitle(NSLocalizedString("match_details", comment: "Match Details"))
        .navigationBarTitleDisplayMode(.inline)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    private var titleHeader: some View {
        Text(NSLocalizedString("match_details", comment: "Match Details"))
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(WatchTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
    }

    private func gameInfoCard(_ record: WatchScoreboardRecord) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(record.gameType.icon)
                    .font(.system(size: 20))
                Text(record.gameType.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(WatchTheme.primaryText)
            }

            scoreRow(record)

            if let winner = record.winner {
                Text("\(winner)\(NSLocalizedString("wins_suffix", comment: " Wins suffix"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WatchTheme.accent)
            }

            VStack(spacing: 2) {
                infoRow(label: NSLocalizedString("date", comment: "Date"), value: formatDate(record.startTime))
                infoRow(label: NSLocalizedString("time", comment: "Time"), value: formatTime(record.startTime))
                infoRow(label: NSLocalizedString("duration", comment: "Duration"), value: watchFormatDuration(record.duration))
            }
        }
        .padding(WatchLayout.cardContentPadding)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    private func scoreRow(_ record: WatchScoreboardRecord) -> some View {
        let usePoints = record.gameType.usesPointScoreInList
        let leftScore = usePoints ? record.team1FinalScore : record.team1SetScore
        let rightScore = usePoints ? record.team2FinalScore : record.team2SetScore
        let teamNames = record.doublesTeamNames ?? (record.team1Name, record.team2Name)
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(teamNames.left)
                        .font(.system(size: 11))
                        .foregroundColor(WatchTheme.secondaryText)
                    Text("\(leftScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(record.winner == record.team1Name ? WatchTheme.accent : WatchTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("-")
                    .font(.system(size: 18))
                    .foregroundColor(WatchTheme.secondaryText)
                VStack(spacing: 2) {
                    Text(teamNames.right)
                        .font(.system(size: 11))
                        .foregroundColor(WatchTheme.secondaryText)
                    Text("\(rightScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(record.winner == record.team2Name ? WatchTheme.accent : WatchTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if record.gameType == .basketballTraining {
                Text("\(NSLocalizedString("watch_bb_hit_rate", comment: "Hit rate")): \(basketballHitRate(record))")
                    .font(.system(size: 11))
                    .foregroundColor(WatchTheme.accent)
            }
        }
    }

    private func basketballHitRate(_ record: WatchScoreboardRecord) -> String {
        let shots = record.basketballTrainingDetails?.shots.count ?? record.team1FinalScore
        let made = record.basketballTrainingDetails?.shots.lazy.filter(\.made).count ?? record.team2FinalScore
        if shots <= 0 { return "0%" }
        let pct = Int(round(Double(made) / Double(shots) * 100))
        return "\(made)/\(shots) = \(pct)%"
    }

    private func basketballDetailsCard(_ details: WatchBasketballTrainingDetails) -> some View {
        VStack(spacing: 7) {
            Text(NSLocalizedString("watch_training_breakdown", value: "投篮明细", comment: ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WatchTheme.primaryText)
            ForEach([1, 2, 3], id: \.self) { points in
                HStack {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
                            points
                        )
                    )
                    Spacer()
                    Text("\(NSLocalizedString("watch_training_miss", value: "未中", comment: "")) \(details.count(points: points, made: false))")
                    Text("\(NSLocalizedString("watch_training_made", value: "命中", comment: "")) \(details.count(points: points, made: true))")
                }
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.secondaryText)
            }
        }
        .padding(WatchLayout.cardContentPadding)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func participantsCard(_ participants: [WatchRecordParticipant]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(participants.enumerated()), id: \.offset) { _, participant in
                HStack {
                    Text(participant.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(participant.score)")
                        .fontWeight(.bold)
                }
                .font(.system(size: 12))
                .foregroundStyle(WatchTheme.primaryText)
            }
        }
        .padding(WatchLayout.cardContentPadding)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionsCard(_ record: WatchScoreboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("match_record", comment: "Match Record"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WatchTheme.primaryText)

            if record.actions.isEmpty {
                Text(NSLocalizedString(
                    "watch_record_actions_unavailable",
                    value: "此记录未保存动作详情",
                    comment: ""
                ))
                .font(.system(size: 11))
                .foregroundColor(WatchTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            ForEach(record.actions) { action in
                HStack(spacing: 8) {
                    Text(formatRelativeTimestamp(actionTime: action.timestamp, startTime: record.startTime))
                        .font(.system(size: 10))
                        .foregroundColor(WatchTheme.secondaryText)
                        .frame(width: 42, alignment: .leading)

                    Text(displayActionDescription(action, record: record))
                        .font(.system(size: 12))
                        .foregroundColor(isSpecialAction(action) ? WatchTheme.accent : WatchTheme.primaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let scoreText = actionScoreText(action) {
                        Text(scoreText)
                            .font(.system(size: 11))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(WatchLayout.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    /// Relative timestamp from match start (MM:SS or HH:MM:SS), aligned with HarmonyOS WatchRecordDetail formatRelativeTimestamp.
    private func formatRelativeTimestamp(actionTime: Date, startTime: Date) -> String {
        let relativeSeconds = max(0, Int(actionTime.timeIntervalSince(startTime)))
        let hours = relativeSeconds / 3600
        let minutes = (relativeSeconds % 3600) / 60
        let seconds = relativeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func isSpecialAction(_ action: WatchScoreAction) -> Bool {
        switch action.actionType {
        case .setEnd, .gameEnd: return true
        default: return false
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Text(NSLocalizedString("delete_record", comment: "Delete Record"))
                .font(.system(size: 14))
                .foregroundColor(WatchTheme.dangerRed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(WatchTheme.dangerRed, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .padding(.top, 8)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(WatchTheme.secondaryText)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(WatchTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func actionScoreText(_ action: WatchScoreAction) -> String? {
        if let setLeft = action.team1SetScore, let setRight = action.team2SetScore,
           action.actionType == .setEnd || action.actionType == .gameEnd {
            return "\(setLeft) - \(setRight)"
        }
        if let left = action.team1Score, let right = action.team2Score {
            return "\(left) - \(right)"
        }
        return nil
    }

    private func displayActionDescription(
        _ action: WatchScoreAction,
        record: WatchScoreboardRecord
    ) -> String {
        if record.gameType != .basketballTraining {
            return structuredActionDescription(action, record: record)
        }
        if action.description == "training_start" {
            return NSLocalizedString("watch_training_start", value: "训练开始", comment: "")
        }
        if action.description.hasPrefix("training_rate_"),
           let rate = Int(action.description.replacingOccurrences(of: "training_rate_", with: "")) {
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_training_rate_format", value: "命中率 %d%%", comment: ""),
                rate
            )
        }

        let values = action.description.split(separator: "_")
        guard values.count == 3,
              values[0] == "training",
              let points = Int(values[1].replacingOccurrences(of: "pt", with: "")) else {
            return action.description
        }
        let status = values[2] == "made"
            ? NSLocalizedString("watch_training_made", value: "命中", comment: "")
            : NSLocalizedString("watch_training_miss", value: "未中", comment: "")
        if record.basketballTrainingDetails?.mode != .free {
            return status
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_training_action_format", value: "%d分 · %@", comment: ""),
            points,
            status
        )
    }

    private func structuredActionDescription(
        _ action: WatchScoreAction,
        record: WatchScoreboardRecord
    ) -> String {
        let actor = actionActorName(action, record: record)
        let actorPrefix = actor.map { "\($0) " } ?? ""
        let delta = action.scoreChange ?? 0
        let code = action.operationCode ?? action.description
        switch code {
        case "game_start":
            return NSLocalizedString("watch_match_start", value: "比赛开始", comment: "")
        case "game_end":
            return NSLocalizedString("watch_match_finished", value: "比赛结束", comment: "")
        case "undo":
            return NSLocalizedString("menu_undo", value: "撤销", comment: "")
        case "point", "tennis_point", "basketball_score":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_score_format", value: "%@得分 +%d", comment: ""),
                actorPrefix, delta
            )
        case "side_out":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_side_out_format", value: "%@获得发球权", comment: ""),
                actor ?? ""
            )
        case "set_completed", "tennis_set_completed", "archery_set_completed":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_set_finished_format", value: "第 %d 局结束 · %@获胜", comment: ""),
                action.setNumber ?? 0, actor ?? ""
            )
        case "game_completed", "tiebreak_completed":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_game_finished_format", value: "第 %d 盘结束 · %@获胜", comment: ""),
                action.gameNumber ?? 0, actor ?? ""
            )
        case "exchange_sides":
            return NSLocalizedString("watch_action_exchange_sides", value: "交换场地", comment: "")
        case "side_change_reminder":
            return NSLocalizedString("watch_action_exchange_sides_reminder", value: "提示交换场地", comment: "")
        case "adjust_points", "adjust_sets", "edit_score", "basketball_adjust_score",
             "archery_adjust_arrow_sum", "archery_adjust_set_points", "eight_ball_admin_adjust",
             "nine_ball_adjust_total", "snooker_admin_correct":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_adjust_score_format", value: "%@调整比分", comment: ""),
                actorPrefix
            )
        case "archery_arrow":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_archery_arrow_format", value: "%@命中 %d 环", comment: ""),
                actorPrefix, delta
            )
        case "archery_miss":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_archery_miss_format", value: "%@脱靶", comment: ""),
                actorPrefix
            )
        case "archery_set_ready":
            return NSLocalizedString("watch_action_archery_set_ready", value: "本组射箭完成", comment: "")
        case "archery_closest_to_center":
            return NSLocalizedString("watch_action_archery_closest", value: "进入近心决胜", comment: "")
        case "archery_shooter_changed":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_shooter_format", value: "%@开始射箭", comment: ""),
                actor ?? ""
            )
        case "eight_ball_rack":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_rack_won_format", value: "%@赢得一局", comment: ""),
                actor ?? ""
            )
        case let value where value.hasPrefix("eight_ball_pot_"):
            let ball = value.replacingOccurrences(of: "eight_ball_pot_", with: "")
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_ball_potted_format", value: "%@打进 %@ 号球", comment: ""),
                actor ?? "", ball
            )
        case let value where value.hasPrefix("nine_ball_"):
            let event = nineBallActionName(String(value.dropFirst("nine_ball_".count)))
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_nine_ball_format", value: "%@ · %@ (%+d)", comment: ""),
                actor ?? "", event, delta
            )
        case "snooker_pot":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_snooker_pot_format", value: "%@进球 +%d", comment: ""),
                actorPrefix, delta
            )
        case "snooker_foul":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_snooker_foul_format", value: "%@犯规，对手 +%d", comment: ""),
                actorPrefix, delta
            )
        case "snooker_miss":
            return String.localizedStringWithFormat(NSLocalizedString("watch_action_snooker_miss_format", value: "%@未进", comment: ""), actorPrefix)
        case "snooker_handover", "snooker_turn_changed":
            return String.localizedStringWithFormat(NSLocalizedString("watch_action_snooker_handover_format", value: "交接给 %@", comment: ""), actor ?? "")
        case "snooker_frame_settled":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_snooker_frame_format", value: "第 %d 局结算 · %@获胜", comment: ""),
                action.roundNumber ?? 0, actor ?? ""
            )
        case "snooker_next_frame":
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_action_snooker_next_frame_format", value: "开始第 %d 局", comment: ""),
                action.roundNumber ?? 0
            )
        case "basketball_foul", "basketball_foul_adjust":
            return String.localizedStringWithFormat(NSLocalizedString("watch_action_basketball_foul_format", value: "%@犯规", comment: ""), actorPrefix)
        case "basketball_timeout", "basketball_timeout_adjust":
            return String.localizedStringWithFormat(NSLocalizedString("watch_action_basketball_timeout_format", value: "%@暂停", comment: ""), actorPrefix)
        case "basketball_period_changed":
            return String.localizedStringWithFormat(NSLocalizedString("watch_action_basketball_period_format", value: "进入第 %d 节", comment: ""), action.periodNumber ?? 0)
        case "basketball_overtime":
            return NSLocalizedString("watch_bball_overtime", value: "进入加时", comment: "")
        case "edit_name":
            return NSLocalizedString("watch_action_edit_name", value: "修改名称", comment: "")
        default:
            return action.description
        }
    }

    private func actionActorName(_ action: WatchScoreAction, record: WatchScoreboardRecord) -> String? {
        if let index = action.roundNumber.map({ $0 - 1 }),
           action.operationCode?.hasPrefix("nine_ball_") == true,
           let participants = action.participants,
           participants.indices.contains(index) {
            return participants[index].name
        }
        let names = record.doublesTeamNames ?? (record.team1Name, record.team2Name)
        switch action.team {
        case .team1: return names.left
        case .team2: return names.right
        case .team3:
            return action.participants?.indices.contains(2) == true ? action.participants?[2].name : nil
        case .team4:
            return action.participants?.indices.contains(3) == true ? action.participants?[3].name : nil
        case nil: return nil
        }
    }

    private func nineBallActionName(_ code: String) -> String {
        switch code {
        case "big_gold": NSLocalizedString("nine_ball_big_gold", value: "大金", comment: "")
        case "small_gold": NSLocalizedString("nine_ball_small_gold", value: "小金", comment: "")
        case "golden_nine": NSLocalizedString("nine_ball_golden_nine", value: "金九", comment: "")
        case "normal_win": NSLocalizedString("nine_ball_normal_win", value: "普通胜", comment: "")
        case "ball_in_hand": NSLocalizedString("nine_ball_ball_in_hand", value: "自由球", comment: "")
        case "foul": NSLocalizedString("nine_ball_foul", value: "犯规", comment: "")
        default: code
        }
    }

    private func loadRecord() {
        record = WatchRecordManager.shared.getRecord(id: recordID)
        loading = false
    }

    private func deleteRecord() {
        guard let record = record else { return }
        if WatchRecordManager.shared.deleteRecord(id: record.id) {
            self.record = nil
            dismiss()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM-dd"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
