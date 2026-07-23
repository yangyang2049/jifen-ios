import Foundation

enum GameType: String, Codable, CaseIterable {
    case pingpong
    case badminton
    case tennis
    case basketball
    case football
    case volleyball
    case pickleball
    case guandan
    case doudizhu
    case simpleScore
    case multiScoreboard
    case counter
    case stopwatch

    var displayName: String {
        switch self {
        case .pingpong: return "乒乓球"
        case .badminton: return "羽毛球"
        case .tennis: return "网球"
        case .basketball: return "篮球"
        case .football: return "足球"
        case .volleyball: return "排球"
        case .pickleball: return "匹克球"
        case .guandan: return "掼蛋"
        case .doudizhu: return "斗地主"
        case .simpleScore: return "简单计分"
        case .multiScoreboard: return "多人计分"
        case .counter: return "计数器"
        case .stopwatch: return "秒表"
        }
    }
}

enum NameType: String, Codable {
    case team = "TEAM"
    case player = "PLAYER"
}
