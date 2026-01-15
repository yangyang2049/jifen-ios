import Foundation

enum WatchGameType: String, Codable, CaseIterable {
    case pingpong
    case badminton
    case tennis

    var displayName: String {
        switch self {
        case .pingpong:
            return "乒乓球"
        case .badminton:
            return "羽毛球"
        case .tennis:
            return "网球"
        }
    }

    var icon: String {
        switch self {
        case .pingpong:
            return "🏓"
        case .badminton:
            return "🏸"
        case .tennis:
            return "🎾"
        }
    }
}
