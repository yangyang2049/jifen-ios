//
//  MultiScorePaging.swift
//  jifen
//
//  手机端多人计分分页布局（对齐安卓 MultiScoreGrid / multiScorePageLayout）。
//  3～9 人保持原布局与手势；超过 9 人进入分页视图，页码只改变视图，
//  不裁剪玩家、分数或记录。
//

import CoreGraphics

struct MultiScorePageLayout: Equatable {
    let capacity: Int
    let page: Int
    let pageCount: Int
    let start: Int
    let count: Int
    /// 全局席位索引（非本页局部索引）；nil 表示固定空位。
    let rows: [[Int?]]
    let paginated: Bool
    let totalCount: Int
}

/// Distribute the top safe area outside the equal-sized content of each row.
/// The first row's background still extends to the top of the screen.
struct MultiScoreGridGeometry {
    let contentSize: CGSize
    let topInset: CGFloat

    init(size: CGSize, topInset: CGFloat) {
        self.topInset = min(max(0, topInset), max(0, size.height - 1))
        contentSize = CGSize(width: size.width, height: max(1, size.height - self.topInset))
    }

    func rowHeight(at index: Int, rowCount: Int) -> CGFloat {
        contentSize.height / CGFloat(max(1, rowCount)) + (index == 0 ? topInset : 0)
    }
}

enum MultiScorePaging {
    /// 超过该人数进入分页视图（与安卓 3～9 保持原布局一致）。
    static let pageThreshold = 9
    /// 大窗口（平板 / 分屏）按可用短边判定，与安卓 / 鸿蒙同一阈值。
    static let largeWindowShortSide: CGFloat = 600

    /// UNO 共用计分页，但 10 人仍保留原有整页布局与左滑撤销。
    static func usesPaging(gameType: GameType, playerCount: Int) -> Bool {
        gameType == .multiScoreboard && playerCount > pageThreshold
    }

    static func allowsSwipeUndo(gameType: GameType, playerCount: Int) -> Bool {
        !usesPaging(gameType: gameType, playerCount: playerCount)
    }

    static func layout(
        gameType: GameType = .multiScoreboard,
        playerCount: Int,
        landscape: Bool,
        size: CGSize,
        anchorPlayer: Int
    ) -> MultiScorePageLayout {
        let safeCount = max(1, playerCount)
        guard usesPaging(gameType: gameType, playerCount: playerCount) else {
            let rows = ScoreboardPlayerGridLayout.multiRows(
                playerCount: safeCount,
                usesWideLayout: landscape
            )
            return MultiScorePageLayout(
                capacity: safeCount,
                page: 0,
                pageCount: 1,
                start: 0,
                count: safeCount,
                rows: rows,
                paginated: false,
                totalCount: safeCount
            )
        }

        let grid = columnRowCount(
            playerCount: safeCount,
            landscape: landscape,
            size: size
        )
        let capacity = max(1, grid.columns * grid.rows)
        let pageCount = ceilDiv(safeCount, capacity)
        let clampedAnchor = min(max(0, anchorPlayer), safeCount - 1)
        let page = min(clampedAnchor / capacity, max(0, pageCount - 1))
        let start = page * capacity
        let count = min(capacity, safeCount - start)
        let rows: [[Int?]] = (0 ..< grid.rows).map { row in
            (0 ..< grid.columns).map { column in
                let index = start + row * grid.columns + column
                return index < safeCount ? index : nil
            }
        }
        return MultiScorePageLayout(
            capacity: capacity,
            page: page,
            pageCount: pageCount,
            start: start,
            count: count,
            rows: rows,
            paginated: true,
            totalCount: safeCount
        )
    }

    /// 固定列数口径（与安卓 / 鸿蒙一致）：横屏恒 5 列、竖屏恒 3 列。
    /// 手机横屏 5×2（10/页）、竖屏 3×3（9/页）；平板 / 大窗口 5×3（15/页）、3×3（9/页），
    /// 与投屏 / 接收端同一套 5 和 3。大窗口不再自适应算列数（曾最多 8 列）。
    static func columnRowCount(
        playerCount: Int,
        landscape: Bool,
        size: CGSize
    ) -> (columns: Int, rows: Int) {
        guard size.width > 0, size.height > 0 else {
            return landscape ? (5, 2) : (3, 3)
        }
        if min(size.width, size.height) >= largeWindowShortSide {
            return landscape ? (5, 3) : (3, 3)
        }
        return landscape ? (5, 2) : (3, 3)
    }

    /// 字号与实际分数区域共用同一高度，分页圆点的净空必须在排版前扣除。
    static func scoreContentSize(_ cellSize: CGSize, bottomInset: CGFloat) -> CGSize {
        CGSize(width: cellSize.width, height: max(1, cellSize.height - max(0, bottomInset)))
    }

    static func ceilDiv(_ value: Int, _ divisor: Int) -> Int {
        guard divisor > 0 else { return value }
        return (value + divisor - 1) / divisor
    }
}
