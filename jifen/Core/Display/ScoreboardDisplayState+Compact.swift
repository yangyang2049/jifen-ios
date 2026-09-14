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
            centerTextHex: "#\(profile.resolvedTextHex(for: .center))",
            leftScoreHex: ScoreboardDisplayAppearance.resolvedMainHex(profile, .sideLeft),
            rightScoreHex: ScoreboardDisplayAppearance.resolvedMainHex(profile, .sideRight),
            leftSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideLeft),
            rightSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideRight),
            centerSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideCenter),
            style: ScoreboardDisplayStyle(profile: profile, fontCode: fontCode ?? snapshot.font.rawValue)
        )
    }

    /// 主分元素（mainScore）手动色优先；auto/缺失回落扁平文字色。
    fileprivate static func resolvedMainHex(
        _ profile: ScoreboardStyleProfileV2,
        _ slotKey: ScoreboardStyleSlotKeyV2
    ) -> String {
        return "#\(profile.resolvedElementTextHex(.mainScore, slotKey: slotKey))"
    }

    /// 盘/局分元素色：setGameScore → setScore → gameScore 首个手动色优先；否则回落扁平文字色。
    fileprivate static func resolvedSecondaryHex(
        _ profile: ScoreboardStyleProfileV2,
        _ slotKey: ScoreboardStyleSlotKeyV2
    ) -> String {
        let keys: [ScoreboardStyleElementKeyV2] = [.setGameScore, .setScore, .gameScore]
        for key in keys {
            if profile.elementHasManualColor(key, slotKey: slotKey) {
                return "#\(profile.resolvedElementTextHex(key, slotKey: slotKey))"
            }
        }
        return "#\(profile.resolvedTextHex(for: slotKey.legacySlot ?? .team0))"
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
            updatedWallClockMilliseconds: state.updatedWallClockMilliseconds,
            sport: state.sport.rawValue,
            afterAction: state.afterAction.rawValue,
            title: state.title
        )
    }
}

extension ScoreboardDisplayState {
    /// 网球家族 wire 比分：对齐安卓 `toProtocolTennisPointScore` 协议契约。
    /// 常规局显示串 0/15/30/40/AD 统一转成点数序号 0/1/2/3/4（软式网球序号即原始步进值），
    /// 抢七等实际分数是纯数字串，原样透传；显示端由 tennisIsDeuce/tennisAdvantage 表达占先。
    static func wireProtocolScore(gameID: String, display: String) -> Int {
        let tennisFamilyGameIDs: Set<String> = ["tennis", "tennis_doubles", "soft_tennis", "padel"]
        guard tennisFamilyGameIDs.contains(gameID) else {
            return Int(display) ?? 0
        }
        switch display {
        case "0": return 0
        case "15": return 1
        case "30": return 2
        case "40": return 3
        case "AD": return 4
        default: return Int(display) ?? 0
        }
    }

    init(compactState state: LocalScoreboardDisplayState) {
        let profile = ScoreboardAppearanceSnapshot.current(
            styleID: ScoreboardStyleID(rawValue: state.gameID)
        ).styleProfileV2
        let leftValue = Self.wireProtocolScore(gameID: state.gameID, display: state.leftScore)
        let rightValue = Self.wireProtocolScore(gameID: state.gameID, display: state.rightScore)
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
            "rightDisplayScore": .string(state.rightScore),
            // Compact snapshots carry every score level, but the result card
            // needs to know which level represents the match result. Producers
            // with custom one-set/tiebreak-only rules may override this value
            // while enriching the snapshot.
            "resultScoreLevel": .string(
                state.leftSets != nil || state.rightSets != nil ? "sets" : "score"
            )
        ]
        if let detail = state.leftDetail { sport["leftDetail"] = .string(detail) }
        if let detail = state.rightDetail { sport["rightDetail"] = .string(detail) }
        let layout = ScoreboardDisplayLayoutKind.resolve(gameID: state.gameID)
        let winner: String? = state.finished
            ? Self.finishedWinnerID(
                leftScore: leftValue,
                rightScore: rightValue,
                leftSets: state.leftSets,
                rightSets: state.rightSets,
                leftGames: state.leftGames,
                rightGames: state.rightGames
            )
            : nil
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
                leftScoreHex: ScoreboardDisplayAppearance.resolvedMainHex(profile, .sideLeft),
                rightScoreHex: ScoreboardDisplayAppearance.resolvedMainHex(profile, .sideRight),
                leftSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideLeft),
                rightSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideRight),
                centerSecondaryHex: ScoreboardDisplayAppearance.resolvedSecondaryHex(profile, .sideCenter),
                fontSizeMultipliers: ScoreboardDisplayAppearance.multipliers(
                    score: state.scoreMultiplier,
                    name: state.nameMultiplier,
                    secondary: state.secondaryMultiplier
                ),
                style: ScoreboardDisplayStyle(profile: profile, fontCode: state.fontID)
            ),
            result: state.finished ? ScoreboardDisplayResult(
                ended: true,
                winnerID: winner,
                finalScores: [
                    "team_0": .init(
                        score: leftValue,
                        sets: state.leftSets ?? 0,
                        games: state.leftGames ?? 0
                    ),
                    "team_1": .init(
                        score: rightValue,
                        sets: state.rightSets ?? 0,
                        games: state.rightGames ?? 0
                    )
                ]
            ) : nil,
            updatedAt: state.revision,
            keyPoint: state.keyPoint.flatMap { point in
                guard point.isRenderable else { return nil }
                return ScoreboardDisplayKeyPoint(kind: point.kind.rawValue, side: point.side.rawValue)
            }
        )
    }

    private static func finishedWinnerID(
        leftScore: Int,
        rightScore: Int,
        leftSets: Int?,
        rightSets: Int?,
        leftGames: Int?,
        rightGames: Int?
    ) -> String {
        let setScores = (leftSets ?? 0, rightSets ?? 0)
        if setScores.0 != setScores.1 {
            return setScores.0 > setScores.1 ? "team_0" : "team_1"
        }
        let gameScores = (leftGames ?? 0, rightGames ?? 0)
        if gameScores.0 != gameScores.1 {
            return gameScores.0 > gameScores.1 ? "team_0" : "team_1"
        }
        if leftScore == rightScore { return "draw" }
        return leftScore > rightScore ? "team_0" : "team_1"
    }

    static func enriched(
        compact: LocalScoreboardDisplayState,
        layoutKind: ScoreboardDisplayLayoutKind,
        orientation: ScoreboardDisplayOrientation? = nil,
        players: [ScoreboardDisplayPlayer]? = nil,
        sportState: [String: ScoreboardDisplayValue] = [:],
        clock: ScoreboardDisplayClock? = nil,
        rest: ScoreboardDisplayRest? = nil
    ) -> ScoreboardDisplayState {
        var value = ScoreboardDisplayState(compactState: compact)
        value.layoutKind = layoutKind
        value.orientation = orientation ?? (layoutKind == .multiGrid ? .portrait : .landscape)
        value.players = players
        value.sportState?.merge(sportState) { _, next in next }
        value.clock = clock
        value.rest = rest
        value.normalizeLogicalTeamIdentityFromVisualCompact()
        return value
    }

    /// `LocalScoreboardDisplayState` intentionally stores the two visible panels in
    /// screen order so the lightweight display projection can render it directly.
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
