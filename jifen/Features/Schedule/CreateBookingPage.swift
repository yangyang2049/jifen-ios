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
    @State private var reminders: Set<Int> = [120]
    @State private var didLoadInitial: Bool = false

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

                    Stepper(
                        String(format: NSLocalizedString("schedule_duration_minutes", value: "时长 %d 分钟", comment: ""), durationMinutes),
                        value: $durationMinutes,
                        in: 30...360,
                        step: 15
                    )
                }

                Section(NSLocalizedString("schedule_location", value: "地点", comment: "")) {
                    TextField(NSLocalizedString("schedule_location_placeholder", value: "输入地点", comment: ""), text: $location)
                }

                Section(NSLocalizedString("schedule_reminders", value: "提醒", comment: "")) {
                    ForEach(reminderOptions, id: \.self) { minute in
                        Toggle(isOn: bindingForReminder(minute)) {
                            Text(reminderLabel(minute))
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
            .preferredColorScheme(.dark)
            .onAppear {
                applyInitialBookingIfNeeded()
            }
        }
    }

    private func bindingForReminder(_ minute: Int) -> Binding<Bool> {
        Binding(
            get: { reminders.contains(minute) },
            set: { isOn in
                if isOn {
                    reminders.insert(minute)
                } else {
                    reminders.remove(minute)
                }
            }
        )
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
            reminders = [120]
        }
        didLoadInitial = true
    }
}
