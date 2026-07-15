import Foundation
import ScoreCore

func doublesParticipants(_ setup: SportsSetupResult?) -> [SessionParticipant] {
    let setup = setup
    let defaults = ["红A", "红B", "蓝A", "蓝B"]
    let names = [
        setup?.team1Player1Name,
        setup?.team1Player2Name,
        setup?.team2Player1Name,
        setup?.team2Player2Name
    ].enumerated().map { index, name in
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaults[index] : value
    }
    return [
        .init(id: "left-top", name: names[0], role: "player"),
        .init(id: "left-bottom", name: names[1], role: "player"),
        .init(id: "right-top", name: names[2], role: "player"),
        .init(id: "right-bottom", name: names[3], role: "player")
    ]
}
