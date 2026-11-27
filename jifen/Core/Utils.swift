import Foundation

/// Numeric keyboards may emit Arabic, Persian, Indic or full-width digits.
/// Keep decimal digits only and normalize them before passing input to Int.
func normalizedDecimalDigits(_ rawValue: String, limit: Int) -> String {
    String(rawValue.lazy.compactMap { character -> Character? in
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.properties.generalCategory == .decimalNumber,
              let digit = character.wholeNumberValue,
              (0...9).contains(digit) else { return nil }
        return Character(String(digit))
    }.prefix(max(0, limit)))
}

// MARK: - Formatting Helpers

func formatScoreboardDuration(_ duration: TimeInterval, locale: Locale = .current) -> String {
    // Use the system's localized units, grammar and separators for every app
    // language. Record durations display whole seconds, as before.
    // A finite imported value can still overflow Duration's integer storage.
    let seconds = duration.isFinite
        ? min(max(0, duration.rounded(.down)), Double(Int64.max).nextDown)
        : 0
    return Duration.seconds(seconds).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)
            .locale(locale)
    )
}

func formatDuration(_ duration: TimeInterval) -> String {
    return formatScoreboardDuration(duration)
}

func formatDisplayDate(_ dateStr: String) -> String {
    guard let date = RecordDateFormatters.date(dateStr, format: "yyyy-MM-dd") else {
        return dateStr
    }
    
    let calendar = Calendar.current
    
    if calendar.isDateInToday(date) {
        return NSLocalizedString("today", comment: "Today")
    } else if calendar.isDateInYesterday(date) {
        return NSLocalizedString("yesterday", comment: "Yesterday")
    } else {
        return RecordDateFormatters.string(date, format: "MMMM d")
    }
}

/// Record dates are stored as timestamps and formatted only when they are
/// displayed, so a list rendered after a year or time-zone change shows the
/// current local date. Formatters are cached per format, locale and time zone;
/// the cache key keeps a system change from reusing a stale calendar.
enum RecordDateFormatters {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: DateFormatter] = [:]

    static func string(_ date: Date, format: String) -> String {
        formatter(format).string(from: date)
    }

    static func date(_ string: String, format: String) -> Date? {
        formatter(format).date(from: string)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let key = "\(format)|\(TimeZone.current.identifier)|\(Locale.current.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        if cache.count >= 32 { cache.removeAll() }
        cache[key] = formatter
        return formatter
    }
}
