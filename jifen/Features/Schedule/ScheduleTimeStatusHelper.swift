import SwiftUI

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
