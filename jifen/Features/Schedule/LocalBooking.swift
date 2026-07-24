import Foundation

enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case completed
    case cancelled

    var id: String { rawValue }
}

enum BookingSportType: String, Codable, CaseIterable, Identifiable {
    case badminton
    case pingpong
    case basketball
    case tennis
    case football
    case volleyball
    case pickleball
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .badminton:
            return NSLocalizedString("game_badminton", value: "羽毛球", comment: "")
        case .pingpong:
            return NSLocalizedString("game_pingpong", value: "乒乓球", comment: "")
        case .basketball:
            return NSLocalizedString("game_basketball", value: "篮球", comment: "")
        case .tennis:
            return NSLocalizedString("game_tennis", value: "网球", comment: "")
        case .football:
            return NSLocalizedString("game_football", value: "足球", comment: "")
        case .volleyball:
            return NSLocalizedString("game_volleyball", value: "排球", comment: "")
        case .pickleball:
            return NSLocalizedString("game_pickleball", value: "匹克球", comment: "")
        case .other:
            return NSLocalizedString("schedule_sport_other", value: "其他", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .badminton: return "🏸"
        case .pingpong: return "🏓"
        case .basketball: return "🏀"
        case .tennis: return "🎾"
        case .football: return "⚽"
        case .volleyball: return "🏐"
        case .pickleball: return "🏓"
        case .other: return "📅"
        }
    }

    var gameType: GameType? {
        switch self {
        case .badminton: return .badminton
        case .pingpong: return .pingpong
        case .basketball: return .basketball
        case .tennis: return .tennis
        case .football: return .football
        case .volleyball: return .volleyball
        case .pickleball: return .pickleball
        case .other: return nil
        }
    }
}

struct LocalBooking: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var sportType: BookingSportType
    var dateTime: Date
    var durationMinutes: Int
    var location: String
    var matchFormat: String
    var notes: String
    var reminderMinutes: [Int]
    var status: BookingStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        sportType: BookingSportType,
        dateTime: Date,
        durationMinutes: Int,
        location: String,
        matchFormat: String = "",
        notes: String = "",
        reminderMinutes: [Int] = [],
        status: BookingStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sportType = sportType
        self.dateTime = dateTime
        self.durationMinutes = durationMinutes
        self.location = location
        self.matchFormat = matchFormat
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
