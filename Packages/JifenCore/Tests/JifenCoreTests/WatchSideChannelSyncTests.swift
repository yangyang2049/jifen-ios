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

@Test func versionedCommonNamesSnapshotRoundTrips() throws {
    let snapshot = CommonNamesSyncSnapshot(
        teams: ["Red"],
        players: ["Alice"],
        updatedAtEpochMilliseconds: 123,
        revision: 9
    )
    let decoded = try JSONDecoder().decode(
        CommonNamesSyncSnapshot.self,
        from: JSONEncoder().encode(snapshot)
    )
    #expect(decoded == snapshot)
    #expect(decoded.schemaVersion == 2)
    #expect(decoded.revision == 9)
}

@Test func legacyCommonNamesSnapshotDecodesWithDefaults() throws {
    let json = #"{"teams":["Red"],"players":["Alice"],"updatedAtEpochMilliseconds":123}"#
    let decoded = try JSONDecoder().decode(CommonNamesSyncSnapshot.self, from: Data(json.utf8))
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.revision == 0)
    #expect(decoded.players == ["Alice"])
}

@Test func futureCommonNamesSnapshotIsRejected() {
    let value: [String: Any] = [
        "schemaVersion": CommonNamesSyncSnapshot.currentSchemaVersion + 1,
        "teams": [],
        "players": []
    ]
    #expect(CommonNamesSyncSnapshot.fromApplicationContextValue(value) == nil)
}

@Test func invalidOrCorruptedCommonNamesSnapshotsAreRejected() throws {
    let invalidVersion = """
    {
      "schemaVersion": 0,
      "teams": [],
      "players": [],
      "updatedAtEpochMilliseconds": 1,
      "revision": 0
    }
    """
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CommonNamesSyncSnapshot.self, from: Data(invalidVersion.utf8))
    }

    let missingPlayers: [String: Any] = [
        "schemaVersion": CommonNamesSyncSnapshot.currentSchemaVersion,
        "teams": ["Team A"],
        "updatedAt": 1,
        "revision": 1
    ]
    #expect(CommonNamesSyncSnapshot.fromApplicationContextValue(missingPlayers) == nil)

    let negativeRevision: [String: Any] = [
        "schemaVersion": CommonNamesSyncSnapshot.currentSchemaVersion,
        "teams": ["Team A"],
        "players": ["Player A"],
        "updatedAt": 1,
        "revision": -1
    ]
    #expect(CommonNamesSyncSnapshot.fromApplicationContextValue(negativeRevision) == nil)
}

@Test func commonNameMutationAcknowledgementRoundTrips() throws {
    let mutation = CommonNameMutation(
        kind: .rename,
        nameType: .player,
        originalName: "Alice",
        newName: "Alicia"
    )
    let acknowledgement = CommonNameMutationAcknowledgement(
        snapshot: .init(teams: [], players: ["Alicia"], revision: 3),
        results: [.init(mutationId: mutation.id, status: .applied)]
    )
    let decoded = try JSONDecoder().decode(
        CommonNameMutationAcknowledgement.self,
        from: JSONEncoder().encode(acknowledgement)
    )
    #expect(decoded == acknowledgement)
}

@Test func connectivityProbeEnvelopeRoundTripsWithoutMatchSession() throws {
    let probeID = UUID()
    let envelope = LinkEnvelope(
        sessionId: probeID,
        kind: .connectivityProbe,
        sender: .watch,
        senderSequence: 12,
        sessionRevision: 0,
        sentAtEpochMilliseconds: 123,
        payload: ConnectivityProbePayload(probeId: probeID)
    )
    let decoded = try JSONDecoder().decode(
        LinkEnvelope<ConnectivityProbePayload>.self,
        from: JSONEncoder().encode(envelope)
    )
    #expect(decoded.kind == .connectivityProbe)
    #expect(decoded.sessionId == probeID)
    #expect(decoded.payload.probeId == probeID)
}
