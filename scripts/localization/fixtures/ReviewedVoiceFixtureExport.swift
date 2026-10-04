import Foundation
import Testing
@testable import ScoreCore

@Test func exportReviewedVoiceParityFixtures() throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["REVIEWED_VOICE_CATALOGS"] ?? "/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/localization/voice_catalogs")
    let languages = ["ZH": "zh-Hans", "EN": "en", "JA": "ja", "KO": "ko", "FR": "fr", "ES": "es-ES", "PT": "pt-PT", "AR": "ar", "DE": "de", "HE": "he", "RU": "ru", "UK": "uk", "UR": "en"]
    var rows: [[String: Any]] = []
    func emit(_ p: VoiceAnnouncementPayload) throws {
        for (language, localization) in languages.sorted(by: { $0.key < $1.key }) {
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(localization + ".json"))) as! [String: Any]
            let entries = catalog["entries"] as! [String: [String: Any]]
            let message = LocalizedVoiceAnnouncementBuilder.buildReviewed(p, localization: language == "UR" ? "ur" : localization)
            var expected = try #require(message.render(locale: Locale(identifier: localization)) { entries[$0]?["value"] as? String })
            // These hosts fold a sides-exchange event into the scoring payload.
            // iOS represents it as a separate event; include only its reviewed cue.
            if p.sideChange {
                var change = p; change.phase = .sideChange
                let cue = try #require(LocalizedVoiceAnnouncementBuilder.buildReviewed(change, localization: language == "UR" ? "ur" : localization).render(locale: Locale(identifier: localization)) { entries[$0]?["value"] as? String })
                if !cue.isEmpty { expected += ", " + cue }
            }
            rows.append([
                "gameType": p.gameType.rawValue, "phase": p.phase.rawValue, "language": language,
                "leftScore": p.leftScore, "rightScore": p.rightScore, "leftSets": p.leftSets, "rightSets": p.rightSets,
                "leftName": p.leftTeamName, "rightName": p.rightTeamName, "currentSet": p.currentSet ?? 1,
                "serverSide": p.serverSide == .right ? "right" : "left", "winnerSide": p.winnerSide == .right ? "right" : "left",
                "serviceOver": p.serviceOver, "isTieBreak": p.isTieBreak, "criticalPoint": p.criticalPoint?.rawValue ?? "",
                "midGameInterval": p.isInterval, "tennisDeuceMode": p.tennisDeuceMode ?? "advantage",
                "serverNumber": p.serverNumber ?? 0, "breakCue": p.breakCue?.rawValue ?? "time",
                "secondServer": p.secondServer, "starPointReturnedAdvantages": p.starPointReturnedAdvantages,
                "sideChange": p.sideChange,
                "returnedToDeuce": p.returnedToDeuce, "maxSets": p.maxSets ?? 7, "expected": expected
            ])
        }
    }
    let phases: [VoiceAnnouncementPhase] = [.opening, .scoreChange, .gameEnd, .setEnd, .matchEnd, .breakStart, .breakWarning, .breakResume]
    for game in GameType.allCases where VoiceAnnouncementSupport.isSupported(game) {
        for phase in phases {
            let points = [.opening, .scoreChange, .breakResume].contains(phase)
            let tennis = VoiceAnnouncementSupport.isTennisFamily(game) && game != .softTennis
            let left = phase == .opening ? 0 : points && tennis ? 2 : 5
            let right = phase == .opening ? 0 : points && tennis ? 1 : 3
            for servingSide: MatchSide in [.left, .right] {
                try emit(.init(gameType: game, phase: phase, leftTeamName: "Alice %2$@ 3-2", rightTeamName: "Bob", leftScore: left, rightScore: right, leftSets: 1, rightSets: 0, currentSet: 1, serverSide: servingSide, winnerSide: .left, serviceOver: phase == .scoreChange, serverNumber: game == .pickleballDoubles ? 2 : nil, breakCue: .time, maxSets: 7))
            }
        }
    }
    for game: GameType in [.badminton, .tennis, .softTennis, .padel, .squash, .pingpong, .pickleballDoubles] {
        for (left, right) in [(0, 0), (0, 3), (3, 3), (4, 3), (3, 4), (7, 7), (10, 10), (29, 29)] {
            for returned in [false, true] {
                var p = VoiceAnnouncementPayload(gameType: game, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: left, rightScore: right, serverSide: .right, winnerSide: .left, maxSets: 7, returnedToDeuce: returned)
                if game == .badminton && left == 29 { p.criticalPoint = .gamePoint }
                if game == .squash && left == 3 { p.criticalPoint = .matchBall }
                if game == .pickleballDoubles { p.serverNumber = 2; p.secondServer = true }
                if game == .padel { p.tennisDeuceMode = "star_point"; p.starPointReturnedAdvantages = 1 }
                if game == .softTennis && left == 7 { p.isTieBreak = true }
                try emit(p)
            }
        }
    }
    for game: GameType in [.tennis, .padel] {
        for scores in [(3, 2), (0, 3), (6, 6)] {
            try emit(.init(gameType: game, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: scores.0, rightScore: scores.1, serverSide: .right, winnerSide: .left, isTieBreak: true))
        }
        try emit(.init(gameType: game, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 3, tennisDeuceMode: game == .padel ? "golden_point" : "no_ad"))
    }
    for game: GameType in [.badminton, .pingpong, .softTennis, .squash, .pickleballDoubles, .volleyball] {
        for cue: VoiceBreakCue in [.twentySeconds, .fifteenSeconds, .halfTime, .time] {
            try emit(.init(gameType: game, phase: .breakWarning, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 8, rightScore: 7, breakCue: cue))
        }
        try emit(.init(gameType: game, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 4, rightScore: 3, serverSide: .left, sideChange: true))
    }
    let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["REVIEWED_VOICE_FIXTURE_OUTPUT"] ?? "/tmp/reviewed-voice-ios-parity.json"))
    print("Exported \(rows.count) reviewed voice parity fixtures")
}
