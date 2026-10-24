#if DEBUG
import SwiftUI

/// UI automation only. Production builds contain neither mock credentials nor
/// a way to bypass WeChat authorization/account-link confirmation.
@MainActor enum WechatBindingFixture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-UITestWechatBinding") }
    static let status = WechatBindingStatus(sessionProvider: "apple", providers: ["apple"],
        capabilities: .init(wechatBinding: true, accountMerge: true), wechat: .init(bound: false, canBind: true))
    static let accounts = AccountLinkAccounts(
        current: .init(id: "ui-test-user", uid: "10482", name: "杨同学", providers: ["apple"]),
        wechat: .init(id: "ui-wechat-user", uid: "20836", name: "小杨", providers: ["wechat"]))
    static func preview(mode: AccountLinkMode, master: String) -> AccountLinkPreview {
        let owner = ProcessInfo.processInfo.arguments.contains("-UITestWechatBindingOwner")
        let blocked = owner && mode == .keep && master == accounts.wechat.id
        let renewalCount = ProcessInfo.processInfo.arguments.contains("-UITestWechatBindingDualSubscriptions") ? 2
            : ProcessInfo.processInfo.arguments.contains("-UITestWechatBindingSingleSubscription") ? 1 : 0
        return AccountLinkPreview(ticket: "ui-ticket", expiresAt: "2027-01-01T00:00:00Z", mode: mode,
            masterUserId: master, previewToken: "ui-preview", accounts: accounts,
            summary: .init(groups: .init(groupCount: mode == .merge ? 4 : 2, recordCount: mode == .merge ? 21 : 9, selfMatchCount: 1),
                assets: .init(commonNameCount: mode == .merge ? 27 : 12, commonPlaceCount: 2,
                    membership: .init(tier: "vip", billingCycle: "lifetime", autoRenew: false, memberNo: "000046"),
                    automaticRenewalCount: renewalCount,
                    warnings: renewalCount > 1 ? ["双方订阅将保留各自续费状态。账号合并不会替你取消任何自动续费。"] : [])),
            blockers: blocked ? [.init(code: "OWNER_TRANSFER_REQUIRED", message: "")] : [],
            warnings: [], canConfirm: !blocked, dataScope: "cloud")
    }
}

struct WechatBindingCaptureView: View {
    @State private var presented = true
    var body: some View {
        NavigationStack { AccountCenterView() }
            .sheet(isPresented: $presented) { WechatBindingSheet() }
    }
}
#endif
