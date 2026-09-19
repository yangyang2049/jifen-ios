import StoreKit
import SwiftUI

// 对齐安卓 MembershipCenterScreen（AccountMembershipScreens.kt）：
// Hero 头部 → VIP 时横幅 + 身份面板 → 权益标题 + 权益列表 → 方案卡 → 底部购买栏。
/// 方案类型（对齐鸿蒙 VipPage：月/年并排一行，终身独占一行）。
enum MembershipPlanKind {
    case monthly
    case yearly
    case lifetime
}

struct MembershipView: View {
    @Environment(SessionStore.self) private var session
    @State private var manager = StoreKitPurchaseManager.shared
    @State private var acceptedTerms = false
    @State private var agreementHint = false
    @State private var selectedProductID = StoreKitPurchaseManager.lifetimeProductID
    @State private var showLoginSheet = false
    @State private var agreementPage: MembershipAgreementPage?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                    .padding(.bottom, 18)

                if isVIP {
                    activeBanner
                    identityPanel
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }

                sectionTitle(
                    NSLocalizedString("vip_features_title", value: "会员专属权益", comment: "")
                )
                .padding(.bottom, 8)

                featureList
                    .padding(.bottom, 10)

                if !isVIP {
                    planCards
                }

                #if STAGING
                Text(NSLocalizedString("membership_staging_note", value: "当前为 Staging：本地 StoreKit 交易通过隔离测试接口授予测试会员，不代表 App Store 正式链路成功。", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                #endif
            }
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, isVIP ? 24 : 16)
            .frame(maxWidth: Theme.meTabContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("membership_title", value: "会员", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            // 商品读取完成后再显示开通栏，避免 Loading 期间出现不可用的购买按钮。
            if !isVIP && !manager.products.isEmpty {
                purchaseBottomBar
            }
        }
        .task {
            await manager.loadProducts()
            await session.reloadProfile()
        }
        .navigationDestination(item: $agreementPage) { page in
            MembershipAgreementWebPage(page: page)
        }
        .sheet(isPresented: $showLoginSheet) {
            AccountLoginSheet()
        }
    }

    private var isVIP: Bool { session.isVIP }

    /// 商品按 月 → 年 → 终身 排序。
    private var orderedProducts: [Product] {
        manager.products.sorted {
            planOrder($0.id) < planOrder($1.id)
        }
    }

    private func planOrder(_ id: String) -> Int {
        switch id {
        case StoreKitPurchaseManager.monthlyProductID: return 0
        case StoreKitPurchaseManager.yearlyProductID: return 1
        default: return 2
        }
    }

    private func planKind(for id: String) -> MembershipPlanKind {
        switch id {
        case StoreKitPurchaseManager.monthlyProductID: return .monthly
        case StoreKitPurchaseManager.yearlyProductID: return .yearly
        default: return .lifetime
        }
    }

    private func productForPlan(_ kind: MembershipPlanKind) -> Product? {
        orderedProducts.first { planKind(for: $0.id) == kind }
    }

    private var selectedProduct: Product? {
        orderedProducts.first { $0.id == selectedProductID } ?? orderedProducts.first
    }

    /// 当前选中的是否为自动续订商品（月卡/年卡），决定协议行是否包含自动续费条款。
    private var isSubscriptionSelected: Bool {
        guard let id = selectedProduct?.id else { return false }
        return planKind(for: id) != .lifetime
    }

    // MARK: - Hero（对齐安卓 MembershipHeroHeader）

    private var heroHeader: some View {
        VStack(spacing: 0) {
            AppLogoImage(size: 50)
            Text(NSLocalizedString("vip_title", value: "全能计分器 VIP", comment: ""))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text(isVIP
                ? NSLocalizedString("vip_subtitle_active", value: "已解锁全部会员专属功能", comment: "")
                : NSLocalizedString("vip_subtitle", value: "成为会员，解锁更完整的计分体验", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - VIP 横幅 + 身份面板（对齐安卓 MembershipActiveBanner / MembershipIdentityPanel）

    private var activeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accentColor)
                .frame(width: 16, height: 16)
            Text(NSLocalizedString("vip_already_member", value: "您已是 VIP 会员", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentColor.opacity(0.12)))
    }

    private var identityPanel: some View {
        // 服务端已有有效会员时优先展示账号资料；否则即使已登录，当前 VIP 也来自
        // Apple ID 本地权益，不能显示成“VIP / 未开通”的矛盾状态。
        VStack(spacing: 10) {
            if session.user?.isVIP == true {
                authenticatedIdentityRows
            } else {
                localEntitlementIdentityRows
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))
    }

    @ViewBuilder
    private var authenticatedIdentityRows: some View {
        let membership = session.user?.membership
        identityRow(
            label: NSLocalizedString("membership_current_identity", value: "当前身份", comment: ""),
            value: membership?.identitySummary.nilIfBlank
                ?? NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: ""),
            valueColor: Theme.textPrimary,
            valueSize: 13
        )
        if let code = membership?.displayCode.nilIfBlank {
            identityRow(
                label: membership?.numberLabel.nilIfBlank
                    ?? NSLocalizedString("me_profile_membership_number_label", value: "会员编号", comment: ""),
                value: code,
                valueColor: Theme.accentColor,
                valueSize: 14
            )
        }
        identityRow(
            label: NSLocalizedString("membership_valid_until", value: "有效期至", comment: ""),
            value: validUntilText,
            valueColor: Theme.textPrimary,
            valueSize: 13
        )
    }

    @ViewBuilder
    private var localEntitlementIdentityRows: some View {
        identityRow(
            label: NSLocalizedString("membership_current_identity", value: "当前身份", comment: ""),
            value: NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: ""),
            valueColor: Theme.textPrimary,
            valueSize: 13
        )
        identityRow(
            label: NSLocalizedString("membership_valid_until", value: "有效期至", comment: ""),
            value: localValidUntilText,
            valueColor: Theme.textPrimary,
            valueSize: 13
        )
    }

    private var localValidUntilText: String {
        guard let expiration = manager.localEntitlementExpirationDate else {
            return NSLocalizedString("membership_expires_forever", value: "永久有效", comment: "")
        }
        return DateFormatter.localizedString(from: expiration, dateStyle: .medium, timeStyle: .none)
    }

    private func identityRow(label: String, value: String, valueColor: Color, valueSize: CGFloat) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: valueSize, weight: .medium))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var validUntilText: String {
        guard let membership = session.user?.membership else {
            return NSLocalizedString("membership_status_not_open", value: "未开通", comment: "")
        }
        if let expiresAt = membership.expiresAt?.nilIfBlank {
            if let date = APIDateParser.date(from: expiresAt) {
                return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
            }
            if expiresAt.count >= 10 {
                return String(expiresAt.prefix(10))
            }
            return expiresAt
        }
        return NSLocalizedString("membership_expires_forever", value: "永久有效", comment: "")
    }

    // MARK: - 权益标题 / 列表（对齐安卓 MembershipSectionTitle / MembershipFeatureList）

    private func sectionTitle(_ title: String) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private var featureList: some View {
        let benefits: [(String, String)] = [
            ("vip_feature_stats", "高级统计"),
            ("vip_feature_themes", "专属主题"),
            ("vip_feature_cloud", "云端同步"),
            ("vip_feature_no_ads", "无广告体验"),
            ("vip_feature_early_access", "优先体验")
        ]
        let maxWidth: CGFloat = Locale.current.language.languageCode?.identifier == "zh" ? 170 : 250
        return HStack {
            VStack(spacing: 0) {
                ForEach(benefits, id: \.0) { key, fallback in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.accentColor)
                            .frame(width: 16, height: 16)
                        Text(NSLocalizedString(key, value: fallback, comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: maxWidth)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 方案卡（对齐安卓 AccountMembershipScreens.kt）：
    // 手机端一行一个横向卡（MembershipPlanCardHorizontal：标题/副标题在左，价格在右）；
    // 平板端月/年并排一行、终身独占一行（竖卡）。
    @ViewBuilder
    private var planCards: some View {
        if manager.products.isEmpty {
            Group {
                if manager.didLoadProducts {
                    Text(NSLocalizedString("membership_store_unavailable", value: "Apple 内购暂不可用", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                } else {
                    // 商品读取中：只显示一个大号加载指示，不暴露读取来源。
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if Theme.usesPadLayout {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let monthly = productForPlan(.monthly) {
                        planCard(monthly)
                    }
                    if let yearly = productForPlan(.yearly) {
                        planCard(yearly)
                    }
                }
                if let lifetime = productForPlan(.lifetime) {
                    planCard(lifetime)
                }
            }
            .padding(.top, 16)
        } else {
            VStack(spacing: 8) {
                if let monthly = productForPlan(.monthly) {
                    horizontalPlanCard(monthly)
                }
                if let yearly = productForPlan(.yearly) {
                    horizontalPlanCard(yearly)
                }
                if let lifetime = productForPlan(.lifetime) {
                    horizontalPlanCard(lifetime)
                }
            }
            .padding(.top, 16)
        }
    }

    /// 手机端横向方案卡（对齐安卓 MembershipPlanCardHorizontal）：
    /// 左侧标题/副标题、右侧价格，终身在价格下方显示徽标。
    private func horizontalPlanCard(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let plan = planInfo(for: product.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedProductID = product.id }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(plan.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? Theme.accentColor : Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isSelected ? Theme.accentColor : Theme.textPrimary)
                    if planKind(for: product.id) == .lifetime {
                        Text(plan.badge)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.accentColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(isSelected ? Theme.accentColor.opacity(0.12) : Theme.appCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? Theme.accentColor : Theme.divider, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let plan = planInfo(for: product.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedProductID = product.id }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(plan.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(plan.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? Theme.accentColor : Theme.textSecondary)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    Text(product.displayPrice)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isSelected ? Theme.accentColor : Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if !plan.badge.isEmpty {
                    Text(plan.badge)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 14,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 20
                            )
                            .fill(Theme.accentColor)
                        )
                }
            }
            .frame(height: 128)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(isSelected ? Theme.accentColor.opacity(0.12) : Theme.appCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? Theme.accentColor : Theme.divider, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func planInfo(for id: String) -> (title: String, subtitle: String, badge: String) {
        switch planKind(for: id) {
        case .monthly:
            return (
                NSLocalizedString("membership_monthly_plan_title", value: "月卡会员", comment: ""),
                NSLocalizedString("membership_monthly_subtitle", value: "自动续订，可随时取消", comment: ""),
                ""
            )
        case .yearly:
            return (
                NSLocalizedString("membership_yearly_plan_title", value: "年卡会员", comment: ""),
                NSLocalizedString("membership_yearly_subtitle", value: "自动续订，可随时取消", comment: ""),
                NSLocalizedString("membership_yearly_badge", value: "推荐", comment: "")
            )
        case .lifetime:
            return (
                NSLocalizedString("membership_lifetime_plan_title", value: "终身会员", comment: ""),
                NSLocalizedString("vip_one_time_purchase", value: "一次性购买，永久有效", comment: ""),
                NSLocalizedString("membership_lifetime_badge", value: "终身", comment: "")
            )
        }
    }

    // MARK: - 底部购买栏（对齐安卓 MembershipPurchaseBottomBar）

    private var purchaseBottomBar: some View {
        VStack(spacing: 0) {
            if let message = manager.message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(messageColor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            purchaseButton

            agreementRow
                .padding(.top, 10)

            // 登录完全可选（Guideline 5.1.1(v)）：只说明登录带来的跨设备同步能力，不阻断购买。
            if !session.isAuthenticated {
                HStack(spacing: 6) {
                    Text(NSLocalizedString(
                        "vip_optional_sign_in_hint",
                        value: "登录后可在你的其他设备上同步会员权益",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    Button(NSLocalizedString("account_login_title", value: "登录", comment: "")) {
                        showLoginSheet = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }

            Button {
                Task { await manager.restorePurchases() }
            } label: {
                Text(NSLocalizedString("membership_restore", value: "恢复购买", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .underline()
            }
            .disabled(isBusy)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: Theme.meTabContentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Theme.cardBackground)
                .overlay(alignment: .top) { Theme.divider.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var purchaseButton: some View {
        Button {
            Task { await startPurchase() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                    Text(NSLocalizedString("vip_purchasing", value: "购买中...", comment: ""))
                } else {
                    Text(NSLocalizedString("vip_buy_now", value: "立即开通", comment: ""))
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(Theme.accentColor.opacity(isBusy ? 0.48 : 1)))
        }
        .disabled(isBusy)
    }

    /// 协议行（对齐安卓/鸿蒙 VipPage）：
    /// 月卡/年卡 → 已阅读并同意《自动续费服务条款》《会员协议》；终身 → 已阅读并同意《会员协议》。
    private var agreementRow: some View {
        let autoRenewURL = LegalDocuments.autoRenewalTermsURL
        let membershipURL = LegalDocuments.membershipAgreementURL
        let linkFont = Font.system(size: 13, weight: .medium)

        var text = AttributedString(
            NSLocalizedString("vip_agreement_plain_prefix", value: "已阅读并同意", comment: "")
        )
        text.foregroundColor = Theme.textSecondary
        text.font = Font.system(size: 13)

        if isSubscriptionSelected {
            var renewLink = AttributedString(
                NSLocalizedString("vip_auto_renew_terms_link", value: "《自动续费服务条款》", comment: "")
            )
            renewLink.link = autoRenewURL
            renewLink.foregroundColor = Theme.accentColor
            renewLink.font = linkFont
            text += renewLink
            // 中文靠《》书名号分隔；英文需要 " and " 连接两个链接。
            var separator = AttributedString(
                NSLocalizedString("vip_agreement_link_separator", value: "", comment: "")
            )
            separator.foregroundColor = Theme.textSecondary
            separator.font = Font.system(size: 13)
            text += separator
        }

        var membershipLink = AttributedString(
            NSLocalizedString("vip_membership_agreement_link", value: "《会员协议》", comment: "")
        )
        membershipLink.link = membershipURL
        membershipLink.foregroundColor = Theme.accentColor
        membershipLink.font = linkFont
        text += membershipLink

        return HStack(alignment: .center, spacing: 2) {
            Button {
                acceptedTerms.toggle()
                if acceptedTerms { agreementHint = false }
            } label: {
                Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(acceptedTerms ? Color(hex: "30D158") : Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 单行时纵向居中、与左侧勾选圈对齐（对齐安卓 AgreementRow CenterVertically）。
            Text(text)
                .lineSpacing(3)
                .environment(\.openURL, OpenURLAction { url in
                    if url == autoRenewURL {
                        agreementPage = MembershipAgreementPage(kind: .autoRenewal)
                        return .handled
                    }
                    if url == membershipURL {
                        agreementPage = MembershipAgreementPage(kind: .membership)
                        return .handled
                    }
                    return .systemAction
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if agreementHint {
                Text(agreementHintText)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.trailing)
                    .padding(.leading, 8)
            }
        }
    }

    private var agreementHintText: String {
        isSubscriptionSelected
            ? NSLocalizedString(
                "vip_agreement_subscription_hint",
                value: "请阅读并同意自动续费服务条款和会员协议",
                comment: ""
            )
            : NSLocalizedString("vip_agreement_hint", value: "请阅读并同意会员协议", comment: "")
    }

    private func startPurchase() async {
        guard let product = selectedProduct else { return }
        // Guideline 5.1.1(v)：登录不作为购买前提，未登录时由 StoreKit 直接授予权益。
        guard acceptedTerms else {
            agreementHint = true
            return
        }
        agreementHint = false
        await manager.purchase(product)
    }

    private var isBusy: Bool {
        switch manager.state {
        case .loading, .purchasing: return true
        default: return false
        }
    }

    private var messageColor: Color {
        if case .failed = manager.state { return .red }
        return Theme.textSecondary
    }
}

/// 会员协议网页（对齐安卓 LegalConfig：会员协议 / 自动续费服务条款）。
enum MembershipAgreementKind: Hashable {
    case membership
    case autoRenewal
}

struct MembershipAgreementPage: Identifiable, Hashable {
    let kind: MembershipAgreementKind
    var id: MembershipAgreementKind { kind }

    var url: URL {
        switch kind {
        case .membership: return LegalDocuments.membershipAgreementURL
        case .autoRenewal: return LegalDocuments.autoRenewalTermsURL
        }
    }

    var title: String {
        switch kind {
        case .membership:
            return NSLocalizedString("vip_membership_agreement_title", value: "会员协议", comment: "")
        case .autoRenewal:
            return NSLocalizedString("vip_auto_renew_terms_title", value: "自动续费服务条款", comment: "")
        }
    }
}

private struct MembershipAgreementWebPage: View {
    let page: MembershipAgreementPage

    var body: some View {
        AppWebView(url: page.url)
            .background(Theme.backgroundColor)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
