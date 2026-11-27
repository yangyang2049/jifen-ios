import CoreFoundation
import Foundation

nonisolated enum WeekendMembershipSchedule {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static func isActive(at date: Date) -> Bool {
        switch calendar.component(.weekday, from: date) {
        case 6, 7, 1: return true
        default: return false
        }
    }

    static func canPresent(at date: Date, lastShownAt: Date?) -> Bool {
        guard isActive(at: date) else { return false }
        guard let lastShownAt else { return true }
        return date >= lastShownAt && !calendar.isDate(date, equalTo: lastShownAt, toGranularity: .weekOfYear)
    }

    static func isOfferingEnabled(_ metadata: [String: Any], at date: Date) -> Bool {
        guard let enabled = metadata["weekend_membership"] as? NSNumber,
              CFGetTypeID(enabled) == CFBooleanGetTypeID(), enabled.boolValue,
              isActive(at: date) else { return false }
        if metadata["starts_at"] == nil && metadata["ends_at"] == nil { return true }
        guard let start = timestamp(metadata["starts_at"]),
              let end = timestamp(metadata["ends_at"]) else { return false }
        return start <= date.timeIntervalSince1970 && date.timeIntervalSince1970 < end
    }

    static func matchesPaywall(
        hasPaywall: Bool,
        packageCount: Int,
        lifetimeProductID: String?,
        expectedProductID: String
    ) -> Bool {
        hasPaywall && packageCount == 1 && lifetimeProductID == expectedProductID
    }

    private static func timestamp(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}
