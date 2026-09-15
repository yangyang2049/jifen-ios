#if DEBUG
import SwiftUI
import ScoreCore

/// 显示端批量截图 fixture（仅 DEBUG 构建）。
/// 通过 launch argument `-DisplaySnapshotFixture <name>` 启动时，跳过常规首页，
/// 直接渲染指定状态的投屏画面，供 simctl 脚本批量截图后检查布局与样式。
///
/// 与真实显示端一致的三要素：
/// 1. `ScoreboardExternalLiveView` + `.synchronizedDisplay` 投影（跨设备同步显示端同款）；
/// 2. 状态键取自 RallyScoreboardView 的真实同步快照结构
///    （team0ScreenSide / servingSide / resultScoreLevel / tableTennisTeam*Timeout*）；
/// 3. 外观取用户当前外观快照（ScoreboardAppearanceSnapshot.current）。
enum DisplaySnapshotFixture {
    static let argumentName = "-DisplaySnapshotFixture"

    static var requestedName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argumentName),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func state(named name: String) -> ScoreboardDisplayState? {
        fixtures[name]?()
    }

    private static var appearance: ScoreboardDisplayAppearance {
        ScoreboardDisplayAppearance(
            snapshot: .current(styleID: ScoreboardStyleID(scoreCoreGameType: .pingpong))
        )
    }

    private static var nowMilliseconds: Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    // MARK: - Base builders

    private static func rallyState(
        layout: ScoreboardDisplayLayoutKind,
        teams: [ScoreboardDisplayTeam],
        players: [ScoreboardDisplayPlayer]? = nil,
        sportState: [String: ScoreboardDisplayValue],
        keyPoint: ScoreboardDisplayKeyPoint? = nil,
        rest: ScoreboardDisplayRest? = nil,
        result: ScoreboardDisplayResult? = nil
    ) -> ScoreboardDisplayState {
        ScoreboardDisplayState(
            gameType: "pingpong",
            orientation: .portrait,
            layoutKind: layout,
            teams: teams,
            players: players,
            sportState: sportState,
            appearance: appearance,
            result: result,
            updatedAt: 1,
            keyPoint: keyPoint,
            rest: rest
        )
    }

    private static func singles(
        leftSets: Int = 1,
        rightSets: Int = 1,
        leftScore: Int = 7,
        rightScore: Int = 5,
        servingSide: String = "left",
        leftTimeoutUsed: Bool = false,
        rightTimeoutUsed: Bool = false,
        keyPoint: ScoreboardDisplayKeyPoint? = nil,
        rest: ScoreboardDisplayRest? = nil,
        result: ScoreboardDisplayResult? = nil
    ) -> ScoreboardDisplayState {
        rallyState(
            layout: .twoSide,
            teams: [
                .init(id: "team_0", name: "林晓东", score: leftScore, sets: leftSets, order: 0),
                .init(id: "team_1", name: "王志强", score: rightScore, sets: rightSets, order: 1)
            ],
            sportState: [
                "team0ScreenSide": .string("left"),
                "servingSide": .string(servingSide),
                "resultScoreLevel": .string("sets"),
                "tableTennisTeam0TimeoutUsed": .boolean(leftTimeoutUsed),
                "tableTennisTeam0Yellow": .boolean(false),
                "tableTennisTeam0RedCount": .integer(0),
                "tableTennisTeam1TimeoutUsed": .boolean(rightTimeoutUsed),
                "tableTennisTeam1Yellow": .boolean(false),
                "tableTennisTeam1RedCount": .integer(0)
            ],
            keyPoint: keyPoint,
            rest: rest,
            result: result
        )
    }

    private static func doubles(
        leftSets: Int = 1,
        rightSets: Int = 1,
        leftScore: Int = 6,
        rightScore: Int = 8,
        servingSide: String = "right",
        leftTimeoutUsed: Bool = false,
        rightTimeoutUsed: Bool = false,
        keyPoint: ScoreboardDisplayKeyPoint? = nil,
        rest: ScoreboardDisplayRest? = nil,
        result: ScoreboardDisplayResult? = nil
    ) -> ScoreboardDisplayState {
        let serverIsLeft = servingSide == "left"
        return rallyState(
            layout: .doublesCourt,
            teams: [
                .init(id: "team_0", name: "林晓东", score: leftScore, sets: leftSets, order: 0),
                .init(id: "team_1", name: "赵磊", score: rightScore, sets: rightSets, order: 1)
            ],
            players: [
                .init(id: "left_top", name: "林晓东", teamID: "team_0", slot: "top", order: 0, isServer: serverIsLeft),
                .init(id: "right_top", name: "赵磊", teamID: "team_1", slot: "top", order: 1, isServer: !serverIsLeft),
                .init(id: "left_bottom", name: "陈国栋", teamID: "team_0", slot: "bottom", order: 2, isServer: false),
                .init(id: "right_bottom", name: "孙浩", teamID: "team_1", slot: "bottom", order: 3, isServer: false)
            ],
            sportState: [
                "team0ScreenSide": .string("left"),
                "servingSide": .string(servingSide),
                "resultScoreLevel": .string("sets"),
                "tableTennisTeam0TimeoutUsed": .boolean(leftTimeoutUsed),
                "tableTennisTeam0Yellow": .boolean(false),
                "tableTennisTeam0RedCount": .integer(0),
                "tableTennisTeam1TimeoutUsed": .boolean(rightTimeoutUsed),
                "tableTennisTeam1Yellow": .boolean(false),
                "tableTennisTeam1RedCount": .integer(0)
            ],
            keyPoint: keyPoint,
            rest: rest,
            result: result
        )
    }

    private static func rest(
        kind: String,
        phase: String = "countdown",
        remainingSeconds: Int
    ) -> ScoreboardDisplayRest {
        ScoreboardDisplayRest(
            kind: kind,
            phase: phase,
            remainingSeconds: remainingSeconds,
            isRunning: true,
            updatedWallClockMilliseconds: nowMilliseconds,
            sport: "pingpong"
        )
    }

    private static func finishedResult(
        leftSetScore: Int,
        rightSetScore: Int
    ) -> ScoreboardDisplayResult {
        ScoreboardDisplayResult(
            ended: true,
            winnerID: leftSetScore > rightSetScore ? "team_0" : "team_1",
            finalScores: [
                "team_0": .init(score: 33, sets: leftSetScore),
                "team_1": .init(score: 25, sets: rightSetScore)
            ]
        )
    }

    // MARK: - Fixture registry

    private static let fixtures: [String: () -> ScoreboardDisplayState] = [
        // 单打：5 局 3 胜，1-1 局，当前局 7:5
        "pingpong_live": {
            singles()
        },
        // 单打：局点（下 1 分赢下本局）
        "pingpong_game_point": {
            singles(leftScore: 10, rightScore: 7, keyPoint: .init(kind: "game", side: "left"))
        },
        // 单打：赛点（2-1 局，下 1 分赢下整场）
        "pingpong_match_point": {
            singles(leftSets: 2, rightSets: 1, leftScore: 10, rightScore: 6, keyPoint: .init(kind: "match", side: "left"))
        },
        // 单打：10 平（win-by-two 阶段）
        "pingpong_deuce": {
            singles(leftScore: 10, rightScore: 10, servingSide: "right")
        },
        // 单打：暂停（timeout 倒计时 + 已用暂停标记）
        "pingpong_timeout": {
            singles(leftTimeoutUsed: true, rest: rest(kind: "timeout", remainingSeconds: 30))
        },
        // 单打：局间休息（game_break 60 秒倒计时）
        "pingpong_game_break": {
            singles(leftSets: 2, rightSets: 1, rest: rest(kind: "game_break", remainingSeconds: 60))
        },
        // 单打：比赛结束（3-1 胜）
        "pingpong_finished": {
            singles(leftSets: 3, rightSets: 1, leftScore: 11, rightScore: 8, result: finishedResult(leftSetScore: 3, rightSetScore: 1))
        },
        // 双打：局中直播（发球权在右方）
        "pingpong_doubles_live": {
            doubles()
        },
        // 双打：暂停
        "pingpong_doubles_timeout": {
            doubles(rightTimeoutUsed: true, rest: rest(kind: "timeout", remainingSeconds: 30))
        },
        // 双打：比赛结束（1-3 负，右方胜）
        "pingpong_doubles_finished": {
            doubles(leftSets: 1, rightSets: 3, result: finishedResult(leftSetScore: 1, rightSetScore: 3))
        }
    ]
}

/// `-DisplaySnapshotFixture` 命中时的根视图：黑底 + 真实投屏画面（跨设备同步投影）。
struct DisplaySnapshotFixtureView: View {
    let name: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let state = DisplaySnapshotFixture.state(named: name) {
                ScoreboardExternalLiveView(state: state, projection: .synchronizedDisplay)
                    .id("\(state.gameType)-\(state.layoutKind.rawValue)")
            } else {
                VStack(spacing: 8) {
                    Text("Unknown fixture")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Available: \(DisplaySnapshotFixture.availableNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

extension DisplaySnapshotFixture {
    static var availableNames: [String] { Array(fixtures.keys).sorted() }
}
#endif
