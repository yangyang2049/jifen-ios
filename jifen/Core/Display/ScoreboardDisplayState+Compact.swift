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

    /// 对齐安卓 wire 键名（ScoreboardStyleElementKey）。
    static func multipliers(
        score: Double?,
        name: Double?,
        secondary: Double?
    ) -> [String: Double]? {
        guard score != nil || name != nil || secondary != nil else { return nil }
        var map: [String: Double] = [:]
        if let score { map["mainScore"] = score }
        if let name {
            map["teamName"] = name
            map["playerName"] = name
        }
        if let secondary {
            map["setScore"] = secondary
            map["gameScore"] = secondary
            map["setGameScore"] = secondary
        }
        return map
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
                sets: state.leftSets,
                games: state.leftGames,
                color: "#\(profile.team0Hex)",
                order: 0
            ),
            ScoreboardDisplayTeam(
                id: "team_1",
                name: state.rightName,
                score: rightValue,
                sets: state.rightSets,
                games: state.rightGames,
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
                centerTextHex: "#\(profile.resolvedTextHex(for: .center))",
                fontSizeMultipliers: ScoreboardDisplayAppearance.multipliers(
                    score: state.scoreMultiplier,
                    name: state.nameMultiplier,
                    secondary: state.secondaryMultiplier
                )
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
        value.normalizeLogicalTeamIdentityFromVisualCompact()
        return value
    }

    /// `LocalScoreboardDisplayState` intentionally stores the two visible panels in
    /// screen order so the lightweight phone/watch projection can render it directly.
    /// The cross-platform `ScoreboardDisplayState` contract is different: `team_0`
    /// and `team_1` are stable logical identities, while `team0ScreenSide` carries
    /// placement. Normalize exactly once at the compact -> rich-state boundary.
    private mutating func normalizeLogicalTeamIdentityFromVisualCompact() {
        guard sportString("team0ScreenSide") == "right", teams.count == 2 else { return }

        let visualLeft = teams[0]
        let visualRight = teams[1]
        var logicalTeam0 = visualRight
        logicalTeam0.id = "team_0"
        logicalTeam0.order = 0
        logicalTeam0.color = appearance.leftPanelHex
        var logicalTeam1 = visualLeft
        logicalTeam1.id = "team_1"
        logicalTeam1.order = 1
        logicalTeam1.color = appearance.rightPanelHex
        teams = [logicalTeam0, logicalTeam1]

        players = players?.map { player in
            var normalized = player
            switch player.teamID {
            case "team_0": normalized.teamID = "team_1"
            case "team_1": normalized.teamID = "team_0"
            default: break
            }
            return normalized
        }

        guard var result else { return }
        switch result.winnerID {
        case "team_0": result.winnerID = "team_1"
        case "team_1": result.winnerID = "team_0"
        default: break
        }
        if let visualScores = result.finalScores {
            var logicalScores = visualScores
            logicalScores["team_0"] = visualScores["team_1"]
            logicalScores["team_1"] = visualScores["team_0"]
            result.finalScores = logicalScores
        }
        self.result = result
    }
}
