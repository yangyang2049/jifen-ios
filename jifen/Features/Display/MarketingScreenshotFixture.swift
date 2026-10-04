#if DEBUG
import SwiftUI
import ScoreCore

/// Reuses production views with deterministic match data for store artwork.
enum MarketingScreenshotFixture {
    static var requestedName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-MarketingScreenshotFixture"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func isRequested(_ name: String) -> Bool { requestedName == name }

    static var names: [String] {
        let values = DefaultParticipantNames.uiTestParticipantNames
        return values.count >= 2 ? values : ["Ethan", "Liam", "Emma", "Mia"]
    }

    static var setup: SportsSetupResult {
        var result = SportsSetupResult(team1Name: names[0], team2Name: names[1])
        result.playerCount = 4
        result.playerNames = names
        result.isSingles = true
        result.maxSets = 3
        result.gamesPerSet = 6
        result.setScoringMode = "regular"
        result.tennisDeuceMode = "advantage"
        return result
    }

    /// Small Red Book captures use the actual launch view and explicit mode data.
    static func xhsGameType(for name: String) -> GameType {
        switch name {
        case "xhs-shot-fixed", "xhs-shot-free": return .basketballTraining
        case "xhs-shuttlecock-singles", "xhs-shuttlecock-team", "xhs-shuttlecock-mixed": return .shuttlecock
        case "xhs-soft-tennis-singles", "xhs-soft-tennis-doubles": return .softTennis
        case "xhs-nine-ball-multi": return .nineBall
        case "xhs-doudizhu-four": return .doudizhu
        case "xhs-foosball-one": return .foosball
        default: return .football5v5
        }
    }

    static func xhsSetup(for name: String) -> SportsSetupResult {
        var result = setup
        result.team1Name = "刘备"
        result.team2Name = "曹操"
        result.playerNames = ["刘备", "曹操", "孙权", "周瑜"]
        result.playerCount = 4
        result.autoChangeSides = true
        result.pointsPerSet = 21
        result.servingSide = "left"
        switch name {
        case "xhs-shot-fixed", "xhs-shot-free":
            result.basketballTrainingScoringMode = name == "xhs-shot-fixed" ? "fixed_2" : "free"
        case "xhs-shuttlecock-singles":
            result.competitionFormat = .singles
        case "xhs-shuttlecock-team":
            result.isSingles = false
            result.competitionFormat = .team
            result.team1Name = "刘备 / 关羽 / 张飞"
            result.team2Name = "曹操 / 张辽 / 许褚"
            result.team1Player1Name = "刘备"
            result.team1Player2Name = "关羽"
            result.team1Player3Name = "张飞"
            result.team2Player1Name = "曹操"
            result.team2Player2Name = "张辽"
            result.team2Player3Name = "许褚"
        case "xhs-shuttlecock-mixed", "xhs-soft-tennis-doubles":
            result.isSingles = false
            result.competitionFormat = .mixedDoubles
            result.team1Name = "刘备 / 孙尚香"
            result.team2Name = "诸葛亮 / 黄月英"
            result.team1Player1Name = "刘备"
            result.team1Player2Name = "孙尚香"
            result.team2Player1Name = "诸葛亮"
            result.team2Player2Name = "黄月英"
            result.softTennisMatchGames = 7
        case "xhs-soft-tennis-singles":
            result.softTennisMatchGames = 7
        case "xhs-foosball-one":
            result.pointsPerSet = 5
        case "xhs-football-five":
            result.team1Name = "锦城队"
            result.team2Name = "江城队"
            result.footballHalfLengthSeconds = 1200
            result.showMatchTime = true
        default:
            break
        }
        return result
    }
}

struct MarketingScreenshotFixtureView: View {
    let name: String

    var body: some View {
        NavigationStack {
            switch name {
            case "record":
                ScoreboardRecordDetailPage(recordId: "ui-fixture-pingpong")
            case "trend":
                MarketingTrendScreenshotFixtureView()
            case "setup":
                ContentView()
                    .disabled(true)
                    .overlay {
                        CenteredSetupDialogContainer(onBackdropTap: {}) { maxHeight in
                            SportsSetupDialogView(
                                gameType: .tennis,
                                defaultTeam1Name: MarketingScreenshotFixture.names[0],
                                defaultTeam2Name: MarketingScreenshotFixture.names[1],
                                initialMaxSets: 3,
                                initialPointsPerSet: nil,
                                initialTieBreakPoints: 7,
                                initialSetup: MarketingScreenshotFixture.setup,
                                maxDialogHeight: maxHeight
                            )
                        }
                    }
            case "basketball":
                BasketballScoreboardView(initialSetup: MarketingScreenshotFixture.setup)
            case "multi":
                MultiScoreboardView(initialSetup: MarketingScreenshotFixture.setup)
            case "rally":
                BadmintonScoreboardView(initialSetup: MarketingScreenshotFixture.setup)
            case "snooker":
                SnookerScoreboardView(initialSetup: MarketingScreenshotFixture.setup)
            case "xhs-shot-fixed", "xhs-shot-free",
                 "xhs-shuttlecock-singles", "xhs-shuttlecock-team", "xhs-shuttlecock-mixed",
                 "xhs-soft-tennis-singles", "xhs-soft-tennis-doubles",
                 "xhs-nine-ball-multi", "xhs-doudizhu-four", "xhs-foosball-one", "xhs-football-five":
                ScoreboardLaunchView(
                    gameType: MarketingScreenshotFixture.xhsGameType(for: name),
                    setupResult: MarketingScreenshotFixture.xhsSetup(for: name),
                    automaticallyShowsUsageHint: false
                )
            default:
                Text("Unknown marketing screenshot scene")
            }
        }
        .preferredColorScheme(.light)
    }
}
#endif
