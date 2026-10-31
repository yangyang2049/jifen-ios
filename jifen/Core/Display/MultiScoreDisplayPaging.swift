import Foundation

/// 多人计分投屏的分页视口（对齐安卓 `display/model/MultiScoreDisplayPage.kt`）。
///
/// 它只是完整名单上的一层「当前可见窗口」：`start`/`count` 始终是原始
/// `players` 里的全局下标，分页不裁剪名单、不重排座位、不写进战绩或协议。
struct MultiScoreDisplayPage {
    let capacity: Int
    let page: Int
    let pageCount: Int
    let start: Int
    let count: Int
}

/// 分页后的整块网格：行列数与逐格全局席位（`nil` 为末页补的空位）。
///
/// 空位保留与真人格完全相同的行列尺寸，因此末页（例如 50 人的第 4 屏只剩
/// 46–50 号）不会把格子拉大，字号也不会跨页跳动。
struct MultiScoreDisplayGrid {
    let page: MultiScoreDisplayPage
    let columns: Int
    let rows: Int
    /// 行优先排列，长度恒为 `rows * columns`。
    let seats: [Int?]
}

/// 多人计分分页规则（对齐安卓 `multiScoreDisplayPage`）。
///
/// - 3–9 人：整页展示，沿用原有网格布局。
/// - 本地投屏（大屏）：每页最多 15 人，5 列；10 人为 5×2，11–15 人为 5×3，
///   50 人为 15+15+15+5。
/// - 跨设备接收端：横屏每页 15 人（5 列），竖屏每页 9 人（3 列）。
enum MultiScoreDisplayPaging {
    /// 本地投屏 / 接收端横屏：5 列 × 最多 3 行。
    static let landscapeCapacity = 15
    static let landscapeColumns = 5
    /// 接收端竖屏：3 列 × 3 行。
    static let portraitCapacity = 9
    static let portraitColumns = 3

    /// 只有超过 9 人才分页；3–9 人保持原布局。
    static let pagedPlayerCountThreshold = 10

    /// 对齐安卓 `multiScoreDisplayPage`：页码由锚点玩家推导，越界一律夹取。
    static func page(playerCount: Int, landscape: Bool, anchorPlayer: Int) -> MultiScoreDisplayPage {
        let total = max(0, playerCount)
        let capacity = capacity(landscape: landscape)
        let clampedAnchor = min(max(0, anchorPlayer), max(0, total - 1))
        let index = clampedAnchor / capacity
        let start = index * capacity
        return MultiScoreDisplayPage(
            capacity: capacity,
            page: index,
            pageCount: max(1, (total + capacity - 1) / capacity),
            start: start,
            count: min(capacity, max(0, total - start))
        )
    }

    /// 只有多人计分板超过 9 人才分页（UNO、九球、卡牌等仍走原布局）。
    static func usesPaging(gameType: String, playerCount: Int, cardStyle: Bool = false) -> Bool {
        guard !cardStyle, gameType == "multi_scoreboard" else { return false }
        return max(0, playerCount) >= pagedPlayerCountThreshold
    }

    static func capacity(landscape: Bool) -> Int {
        landscape ? landscapeCapacity : portraitCapacity
    }

    static func columns(landscape: Bool) -> Int {
        landscape ? landscapeColumns : portraitColumns
    }

    /// 行数由「第一屏能装多少人」决定，末页沿用同一行数，因此格子尺寸不变。
    static func rowCount(playerCount: Int, landscape: Bool) -> Int {
        let filled = min(max(0, playerCount), capacity(landscape: landscape))
        let columns = columns(landscape: landscape)
        return max(1, (filled + columns - 1) / columns)
    }

    /// 当前屏的完整网格，供显示端直接渲染、供单测校验全量覆盖与末页空位。
    static func grid(playerCount: Int, landscape: Bool, anchorPlayer: Int) -> MultiScoreDisplayGrid {
        let page = page(playerCount: playerCount, landscape: landscape, anchorPlayer: anchorPlayer)
        let rows = rowCount(playerCount: playerCount, landscape: landscape)
        let columns = columns(landscape: landscape)
        let seats = (page.start ..< page.start + page.count).map { Optional($0) }
        let placeholders = Array(repeating: Int?.none, count: max(0, rows * columns - seats.count))
        return MultiScoreDisplayGrid(
            page: page,
            columns: columns,
            rows: rows,
            seats: seats + placeholders
        )
    }
}