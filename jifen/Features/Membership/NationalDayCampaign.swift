import Foundation
import StoreKit

// 国庆会员活动（对齐安卓 NationalDayCampaignPolicy / NationalDayCampaignPrompt）：
// 一次有日期的节日优惠，时间统一换算成北京时间，与设备时区无关；
// 只有服务端/StoreKit 真实购买结果才能解锁成功态。

nonisolated enum NationalDayCampaignPolicy {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static let minimumReshowInterval: TimeInterval = 72 * 60 * 60

    /// 活动窗口：2026-10-01 00:00（含）至 2026-10-08 00:00（不含），按北京时间。
    static func isActive(
        now: Date = Date(),
        calendar: Calendar = NationalDayCampaignPolicy.beijingCalendar
    ) -> Bool {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let endExclusive = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))!
        return now >= start && now < endExclusive
    }

    static func day(now: Date = Date(), calendar: Calendar = beijingCalendar) -> String {
        calendar.dateComponents([.year, .month, .day], from: now).description
    }

    static func shouldOffer(
        now: Date = Date(),
        lastShownAt: Date?,
        isLifetimeMember: Bool,
        purchaseAvailable: Bool,
        hasPendingOrder: Bool = false,
        calendar: Calendar = NationalDayCampaignPolicy.beijingCalendar
    ) -> Bool {
        guard isActive(now: now, calendar: calendar) else { return false }
        if let lastShownAt {
            guard now >= lastShownAt, now.timeIntervalSince(lastShownAt) >= minimumReshowInterval else {
                return false
            }
        }
        return !isLifetimeMember && purchaseAvailable && !hasPendingOrder
    }

    static var beijingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// 展示频次持久化（对齐安卓 NationalDayCampaignPrompt）：
/// 先落盘再展示，Activity/进程重建都不会重复弹出；重启不重置。
@MainActor
final class NationalDayCampaignPrompt {
    static let shared = NationalDayCampaignPrompt()

    private static let lastShownKey = "national_day_2026_last_shown_at"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastShownAt: Date? {
        let value = defaults.double(forKey: Self.lastShownKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    func wasShownToday(now: Date = Date()) -> Bool {
        guard let lastShownAt else { return false }
        if lastShownAt >= now { return true }
        return NationalDayCampaignPolicy.day(now: lastShownAt) == NationalDayCampaignPolicy.day(now: now)
    }

    /// 展示前先持久化；只有通过 72 小时冷却检查才返回 true。
    func reserve(now: Date = Date()) -> Bool {
        guard NationalDayCampaignPolicy.shouldOffer(
            now: now,
            lastShownAt: lastShownAt,
            isLifetimeMember: false,
            purchaseAvailable: true
        ) else { return false }
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastShownKey)
        return true
    }
}

/// 展示资格门控（iOS 侧补充规则）：
/// 活动文案为简体中文，只有设备首选语言是简体中文时才展示；其余语言设备完全无感。
nonisolated enum NationalDayCampaignGate {
    static func deviceUsesSimplifiedChinese(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bool {
        guard let first = preferredLanguages.first else { return false }
        return first.hasPrefix("zh-Hans") || first.hasPrefix("zh_CN")
    }
}

@MainActor
enum NationalDayCampaignReviewGate {
    /// 活动优先于评分邀请（对齐安卓）：活动展示当天不再弹评分邀请；
    /// 今天即将展示（未展示但符合基础资格）也先跳过，避免评分与活动两弹叠加。
    static func blocksReviewToday(now: Date = Date()) -> Bool {
        guard NationalDayCampaignGate.deviceUsesSimplifiedChinese() else { return false }
        guard NationalDayCampaignPolicy.isActive(now: now) else { return false }
        let prompt = NationalDayCampaignPrompt.shared
        if prompt.wasShownToday(now: now) { return true }
        guard AppStore.canMakePayments, !SessionStore.shared.isVIP else { return false }
        return NationalDayCampaignPolicy.shouldOffer(
            now: now,
            lastShownAt: prompt.lastShownAt,
            isLifetimeMember: false,
            purchaseAvailable: true
        )
    }
}
