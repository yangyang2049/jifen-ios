import XCTest
import SwiftUI
import UIKit
@testable import jifen

/// 多人计分投屏分页：人数边界、末页空位、横竖屏差异、锚点夹取与协议完整性。
final class MultiScoreDisplayPagingTests: XCTestCase {
    @MainActor
    func testEverySolidColorSurvivesWireAndRendersLastPagePlaceholders() async throws {
        let outputs = ScoreboardDisplayOutputs.shared
        let oldAnchor = outputs.localMultiScoreAnchorPlayer
        let size = CGSize(width: 900, height: 600)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: ScoreboardExternalDisplayRootView())
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
            outputs.setLocalMultiScoreAnchorPlayer(oldAnchor)
        }
        for color in MultiScoreboardStyle.SolidColor.allCases {
            var source = multiScoreState(count: 50)
            let style = MultiScoreboardStyle(mode: .solid, solidColor: color)
            source.appearance.style = style.displayStyle(appearance: source.appearance, players: try XCTUnwrap(source.players))
            let encoded = try XCTUnwrap(DisplayStateWireCodec.encode(source))
            let state = try XCTUnwrap(DisplayStateWireCodec.decode(encoded))
            XCTAssertEqual(state.players?.count, 50)
            XCTAssertEqual(state.appearance.style?.panels.count, 50)
            XCTAssertEqual(state.appearance.style?.renderColor("mainScore", slot: "player_49"), "#" + style.foregroundHex)
            let owner = "solid-projection-" + UUID().uuidString
            let lease = outputs.bind(ownerID: owner, initial: state)
            defer { outputs.release(ownerID: owner, leaseID: lease) }
            let rgb = stride(from: 0, to: 6, by: 2).map { offset in
                Int(color.hex.dropFirst(offset).prefix(2), radix: 16)!
            }
            for anchor in [0, 45] {
                outputs.setLocalMultiScoreAnchorPlayer(anchor)
                try await Task.sleep(for: .milliseconds(100))
                host.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let cg = try XCTUnwrap(image.cgImage)
                for point in [CGPoint(x: 10, y: 10), CGPoint(x: 890, y: 590)] {
                    var pixel = [UInt8](repeating: 0, count: 4)
                    try pixel.withUnsafeMutableBytes { bytes in
                        let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        context.draw(cg, in: CGRect(x: -point.x, y: -point.y, width: size.width, height: size.height))
                    }
                    for channel in 0..<3 {
                        XCTAssertEqual(Int(pixel[channel]), rgb[channel], accuracy: 3, "\(color.rawValue)/\(anchor)/\(point)")
                    }
                }
                if color == .paper || color == .ink {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "projection_\(color.rawValue)_\(anchor)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    func testLocalProjectionRendersNewPageWithoutAnyScorePublication() async throws {
        let outputs = ScoreboardDisplayOutputs.shared
        let oldAnchor = outputs.localMultiScoreAnchorPlayer
        var state = multiScoreState(count: 50)
        state.players = state.players?.enumerated().map { index, player in
            var value = player
            value.color = index < 15 ? "#FF0000" : "#0000FF"
            return value
        }
        let owner = "projection-regression-" + UUID().uuidString
        let lease = outputs.bind(ownerID: owner, initial: state)
        outputs.setLocalMultiScoreAnchorPlayer(0)
        let size = CGSize(width: 900, height: 600)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: ScoreboardExternalDisplayRootView())
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
            outputs.release(ownerID: owner, leaseID: lease)
            outputs.setLocalMultiScoreAnchorPlayer(oldAnchor)
        }
        func panelRGB() throws -> [UInt8] {
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let cg = try XCTUnwrap(image.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: -10, y: -10, width: size.width, height: size.height))
            }
            return pixel
        }
        try await Task.sleep(for: .milliseconds(100))
        let first = try panelRGB()
        XCTAssertGreaterThan(first[0], 200, "First projection page must show the red first 15 players")
        XCTAssertLessThan(first[2], 30)
        outputs.setLocalMultiScoreAnchorPlayer(15)
        try await Task.sleep(for: .milliseconds(100))
        let next = try panelRGB()
        XCTAssertLessThan(next[0], 30)
        XCTAssertGreaterThan(next[2], 200, "@ObservedObject must redraw the existing root on anchor-only changes")
        XCTAssertEqual(outputs.displayState, state, "Paging must not publish or trim the score snapshot")
    }

    func testTenToFifteenPlayersFitFiveColumnsOnASinglePage() {
        let ten = MultiScoreDisplayPaging.grid(playerCount: 10, landscape: true, anchorPlayer: 0)
        XCTAssertEqual(ten.columns, 5)
        XCTAssertEqual(ten.rows, 2)
        XCTAssertEqual(ten.page.pageCount, 1)
        XCTAssertEqual(ten.page.count, 10)
        XCTAssertEqual(ten.seats.compactMap { $0 }, Array(0..<10))

        for count in 11...15 {
            let grid = MultiScoreDisplayPaging.grid(playerCount: count, landscape: true, anchorPlayer: 0)
            XCTAssertEqual(grid.columns, 5, "\(count)")
            XCTAssertEqual(grid.rows, 3, "\(count)")
            XCTAssertEqual(grid.page.pageCount, 1, "\(count)")
            XCTAssertEqual(grid.seats.compactMap { $0 }, Array(0..<count), "\(count)")
        }
    }

    func testFiftyPlayersSplitIntoFifteenPlusFifteenPlusFifteenPlusFive() {
        let first = MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: 0)
        XCTAssertEqual(first.pageCount, 4)
        XCTAssertEqual(first.capacity, 15)

        let counts = (0..<first.pageCount).map { index in
            MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: index * first.capacity).count
        }
        XCTAssertEqual(counts, [15, 15, 15, 5])

        let last = MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: 49)
        XCTAssertEqual(last.page, 3)
        XCTAssertEqual(last.start, 45)
        XCTAssertEqual(last.count, 5)
    }

    func testLastPageKeepsTheSameGridWithBlankSeatPlaceholders() {
        let grid = MultiScoreDisplayPaging.grid(playerCount: 50, landscape: true, anchorPlayer: 45)
        XCTAssertEqual(grid.columns, 5)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.seats.count, 15)
        XCTAssertEqual(grid.seats.compactMap { $0 }, [45, 46, 47, 48, 49])
        XCTAssertEqual(grid.seats.filter { $0 == nil }.count, 10)
    }

    func testEveryPlayerAppearsExactlyOnceAcrossPages() {
        for count in 10...50 {
            for landscape in [false, true] {
                let first = MultiScoreDisplayPaging.grid(playerCount: count, landscape: landscape, anchorPlayer: 0)
                var seats: [Int] = []
                for index in 0..<first.page.pageCount {
                    let grid = MultiScoreDisplayPaging.grid(
                        playerCount: count,
                        landscape: landscape,
                        anchorPlayer: index * first.page.capacity
                    )
                    XCTAssertEqual(grid.columns, first.columns, "\(count)/\(landscape)")
                    XCTAssertEqual(grid.rows, first.rows, "\(count)/\(landscape)")
                    XCTAssertEqual(grid.seats.count, first.columns * first.rows, "\(count)/\(landscape)")
                    seats += grid.seats.compactMap { $0 }
                }
                XCTAssertEqual(seats, Array(0..<count), "\(count)/\(landscape)")
            }
        }
    }

    func testReceiverPortraitPacksNineAndLandscapePacksFifteen() {
        let portrait = MultiScoreDisplayPaging.grid(playerCount: 50, landscape: false, anchorPlayer: 0)
        XCTAssertEqual(portrait.page.capacity, 9)
        XCTAssertEqual(portrait.page.pageCount, 6)
        XCTAssertEqual(portrait.columns, 3)
        XCTAssertEqual(portrait.rows, 3)
        XCTAssertEqual(portrait.seats.count, 9)
        XCTAssertEqual(portrait.seats.compactMap { $0 }, Array(0..<9))

        let landscape = MultiScoreDisplayPaging.grid(playerCount: 50, landscape: true, anchorPlayer: 0)
        XCTAssertEqual(landscape.page.capacity, 15)
        XCTAssertEqual(landscape.page.pageCount, 4)
        XCTAssertEqual(landscape.columns, 5)
        XCTAssertEqual(landscape.rows, 3)
        XCTAssertEqual(landscape.seats.count, 15)

        // 竖屏 50 人第 6 屏只剩 45–49 五人，格子尺寸不变。
        let lastPortrait = MultiScoreDisplayPaging.grid(playerCount: 50, landscape: false, anchorPlayer: 45)
        XCTAssertEqual(lastPortrait.page.start, 45)
        XCTAssertEqual(lastPortrait.page.count, 5)
        XCTAssertEqual(lastPortrait.seats.compactMap { $0 }, [45, 46, 47, 48, 49])
    }

    func testAnchorOutsideTheRosterClampsToTheFirstOrLastPage() {
        XCTAssertEqual(MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: -10).page, 0)
        XCTAssertEqual(MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: -10).start, 0)

        let overflowLandscape = MultiScoreDisplayPaging.page(playerCount: 50, landscape: true, anchorPlayer: Int.max)
        XCTAssertEqual(overflowLandscape.page, 3)
        XCTAssertEqual(overflowLandscape.start, 45)
        XCTAssertEqual(overflowLandscape.count, 5)

        let overflowPortrait = MultiScoreDisplayPaging.page(playerCount: 50, landscape: false, anchorPlayer: Int.max)
        XCTAssertEqual(overflowPortrait.page, 5)
        XCTAssertEqual(overflowPortrait.start, 45)

        let empty = MultiScoreDisplayPaging.page(playerCount: 0, landscape: true, anchorPlayer: 0)
        XCTAssertEqual(empty.pageCount, 1)
        XCTAssertEqual(empty.page, 0)
        XCTAssertEqual(empty.count, 0)
    }

    func testAnchorStaysOnItsPageAfterRotation() {
        for anchor in 0..<50 {
            for landscape in [false, true] {
                let page = MultiScoreDisplayPaging.page(playerCount: 50, landscape: landscape, anchorPlayer: anchor)
                XCTAssertTrue(
                    (page.start ..< page.start + page.count).contains(anchor),
                    "anchor=\(anchor) landscape=\(landscape)"
                )
            }
        }
    }

    func testThreeToNinePlayersStayOnASinglePageWithTheLegacyLayout() {
        for count in 3...9 {
            for landscape in [false, true] {
                let grid = MultiScoreDisplayPaging.grid(playerCount: count, landscape: landscape, anchorPlayer: 0)
                XCTAssertEqual(grid.page.pageCount, 1, "\(count)/\(landscape)")
                XCTAssertEqual(grid.page.start, 0)
                XCTAssertEqual(grid.page.count, count)
            }
            XCTAssertFalse(
                MultiScoreDisplayPaging.usesPaging(gameType: "multi_scoreboard", playerCount: count),
                "\(count)"
            )
        }
    }

    func testOnlyMultiScoreboardsBeyondNinePlayersPage() {
        XCTAssertTrue(MultiScoreDisplayPaging.usesPaging(gameType: "multi_scoreboard", playerCount: 10))
        XCTAssertTrue(MultiScoreDisplayPaging.usesPaging(gameType: "multi_scoreboard", playerCount: 50))
        XCTAssertFalse(MultiScoreDisplayPaging.usesPaging(gameType: "multi_scoreboard", playerCount: 9))
        XCTAssertFalse(MultiScoreDisplayPaging.usesPaging(gameType: "uno", playerCount: 50))
        XCTAssertFalse(MultiScoreDisplayPaging.usesPaging(gameType: "nine_ball", playerCount: 50))
        XCTAssertFalse(MultiScoreDisplayPaging.usesPaging(gameType: "multi_scoreboard", playerCount: 50, cardStyle: true))
    }

    func testFiftyPlayerRosterIsNeverTrimmedAndPagingNeverEntersTheWire() throws {
        let state = multiScoreState(count: 50)
        XCTAssertEqual(state.players?.count, 50)

        let encoded = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let players = try XCTUnwrap(encoded["players"] as? [[String: Any]])
        XCTAssertEqual(players.count, 50)
        XCTAssertEqual(players.first?["name"] as? String, "玩家1")
        XCTAssertEqual(players.last?["name"] as? String, "玩家50")

        // 页码/锚点只是本机视图窗口：协议里不出现任何分页字段。
        let wireKeys = encoded.keys.map { $0.lowercased() }
        XCTAssertTrue(wireKeys.filter { $0.contains("page") || $0.contains("anchor") }.isEmpty, "\(wireKeys)")

        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(encoded))
        XCTAssertEqual(decoded.players?.count, 50)

        // 逐屏渲染只挑选窗口内的全局席位，不会改动完整名单。
        for anchor in stride(from: 0, to: 50, by: 15) {
            let grid = MultiScoreDisplayPaging.grid(
                playerCount: decoded.players?.count ?? 0,
                landscape: true,
                anchorPlayer: anchor
            )
            XCTAssertTrue(grid.seats.compactMap { $0 }.allSatisfy { (0..<50).contains($0) })
        }
        XCTAssertEqual(decoded.players?.count, 50)
    }

    private func multiScoreState(count: Int) -> ScoreboardDisplayState {
        ScoreboardDisplayState(
            gameType: "multi_scoreboard",
            orientation: .portrait,
            layoutKind: .multiGrid,
            // 多人计分板的队伍只是历史占位，但 wire 解码要求至少一队才认这一帧。
            teams: [ScoreboardDisplayTeam(id: "team_0", name: "多人计分", score: 0, order: 0)],
            players: (0..<count).map { index in
                ScoreboardDisplayPlayer(
                    id: "player_\(index)",
                    name: "玩家\(index + 1)",
                    score: index,
                    order: index,
                    color: nil
                )
            },
            appearance: ScoreboardDisplayAppearance(
                theme: "default",
                fontCode: "default",
                backgroundHex: "#111827",
                foregroundHex: "#FFFFFF",
                leftPanelHex: "#1F2937",
                rightPanelHex: "#1F2937",
                centerPanelHex: "#1F2937",
                leftTextHex: "#FFFFFF",
                rightTextHex: "#FFFFFF",
                centerTextHex: "#FFFFFF"
            ),
            updatedAt: 1
        )
    }
}
