import SwiftUI

struct CreateBookingPage: View {
    @Environment(\.dismiss) private var dismiss

    var initialBooking: LocalBooking? = nil
    var onCreated: (() -> Void)? = nil

    @State private var sportType: BookingSportType = .badminton
    @State private var dateTime: Date = Date().addingTimeInterval(3600)
    @State private var durationMinutes: Int = 90
    @State private var location: String = ""
    @State private var notes: String = ""
    /// 默认与鸿蒙 CreateBookingPage.ets DEFAULT_REMINDER_MINUTES 一致：2 小时 + 15 分钟
    @State private var reminders: Set<Int> = [120, 15]
    @State private var didLoadInitial: Bool = false
    @State private var showReminderHelp = false

    private let reminderOptions = [120, 30, 15]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(NSLocalizedString("schedule_sport", value: "项目", comment: ""), selection: $sportType) {
                        ForEach(BookingSportType.allCases) { type in
                            Text("\(type.icon) \(type.displayName)").tag(type)
                        }
                    }

                    DatePicker(
                        NSLocalizedString("schedule_datetime", value: "时间", comment: ""),
                        selection: $dateTime,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .onChange(of: dateTime) { _, _ in
                        normalizeReminderSelection()
                    }

                    HStack {
                        Text(NSLocalizedString("schedule_duration", value: "时长", comment: ""))
                        Spacer()
                        HStack(spacing: Theme.sm) {
                            Button {
                                if durationMinutes > 30 {
                                    durationMinutes = max(30, durationMinutes - 15)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(durationMinutes > 30 ? Color.white : Color.gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .disabled(durationMinutes <= 30)

                            Text(String(format: NSLocalizedString("schedule_duration_short", value: "%d分钟", comment: ""), durationMinutes))
                                .font(.body)
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.center)

                            Button {
                                if durationMinutes < 360 {
                                    durationMinutes = min(360, durationMinutes + 15)
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(durationMinutes < 360 ? Color.white : Color.gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .disabled(durationMinutes >= 360)
                        }
                    }
                }

                Section(NSLocalizedString("schedule_location", value: "地点", comment: "")) {
                    TextField(NSLocalizedString("schedule_location_placeholder", value: "输入地点", comment: ""), text: $location)
                }

                Section {
                    HStack(spacing: 8) {
                        Text(NSLocalizedString("schedule_reminders", value: "提醒", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                        Button {
                            showReminderHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        ForEach(reminderOptions, id: \.self) { minute in
                            reminderChip(minute: minute)
                        }
                    }
                }

                Section(NSLocalizedString("schedule_notes", value: "备注", comment: "")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(
                initialBooking == nil
                ? NSLocalizedString("schedule_create_title", value: "预约新球局", comment: "")
                : NSLocalizedString("schedule_edit", value: "编辑", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        createBooking()
                    }
                    .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                applyInitialBookingIfNeeded()
            }
            .alert(NSLocalizedString("schedule_reminder_help_title", value: "提醒说明", comment: ""), isPresented: $showReminderHelp) {
                Button(NSLocalizedString("confirm", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("schedule_reminder_help_message", value: "这些提醒为本地通知，由设备在预约时间前触发。\n- 需开启系统通知权限\n- 若应用被卸载、通知被关闭或系统限制后台，提醒可能无法送达\n- 修改或取消预约时，相关提醒会同步更新或移除", comment: ""))
            }
        }
    }

    /// 与鸿蒙 isReminderOptionEnabled 一致：预约时间距现在超过该分钟数时可选
    private func isReminderOptionEnabled(_ minute: Int) -> Bool {
        dateTime.timeIntervalSinceNow > Double(minute * 60)
    }

    /// 与鸿蒙 syncReminderSelectionBySchedule / normalizeReminderSelection 一致：去掉已不可选的提醒
    private func normalizeReminderSelection() {
        let valid = reminders.filter { isReminderOptionEnabled($0) }
        if valid.count != reminders.count {
            reminders = Set(valid)
        }
    }

    @ViewBuilder
    private func reminderChip(minute: Int) -> some View {
        let enabled = isReminderOptionEnabled(minute)
        let selected = reminders.contains(minute)
        Button {
            guard enabled else { return }
            if selected {
                reminders.remove(minute)
            } else {
                reminders.insert(minute)
            }
        } label: {
            Text(reminderLabel(minute))
                .font(.system(size: Theme.fontBody2, weight: selected ? .medium : .regular))
                .foregroundColor(enabled ? (selected ? .white : Theme.textPrimary) : Theme.textSecondary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(enabled ? (selected ? Theme.primary.opacity(0.9) : Color.white.opacity(0.06)) : Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(enabled ? (selected ? Theme.primary : Color.white.opacity(0.12)) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .opacity(enabled ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func reminderLabel(_ minute: Int) -> String {
        if minute >= 60 {
            return String(format: NSLocalizedString("schedule_reminder_hours_before", value: "%d 小时前", comment: ""), minute / 60)
        }
        return String(format: NSLocalizedString("schedule_reminder_minutes_before", value: "%d 分钟前", comment: ""), minute)
    }

    private func createBooking() {
        let reminderValues = reminders.filter { $0 != 1440 }.sorted(by: >)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let booking = LocalBooking(
            id: initialBooking?.id ?? UUID().uuidString,
            sportType: sportType,
            dateTime: dateTime,
            durationMinutes: durationMinutes,
            location: trimmedLocation,
            matchFormat: "",
            notes: trimmedNotes,
            reminderMinutes: reminderValues,
            status: initialBooking?.status ?? .pending,
            createdAt: initialBooking?.createdAt ?? Date(),
            updatedAt: Date()
        )
        _ = LocalBookingManager.shared.upsertBooking(booking)
        onCreated?()
        dismiss()
    }

    private func applyInitialBookingIfNeeded() {
        guard !didLoadInitial, let booking = initialBooking else { return }
        sportType = booking.sportType
        dateTime = booking.dateTime
        durationMinutes = booking.durationMinutes
        location = booking.location
        notes = booking.notes
        reminders = Set(booking.reminderMinutes.filter { $0 != 1440 })
        if reminders.isEmpty {
            reminders = [120, 15]
        }
        normalizeReminderSelection()
        didLoadInitial = true
    }
}
