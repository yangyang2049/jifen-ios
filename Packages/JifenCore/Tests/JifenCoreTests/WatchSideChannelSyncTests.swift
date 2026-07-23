import Foundation
import LinkCore
import Testing

@Test func legacyWatchRecordPayloadStillDecodes() throws {
    let json = """
    {
      "id": "legacy-watch-record",
      "gameType": "nineBall",
      "startTimeEpochMilliseconds": 1000,
      "endTimeEpochMilliseconds": 2000,
      "durationSeconds": 1,
      "team1Name": "A",
      "team2Name": "B",
      "team1FinalScore": 3,
      "team2FinalScore": 2,
      "team1SetScore": 3,
      "team2SetScore": 2,
      "actions": [],
      "totalScoreChanges": 5
    }
    """
    let payload = try JSONDecoder().decode(
        WatchRecordTransferPayload.self,
        from: Data(json.utf8)
    )
    #expect(payload.participants == nil)
    #expect(payload.projectConfiguration == nil)
    #expect(payload.team1Name == "A")
}

@Test func multiPlayerWatchRecordPayloadRoundTrips() throws {
    let payload = WatchRecordTransferPayload(
        id: "nine-ball-4",
        gameType: "nineBall",
        startTimeEpochMilliseconds: 1_000,
        endTimeEpochMilliseconds: 2_000,
        durationSeconds: 1,
        team1Name: "A",
        team2Name: "B",
        team1FinalScore: 9,
        team2FinalScore: 7,
        team1SetScore: 9,
        team2SetScore: 7,
        winner: "A",
        actions: [],
        totalScoreChanges: 22,
        participants: [
            .init(name: "A", score: 9),
            .init(name: "B", score: 7),
            .init(name: "C", score: 4),
            .init(name: "D", score: 2)
        ],
        projectConfiguration: ["playerCount": "4"]
    )
    let decoded = try JSONDecoder().decode(
        WatchRecordTransferPayload.self,
        from: JSONEncoder().encode(payload)
    )
    #expect(decoded.participants?.map(\.name) == ["A", "B", "C", "D"])
    #expect(decoded.projectConfiguration?["playerCount"] == "4")
}

@Test func commonNameUsagePayloadRoundTrips() throws {
    let payload = CommonNameUsagePayload(names: ["Alice", "Bob"])
    let decoded = try JSONDecoder().decode(
        CommonNameUsagePayload.self,
        from: JSONEncoder().encode(payload)
    )
    #expect(decoded == payload)
    #expect(decoded.nameType == "player")
}
