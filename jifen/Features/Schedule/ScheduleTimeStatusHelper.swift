import SwiftUI

private let defaultBookingLeadTime: TimeInterval = 5.5 * 60 * 60
private let bookingDateChangeLeadTime: TimeInterval = 2 * 60 * 60

/// Android 3.1 parity: roughly six hours ahead, snapped to :00/:30, inside 09:00...20:00.
/// At or after 18:00 the default is 09:00 on the next day.
func defaultBookingDateTime(
    now: Date = Date(),
    calendar suppliedCalendar: Calendar = .current
) -> Date {
    var calendar = suppliedCalendar
    calendar.locale = suppliedCalendar.locale

    if calendar.component(.hour, from: now) >= 18 {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    let minimum = now.addingTimeInterval(defaultBookingLeadTime)
    let sixHourAnchor = calendar.date(byAdding: .hour, value: 6, to: now)
        ?? now.addingTimeInterval(6 * 60 * 60)
    var candidate = bookingDateSnappedToNearestHalfHour(sixHourAnchor, calendar: calendar)
    while candidate < minimum {
        candidate = calendar.date(byAdding: .minute, value: 30, to: candidate)
            ?? candidate.addingTimeInterval(30 * 60)
    }
    return clampDefaultBookingDate(candidate, minimum: minimum, calendar: calendar)
}

/// Keeps a user-selected day while reproducing Android's date-change reconciliation policy.
func reconciledBookingDateTime(
    _ selected: Date,
    now: Date = Date(),
    calendar suppliedCalendar: Calendar = .current
) -> Date {
    let calendar = suppliedCalendar
    if calendar.isDate(selected, inSameDayAs: now) {
        let minimum = bookingDateRoundedUpToHalfHour(
            now.addingTimeInterval(bookingDateChangeLeadTime),
            calendar: calendar
        )
        return max(bookingDateSnappedToNearestHalfHour(selected, calendar: calendar), minimum)
    }

    let minimum = now.addingTimeInterval(defaultBookingLeadTime)
    var candidate = bookingDateSnappedToNearestHalfHour(selected, calendar: calendar)
    while candidate < minimum {
        candidate = calendar.date(byAdding: .minute, value: 30, to: candidate)
            ?? candidate.addingTimeInterval(30 * 60)
    }
    return clampDefaultBookingDate(candidate, minimum: minimum, calendar: calendar)
}

func enabledBookingReminderOptions(
    for scheduledAt: Date,
    now: Date = Date(),
    options: [Int] = LocalBooking.reminderOptions
) -> Set<Int> {
    Set(options.filter { scheduledAt.timeIntervalSince(now) > Double($0 * 60) })
}

private func bookingDateSnappedToNearestHalfHour(_ date: Date, calendar: Calendar) -> Date {
    let minute = calendar.component(.minute, from: date)
    let base = calendar.date(bySetting: .second, value: 0, of: date) ?? date
    switch minute {
    case ..<15:
        return calendar.date(byAdding: .minute, value: -minute, to: base) ?? base
    case 15..<45:
        return calendar.date(byAdding: .minute, value: 30 - minute, to: base) ?? base
    default:
        return calendar.date(byAdding: .minute, value: 60 - minute, to: base) ?? base
    }
}

private func bookingDateRoundedUpToHalfHour(_ date: Date, calendar: Calendar) -> Date {
    let minute = calendar.component(.minute, from: date)
    let base = calendar.date(bySetting: .second, value: 0, of: date) ?? date
    if minute == 0 || minute == 30 { return base }
    let delta = minute < 30 ? 30 - minute : 60 - minute
    return calendar.date(byAdding: .minute, value: delta, to: base) ?? base
}

private func clampDefaultBookingDate(
    _ proposed: Date,
    minimum: Date,
    calendar: Calendar
) -> Date {
    var candidate = proposed
    for _ in 0..<400 {
        while candidate < minimum {
            candidate = calendar.date(byAdding: .minute, value: 30, to: candidate)
                ?? candidate.addingTimeInterval(30 * 60)
        }

        let hour = calendar.component(.hour, from: candidate)
        let minute = calendar.component(.minute, from: candidate)
        if hour >= 9, hour < 20 || (hour == 20 && minute == 0) {
            return candidate
        }

        if hour < 9 {
            candidate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: candidate) ?? candidate
        } else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            candidate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
    return candidate
}

enum ScheduleTimeStatus {
    case scheduled
    case startingSoon
    case ready
    case overdue
}

struct ScheduleTimeStatusStyle {
    let textColor: Color
    let backgroundColor: Color
    let borderColor: Color
}

func getScheduleTimeStatus(scheduledAt: Date, now: Date = Date()) -> ScheduleTimeStatus {
    let deltaMinutes = Int(floor(scheduledAt.timeIntervalSince(now) / 60))
    if deltaMinutes > 30 {
        return .scheduled
    }
    if deltaMinutes > 0 {
        return .startingSoon
    }
    if deltaMinutes >= -120 {
        return .ready
    }
    return .overdue
}

extension ScheduleTimeStatus {
    var localizedLabel: String {
        switch self {
        case .scheduled:
            return NSLocalizedString("schedule_time_status_scheduled", value: "待开始", comment: "")
        case .startingSoon:
            return NSLocalizedString("schedule_time_status_starting_soon", value: "即将开始", comment: "")
        case .ready:
            return NSLocalizedString("schedule_time_status_ready", value: "可开赛", comment: "")
        case .overdue:
            return NSLocalizedString("schedule_time_status_overdue", value: "已过时间", comment: "")
        }
    }

    var style: ScheduleTimeStatusStyle {
        switch self {
        case .scheduled:
            return ScheduleTimeStatusStyle(
                textColor: Theme.textSecondary,
                backgroundColor: Theme.controlBackground,
                borderColor: Theme.divider
            )
        case .startingSoon:
            return ScheduleTimeStatusStyle(
                textColor: Color(uiColor: .systemOrange),
                backgroundColor: Color(uiColor: .systemOrange).opacity(0.14),
                borderColor: Color(uiColor: .systemOrange).opacity(0.4)
            )
        case .ready:
            return ScheduleTimeStatusStyle(
                textColor: Color(uiColor: .systemGreen),
                backgroundColor: Color(uiColor: .systemGreen).opacity(0.14),
                borderColor: Color(uiColor: .systemGreen).opacity(0.4)
            )
        case .overdue:
            return ScheduleTimeStatusStyle(
                textColor: Color(uiColor: .systemRed),
                backgroundColor: Color(uiColor: .systemRed).opacity(0.14),
                borderColor: Color(uiColor: .systemRed).opacity(0.4)
            )
        }
    }
}
