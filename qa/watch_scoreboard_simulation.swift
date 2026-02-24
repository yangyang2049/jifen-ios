import Foundation

private enum SimError: Error {
    case failed(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SimError.failed(message)
    }
}

private func runWatchRuleSimulations() throws {
    let pingpong = WatchPingPongRules(maxSets: 3)
    try expect(pingpong.shouldEndSet(redScore: 11, blueScore: 9, redGames: 0, blueGames: 0, isTiebreak: false), "PingPong 11:9 should end set")
    try expect(!pingpong.shouldEndSet(redScore: 11, blueScore: 10, redGames: 0, blueGames: 0, isTiebreak: false), "PingPong 11:10 should not end set")
    try expect(pingpong.shouldEndSet(redScore: 22, blueScore: 20, redGames: 0, blueGames: 0, isTiebreak: false), "PingPong 22:20 should end set")

    let badminton = WatchBadmintonRules(maxSets: 3)
    try expect(badminton.shouldEndSet(redScore: 21, blueScore: 19, redGames: 0, blueGames: 0, isTiebreak: false), "Badminton 21:19 should end set")
    try expect(!badminton.shouldEndSet(redScore: 20, blueScore: 20, redGames: 0, blueGames: 0, isTiebreak: false), "Badminton 20:20 should not end set")
    try expect(badminton.shouldEndSet(redScore: 30, blueScore: 29, redGames: 0, blueGames: 0, isTiebreak: false), "Badminton 30:29 should end set (cap)")
    try expect(badminton.shouldEndSet(redScore: 29, blueScore: 30, redGames: 0, blueGames: 0, isTiebreak: false), "Badminton 29:30 should end set (cap)")

    let pickleball = WatchPickleballRules(maxSets: 5)
    try expect(pickleball.shouldEndSet(redScore: 11, blueScore: 8, redGames: 0, blueGames: 0, isTiebreak: false), "Pickleball 11:8 should end set")
    try expect(!pickleball.shouldEndSet(redScore: 11, blueScore: 10, redGames: 0, blueGames: 0, isTiebreak: false), "Pickleball 11:10 should not end set")

    let tennis = WatchTennisRules(maxSets: 3)
    try expect(tennis.shouldStartTiebreak(redGames: 6, blueGames: 6), "Tennis 6:6 should start tiebreak")
    try expect(!tennis.shouldEndGame(redScore: 4, blueScore: 3, redGames: 0, blueGames: 0, isTiebreak: false), "Tennis 4:3 should not end game")
    try expect(tennis.shouldEndGame(redScore: 5, blueScore: 3, redGames: 0, blueGames: 0, isTiebreak: false), "Tennis 5:3 should end game")
    try expect(!tennis.shouldEndGame(redScore: 7, blueScore: 6, redGames: 6, blueGames: 6, isTiebreak: true), "Tennis tiebreak 7:6 should not end")
    try expect(tennis.shouldEndGame(redScore: 8, blueScore: 6, redGames: 6, blueGames: 6, isTiebreak: true), "Tennis tiebreak 8:6 should end")

    var redScore = 5
    var blueScore = 5
    var redGames = 0
    var blueGames = 0
    var redSets = 0
    var blueSets = 0
    var isTiebreak = false
    tennis.onScoreChange(
        redScore: &redScore,
        blueScore: &blueScore,
        redGames: &redGames,
        blueGames: &blueGames,
        redSets: &redSets,
        blueSets: &blueSets,
        isTiebreak: &isTiebreak
    )
    try expect(redScore == 3 && blueScore == 3, "Tennis deuce normalization should reset 5:5 -> 3:3")

    let customPingpong = WatchPingPongRules(maxSets: 9)
    let customText = customPingpong.setOptionsText
    try expect(customText.contains("9"), "Generic set options text should include max sets number")
}

do {
    try runWatchRuleSimulations()
    print("[WatchSimulation] PASS: all scoreboard rule scenarios passed")
} catch {
    fputs("[WatchSimulation] FAIL: \(error)\n", stderr)
    exit(1)
}
