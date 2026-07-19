import SwiftUI

struct BookingDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let bookingId: String
    var onStartGame: ((GameType) -> Void)? = nil
    var onChanged: (() -> Void)? = nil

    @State private var booking: LocalBooking?
    @State private var showCancelConfirm = false
    @State private var showEditPage = false

    var body: some View {
        List {
            if let currentBooking = booking {
                Section {
                    infoRow(
                        title: NSLocalizedString("schedule_sport", value: "项目", comment: ""),
                        value: "\(currentBooking.sportType.icon) \(currentBooking.sportType.displayName)"
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
                }

                Section {
                    if currentBooking.status == .pending {
                        VStack(spacing: 12) {
                            Button {
                                if let gameType = currentBooking.sportType.gameType {
                                    _ = LocalBookingManager.shared.markCompleted(currentBooking.id)
                                    booking = LocalBookingManager.shared.getBooking(by: bookingId)
                                    onChanged?()
                                    onStartGame?(gameType)
                                }
                            } label: {
                                Text(NSLocalizedString("schedule_start_game", value: "一键开赛", comment: ""))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Theme.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(currentBooking.sportType.gameType == nil || onStartGame == nil)
                            .opacity((currentBooking.sportType.gameType == nil || onStartGame == nil) ? 0.45 : 1.0)

                            HStack(spacing: 10) {
                                Button {
                                    showEditPage = true
                                } label: {
                                    Text(NSLocalizedString("schedule_edit", value: "编辑", comment: ""))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(Theme.controlBackground)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showCancelConfirm = true
                                } label: {
                                    Text(NSLocalizedString("schedule_cancel_booking", value: "取消预约", comment: ""))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Color(uiColor: .systemRed))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(Color(uiColor: .systemRed).opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            } else {
                Section {
                    Text(NSLocalizedString("schedule_booking_not_found", value: "未找到该预约", comment: ""))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("schedule_detail_title", value: "球局详情", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $showEditPage) {
            if let booking {
                CreateBookingPage(initialBooking: booking) {
                    reload()
                    onChanged?()
                }
            }
        }
        .alert(
            NSLocalizedString("schedule_cancel_booking", value: "取消预约", comment: ""),
            isPresented: $showCancelConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("confirm", comment: ""), role: .destructive) {
                cancelBooking()
            }
        } message: {
            Text(NSLocalizedString("schedule_cancel_confirm_message", value: "确认取消这场预约吗？", comment: ""))
        }
    }

    private func reload() {
        booking = LocalBookingManager.shared.getBooking(by: bookingId)
    }

    private func cancelBooking() {
        _ = LocalBookingManager.shared.cancelBooking(bookingId)
        onChanged?()
        dismiss()
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func reminderText(_ reminders: [Int]) -> String {
        reminders
            .filter { $0 != 1440 }
            .sorted(by: >)
            .map { minute in
                if minute >= 60 {
                    return String(format: NSLocalizedString("schedule_reminder_hours_before", value: "%d 小时前", comment: ""), minute / 60)
                }
                return String(format: NSLocalizedString("schedule_reminder_minutes_before", value: "%d 分钟前", comment: ""), minute)
            }
            .joined(separator: " / ")
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.md) {
            Text(title)
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: Theme.md)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundColor(Theme.textPrimary)
        }
    }
}
