import XCTest
import UIKit
@testable import jifen

final class MultiScorePagingTests: XCTestCase {
    private let phonePortrait = CGSize(width: 390, height: 844)
    private let phoneLandscape = CGSize(width: 844, height: 390)
    private let largePortrait = CGSize(width: 834, height: 1112)
    private let largeLandscape = CGSize(width: 1112, height: 834)

    func testDuoPortraitSafeAreaDoesNotConsumeFirstRowScore() {
        let fullSize = CGSize(width: 669, height: 951)
        let geometry = MultiScoreGridGeometry(size: fullSize, topInset: 86)
        let layout = MultiScorePaging.layout(playerCount: 50, landscape: false,
                                            size: geometry.contentSize, anchorPlayer: 40)
        XCTAssertEqual(layout.capacity, 16, "The notch must participate in the usable grid capacity")
        let rowCount = layout.rows.count
        let firstHeight = geometry.rowHeight(at: 0, rowCount: rowCount)
        let otherHeight = geometry.rowHeight(at: 1, rowCount: rowCount)
        XCTAssertEqual(firstHeight - geometry.topInset, otherHeight, accuracy: 0.001)
        XCTAssertEqual((0..<rowCount).reduce(CGFloat.zero) {
            $0 + geometry.rowHeight(at: $1, rowCount: rowCount)
        }, fullSize.height, accuracy: 0.001)
        for score in ["2", "0", "-9999"] {
            let typography = ScoreboardTypographyResolver.resolve(.init(
                profile: .multi,
                containerSize: MultiScorePaging.scoreContentSize(
                    CGSize(width: fullSize.width / 4, height: firstHeight - geometry.topInset), bottomInset: 62),
                nameText: "Player 41", scoreText: score,
                preference: .init(font: .default, scoreMultiplier: 1, nameMultiplier: 1, secondaryMultiplier: 1),
                horizontalPadding: 12, reservedHeight: 36
            ))
            XCTAssertGreaterThanOrEqual(typography.scoreFontSize, 24, "First-row score must remain readable")
        }
        // With the former equal-height rows and safe-area reservation, this
        // actual Duo geometry reduced every first-row score to 1 point.
        let former = ScoreboardTypographyResolver.resolve(.init(
            profile: .multi,
            containerSize: MultiScorePaging.scoreContentSize(
                CGSize(width: fullSize.width / 4, height: fullSize.height / 5), bottomInset: 62),
            nameText: "Player 41", scoreText: "2",
            preference: .init(font: .default, scoreMultiplier: 1, nameMultiplier: 1, secondaryMultiplier: 1),
            horizontalPadding: 12, reservedHeight: 28 + 86 + 8
        ))
        XCTAssertEqual(former.scoreFontSize, 1, "Reproducer must exercise the observed failure")
    }

    func testFourDigitScoreTypographyAccountsForPagingClearance() {
        let size = CGSize(width: 360, height: 140)
        let available = MultiScorePaging.scoreContentSize(size, bottomInset: 20)
        XCTAssertEqual(available.height, 120)
        for score in ["1000", "-1000", "99999"] {
            let typography = ScoreboardTypographyResolver.resolve(.init(
                profile: .multi, containerSize: available, nameText: "Player", scoreText: score,
                preference: .init(font: .default, scoreMultiplier: 1.6, nameMultiplier: 1, secondaryMultiplier: 1),
                horizontalPadding: 12, reservedHeight: 20))
            let lineRatio = UIFont.systemFont(ofSize: 100, weight: .bold).lineHeight / 100
            XCTAssertLessThanOrEqual(typography.scoreFontSize * lineRatio, available.height - 20)
        }
        XCTAssertEqual(MultiScorePaging.scoreContentSize(size, bottomInset: 0), size)
    }

    func testSinglePageKeepsOriginalLayoutUpToNinePlayers() {
        for count in 3 ... 9 {
            for size in [phonePortrait, phoneLandscape, largePortrait] {
                let layout = MultiScorePaging.layout(
                    playerCount: count,
                    landscape: size.width > size.height,
                    size: size,
                    anchorPlayer: 0
                )
                XCTAssertFalse(layout.paginated, "\(count) 人应保持原布局")
                XCTAssertEqual(layout.pageCount, 1)
                XCTAssertEqual(layout.capacity, count)
                XCTAssertEqual(layout.rows.flatMap { $0 }.compactMap { $0 }.count, count)
            }
        }
    }

    func testTenPlayerUnoKeepsAllPlayersOnOnePageAndSwipeUndo() {
        for size in [phonePortrait, phoneLandscape, largePortrait, largeLandscape] {
            let landscape = size.width > size.height
            let layout = MultiScorePaging.layout(
                gameType: .uno,
                playerCount: 10,
                landscape: landscape,
                size: size,
                anchorPlayer: 9
            )
            XCTAssertFalse(layout.paginated)
            XCTAssertEqual(layout.pageCount, 1)
            XCTAssertEqual(layout.count, 10)
            XCTAssertEqual(layout.rows, ScoreboardPlayerGridLayout.multiRows(playerCount: 10, usesWideLayout: landscape))
            XCTAssertEqual(layout.rows.flatMap { $0 }.compactMap { $0 }, Array(0..<10))
        }
        XCTAssertTrue(MultiScorePaging.allowsSwipeUndo(gameType: .uno, playerCount: 10))
        XCTAssertTrue(MultiScorePaging.allowsSwipeUndo(gameType: .multiScoreboard, playerCount: 9))
        XCTAssertFalse(MultiScorePaging.allowsSwipeUndo(gameType: .multiScoreboard, playerCount: 10))
    }

    func testPortraitPhoneUsesNinePerPage() {
        let layout = MultiScorePaging.layout(
            playerCount: 50,
            landscape: false,
            size: phonePortrait,
            anchorPlayer: 0
        )
        XCTAssertTrue(layout.paginated)
        XCTAssertEqual(layout.capacity, 9)
        XCTAssertEqual(layout.pageCount, 6)
        XCTAssertEqual(layout.rows.count, 3)
        XCTAssertEqual(layout.rows.first?.count, 3)
    }

    func testLandscapePhoneUsesTenPerPage() {
        let layout = MultiScorePaging.layout(
            playerCount: 50,
            landscape: true,
            size: phoneLandscape,
            anchorPlayer: 0
        )
        XCTAssertEqual(layout.capacity, 10)
        XCTAssertEqual(layout.pageCount, 5)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertEqual(layout.rows.first?.count, 5)
    }

    func testLastPageKeepsEmptySlotsAndGlobalSeatNumbers() {
        let layout = MultiScorePaging.layout(
            playerCount: 50,
            landscape: false,
            size: phonePortrait,
            anchorPlayer: 45
        )
        XCTAssertEqual(layout.page, 5)
        XCTAssertEqual(layout.start, 45)
        XCTAssertEqual(layout.count, 5)
        let seats = layout.rows.flatMap { $0 }
        XCTAssertEqual(seats.count, 9, "末页保留固定空位")
        XCTAssertEqual(seats.compactMap { $0 }, Array(45 ..< 50))
        XCTAssertEqual(seats.filter { $0 == nil }.count, 4)
    }

    func testAnchorClampsIntoValidPage() {
        let high = MultiScorePaging.layout(
            playerCount: 20,
            landscape: false,
            size: phonePortrait,
            anchorPlayer: 999
        )
        XCTAssertEqual(high.page, 2)
        XCTAssertEqual(high.start, 18)
        XCTAssertEqual(high.count, 2)

        let negative = MultiScorePaging.layout(
            playerCount: 20,
            landscape: false,
            size: phonePortrait,
            anchorPlayer: -5
        )
        XCTAssertEqual(negative.page, 0)
        XCTAssertEqual(negative.start, 0)
    }

    func testLargeWindowUsesFewerPagesThanPhone() {
        let size = largePortrait
        let layout = MultiScorePaging.layout(
            playerCount: 50,
            landscape: false,
            size: size,
            anchorPlayer: 0
        )
        XCTAssertTrue(layout.paginated)
        XCTAssertGreaterThanOrEqual(layout.capacity, 9)
        XCTAssertLessThanOrEqual(layout.pageCount, 6)
        XCTAssertEqual(layout.rows.count * (layout.rows.first?.count ?? 0), layout.capacity)
    }

    func testRotationKeepsAnchorPlayerVisible() {
        let portrait = MultiScorePaging.layout(
            playerCount: 30,
            landscape: false,
            size: phonePortrait,
            anchorPlayer: 10
        )
        XCTAssertTrue(portrait.start <= 10 && 10 < portrait.start + portrait.capacity)

        let landscape = MultiScorePaging.layout(
            playerCount: 30,
            landscape: true,
            size: phoneLandscape,
            anchorPlayer: portrait.start
        )
        XCTAssertTrue(landscape.start <= portrait.start)
        XCTAssertEqual(landscape.rows.flatMap { $0 }.compactMap { $0 }.count, landscape.count)
    }

    func testAllRosterIndicesAppearExactlyOnceAcrossPages() {
        for count in [10, 11, 15, 16, 49, 50] {
            var seen: [Int] = []
            let probe = MultiScorePaging.layout(
                playerCount: count,
                landscape: false,
                size: phonePortrait,
                anchorPlayer: 0
            )
            for page in 0 ..< probe.pageCount {
                let layout = MultiScorePaging.layout(
                    playerCount: count,
                    landscape: false,
                    size: phonePortrait,
                    anchorPlayer: page * probe.capacity
                )
                seen.append(contentsOf: layout.rows.flatMap { $0 }.compactMap { $0 })
            }
            XCTAssertEqual(seen.sorted(), Array(0 ..< count), "\(count) 人分页不得裁剪或重复")
        }
    }
}
