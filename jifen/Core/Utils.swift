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
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    guard let date = dateFormatter.date(from: dateStr) else {
        return dateStr
    }
    
    let calendar = Calendar.current
    
    if calendar.isDateInToday(date) {
        return NSLocalizedString("today", comment: "Today")
    } else if calendar.isDateInYesterday(date) {
        return NSLocalizedString("yesterday", comment: "Yesterday")
    } else {
        let monthDayFormatter = DateFormatter()
        monthDayFormatter.dateFormat = "MMMM d"
        return monthDayFormatter.string(from: date)
    }
}
