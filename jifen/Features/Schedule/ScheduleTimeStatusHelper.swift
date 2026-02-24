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

    var darkStyle: ScheduleTimeStatusStyle {
        switch self {
        case .scheduled:
            return ScheduleTimeStatusStyle(
                textColor: .white,
                backgroundColor: Color.white.opacity(0.12),
                borderColor: Color.white.opacity(0.26)
            )
        case .startingSoon:
            return ScheduleTimeStatusStyle(
                textColor: Color(hex: "FFB74D"),
                backgroundColor: Color(hex: "FF9500").opacity(0.16),
                borderColor: Color(hex: "FF9500").opacity(0.42)
            )
        case .ready:
            return ScheduleTimeStatusStyle(
                textColor: Color(hex: "FF9F0A"),
                backgroundColor: Color(hex: "FF9F0A").opacity(0.18),
                borderColor: Color(hex: "FF9F0A").opacity(0.44)
            )
        case .overdue:
            return ScheduleTimeStatusStyle(
                textColor: Color(hex: "FF6B6B"),
                backgroundColor: Color(hex: "FF6B6B").opacity(0.16),
                borderColor: Color(hex: "FF6B6B").opacity(0.42)
            )
        }
    }
}
