import Foundation

enum WatchScoreActionType: String, Codable {
    case gameStart
    case scoreAdd
    case setEnd
    case gameEnd
    case undo
    case stop
    case resume
}

struct WatchScoreAction: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let actionType: WatchScoreActionType
    let description: String
    var team1Score: Int?
    var team2Score: Int?
    var team1SetScore: Int?
    var team2SetScore: Int?

    init(actionType: WatchScoreActionType,
         description: String,
         team1Score: Int? = nil,
         team2Score: Int? = nil,
         team1SetScore: Int? = nil,
         team2SetScore: Int? = nil,
         timestamp: Date = Date()) {
        self.id = UUID().uuidString
        self.timestamp = timestamp
        self.actionType = actionType
        self.description = description
        self.team1Score = team1Score
        self.team2Score = team2Score
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
    }
}
