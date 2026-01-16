import Foundation

// MARK: - Formatting Helpers

func formatScoreboardDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m \(seconds)s"
    } else if minutes > 0 {
        return "\(minutes)m \(seconds)s"
    } else {
        return "\(seconds)s"
    }
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
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        let monthDayFormatter = DateFormatter()
        monthDayFormatter.dateFormat = "MMMM d"
        return monthDayFormatter.string(from: date)
    }
}
