import XCTest
@testable import jifen

@MainActor
final class BoardTimerConfigTests: XCTestCase {
    func testAvailableModesMatchHarmony() {
        XCTAssertEqual(BoardTimerConfig.availableModes(for: .go), [.countdown, .byoyomi])
        XCTAssertEqual(BoardTimerConfig.availableModes(for: .xiangqi), [.countdown, .increment])
        XCTAssertEqual(BoardTimerConfig.availableModes(for: .chess), [.countdown, .increment, .delay])
        XCTAssertEqual(BoardTimerConfig.availableModes(for: .checkers), [.countdown, .increment])
    }

    func testDefaultConfigsMatchHarmonyFastPreset() {
        let go = BoardTimerConfig.default(for: .go)
        XCTAssertEqual(go.timeMode, .byoyomi)
        XCTAssertEqual(go.mainMinutes, 60)
        XCTAssertEqual(go.byoyomiSeconds, 30)
        XCTAssertEqual(go.byoyomiPeriods, 3)

        let xiangqi = BoardTimerConfig.default(for: .xiangqi)
        XCTAssertEqual(xiangqi.timeMode, .increment)
        XCTAssertEqual(xiangqi.mainMinutes, 10)
        XCTAssertEqual(xiangqi.incrementSeconds, 10)

        let chess = BoardTimerConfig.default(for: .chess)
        XCTAssertEqual(chess.timeMode, .increment)
        XCTAssertEqual(chess.mainMinutes, 15)
        XCTAssertEqual(chess.incrementSeconds, 10)

        let checkers = BoardTimerConfig.default(for: .checkers)
        XCTAssertEqual(checkers.timeMode, .increment)
        XCTAssertEqual(checkers.mainMinutes, 15)
        XCTAssertEqual(checkers.incrementSeconds, 10)
    }

    func testModeDefaultsFillSecondaryFields() {
        let chessDelay = BoardTimerConfig.modeDefaults(for: .chess, mode: .delay)
        XCTAssertEqual(chessDelay.timeMode, .delay)
        XCTAssertEqual(chessDelay.delaySeconds, 5)
        XCTAssertEqual(chessDelay.mainMinutes, 15)

        let goCountdown = BoardTimerConfig.modeDefaults(for: .go, mode: .countdown)
        XCTAssertEqual(goCountdown.timeMode, .countdown)
        XCTAssertEqual(goCountdown.mainMinutes, 60)
        XCTAssertEqual(goCountdown.byoyomiSeconds, 0)
    }

    func testNormalizeClampsMainTimeAndScrubsInactiveFields() {
        var config = BoardTimerConfig.default(for: .xiangqi)
        config.mainMinutes = 0
        config.mainSeconds = 10
        config.byoyomiSeconds = 99
        config.byoyomiPeriods = 9
        config.delaySeconds = 7
        config.normalize()

        XCTAssertEqual(config.timeMode, .increment)
        XCTAssertEqual(config.mainSeconds, 30)
        XCTAssertEqual(config.byoyomiSeconds, 0)
        XCTAssertEqual(config.byoyomiPeriods, 0)
        XCTAssertEqual(config.delaySeconds, 0)
        XCTAssertEqual(config.incrementSeconds, 10)
    }

    func testNormalizeDemotesWhenSecondaryValuesAreZero() {
        var go = BoardTimerConfig.default(for: .go)
        go.byoyomiSeconds = 0
        go.byoyomiPeriods = 0
        go.normalize()
        XCTAssertEqual(go.timeMode, .countdown)

        var chess = BoardTimerConfig.default(for: .chess)
        chess.timeMode = .delay
        chess.delaySeconds = 0
        chess.incrementSeconds = 0
        chess.normalize()
        XCTAssertEqual(chess.timeMode, .countdown)
    }

    func testApplyTimeModeFillsEmptySecondaryValues() {
        var chess = BoardTimerConfig.modeDefaults(for: .chess, mode: .countdown)
        chess.applyTimeMode(.delay)
        XCTAssertEqual(chess.timeMode, .delay)
        XCTAssertEqual(chess.delaySeconds, 5)

        var go = BoardTimerConfig.modeDefaults(for: .go, mode: .countdown)
        go.applyTimeMode(.byoyomi)
        XCTAssertEqual(go.timeMode, .byoyomi)
        XCTAssertEqual(go.byoyomiSeconds, 30)
        XCTAssertEqual(go.byoyomiPeriods, 3)
    }
}
