import Foundation
import ScoreCore

extension ScoreboardDisplayAppearance {
    init(snapshot: ScoreboardAppearanceSnapshot, fontCode: String? = nil) {
        let profile = snapshot.styleProfileV2
        self.init(
            theme: snapshot.theme.rawValue,
            fontCode: fontCode ?? snapshot.font.rawValue,
            backgroundHex: "#\(profile.backgroundHex)",
            foregroundHex: "#\(profile.foregroundHex)",
            leftPanelHex: "#\(profile.team0Hex)",
            rightPanelHex: "#\(profile.team1Hex)",
            centerPanelHex: "#\(profile.centerHex)",
            leftTextHex: "#\(profile.resolvedTextHex(for: .team0))",
            rightTextHex: "#\(profile.resolvedTextHex(for: .team1))",
            centerTextHex: "#\(profile.resolvedTextHex(for: .center))"
        )
    }
}

extension ScoreboardDisplayRest {
    nonisolated init(_ state: OfficialBreakState) {
        self.init(
            kind: state.kind.rawValue,
            phase: state.phase.rawValue,
            remainingSeconds: state.remainingSeconds,
            isRunning: state.isRunning,
            updatedWallClockMilliseconds: state.updatedWallClockMilliseconds
        )
    }
}

extension ScoreboardDisplayState {
    init(compactState state: LocalScoreboardDisplayState) {
        let profile = ScoreboardAppearanceSnapshot.current(
            styleID: ScoreboardStyleID(rawValue: state.gameID)
        ).styleProfileV2
        let leftValue = Int(state.leftScore) ?? 0
        let rightValue = Int(state.rightScore) ?? 0
        let teams = [
            ScoreboardDisplayTeam(
                id: "team_0",
                name: state.leftName,
                score: leftValue,
                color: "#\(profile.team0Hex)",
                order: 0
            ),
            ScoreboardDisplayTeam(
                id: "team_1",
                name: state.rightName,
                score: rightValue,
                color: "#\(profile.team1Hex)",
                order: 1
            )
        ]
        var sport: [String: ScoreboardDisplayValue] = [
            "leftDisplayScore": .string(state.leftScore),
            "rightDisplayScore": .string(state.rightScore)
        ]
        if let detail = state.leftDetail { sport["leftDetail"] = .string(detail) }
        if let detail = state.rightDetail { sport["rightDetail"] = .string(detail) }
        let layout = ScoreboardDisplayLayoutKind.resolve(gameID: state.gameID)
        let winner: String? = if state.finished {
            leftValue == rightValue ? "draw" : (leftValue > rightValue ? "team_0" : "team_1")
        } else {
            nil
        }
        self.init(
            gameType: state.gameID,
            orientation: layout == .multiGrid ? .portrait : .landscape,
            layoutKind: layout,
            teams: teams,
            matchTitle: state.title,
            sportState: sport,
            appearance: ScoreboardDisplayAppearance(
                theme: state.themeID,
                fontCode: state.fontID,
                backgroundHex: "#\(profile.backgroundHex)",
                foregroundHex: "#\(profile.foregroundHex)",
                leftPanelHex: "#\(profile.team0Hex)",
                rightPanelHex: "#\(profile.team1Hex)",
                centerPanelHex: "#\(profile.centerHex)",
                leftTextHex: "#\(profile.resolvedTextHex(for: .team0))",
                rightTextHex: "#\(profile.resolvedTextHex(for: .team1))",
                centerTextHex: "#\(profile.resolvedTextHex(for: .center))"
            ),
            result: state.finished ? ScoreboardDisplayResult(
                ended: true,
                winnerID: winner,
                finalScores: [
                    "team_0": .init(score: leftValue),
                    "team_1": .init(score: rightValue)
                ]
            ) : nil,
            updatedAt: state.revision,
            keyPoint: state.keyPoint.flatMap { point in
                guard point.isRenderable else { return nil }
                return ScoreboardDisplayKeyPoint(kind: point.kind.rawValue, side: point.side.rawValue)
            }
        )
    }

    static func enriched(
        compact: LocalScoreboardDisplayState,
        layoutKind: ScoreboardDisplayLayoutKind,
        players: [ScoreboardDisplayPlayer]? = nil,
        sportState: [String: ScoreboardDisplayValue] = [:],
        clock: ScoreboardDisplayClock? = nil,
        rest: ScoreboardDisplayRest? = nil
    ) -> ScoreboardDisplayState {
        var value = ScoreboardDisplayState(compactState: compact)
        value.layoutKind = layoutKind
        value.orientation = layoutKind == .multiGrid ? .portrait : .landscape
        value.players = players
        value.sportState?.merge(sportState) { _, next in next }
        value.clock = clock
        value.rest = rest
        return value
    }
}
