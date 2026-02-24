//
//  TimerRecordDetailPage.swift
//  jifen
//
//  计时记录详情：展示单条计时记录（项目、时长、日期时间）。
//

import SwiftUI

struct TimerRecordDetailPage: View {
    let recordId: String
    @StateObject private var timerVM = TimerRecordsViewModel.shared

    private var record: GameRecordSummary? {
        timerVM.records.first { $0.id == recordId }
    }

    var body: some View {
        Group {
            if let r = record {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.md) {
                        gameInfoCard(r)
                        basicInfoCard(r)
                        actionsCard(r)
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.top, Theme.sm)
                    .padding(.bottom, Theme.lg)
                }
            } else {
                Text(NSLocalizedString("unknown", comment: "Unknown"))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.backgroundColor)
        .navigationTitle(record?.title ?? NSLocalizedString("tab_timer_record", value: "计时记录", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            timerVM.loadFromStorage()
        }
    }

    private func gameInfoCard(_ record: GameRecordSummary) -> some View {
        HStack(spacing: Theme.md) {
            Text(record.gameType.icon)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.system(size: Theme.fontH5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                if let dur = record.duration {
                    Text(formatDuration(dur))
                        .font(.system(size: Theme.fontBody1))
                        .foregroundColor(Theme.textSecondary)
                }
                if let winner = record.winner {
                    Text(String(format: NSLocalizedString("game_winner_format", value: "%@ 获胜", comment: ""), winner))
                        .font(.system(size: Theme.fontCaption, weight: .medium))
                        .foregroundColor(Theme.accentColor)
                }
            }
            Spacer()
        }
        .padding(Theme.padding)
        .background(Theme.homeCardDark)
        .cornerRadius(Theme.cornerRadius)
    }

    private func basicInfoCard(_ record: GameRecordSummary) -> some View {
        VStack(spacing: Theme.sm) {
            detailRow(label: NSLocalizedString("timer_record_time", value: "记录时间", comment: ""), value: "\(record.date) \(record.time)")
            if let duration = record.duration {
                detailRow(label: NSLocalizedString("record_duration", value: "持续时间", comment: ""), value: formatDuration(duration))
            }
        }
        .padding(Theme.padding)
        .background(Theme.homeCardDark)
        .cornerRadius(Theme.cornerRadius)
    }

    private func actionsCard(_ record: GameRecordSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(NSLocalizedString("match_record", value: "比赛记录", comment: ""))
                .font(.system(size: Theme.fontBody1, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            let actions = record.actions ?? []
            if actions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    EmptyStateCourtIcon(size: 36)
                    Text(NSLocalizedString("no_actions_recorded", value: "未记录任何操作", comment: ""))
                        .font(.system(size: Theme.fontBody2))
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.xs)
            } else {
                VStack(spacing: Theme.sm) {
                    ForEach(actions) { action in
                        actionRow(action)
                    }
                }
            }
        }
        .padding(Theme.padding)
        .background(Theme.homeCardDark)
        .cornerRadius(Theme.cornerRadius)
    }

    private func actionRow(_ action: TimerActionRecord) -> some View {
        HStack(spacing: Theme.sm) {
            Text(formatElapsed(action.elapsed))
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 56, alignment: .leading)

            Text(actionText(action))
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(highlightColor(action))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let left = action.leftRemaining, let right = action.rightRemaining {
                Text("\(formatClock(left)) - \(formatClock(right))")
                    .font(.system(size: Theme.fontCaption, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private func highlightColor(_ action: TimerActionRecord) -> Color {
        switch action.type {
        case .timeout, .gameEnd:
            return Theme.accentColor
        default:
            return Theme.textPrimary
        }
    }

    private func actionText(_ action: TimerActionRecord) -> String {
        switch action.type {
        case .start:
            return NSLocalizedString("timer_action_start", value: "开始计时", comment: "")
        case .pause:
            return NSLocalizedString("timer_action_pause", value: "暂停计时", comment: "")
        case .resume:
            return NSLocalizedString("timer_action_resume", value: "继续计时", comment: "")
        case .move:
            return String(format: NSLocalizedString("timer_action_move_format", value: "%@ 行棋", comment: ""), action.actor ?? NSLocalizedString("dual_timer_player", value: "玩家", comment: ""))
        case .timeout:
            return String(format: NSLocalizedString("timer_action_timeout_format", value: "%@ 超时", comment: ""), action.actor ?? NSLocalizedString("dual_timer_player", value: "玩家", comment: ""))
        case .manualStop:
            return NSLocalizedString("timer_action_manual_stop", value: "手动停止", comment: "")
        case .gameEnd:
            if let actor = action.actor, !actor.isEmpty {
                return String(format: NSLocalizedString("timer_action_game_end_winner_format", value: "比赛结束，%@ 获胜", comment: ""), actor)
            }
            return NSLocalizedString("timer_action_game_end", value: "比赛结束", comment: "")
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: Theme.fontCaption, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatClock(_ remaining: Int) -> String {
        let safe = max(0, remaining)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let seconds = safe % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        TimerRecordDetailPage(recordId: "dummy-id")
    }
}
