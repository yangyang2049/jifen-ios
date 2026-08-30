import XCTest
import PersistenceCore
import ScoreCore
import SessionCore
@testable import jifen

private final class BookingFootballClock: @unchecked Sendable, FootballClock {
    var monotonic: Int64
    var wall: Int64

    init(monotonic: Int64, wall: Int64) {
        self.monotonic = monotonic
        self.wall = wall
    }

    func monotonicSeconds() -> Int64 { monotonic }
    func wallClockMilliseconds() -> Int64 { wall }
}

@MainActor
final class BookingStartPersistenceTests: XCTestCase {
    private struct StartCase {
        let sport: BookingSportType
        let billiardsFormat: BookingBilliardsFormat?
        let exactType: ScoreCore.GameType
    }

    func testScheduledFootballUsesNormalRunningClockWithWallAnchor() {
        let clock = BookingFootballClock(monotonic: 42, wall: 1_700_000_000_000)
        let state = BookingStartPersistence.initialFootballTimerState(
            halfLengthSeconds: 30 * 60,
            clock: clock
        )

        XCTAssertEqual(state.stage, 1)
        XCTAssertEqual(state.halfLengthSeconds, 30 * 60)
        XCTAssertEqual(state.elapsedSeconds, 0)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.savedWallClockMilliseconds, 1_700_000_000_000)
    }

    func testAllTenBookingSportsAndFourBilliardsFormatsPersistRestorableExactState() async throws {
        let cases: [StartCase] = [
            .init(sport: .badminton, billiardsFormat: nil, exactType: .badminton),
            .init(sport: .pingpong, billiardsFormat: nil, exactType: .pingpong),
            .init(sport: .basketball, billiardsFormat: nil, exactType: .basketball),
            .init(sport: .tennis, billiardsFormat: nil, exactType: .tennis),
            .init(sport: .football, billiardsFormat: nil, exactType: .football),
            .init(sport: .volleyball, billiardsFormat: nil, exactType: .volleyball),
            .init(sport: .airVolleyball, billiardsFormat: nil, exactType: .airVolleyball),
            .init(sport: .beachVolleyball, billiardsFormat: nil, exactType: .beachVolleyball),
            .init(sport: .pickleball, billiardsFormat: nil, exactType: .pickleball),
            .init(sport: .billiards, billiardsFormat: .standard, exactType: .billiards),
            .init(sport: .billiards, billiardsFormat: .eightBall, exactType: .eightBall),
            .init(sport: .billiards, billiardsFormat: .nineBall, exactType: .nineBall),
            .init(sport: .billiards, billiardsFormat: .snooker, exactType: .snooker)
        ]
        XCTAssertEqual(Set(cases.map(\.sport)), Set(BookingSportType.creatableCases))
        XCTAssertEqual(cases.filter { $0.sport == .billiards }.count, 4)

        var persistedIDs: [UUID] = []
        do {
            for fixture in cases {
                let booking = LocalBooking(
                    id: "booking-\(fixture.exactType.rawValue)",
                    sportType: fixture.sport,
                    dateTime: Date(),
                    location: "Local court",
                    gameFormat: fixture.billiardsFormat?.rawValue,
                    team1Name: "Alpha",
                    team2Name: "Beta",
                    participantNames: ["Alpha", "Beta"]
                )
                let request = try XCTUnwrap(booking.makeStartRequest())
                XCTAssertEqual(request.gameType.scoreCoreGameType, fixture.exactType)

                let persistedValue = try XCTUnwrap(await BookingStartPersistence.persist(request))
                let sessionID = try XCTUnwrap(UUID(uuidString: persistedValue))
                persistedIDs.append(sessionID)
                let envelope = try XCTUnwrap(
                    try ResumeSessionRepository.loadEnvelope(sessionId: sessionID)
                )

                XCTAssertEqual(envelope.sessionId, sessionID)
                XCTAssertEqual(envelope.gameType, fixture.exactType)
                XCTAssertGreaterThanOrEqual(envelope.participants.count, 2)
                try assertInitialState(envelope)
            }
        } catch {
            await removeResumeSessions(persistedIDs)
            throw error
        }
        await removeResumeSessions(persistedIDs)
    }

    func testScheduledPickleballPreservesAndroid31SinglesAndDoublesNextSetServing() async throws {
        var persistedIDs: [UUID] = []
        do {
            for isSingles in [true, false] {
                var setup = SportsSetupResult(team1Name: "Alpha", team2Name: "Beta")
                setup.isSingles = isSingles
                setup.maxSets = 3
                setup.targetScore = 11
                if !isSingles {
                    setup.team1Player1Name = "A1"
                    setup.team1Player2Name = "A2"
                    setup.team2Player1Name = "B1"
                    setup.team2Player2Name = "B2"
                }
                let request = BookingStartRequest(
                    bookingId: "pickleball-\(isSingles ? "singles" : "doubles")",
                    gameType: .pickleball,
                    setup: setup
                )
                let persisted = try XCTUnwrap(await BookingStartPersistence.persist(request))
                let sessionID = try XCTUnwrap(UUID(uuidString: persisted))
                persistedIDs.append(sessionID)
                let payload = try XCTUnwrap(
                    try ResumeSessionRepository.loadPayload(
                        sessionId: sessionID,
                        expectedKind: .scoreSessionBundle
                    )
                )
                let bundle = try JSONDecoder().decode(
                    ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
                    from: payload
                )
                XCTAssertEqual(bundle.currentSession.gameType, isSingles ? .pickleball : .pickleballDoubles)
                XCTAssertEqual(
                    bundle.currentSession.state.rules.nextSetServerModel,
                    isSingles ? .opening : .alternateFromOpening
                )
                XCTAssertEqual(bundle.currentSession.state.rules.sportProfile, .pickleball)
            }
        } catch {
            await removeResumeSessions(persistedIDs)
            throw error
        }
        await removeResumeSessions(persistedIDs)
    }

    private func assertInitialState(_ envelope: ResumeSessionEnvelope) throws {
        let decoder = JSONDecoder()
        switch envelope.gameType {
        case .pingpong, .badminton, .volleyball, .airVolleyball,
             .beachVolleyball, .pickleball:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, envelope.gameType)
            XCTAssertEqual(bundle.currentSession.status, .live)
            XCTAssertEqual(bundle.currentSession.state.leftPoints, 0)
            XCTAssertEqual(bundle.currentSession.state.rightPoints, 0)
            XCTAssertFalse(bundle.currentSession.state.finished)

        case .tennis:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, .tennis)
            XCTAssertEqual(bundle.currentSession.state.leftPoints, 0)
            XCTAssertEqual(bundle.currentSession.state.rightPoints, 0)
            XCTAssertFalse(bundle.currentSession.state.finished)

        case .basketball:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, .basketball)
            XCTAssertEqual(bundle.currentSession.state.leftScore, 0)
            XCTAssertEqual(bundle.currentSession.state.rightScore, 0)
            XCTAssertFalse(bundle.currentSession.state.finished)

        case .football, .billiards:
            XCTAssertEqual(envelope.payloadKind, .manualState)
            let manual = try decoder.decode(ManualScoreboardResumeState.self, from: envelope.payload)
            XCTAssertEqual(manual.scoreCoreGameType, envelope.gameType)
            let snapshot = try XCTUnwrap(manual.stateSnapshot)
            if envelope.gameType == .football {
                let football = try decoder.decode(FootballResumeStateV2.self, from: snapshot)
                XCTAssertEqual(football.lineScore.state.leftScore, 0)
                XCTAssertEqual(football.lineScore.state.rightScore, 0)
                XCTAssertTrue(football.timer.isRunning)
                XCTAssertGreaterThan(football.timer.savedWallClockMilliseconds, 0)
            } else {
                let billiards = try decoder.decode(LineScoreResumeState.self, from: snapshot)
                XCTAssertEqual(billiards.state.leftScore, 0)
                XCTAssertEqual(billiards.state.rightScore, 0)
            }

        case .eightBall:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, .eightBall)
            XCTAssertEqual(bundle.currentSession.state.leftPoints, 0)
            XCTAssertEqual(bundle.currentSession.state.rightPoints, 0)
            XCTAssertFalse(bundle.currentSession.state.finished)

        case .nineBall:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, .nineBall)
            XCTAssertEqual(bundle.currentSession.state.playerPoints, [0, 0, 0, 0])
            XCTAssertFalse(bundle.currentSession.state.finished)

        case .snooker:
            XCTAssertEqual(envelope.payloadKind, .scoreSessionBundle)
            let bundle = try decoder.decode(
                ScoreSessionResumeBundle<SnookerState, SnookerEvent, SnookerIntent>.self,
                from: envelope.payload
            )
            XCTAssertEqual(bundle.currentSession.gameType, .snooker)
            XCTAssertEqual(bundle.currentSession.state.leftScore, 0)
            XCTAssertEqual(bundle.currentSession.state.rightScore, 0)
            XCTAssertFalse(bundle.currentSession.state.finished)

        default:
            XCTFail("Unexpected scheduled exact type: \(envelope.gameType.rawValue)")
        }
    }

    private func removeResumeSessions(_ ids: [UUID]) async {
        let repository = ResumeSessionRepository()
        for id in ids {
            try? await repository.remove(sessionId: id)
        }
    }
}
