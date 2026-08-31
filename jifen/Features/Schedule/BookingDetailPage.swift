import SwiftUI

struct BookingDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let bookingId: String
    /// Preferred integration: return true only after the resumable initial
    /// state, booking completion, and reminder cancellation all succeeded.
    var onStartBooking: ((BookingStartRequest) async -> Bool)? = nil
    /// Legacy HomeTab bridge. It remains source-compatible but does not complete the booking early.
    var onStartGame: ((GameType) -> Void)? = nil
    var onChanged: (() -> Void)? = nil

    @State private var booking: LocalBooking?
    @State private var showCancelConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEditPage = false
    @State private var showCopyPage = false
    @State private var isStartingBooking = false

    var body: some View {
        List {
            if let currentBooking = booking {
                bookingInformation(currentBooking)
                bookingActions(currentBooking)
            } else {
                Section {
                    Text(NSLocalizedString("schedule_booking_not_found", value: "未找到该预约", comment: ""))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: Theme.focusedContentMaxWidth)
        .frame(maxWidth: .infinity)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("schedule_detail_title", value: "球局详情", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: reload)
        .analyticsScreen(.bookingDetailPage, source: .scheduleList)
        .sheet(isPresented: $showEditPage) {
            if let booking {
                CreateBookingPage(initialBooking: booking) {
                    reload()
                    onChanged?()
                }
            }
        }
        .sheet(isPresented: $showCopyPage) {
            if let booking {
                CreateBookingPage(copyingBooking: booking) {
                    onChanged?()
                    dismiss()
                }
            }
        }
        .alert(
            NSLocalizedString("schedule_cancel_booking", value: "取消预约", comment: ""),
            isPresented: $showCancelConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("confirm", comment: ""), role: .destructive) { cancelBooking() }
        } message: {
            Text(NSLocalizedString("schedule_cancel_confirm_message", value: "确认取消这场预约吗？", comment: ""))
        }
        .alert(
            NSLocalizedString("schedule_delete_booking", value: "删除预约", comment: ""),
            isPresented: $showDeleteConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("delete", comment: ""), role: .destructive) { deleteBooking() }
        } message: {
            Text(NSLocalizedString("schedule_delete_booking_message", value: "删除后无法恢复，确定继续吗？", comment: ""))
        }
    }

    private func bookingInformation(_ currentBooking: LocalBooking) -> some View {
        Section {
            infoRow(
                title: NSLocalizedString("schedule_sport", value: "项目", comment: ""),
                value: "\(currentBooking.sportType.icon) \(currentBooking.displayName)"
            )
            infoRow(
                title: NSLocalizedString("schedule_status", value: "状态", comment: ""),
                value: statusText(currentBooking.status)
            )
            infoRow(
                title: NSLocalizedString("schedule_datetime", value: "时间", comment: ""),
                value: formatDateTime(currentBooking.dateTime)
            )
            infoRow(
                title: NSLocalizedString("schedule_duration", value: "时长", comment: ""),
                value: String(format: NSLocalizedString("schedule_duration_minutes", value: "时长 %d 分钟", comment: ""), currentBooking.durationMinutes)
            )
            infoRow(
                title: NSLocalizedString("schedule_location", value: "地点", comment: ""),
                value: currentBooking.location
            )
            if !currentBooking.participantNames.isEmpty {
                infoRow(
                    title: NSLocalizedString("schedule_participants", value: "参与者", comment: ""),
                    value: currentBooking.participantNames.joined(separator: "、")
                )
            }
            if let preset = presetSummary(currentBooking) {
                infoRow(
                    title: NSLocalizedString("schedule_start_preset", value: "开局预设", comment: ""),
                    value: preset
                )
            }
            if !currentBooking.notes.isEmpty {
                infoRow(
                    title: NSLocalizedString("schedule_notes", value: "备注", comment: ""),
                    value: currentBooking.notes
                )
            }
            if !currentBooking.reminderMinutes.isEmpty {
                infoRow(
                    title: NSLocalizedString("schedule_reminders", value: "提醒", comment: ""),
                    value: reminderText(currentBooking.reminderMinutes)
                )
            }
            if let completedAt = currentBooking.completedAt {
                infoRow(
                    title: NSLocalizedString("schedule_completed_at", value: "完成时间", comment: ""),
                    value: formatDateTime(completedAt)
                )
            }
        }
    }

    @ViewBuilder
    private func bookingActions(_ currentBooking: LocalBooking) -> some View {
        Section {
            if currentBooking.status == .pending {
                VStack(spacing: 12) {
                    Button { startBooking(currentBooking) } label: {
                        Text(NSLocalizedString("schedule_start_game", value: "一键开赛", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart(currentBooking) || isStartingBooking)
                    .opacity(canStart(currentBooking) && !isStartingBooking ? 1 : 0.45)

                    HStack(spacing: 10) {
                        secondaryAction(
                            title: NSLocalizedString("schedule_edit", value: "编辑", comment: ""),
                            tint: Theme.textPrimary
                        ) {
                            AppAnalytics.track(.selectContent, parameters: [
                                .contentType: .string("booking"),
                                .actionName: .string("edit")
                            ])
                            showEditPage = true
                        }
                        secondaryAction(
                            title: NSLocalizedString("schedule_cancel_booking", value: "取消预约", comment: ""),
                            tint: Color(uiColor: .systemRed)
                        ) {
                            showCancelConfirm = true
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            } else if currentBooking.status == .cancelled || currentBooking.status == .noShow {
                HStack(spacing: 10) {
                    secondaryAction(
                        title: NSLocalizedString("schedule_copy_booking", value: "复制预约", comment: ""),
                        tint: Theme.primaryDark
                    ) {
                        showCopyPage = true
                    }
                    .disabled(currentBooking.sportType == .other)
                    .opacity(currentBooking.sportType == .other ? 0.45 : 1)

                    secondaryAction(
                        title: NSLocalizedString("delete", value: "删除", comment: ""),
                        tint: Color(uiColor: .systemRed)
                    ) {
                        showDeleteConfirm = true
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func secondaryAction(
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Theme.controlBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func canStart(_ booking: LocalBooking) -> Bool {
        booking.makeStartRequest() != nil && (onStartBooking != nil || onStartGame != nil)
    }

    private func startBooking(_ booking: LocalBooking) {
        guard let request = booking.makeStartRequest() else { return }
        AppAnalytics.track(.selectContent, parameters: [
            .contentType: .string("booking"),
            .actionName: .string("start_game"),
            .gameType: .string(request.gameType.analyticsIdentifier),
            .entryPoint: .string(AnalyticsEntryPoint.bookingDetail.rawValue)
        ])

        if let onStartBooking {
            guard !isStartingBooking else { return }
            isStartingBooking = true
            Task { @MainActor in
                let started = await onStartBooking(request)
                guard started else {
                    isStartingBooking = false
                    return
                }
                reload()
                onChanged?()
                isStartingBooking = false
            }
        } else {
            // HomeTab currently exposes only GameType. Keep that path working, but do not
            // mutate status before a future integration can acknowledge the full request.
            onStartGame?(request.gameType)
        }
    }

    private func reload() {
        booking = LocalBookingManager.shared.getBooking(by: bookingId)
    }

    private func cancelBooking() {
        let cancelled = LocalBookingManager.shared.cancelBooking(bookingId)
        AppAnalytics.track(.selectContent, parameters: [
            .contentType: .string("booking"),
            .actionName: .string("cancel"),
            .result: .string(cancelled ? AnalyticsResult.success.rawValue : AnalyticsResult.failed.rawValue)
        ])
        onChanged?()
        dismiss()
    }

    private func deleteBooking() {
        let deleted = LocalBookingManager.shared.deleteBooking(bookingId)
        guard deleted else { return }
        onChanged?()
        dismiss()
    }

    private func statusText(_ status: BookingStatus) -> String {
        switch status {
        case .pending:
            return NSLocalizedString("schedule_status_pending", value: "待进行", comment: "")
        case .completed:
            return NSLocalizedString("schedule_status_completed", value: "已完成", comment: "")
        case .cancelled:
            return NSLocalizedString("schedule_status_cancelled", value: "已取消", comment: "")
        case .noShow:
            return NSLocalizedString("schedule_status_no_show", value: "未到场", comment: "")
        }
    }

    private func presetSummary(_ booking: LocalBooking) -> String? {
        var parts: [String] = []
        if booking.sportType.supportsSinglesAndDoubles {
            parts.append(booking.matchMode == .doubles
                ? NSLocalizedString("doubles", value: "双打", comment: "")
                : NSLocalizedString("singles", value: "单打", comment: ""))
        }
        if booking.matchMode == .doubles {
            let left = [booking.redTopName, booking.redBottomName].compactMap { $0 }.joined(separator: "/")
            let right = [booking.blueTopName, booking.blueBottomName].compactMap { $0 }.joined(separator: "/")
            if !left.isEmpty || !right.isEmpty { parts.append("\(left) vs \(right)") }
        } else if let left = booking.team1Name, let right = booking.team2Name {
            parts.append("\(left) vs \(right)")
        }
        if let maxSets = booking.maxSets {
            parts.append(String(format: NSLocalizedString("schedule_sets_summary", value: "%d 局/盘", comment: ""), maxSets))
        }
        if let points = booking.pointsPerSet {
            parts.append(String(format: NSLocalizedString("schedule_points_summary", value: "每局 %d 分", comment: ""), points))
        }
        if let tieBreak = booking.tieBreakPoints {
            parts.append(String(format: NSLocalizedString("schedule_tiebreak_summary", value: "抢七 %d 分", comment: ""), tieBreak))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func reminderText(_ reminders: [Int]) -> String {
        reminders.sorted(by: >).map { minute in
            if minute >= 60 {
                return String(format: NSLocalizedString("schedule_reminder_hours_before", value: "%d 小时前", comment: ""), minute / 60)
            }
            return String(format: NSLocalizedString("schedule_reminder_minutes_before", value: "%d 分钟前", comment: ""), minute)
        }
        .joined(separator: " / ")
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.md) {
            Text(title).foregroundColor(Theme.textSecondary)
            Spacer(minLength: Theme.md)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundColor(Theme.textPrimary)
        }
    }
}
