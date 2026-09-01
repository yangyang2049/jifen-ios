import Foundation
import ScoreCore

/// ScoreboardDisplayState ↔ 安卓 DisplayState wire JSON 编解码器。
///
/// 两端模型存在历史差异（winnerId/teamId 字段名、appearance/clock 结构不同），
/// 这里集中处理，保证 iOS 分享端发出的帧可被安卓/鸿蒙显示端解析，
/// iOS 显示端也能解析安卓/鸿蒙分享端的帧。
enum DisplayStateWireCodec {

    // MARK: - Encode（iOS → 云端）

    static func encode(_ state: ScoreboardDisplayState, atWallClockMilliseconds now: Int64 = currentWallClockMs()) -> [String: Any]? {
        var map: [String: Any] = [
            "schemaVersion": ScoreboardDisplayState.schemaVersion,
            "gameType": state.gameType,
            "orientation": state.orientation.rawValue,
            "layoutKind": state.layoutKind.rawValue,
            "teams": state.teams.map(encodeTeam),
            "updatedAt": state.updatedAt
        ]
        if let matchTitle = state.matchTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !matchTitle.isEmpty {
            map["matchTitle"] = matchTitle
        }
        if let players = state.players, !players.isEmpty {
            map["players"] = players.map(encodePlayer)
        }
        if let sportState = projectSportState(state) {
            map["sportState"] = sportState
        }
        map["appearance"] = encodeAppearance(state.appearance)
        if let result = state.result {
            map["result"] = encodeResult(result)
        }
        if let keyPoint = state.keyPoint,
           (keyPoint.kind == "game" || keyPoint.kind == "set" || keyPoint.kind == "match"),
           (keyPoint.side == "left" || keyPoint.side == "right") {
            map["keyPoint"] = ["kind": keyPoint.kind, "side": keyPoint.side]
        }
        if let clock = encodeClock(state.clock, now: now) {
            map["clock"] = clock
        }
        // rest（官方休息态）两端 wire 模型差异较大，v1 不透传，显示端优雅降级。
        return map
    }

    /// 对齐安卓 isDisplayState 的最小完整性校验。
    static func isValid(_ map: [String: Any]) -> Bool {
        guard map["gameType"] is String,
              (map["schemaVersion"] as? Int) == 1 || (map["schemaVersion"] as? Double) == 1,
              map["layoutKind"] is String,
              (map["updatedAt"] as? NSNumber) != nil,
              map["teams"] is [[String: Any]] else {
            return false
        }
        if let players = map["players"], !(players is [[String: Any]]) { return false }
        if let sportState = map["sportState"], !(sportState is [String: Any]) { return false }
        if let keyPoint = map["keyPoint"], !(keyPoint is [String: Any]) { return false }
        return true
    }

    private static func encodeTeam(_ team: ScoreboardDisplayTeam) -> [String: Any] {
        var map: [String: Any] = [
            "id": team.id,
            "name": team.name,
            "score": team.score,
            "order": team.order
        ]
        if let sets = team.sets { map["sets"] = sets }
        if let games = team.games { map["games"] = games }
        if let color = team.color { map["color"] = color }
        return map
    }

    private static func encodePlayer(_ player: ScoreboardDisplayPlayer) -> [String: Any] {
        var map: [String: Any] = [
            "id": player.id,
            "name": player.name,
            "order": player.order
        ]
        if let score = player.score { map["score"] = score }
        if let teamID = player.teamID { map["teamId"] = teamID }
        if let slot = player.slot { map["slot"] = slot }
        if let color = player.color { map["color"] = color }
        if let isServer = player.isServer { map["isServer"] = isServer }
        return map
    }

    private static func encodeResult(_ result: ScoreboardDisplayResult) -> [String: Any] {
        var map: [String: Any] = ["ended": result.ended]
        if result.manualEnd { map["manualEnd"] = result.manualEnd }
        if let winnerID = result.winnerID { map["winnerId"] = winnerID }
        if let finalScores = result.finalScores {
            map["finalScores"] = finalScores.mapValues { score in
                ["score": score.score, "sets": score.sets, "games": score.games]
            }
        }
        return map
    }

    /// iOS appearance（扁平面板色）→ 安卓 DisplayAppearanceState。
    private static func encodeAppearance(_ appearance: ScoreboardDisplayAppearance) -> [String: Any] {
        var map: [String: Any] = [
            "theme": appearance.theme,
            "fontCode": appearance.fontCode
        ]
        if appearance.leftTextHex != appearance.rightTextHex {
            map["scoreColor"] = appearance.leftTextHex
            map["secondaryScoreColor"] = appearance.rightTextHex
        } else {
            map["scoreColor"] = appearance.leftTextHex
        }
        map["leftTeamColor"] = appearance.leftPanelHex
        map["rightTeamColor"] = appearance.rightPanelHex
        map["centerTeamColor"] = appearance.centerPanelHex
        // 对齐安卓 DisplayAppearanceState.toMap：字号倍率在嵌套 style.fontSizeMultipliers。
        if let multipliers = appearance.fontSizeMultipliers, !multipliers.isEmpty {
            map["style"] = ["fontSizeMultipliers": multipliers]
        }
        return map
    }

    /// iOS 投影时钟 → 安卓 DisplayMatchClockState（version=1, mode="elapsed"）。
    private static func encodeClock(_ clock: ScoreboardDisplayClock?, now: Int64) -> [String: Any]? {
        guard let clock else { return nil }
        var startedAt = clock.anchorWallClockMilliseconds
        if startedAt <= 0 {
            startedAt = max(1, now - clock.elapsedMilliseconds)
        }
        var map: [String: Any] = [
            "version": 1,
            "mode": "elapsed",
            "visible": clock.visible,
            "running": clock.isRunning,
            "startedAt": startedAt,
            "elapsedMs": clock.elapsedMilliseconds
        ]
        // 对齐安卓 DisplayMatchClockState.toMap：足球阶段字段。
        if let half = clock.footballHalf, (1...4).contains(half) {
            map["footballHalf"] = half
        }
        if let halfLength = clock.footballHalfLengthMs, halfLength >= 0 {
            map["footballHalfLengthMs"] = halfLength
        }
        if let injuryTarget = clock.footballInjuryTargetMs, injuryTarget >= 0 {
            map["footballInjuryTargetMs"] = injuryTarget
        }
        if let label = clock.label, !label.isEmpty {
            map["halfLabel"] = label
        }
        return map
    }

    // MARK: - Decode（云端 → iOS）

    static func decode(_ map: [String: Any]) -> ScoreboardDisplayState? {
        guard isValid(map) else { return nil }
        let gameType = map["gameType"] as? String ?? ""
        let teams: [ScoreboardDisplayTeam] = ((map["teams"] as? [[String: Any]]) ?? []).map { team in
            ScoreboardDisplayTeam(
                id: team["id"] as? String ?? "",
                name: team["name"] as? String ?? "",
                score: int(team["score"]) ?? 0,
                sets: int(team["sets"]),
                games: int(team["games"]),
                color: team["color"] as? String,
                order: int(team["order"]) ?? 0
            )
        }
        guard !teams.isEmpty else { return nil }

        let players: [ScoreboardDisplayPlayer]? = ((map["players"] as? [[String: Any]]) ?? []).map { player in
            ScoreboardDisplayPlayer(
                id: player["id"] as? String ?? "",
                name: player["name"] as? String ?? "",
                score: int(player["score"]),
                teamID: player["teamId"] as? String,
                slot: player["slot"] as? String,
                order: int(player["order"]) ?? 0,
                color: player["color"] as? String,
                isServer: player["isServer"] as? Bool
            )
        }

        var sportState: [String: ScoreboardDisplayValue]?
        if let raw = map["sportState"] as? [String: Any] {
            var decoded: [String: ScoreboardDisplayValue] = [:]
            for (key, value) in raw {
                if let value = decodeValue(value) {
                    decoded[key] = value
                }
            }
            sportState = decoded.isEmpty ? nil : decoded
        }

        var orientation = ScoreboardDisplayOrientation.landscape
        if let raw = map["orientation"] as? String, raw == "portrait" {
            orientation = .portrait
        }
        var layoutKind = ScoreboardDisplayLayoutKind.twoSide
        if let raw = map["layoutKind"] as? String,
           let kind = ScoreboardDisplayLayoutKind(rawValue: raw) {
            layoutKind = kind
        }

        let result = (map["result"] as? [String: Any]).flatMap(decodeResult)
        let keyPoint = (map["keyPoint"] as? [String: Any]).flatMap(decodeKeyPoint)
        let clock = (map["clock"] as? [String: Any]).flatMap(decodeClock)
        let rest = (map["rest"] as? [String: Any]).flatMap(decodeRest)
        let appearance = decodeAppearance(map["appearance"] as? [String: Any], gameType: gameType)

        return ScoreboardDisplayState(
            gameType: gameType,
            orientation: orientation,
            layoutKind: layoutKind,
            teams: teams,
            matchTitle: map["matchTitle"] as? String,
            players: players?.isEmpty == true ? nil : players,
            sportState: sportState,
            appearance: appearance,
            result: result,
            updatedAt: UInt64(int(map["updatedAt"]) ?? 0),
            keyPoint: keyPoint,
            clock: clock,
            rest: rest
        )
    }

    private static func decodeResult(_ map: [String: Any]) -> ScoreboardDisplayResult? {
        guard let ended = map["ended"] as? Bool else { return nil }
        let finalScores: [String: ScoreboardDisplayFinalScore]? = (map["finalScores"] as? [String: [String: Any]])?.mapValues { values in
            ScoreboardDisplayFinalScore(
                score: int(values["score"]) ?? 0,
                sets: int(values["sets"]) ?? 0,
                games: int(values["games"]) ?? 0
            )
        }
        return ScoreboardDisplayResult(
            ended: ended,
            manualEnd: map["manualEnd"] as? Bool ?? false,
            winnerID: map["winnerId"] as? String,
            finalScores: finalScores
        )
    }

    private static func decodeKeyPoint(_ map: [String: Any]) -> ScoreboardDisplayKeyPoint? {
        guard let kind = map["kind"] as? String, let side = map["side"] as? String else { return nil }
        return ScoreboardDisplayKeyPoint(kind: kind, side: side)
    }

    /// 安卓 DisplayMatchClockState → iOS 投影时钟。
    private static func decodeClock(_ map: [String: Any]) -> ScoreboardDisplayClock? {
        guard let version = int(map["version"]), version == 1,
              let mode = map["mode"] as? String, mode == "elapsed",
              let visible = map["visible"] as? Bool,
              let running = map["running"] as? Bool,
              let startedAt = int64(map["startedAt"]), startedAt > 0,
              let elapsedMs = int64(map["elapsedMs"]), elapsedMs >= 0 else {
            return nil
        }
        return ScoreboardDisplayClock(
            elapsedMilliseconds: elapsedMs,
            isRunning: running,
            countsDown: false,
            durationMilliseconds: nil,
            anchorWallClockMilliseconds: startedAt,
            label: map["halfLabel"] as? String,
            visible: visible,
            footballHalf: (map["footballHalf"] as? NSNumber).flatMap { (1...4).contains($0.intValue) ? $0.intValue : nil },
            footballHalfLengthMs: (map["footballHalfLengthMs"] as? NSNumber).flatMap { $0.int64Value >= 0 ? $0.int64Value : nil },
            footballInjuryTargetMs: (map["footballInjuryTargetMs"] as? NSNumber).flatMap { $0.int64Value >= 0 ? $0.int64Value : nil }
        )
    }

    private static func decodeRest(_ map: [String: Any]) -> ScoreboardDisplayRest? {
        guard let phase = map["phase"] as? String,
              let remainingMs = int64(map["remainingMs"]), remainingMs >= 0 else {
            return nil
        }
        // kind 取安卓 MID_GAME/GAME_BREAK/SET_BREAK 等的 wire 值，尽量映射；未知则丢弃。
        let rawKind = (map["kind"] as? String) ?? ""
        let kind = rawKind.isEmpty ? "set_break" : rawKind.lowercased()
        return ScoreboardDisplayRest(
            kind: kind,
            phase: phase.lowercased(),
            remainingSeconds: Int(remainingMs / 1000),
            isRunning: phase.lowercased() == "countdown",
            updatedWallClockMilliseconds: currentWallClockMs()
        )
    }

    /// 安卓 DisplayAppearanceState → iOS appearance；缺省字段用本地主题兜底。
    private static func decodeAppearance(_ map: [String: Any]?, gameType: String) -> ScoreboardDisplayAppearance {
        var appearance = ScoreboardDisplayAppearance(
            theme: "default",
            fontCode: "default",
            backgroundHex: "#0A0F14",
            foregroundHex: "#FFFFFF",
            leftPanelHex: "#EF4444",
            rightPanelHex: "#3B82F6",
            centerPanelHex: "#1E293B",
            leftTextHex: "#FFFFFF",
            rightTextHex: "#FFFFFF",
            centerTextHex: "#FFFFFF"
        )
        guard let map else { return appearance }
        if let theme = map["theme"] as? String, !theme.isEmpty { appearance.theme = theme }
        if let fontCode = map["fontCode"] as? String, !fontCode.isEmpty { appearance.fontCode = fontCode }
        if let scoreColor = validColor(map["scoreColor"]) { appearance.leftTextHex = scoreColor; appearance.rightTextHex = scoreColor }
        if let secondary = validColor(map["secondaryScoreColor"]) { appearance.rightTextHex = secondary }
        if let left = validColor(map["leftTeamColor"]) { appearance.leftPanelHex = left }
        if let right = validColor(map["rightTeamColor"]) { appearance.rightPanelHex = right }
        if let center = validColor(map["centerTeamColor"]) { appearance.centerPanelHex = center }
        if let background = validColor(map["backgroundHex"]) { appearance.backgroundHex = background }
        if let foreground = validColor(map["foregroundHex"]) { appearance.foregroundHex = foreground }
        // 安卓 style.fontSizeMultipliers → iOS 倍率（键同安卓 ScoreboardStyleElementKey）。
        if let style = map["style"] as? [String: Any],
           let raw = style["fontSizeMultipliers"] as? [String: Any] {
            var multipliers: [String: Double] = [:]
            for (key, value) in raw where multiplierKeys.contains(key) {
                if let number = value as? NSNumber, number.doubleValue > 0 {
                    multipliers[key] = number.doubleValue
                }
            }
            if !multipliers.isEmpty { appearance.fontSizeMultipliers = multipliers }
        }
        return appearance
    }

    private static let multiplierKeys: Set<String> = [
        "mainScore", "teamName", "playerName", "setScore", "gameScore", "setGameScore", "matchTitle"
    ]

    private static func validColor(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let hex = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8,
              hex.allSatisfy({ $0.isNumber || "abcdef".contains(Character($0.lowercased())) }) else {
            return nil
        }
        return "#" + hex.uppercased()
    }

    // MARK: - sportState 投影（对齐安卓 projectDisplaySportState）

    private static let commonSportKeys: Set<String> = [
        "currentSet", "servingTeam", "serverSlotIndex", "team0ScreenSide",
        "multiGridColumns", "multiGridTileGap", "multiGridOuterPadding",
        "multiGridNamePlacement", "multiGridNameTopPadding", "multiGridLargeScore",
        "leftDisplayScore", "rightDisplayScore", "leftDetail", "rightDetail"
    ]

    private static let sportKeysByGameType: [String: Set<String>] = [
        "badminton": ["badmintonServerSide", "competitionFormat", "ruleProfileVersion", "layoutKind", "teamCourtPlayers"],
        "badminton_doubles": ["badmintonServerSide", "competitionFormat", "ruleProfileVersion", "layoutKind", "teamCourtPlayers"],
        "shuttlecock": ["badmintonServerSide", "competitionFormat", "ruleProfileVersion", "layoutKind", "teamCourtPlayers"],
        "squash": ["competitionFormat", "ruleProfileVersion"],
        "pingpong": ["tableTennisTeam0TimeoutUsed", "tableTennisTeam0Yellow", "tableTennisTeam0RedCount",
                     "tableTennisTeam1TimeoutUsed", "tableTennisTeam1Yellow", "tableTennisTeam1RedCount"],
        "pingpong_doubles": ["tableTennisTeam0TimeoutUsed", "tableTennisTeam0Yellow", "tableTennisTeam0RedCount",
                             "tableTennisTeam1TimeoutUsed", "tableTennisTeam1Yellow", "tableTennisTeam1RedCount"],
        "tennis": ["tennisDeuceMode", "tennisIsTieBreak", "tennisTiebreakOnly", "tennisIsDeuce", "tennisAdvantage",
                   "competitionFormat", "ruleProfileVersion", "softTennisMatchGames", "padelDeuceMode", "starPointReturnedAdvantages"],
        "tennis_doubles": ["tennisDeuceMode", "tennisIsTieBreak", "tennisTiebreakOnly", "tennisIsDeuce", "tennisAdvantage",
                           "competitionFormat", "ruleProfileVersion", "softTennisMatchGames", "padelDeuceMode", "starPointReturnedAdvantages"],
        "soft_tennis": ["tennisDeuceMode", "tennisIsTieBreak", "tennisTiebreakOnly", "tennisIsDeuce", "tennisAdvantage",
                        "competitionFormat", "ruleProfileVersion", "softTennisMatchGames", "padelDeuceMode", "starPointReturnedAdvantages"],
        "padel": ["tennisDeuceMode", "tennisIsTieBreak", "tennisTiebreakOnly", "tennisIsDeuce", "tennisAdvantage",
                  "competitionFormat", "ruleProfileVersion", "softTennisMatchGames", "padelDeuceMode", "starPointReturnedAdvantages"],
        "pickleball": ["pickleballTeam0PartnersSwapped", "pickleballTeam1PartnersSwapped"],
        "pickleball_doubles": ["pickleballTeam0PartnersSwapped", "pickleballTeam1PartnersSwapped"],
        "snooker": ["snookerLeftBreak", "snookerRightBreak", "snookerMaxFrames"],
        "boxing": ["boxingCurrentRound", "boxingMaxRounds"],
        "eight_ball": ["eightBallTargetRacks", "eightBallHandicapRacks", "eightBallHandicapBeneficiary"],
        "nine_ball": ["chasePlayerCount", "chasePlayerNames", "chasePlayerCounts", "chaseLeftCounts", "chaseRightCounts", "chasePoints"],
        "archery_dual": ["archeryCurrentShooter"],
        "basketball": ["basketballCurrentPeriod", "basketballIsOT", "basketballLeftFouls", "basketballRightFouls",
                       "basketballGameTime", "basketballShotTime", "basketballGameRunning", "basketballShotRunning",
                       "basketballClockRevision", "basketballClockStarted"],
        "three_basketball": ["basketballCurrentPeriod", "basketballIsOT", "basketballLeftFouls", "basketballRightFouls",
                             "basketballGameTime", "basketballShotTime", "basketballGameRunning", "basketballShotRunning",
                             "basketballClockRevision", "basketballClockStarted"],
        "uno": ["unoRoundCount", "unoTargetScore"],
        "guandan": ["guandanRedRank", "guandanBlueRank", "guandanLeftAFailCount", "guandanRightAFailCount",
                    "guandanTripleAEnabled", "guandanBankerTeam"],
        "shengji": ["shengjiRedRank", "shengjiBlueRank", "shengjiBankerTeam"]
    ]

    private static func projectSportState(_ state: ScoreboardDisplayState) -> [String: Any]? {
        guard let sportState = state.sportState, !sportState.isEmpty else { return nil }
        var allowed = commonSportKeys.union(sportKeysByGameType[state.gameType] ?? [])
        if state.gameType == "basketball" || state.gameType == "three_basketball" {
            allowed.formUnion(["basketballGameTime", "basketballShotTime", "basketballClockRevision",
                               "basketballGameRunning", "basketballShotRunning", "basketballClockStarted"])
        }
        var projected: [String: Any] = [:]
        for (key, value) in sportState where allowed.contains(key) {
            if let wire = wireValue(value) {
                projected[key] = wire
            }
        }
        return projected.isEmpty ? nil : projected
    }

    private static func wireValue(_ value: ScoreboardDisplayValue) -> Any? {
        switch value {
        case .string(let value): return value
        case .integer(let value): return value
        case .double(let value): return value
        case .boolean(let value): return value
        case .strings(let value): return value
        case .integers(let value): return value
        }
    }

    private static func decodeValue(_ value: Any) -> ScoreboardDisplayValue? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            if number.doubleValue == number.doubleValue.rounded() && abs(number.doubleValue) < 9_007_199_254_740_992 {
                return .integer(number.intValue)
            }
            return .double(number.doubleValue)
        case let string as String:
            return .string(string)
        case let strings as [String]:
            return .strings(strings)
        case let integers as [NSNumber]:
            return .integers(integers.map(\.intValue))
        default:
            return nil
        }
    }

    // MARK: - 数值工具

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    static func currentWallClockMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
