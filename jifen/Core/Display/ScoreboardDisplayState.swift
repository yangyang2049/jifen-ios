import Foundation

enum ScoreboardDisplayOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

enum ScoreboardDisplayLayoutKind: String, Codable, Sendable {
    case twoSide = "two_side"
    case doublesCourt = "doubles_court"
    case teamCourt = "team_court"
    case multiGrid = "multi_grid"
    case boardCard = "board_card"
    case trainingCounter = "training_counter"
    /// 投篮训练：复刻手机端未中/命中分区（自由模式 3×2 六格 + 中心线分值）。
    case shotTrainingGrid = "shot_training_grid"
}

enum ScoreboardDisplayValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case strings([String])
    case integers([Int])
    /// 嵌套整数数组（九球 chasePlayerCounts：每个逻辑玩家一行的计数表）。
    case integersArrays([[Int]])
    /// 九球追分计分配置，固定键和值均为整数。
    case integerMap([String: Int])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([Int].self) { self = .integers(value); return }
        if let value = try? container.decode([[Int]].self) { self = .integersArrays(value); return }
        if let value = try? container.decode([String: Int].self) { self = .integerMap(value); return }
        self = .strings(try container.decode([String].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        case .integers(let value): try container.encode(value)
        case .integersArrays(let value): try container.encode(value)
        case .integerMap(let value): try container.encode(value)
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): "\(value)"
        case .double(let value): "\(value)"
        case .boolean(let value): value ? "true" : "false"
        default: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): value
        case .double(let value): Int(value)
        case .string(let value): Int(value)
        default: nil
        }
    }
}

struct ScoreboardDisplayTeam: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var score: Int
    var sets: Int? = nil
    var games: Int? = nil
    var color: String? = nil
    var order: Int
}

struct ScoreboardDisplayPlayer: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var score: Int? = nil
    var teamID: String? = nil
    var slot: String? = nil
    var order: Int
    var color: String? = nil
    var isServer: Bool? = nil
    var rank: Int? = nil
}

struct ScoreboardDisplayAppearance: Codable, Equatable, Sendable {
    var theme: String
    var fontCode: String
    var backgroundHex: String
    var foregroundHex: String
    var leftPanelHex: String
    var rightPanelHex: String
    var centerPanelHex: String
    var leftTextHex: String
    var rightTextHex: String
    var centerTextHex: String
    /// 逐元素文字色（主分/盘局分），对齐安卓 wire scoreColor/secondaryScoreColor 与本地逐元素 style。
    /// 为 nil 时回落旧扁平 leftTextHex/rightTextHex。
    var leftScoreHex: String? = nil
    var rightScoreHex: String? = nil
    var leftSecondaryHex: String? = nil
    var rightSecondaryHex: String? = nil
    var centerSecondaryHex: String? = nil
    /// 字号倍率，对齐安卓 DisplayStyleSnapshotV2.fontSizeMultipliers
    /// （键：mainScore/teamName/playerName/setScore/gameScore/setGameScore）。
    var fontSizeMultipliers: [String: Double]? = nil
    var style: ScoreboardDisplayStyle? = nil

    /// 主分文字色（逐元素优先，回落扁平文字色）。
    var leftMainTextHex: String { leftScoreHex ?? leftTextHex }
    var rightMainTextHex: String { rightScoreHex ?? rightTextHex }
    /// 盘/局分文字色（逐元素优先，回落扁平文字色）。
    var leftSecondaryTextHex: String { leftSecondaryHex ?? leftTextHex }
    var rightSecondaryTextHex: String { rightSecondaryHex ?? rightTextHex }
}

struct ScoreboardDisplayFinalScore: Codable, Equatable, Sendable {
    var score: Int
    var sets: Int = 0
    var games: Int = 0
}

struct ScoreboardDisplayResult: Codable, Equatable, Sendable {
    var ended: Bool
    var manualEnd: Bool = false
    var winnerID: String? = nil
    var finalScores: [String: ScoreboardDisplayFinalScore]? = nil
}

struct ScoreboardDisplayKeyPoint: Codable, Equatable, Sendable {
    var kind: String
    var side: String
}

struct ScoreboardDisplayClock: Codable, Equatable, Sendable {
    var elapsedMilliseconds: Int64
    var isRunning: Bool
    var countsDown: Bool = false
    var durationMilliseconds: Int64? = nil
    var anchorWallClockMilliseconds: Int64
    var label: String? = nil
    var visible: Bool = true
    /// 足球阶段（1=上半场 2=下半场 3=加时上半场 4=加时下半场），对齐安卓 DisplayMatchClockState.footballHalf
    var footballHalf: Int? = nil
    /// 当前半场时长（毫秒），足球专用
    var footballHalfLengthMs: Int64? = nil
    /// 补时目标时长（毫秒），足球专用
    var footballInjuryTargetMs: Int64? = nil
    /// 兼容安卓/鸿蒙的补时文案字段；计时 UI 仍优先由数值锚点计算。
    var injuryTimeText: String? = nil

    func projectedMilliseconds(atWallClockMilliseconds now: Int64) -> Int64 {
        guard isRunning else { return elapsedMilliseconds }
        let delta = max(0, now - anchorWallClockMilliseconds)
        if countsDown {
            return max(0, elapsedMilliseconds - delta)
        }
        return elapsedMilliseconds + delta
    }
}

struct ScoreboardDisplayRest: Codable, Equatable, Sendable {
    var kind: String
    var phase: String
    var remainingSeconds: Int
    var isRunning: Bool
    var updatedWallClockMilliseconds: Int64
    var sport: String? = nil
    var afterAction: String? = nil
    var revision: Int64? = nil
    var title: String? = nil

    func projectedRemainingSeconds(atWallClockMilliseconds now: Int64) -> Int {
        guard isRunning else { return remainingSeconds }
        let elapsedSeconds = max(0, now - updatedWallClockMilliseconds) / 1_000
        return max(0, remainingSeconds - Int(elapsedSeconds))
    }
}

struct ScoreboardDisplayState: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int = Self.schemaVersion
    var gameType: String
    var orientation: ScoreboardDisplayOrientation
    var layoutKind: ScoreboardDisplayLayoutKind
    var teams: [ScoreboardDisplayTeam]
    var matchTitle: String? = nil
    var players: [ScoreboardDisplayPlayer]? = nil
    var sportState: [String: ScoreboardDisplayValue]? = nil
    var appearance: ScoreboardDisplayAppearance
    var result: ScoreboardDisplayResult? = nil
    var updatedAt: UInt64
    var keyPoint: ScoreboardDisplayKeyPoint? = nil
    var clock: ScoreboardDisplayClock? = nil
    var rest: ScoreboardDisplayRest? = nil

    func sportString(_ key: String) -> String? { sportState?[key]?.stringValue }
    func sportInt(_ key: String) -> Int? { sportState?[key]?.intValue }

    func displayScore(forVisualIndex index: Int) -> String {
        if let override = sportString(index == 0 ? "leftDisplayScore" : "rightDisplayScore") {
            return override
        }
        guard teams.indices.contains(index) else { return "0" }
        return "\(teams[index].score)"
    }

    func detail(forVisualIndex index: Int) -> String? {
        sportString(index == 0 ? "leftDetail" : "rightDetail")
    }
}

extension ScoreboardDisplayLayoutKind {
    static func resolve(gameID: String, playerCount: Int = 2, requested: ScoreboardDisplayLayoutKind? = nil) -> Self {
        if let requested { return requested }
        switch gameID {
        case "pingpong_doubles", "badminton_doubles", "tennis_doubles", "pickleball_doubles", "foosball_doubles", "padel":
            return .doublesCourt
        case "uno", "multi_scoreboard":
            return .multiGrid
        case "guandan", "shengji", "doudizhu", "xiangqi", "go", "chess", "checkers":
            return .boardCard
        case "counter":
            return .trainingCounter
        case "basketball_training":
            return .shotTrainingGrid
        case "nine_ball" where playerCount > 2:
            return .multiGrid
        default:
            return .twoSide
        }
    }
}
