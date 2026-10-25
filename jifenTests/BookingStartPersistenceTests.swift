import XCTest
import SwiftUI
import UIKit
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
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("booking-identity-" + UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func identityStore() throws -> ParticipantIdentityStore {
        let store = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("identity.json"))
        try store.migrateLegacyIfNeeded(scoreIDs: [], timerIDs: [])
        return store
    }

    private struct StartCase {
        let sport: BookingSportType
        let billiardsFormat: BookingBilliardsFormat?
        let exactType: ScoreCore.GameType
    }

    func testScheduledTournamentPreservesVersionConfigurationAndFirstBreaker() async throws {
        let identity = try identityStore()
        let setup = SportsSetupResult(team1Name: "A", team2Name: "B", nineBallBreakerPlayer: 1,
            nineBallRuleFamily: "tournament", nineBallThirdFoul: 6, nineBallBreakRule: "alternate", nineBallTotalRacks: 5)
        let request = BookingStartRequest(bookingId: "nine-ball-v3", gameType: .nineBall, setup: setup)
        let result = await BookingStartPersistence.persist(request, identity: identity, currentSessionAccountID: { nil })
        let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(result)))
        defer { Task { await self.removeResumeSessions([id]) } }
        let envelope = try XCTUnwrap(try ResumeSessionRepository.loadEnvelope(sessionId: id))
        let bundle = try JSONDecoder().decode(ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>.self, from: envelope.payload)
        let state = bundle.currentSession.state
        XCTAssertEqual(state.ruleVersion, 3)
        XCTAssertTrue(state.isTournament)
        XCTAssertEqual(state.breakerPlayer, 1)
        XCTAssertEqual(state.config.thirdFoul, 6)
        XCTAssertEqual(state.config.breakRule, .alternate)
        XCTAssertEqual(state.config.totalRacks, 5)
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
        let identity = try identityStore()
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

                let persistenceResult = await BookingStartPersistence.persist(request, identity: identity, currentSessionAccountID: { nil })
                let persistedValue = try XCTUnwrap(persistenceResult)
                XCTAssertTrue(identity.canRead(recordKey: persistedValue))
                XCTAssertEqual(identity.libraryId(for: persistedValue), identity.ledger.libraryId)
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
        let identity = try identityStore()
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
                let persistenceResult = await BookingStartPersistence.persist(request, identity: identity, currentSessionAccountID: { nil })
                let persisted = try XCTUnwrap(persistenceResult)
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

    func testScheduledStartRegistersSelectionsBeforeResumeAndResumePreservesThem() async throws {
        let identity = try identityStore()
        var setup = SportsSetupResult(team1Name: "Alpha", team2Name: "Beta")
        let ownSelection = ParticipantSelection(name: "Alpha", personRef: identity.person)
        setup.participantSelections = ["side:0": ownSelection]
        let request = BookingStartRequest(bookingId: "bound-booking", gameType: .billiards, setup: setup)
        let result = await BookingStartPersistence.persist(request, identity: identity, currentSessionAccountID: { nil })
        let id = try XCTUnwrap(result), sessionID = try XCTUnwrap(UUID(uuidString: id))
        defer { Task { await self.removeResumeSessions([sessionID]) } }
        XCTAssertTrue(identity.canRead(recordKey: id))
        XCTAssertEqual(identity.selections(for: id), ["side:0": ownSelection])
        let restoredIdentity = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("identity.json"))
        XCTAssertTrue(restoredIdentity.canRead(recordKey: id))
        XCTAssertEqual(restoredIdentity.selections(for: id), ["side:0": ownSelection])

        let host = UIHostingController(rootView: Text("resume")
            .registerParticipantSetupOnAppear(recordID: id, selections: nil, identity: identity))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(identity.selections(for: id), ["side:0": ownSelection])
    }

    func testScheduledStartCommitRejectsChangedOwnerAndDoesNotOverwriteExistingResumeSelections() throws {
        let identity = try identityStore()
        try identity.beginAccount("account-A")
        let context = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { nil })
        let selection = ParticipantSelection(name: "Alpha", personRef: identity.person)
        var setup = SportsSetupResult(team1Name: "Alpha", team2Name: "Beta")
        setup.participantSelections = ["side:0": selection]
        let request = BookingStartRequest(bookingId: "owner-switch", gameType: .billiards, setup: setup)
        try identity.beginAccount("account-B")
        XCTAssertNil(BookingStartPersistence.finishPersistedStart("late-session", request: request,
            groupContext: nil, identity: identity, context: context))
        XCTAssertNil(identity.state.recordLibraries["late-session"])

        let current = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { nil })
        let original = ParticipantSelection(name: "Beta", personRef: identity.person)
        try identity.registerRecord("existing-resume", selections: ["side:1": original])
        let ownerOnlyRequest = BookingStartRequest(bookingId: "resume", gameType: .billiards,
            setup: SportsSetupResult(team1Name: "Alpha", team2Name: "Beta"))
        XCTAssertEqual(BookingStartPersistence.finishPersistedStart("existing-resume", request: ownerOnlyRequest,
            groupContext: nil, identity: identity, context: current), "existing-resume")
        XCTAssertEqual(identity.selections(for: "existing-resume"), ["side:1": original])
    }

    func testScheduledStartRemovesUnownedSnapshotAfterAccountSwitch() async throws {
        // Persist a real initial bundle to represent the disk write that has
        // just completed while the original caller was suspended.
        let fixtureIdentity = try identityStore()
        let request = BookingStartRequest(bookingId: "owner-switch-cleanup", gameType: .billiards,
            setup: SportsSetupResult(team1Name: "Private A", team2Name: "Opponent"))
        let saved = await BookingStartPersistence.persist(request, identity: fixtureIdentity,
            currentSessionAccountID: { nil })
        let recordID = try XCTUnwrap(saved)
        let sessionID = try XCTUnwrap(ManualResumeSessionStore.sessionID(for: recordID))
        defer { Task { await self.removeResumeSessions([sessionID]) } }
        XCTAssertNotNil(try ResumeSessionRepository.loadEnvelope(sessionId: sessionID))

        let identity = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("switching-identity.json"))
        try identity.beginAccount("account-A")
        let context = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { nil })
        try identity.beginAccount("account-B")
        let result = await BookingStartPersistence.completePersistedStart(recordID, request: request,
            groupContext: nil, identity: identity, context: context)

        XCTAssertNil(result)
        XCTAssertNil(identity.state.recordLibraries[recordID])
        XCTAssertNil(try ResumeSessionRepository.loadEnvelope(sessionId: sessionID),
                     "Home must not discover another account's uncommitted start as legacy history")
    }

    func testScheduledStartCommitRejectsSessionChangeBeforeIdentityWarmup() throws {
        let identity = try identityStore()
        try identity.beginAccount("account-A")
        var currentAccount: String? = "account-A"
        let context = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { currentAccount })
        let request = BookingStartRequest(bookingId: "session-switch", gameType: .billiards,
            setup: SportsSetupResult(team1Name: "Alpha", team2Name: "Beta"))
        currentAccount = "account-B"
        XCTAssertNil(BookingStartPersistence.finishPersistedStart("late-session", request: request,
            groupContext: nil, identity: identity, context: context))
        XCTAssertEqual(identity.state.activeAccountId, "account-A")
        XCTAssertNil(identity.state.recordLibraries["late-session"])
    }

    func testScheduledStartIdentityFailureDoesNotReportLaunchSuccess() throws {
        let identity = try identityStore(), context = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { nil })
        let path = directory.appendingPathComponent("identity.json")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let request = BookingStartRequest(bookingId: "write-failure", gameType: .billiards,
            setup: SportsSetupResult(team1Name: "Alpha", team2Name: "Beta"))
        XCTAssertNil(BookingStartPersistence.finishPersistedStart("not-launchable", request: request,
            groupContext: nil, identity: identity, context: context))
        XCTAssertNil(identity.state.recordLibraries["not-launchable"])
    }

    func testScheduledGroupStartRegistersOwnerWithoutPrivateSelfSelection() throws {
        let identity = try identityStore(), context = BookingStartPersistence.IdentityContext(identity: identity, currentSessionAccountID: { nil })
        var setup = SportsSetupResult(team1Name: "Alpha", team2Name: "Beta")
        setup.participantSelections = ["side:0": ParticipantSelection(name: "Alpha", personRef: identity.person)]
        let request = BookingStartRequest(bookingId: "group-booking", gameType: .badminton, setup: setup)
        let rules = GroupMatchRules(sport: .badminton, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 21,
            winByTwo: true, useRallyScoring: true, gamesPerSet: 6, tieBreakPoints: 7, setScoringMode: "regular", usesNoAdScoring: false)
        let group = GroupMatchContext(accountID: "group-account", groupID: "group", groupName: "Group", gameID: nil,
            clientSessionID: "client-session", format: .singles, rules: rules, participants: [])
        XCTAssertEqual(BookingStartPersistence.finishPersistedStart("group-session", request: request,
            groupContext: group, identity: identity, context: context), "group-session")
        XCTAssertTrue(identity.canRead(recordKey: "group-session"))
        XCTAssertTrue(identity.selections(for: "group-session").isEmpty)
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
