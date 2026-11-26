import XCTest
@testable import jifenWatch_Watch_App

/// 联动确认悬浮层的倒计时口径：presenter 写入 deadline 时以它为准，
/// 否则必须有一个本地兜底，不能留下 deadline == nil 时永不超时的分支。
final class WatchLinkedSetupConfirmDeadlineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testMissingPresenterDeadlineFallsBackToFirstRenderPlusTimeout() {
        let resolved = LinkedSetupConfirmDeadline.resolve(
            deadline: nil,
            startedAt: start,
            timeout: 20
        )
        XCTAssertEqual(resolved, start.addingTimeInterval(20))
    }

    func testPresenterDeadlineWinsWhenProvided() {
        let presenterDeadline = start.addingTimeInterval(5)
        let resolved = LinkedSetupConfirmDeadline.resolve(
            deadline: presenterDeadline,
            startedAt: start,
            timeout: 20
        )
        XCTAssertEqual(resolved, presenterDeadline)
    }

    func testNonPositiveTimeoutIsClampedSoTheRingStillAdvances() {
        let resolved = LinkedSetupConfirmDeadline.resolve(
            deadline: nil,
            startedAt: start,
            timeout: 0
        )
        XCTAssertEqual(resolved, start.addingTimeInterval(1))
    }

    func testStalePendingRequestResolvesToAnAlreadyExpiredDeadline() {
        // 悬浮层在请求已经 pending 很久之后才被构建：兜底 deadline 必须已经过期，
        // 这样 TimelineView 的 initial 回调会立刻走 onDecline，而不是停在满格。
        let now = start.addingTimeInterval(30)
        let resolved = LinkedSetupConfirmDeadline.resolve(
            deadline: nil,
            startedAt: start,
            timeout: 20
        )
        XCTAssertLessThan(resolved, now)
    }
}
