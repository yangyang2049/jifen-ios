import Foundation
import LinkCore
import ScoreCore
import Testing

struct WatchSportRegistryTests {
    private let doublesNames = ["A1", "B1", "A2", "B2"]
    private let twoParticipants = ["A", "B"]

    @Test func exposesExactlyTheCurrentNineteenLinkedSports() throws {
        let expected: Set<GameType> = [
            .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles,
            .pickleball, .pickleballDoubles, .shuttlecock, .squash, .foosball, .foosballDoubles,
            .tennis, .tennisDoubles, .archeryDual, .eightBall, .nineBall, .snooker,
            .football, .football5v5, .basketballTraining,
        ]

        #expect(WatchSportRegistry.allLinkedGameTypes == expected)
        #expect(WatchSportRegistry.allLinkedGameTypes.count == 19)
        for gameType in GameType.allCases {
            #expect(WatchSportRegistry.supportsPhoneWatchLink(gameType) == expected.contains(gameType))
            if expected.contains(gameType) {
                let descriptor = try #require(WatchSportRegistry.descriptor(for: gameType))
                #expect(descriptor.gameType == gameType)
                #expect(descriptor.supportsPhoneWatchLink)
                #expect(descriptor.supportsWatchLocalSetup == (gameType != .foosballDoubles))
            } else {
                #expect(WatchSportRegistry.descriptor(for: gameType) == nil)
            }
        }
    }

    @Test func retainsCurrentLinkedAndLocalSetupDefaults() {
        let defaults: [GameType: Int] = [
            .pingpong: 5, .pingpongDoubles: 5, .badminton: 3, .badmintonDoubles: 3,
            .pickleball: 3, .pickleballDoubles: 3, .shuttlecock: 3, .squash: 5, .foosball: 3,
            .foosballDoubles: 3, .tennis: 3, .tennisDoubles: 3, .snooker: 1,
        ]
        let doubles: Set<GameType> = [
            .pingpongDoubles, .badmintonDoubles, .pickleballDoubles, .foosballDoubles, .tennisDoubles,
        ]
        let halfLengthDefaults: [GameType: Int] = [.football: 2_700, .football5v5: 1_200]

        for gameType in WatchSportRegistry.allLinkedGameTypes {
            let descriptor = WatchSportRegistry.descriptor(for: gameType)
            #expect(descriptor?.defaultMaxSets == defaults[gameType])
            #expect(descriptor?.isDoubles == doubles.contains(gameType))
            #expect(descriptor?.defaultFootballHalfLengthSeconds == halfLengthDefaults[gameType])
        }
    }

    @Test func phoneSetupPreservesShuttlecockFormatsAndNineBallPlayerCounts() {
        #expect(WatchSportRegistry.supportsPhoneWatchLink(.nineBall))
        for count in 1...5 {
            #expect(WatchSportRegistry.supportsPhoneWatchLink(.nineBall, playerCount: count) == (2...4).contains(count))
        }
        for format in CompetitionFormat.allCases {
            #expect(WatchSportRegistry.supportsPhoneWatchLink(.shuttlecock, competitionFormat: format) == (format != .team))
        }
        #expect(WatchSportRegistry.supportsPhoneWatchLink(.shuttlecock))
        #expect(WatchSportRegistry.supportsPhoneWatchLink(.basketballTraining, playerCount: 1))
        #expect(!WatchSportRegistry.supportsPhoneWatchLink(.basketball, playerCount: 2))
    }

    @Test func setupValidationUsesTheCorrectSnapshotFamilyForEverySport() {
        let cases: [(GameType, WatchSetupFamily, LinkedScoreboardSnapshot)] = [
            (.pingpong, .rally, rally(.pingPong())),
            (.pingpongDoubles, .rally, rally(.pingPong(), doubles: .pingPong(playerNames: doublesNames))),
            (.badminton, .rally, rally(.badminton())),
            (.badmintonDoubles, .rally, rally(.badminton(), doubles: .badminton(playerNames: doublesNames))),
            (.pickleball, .rally, rally(.pickleball())),
            (.pickleballDoubles, .rally, rally(.pickleball(), doubles: .pickleball(playerNames: doublesNames))),
            (.shuttlecock, .rally, rally(.shuttlecock())),
            (.squash, .rally, rally(.squash())),
            (.foosball, .rally, rally(.foosball())),
            (.foosballDoubles, .rally, rally(.foosball(), doubles: .foosball(playerNames: doublesNames))),
            (.tennis, .tennis, .tennis(.init(leftName: "A", rightName: "B"))),
            (.tennisDoubles, .tennis, .tennis(.init(leftName: "A", rightName: "B", doublesPlayerNames: doublesNames))),
            (.archeryDual, .archery, .archery(.init(leftName: "A", rightName: "B"))),
            (.eightBall, .eightBall, .eightBall(.initial())),
            (.nineBall, .nineBall, .nineBall(.initial(playerCount: 2))),
            (.snooker, .snooker, .snooker(.initial())),
            (.football, .football, .football(.init(leftName: "A", rightName: "B"))),
            (.football5v5, .football, .football(.init(leftName: "A", rightName: "B"))),
            (.basketballTraining, .basketballTraining, .basketballTraining(.init(mode: .free, startTime: Date(timeIntervalSince1970: 1)))),
        ]

        #expect(Set(cases.map(\.0)) == WatchSportRegistry.allLinkedGameTypes)
        for (gameType, family, snapshot) in cases {
            #expect(WatchSportRegistry.descriptor(for: gameType)?.setupFamily == family)
            #expect(snapshot.matches(gameType: gameType))
            #expect(valid(gameType, snapshot, participants: twoParticipants))
            #expect(!valid(gameType, nil))
            for (_, otherFamily, otherSnapshot) in cases where otherFamily != family {
                #expect(!otherSnapshot.matches(gameType: gameType))
                #expect(!valid(gameType, otherSnapshot, participants: twoParticipants))
            }
        }
        #expect(!valid(.volleyball, rally(.volleyball())))
        #expect(!valid(.softTennis, .tennis(.init(leftName: "A", rightName: "B"))))
    }

    @Test func doublesSetupUsesFourMembersAndAcceptsBothShuttlecockModes() {
        let singles = rally(.pingPong())
        var doubles = RallyDoublesState.pingPong(playerNames: doublesNames)
        let validDoubles = rally(.pingPong(), doubles: doubles)
        doubles.playerNames.removeLast()
        let incompleteDoubles = rally(.pingPong(), doubles: doubles)

        #expect(!valid(.pingpongDoubles, singles, participants: doublesNames))
        #expect(!valid(.pingpong, validDoubles, participants: twoParticipants))
        #expect(!valid(.pingpongDoubles, incompleteDoubles))
        #expect(valid(.shuttlecock, rally(.shuttlecock())))
        #expect(valid(.shuttlecock, rally(.shuttlecock(), doubles: .badminton(playerNames: doublesNames))))
        #expect(!valid(.shuttlecock, rally(.shuttlecock(), doubles: doubles)))

        var tennis = TennisMatchState(leftName: "A", rightName: "B")
        #expect(!valid(.tennisDoubles, .tennis(tennis), participants: doublesNames))
        tennis.doublesPlayerNames = doublesNames
        #expect(!valid(.tennis, .tennis(tennis)))
        tennis.doublesPlayerNames = ["A1", "B1", "A2"]
        #expect(!valid(.tennisDoubles, .tennis(tennis)))
    }

    @Test func billiardsUsesTheCurrentParticipantCounts() {
        for participants in [[], ["A"], ["A", "A"], ["A", "B", "C"]] {
            let validPair = participants.count == 2
            #expect(valid(.eightBall, .eightBall(.initial()), participants: participants) == validPair)
            #expect(valid(.snooker, .snooker(.initial()), participants: participants) == validPair)
        }

        for count in 1...5 {
            var state = NineBallChaseState.initial(playerCount: 2)
            state.playerCount = count
            #expect(valid(.nineBall, .nineBall(state)) == (2...4).contains(count))
        }
    }

    private func rally(_ rules: RallyRuleSet, doubles: RallyDoublesState? = nil) -> LinkedScoreboardSnapshot {
        .rally(RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules, doubles: doubles))
    }

    private func valid(
        _ gameType: GameType,
        _ snapshot: LinkedScoreboardSnapshot?,
        participants: [String] = []
    ) -> Bool {
        WatchSportRegistry.isValidLinkedSetup(.init(
            gameType: gameType, initialSnapshot: snapshot, participantNames: participants
        ))
    }
}
