import StoreKit
import SwiftUI

// 未开通：Hero 头部 → 权益列表 → 方案卡 → 底部购买栏。
// 已开通：会员摘要卡 → 已解锁权益列表。
/// 方案类型（对齐鸿蒙 VipPage：月/年并排一行，终身独占一行）。
enum MembershipPlanKind {
    case monthly
    case yearly
    case lifetime
}

nonisolated enum MembershipSummarySource: Equatable, Sendable {
    case server
    case localStore
    case legacyServer
}

nonisolated enum MembershipSummarySourcePolicy {
    static func resolve(
        hasActiveServerMembership: Bool,
        hasLocalEntitlement: Bool
    ) -> MembershipSummarySource {
        if hasActiveServerMembership {
            return .server
        }
        if hasLocalEntitlement {
            return .localStore
        }
        return .legacyServer
    }
}

struct MembershipView: View {
    @Environment(SessionStore.self) private var session
    @State private var manager = StoreKitPurchaseManager.shared
    @State private var acceptedTerms = false
    @State private var agreementHint = false
    @State private var selectedProductID = StoreKitPurchaseManager.lifetimeProductID
    @State private var showLoginSheet = false
    @State private var showOfferCodeRedemption = false
    @State private var agreementPage: MembershipAgreementPage?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isVIP {
                    activeMembershipCard
                        .padding(.bottom, 24)
                    activeBenefitsSection
                } else {
                    heroHeader
                        .padding(.bottom, 18)
                    sectionTitle(
                        NSLocalizedString("vip_features_title", value: "会员专属权益", comment: "")
                    )
                    .padding(.bottom, 8)
                    featureList
                        .padding(.bottom, 10)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    manager.offerCodeRedemptionWillPresent()
                    showOfferCodeRedemption = true
                } label: {
                    Text(NSLocalizedString("membership_redeem_offer_code", value: "兑换", comment: ""))
                }
                .disabled(isBusy)
                .accessibilityIdentifier("membership_redeem_offer_code")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .appAnalyticsScreen(.vipPage)
        .modifier(
            MembershipOfferCodeRedemptionPresenter(
                isPresented: $showOfferCodeRedemption,
                manager: manager
            )
        )
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
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 已开通会员摘要

    private var activeMembershipCard: some View {
        let membership = activeServerMembership
        let membershipCode = membership?.displayCode.nilIfBlank
            ?? membership?.memberNo.nilIfBlank
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppLogoImage(size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(activeMembershipTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        activeStatusBadge
                    }
                    Text(NSLocalizedString("vip_title", value: "全能计分器 VIP", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                identityRow(
                    label: NSLocalizedString("membership_valid_until", value: "有效期至", comment: ""),
                    value: activeValidUntilText,
                    valueColor: Theme.textPrimary,
                    valueSize: 13
                )
                if let code = membershipCode {
                    identityRow(
                        label: membership?.numberLabel.nilIfBlank
                            ?? NSLocalizedString("me_profile_membership_number_label", value: "会员编号", comment: ""),
                        value: code,
                        valueColor: Theme.textPrimary,
                        valueSize: 13
                    )
                }
            }
            .padding(.top, 13)
            .overlay(alignment: .top) {
                Theme.divider.frame(height: 1)
            }
            .padding(.top, 15)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))
    }

    private var activeStatusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(NSLocalizedString("membership_status_active", value: "已开通", comment: ""))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(Theme.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.accentColor.opacity(0.12)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var activeMembershipSource: MembershipSummarySource {
        MembershipSummarySourcePolicy.resolve(
            hasActiveServerMembership: activeServerMembership != nil,
            hasLocalEntitlement: manager.hasLocalEntitlement
        )
    }

    private var activeServerMembership: AppMembership? {
        guard let membership = session.user?.membership,
              membership.isActive else {
            return nil
        }
        return membership
    }

    private var activeMembershipTitle: String {
        switch activeMembershipSource {
        case .server:
            return activeServerMembership?.identitySummary.nilIfBlank
                ?? NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
        case .localStore:
            if manager.localEntitlementExpirationDate == nil {
                return NSLocalizedString("membership_lifetime_plan_title", value: "终身会员", comment: "")
            }
            return NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
        case .legacyServer:
            return NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
        }
    }

    private var activeValidUntilText: String {
        switch activeMembershipSource {
        case .server:
            guard let membership = activeServerMembership else {
                return localValidUntilText
            }
            return validUntilText(for: membership)
        case .localStore:
            return localValidUntilText
        case .legacyServer:
            return NSLocalizedString("membership_expires_forever", value: "永久有效", comment: "")
        }
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
                .multilineTextAlignment(.leading)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: valueSize, weight: .medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func validUntilText(for membership: AppMembership) -> String {
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

    private var membershipBenefits: [(String, String, String)] {
        [
            ("vip_feature_stats", "高级统计", "chart.bar.xaxis"),
            ("vip_feature_themes", "专属主题", "paintpalette"),
            ("vip_feature_cloud", "云端同步", "icloud.and.arrow.up"),
            ("vip_feature_no_ads", "无广告体验", "rectangle.badge.xmark"),
            ("vip_feature_early_access", "优先体验", "sparkles")
        ]
    }

    private var featureList: some View {
        let maxWidth: CGFloat = Locale.current.language.languageCode?.identifier == "zh" ? 170 : 250
        return HStack {
            VStack(spacing: 0) {
                ForEach(membershipBenefits, id: \.0) { key, fallback, symbol in
                    HStack(spacing: 10) {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.accentColor)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
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

    private var activeBenefitsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text(NSLocalizedString("vip_features_title", value: "会员专属权益", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text(NSLocalizedString("membership_all_unlocked", value: "已全部解锁", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(membershipBenefits.indices, id: \.self) { index in
                    let benefit = membershipBenefits[index]
                    HStack(spacing: 12) {
                        Image(systemName: benefit.2)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.accentColor)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accentColor.opacity(0.12))
                            )
                            .accessibilityHidden(true)
                        Text(NSLocalizedString(benefit.0, value: benefit.1, comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Spacer(minLength: 12)
                        Text(NSLocalizedString("membership_feature_unlocked", value: "已解锁", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(minHeight: 56)
                    .padding(.horizontal, 16)

                    if index < membershipBenefits.count - 1 {
                        Theme.divider
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))

            Text(NSLocalizedString("membership_thanks", value: "感谢支持全能计分器", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
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
    /// 安卓未登录购买会强制登录、并在登录页同意《用户协议》；iOS 未登录可直接购买（Guideline 5.1.1(v)），
    /// 故未登录时在最前面补充《用户协议》勾选项。
    private var agreementRow: some View {
        let autoRenewURL = LegalDocuments.autoRenewalTermsURL
        let membershipURL = LegalDocuments.membershipAgreementURL
        let linkFont = Font.system(size: 13, weight: .medium)

        var text = AttributedString(
            NSLocalizedString("vip_agreement_plain_prefix", value: "已阅读并同意", comment: "")
        )
        text.foregroundColor = Theme.textSecondary
        text.font = Font.system(size: 13)

        var links: [AttributedString] = []

        if requiresUserAgreement {
            var userLink = AttributedString(
                NSLocalizedString("vip_user_agreement_link", value: "《用户协议》", comment: "")
            )
            userLink.link = LegalDocuments.termsURL
            userLink.foregroundColor = Theme.accentColor
            userLink.font = linkFont
            links.append(userLink)
        }

        if isSubscriptionSelected {
            var renewLink = AttributedString(
                NSLocalizedString("vip_auto_renew_terms_link", value: "《自动续费服务条款》", comment: "")
            )
            renewLink.link = autoRenewURL
            renewLink.foregroundColor = Theme.accentColor
            renewLink.font = linkFont
            links.append(renewLink)
        }

        var membershipLink = AttributedString(
            NSLocalizedString("vip_membership_agreement_link", value: "《会员协议》", comment: "")
        )
        membershipLink.link = membershipURL
        membershipLink.foregroundColor = Theme.accentColor
        membershipLink.font = linkFont
        links.append(membershipLink)

        // 中文靠《》书名号分隔（空串）；英文多个链接用 ", " 连接、末尾用 " and "。
        for (index, link) in links.enumerated() {
            if index > 0 {
                let isLast = index == links.count - 1
                var separator = AttributedString(
                    NSLocalizedString(
                        isLast ? "vip_agreement_link_separator" : "vip_agreement_link_middle_separator",
                        value: isLast ? " and " : ", ",
                        comment: ""
                    )
                )
                separator.foregroundColor = Theme.textSecondary
                separator.font = Font.system(size: 13)
                text += separator
            }
            text += link
        }

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
                    if url == LegalDocuments.termsURL {
                        agreementPage = MembershipAgreementPage(kind: .user)
                        return .handled
                    }
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
        switch (requiresUserAgreement, isSubscriptionSelected) {
        case (true, true):
            return NSLocalizedString(
                "vip_agreement_subscription_hint_signed_out",
                value: "请阅读并同意用户协议、自动续费服务条款和会员协议",
                comment: ""
            )
        case (true, false):
            return NSLocalizedString(
                "vip_agreement_hint_signed_out",
                value: "请阅读并同意用户协议和会员协议",
                comment: ""
            )
        case (false, true):
            return NSLocalizedString("vip_agreement_subscription_hint", value: "请阅读并同意自动续费服务条款和会员协议", comment: "")
        case (false, false):
            return NSLocalizedString("vip_agreement_hint", value: "请阅读并同意会员协议", comment: "")
        }
    }

    /// 安卓未登录购买会强制登录、并在登录页同意《用户协议》；iOS 未登录可直接购买（Guideline 5.1.1(v)），
    /// 因此未登录时协议行需一并勾选《用户协议》。
    private var requiresUserAgreement: Bool {
        !session.isAuthenticated
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

/// Uses Apple's system redemption sheet instead of accepting codes in app UI.
/// StoreKit 2 returns the redeemed transaction directly on iOS 27; on iOS 26
/// the transaction is delivered through `Transaction.updates`, with the sheet
/// completion used as a fallback reconciliation trigger.
private struct MembershipOfferCodeRedemptionPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let manager: StoreKitPurchaseManager

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.offerCodeRedemption(
                options: [],
                isPresented: $isPresented
            ) { result in
                Task { await manager.completeOfferCodeRedemption(result) }
            }
        } else {
            content.offerCodeRedemption(isPresented: $isPresented) { result in
                Task { await manager.offerCodeRedemptionSheetDidClose(result) }
            }
        }
    }
}

/// 会员协议网页（对齐安卓 LegalConfig：用户协议 / 会员协议 / 自动续费服务条款）。
enum MembershipAgreementKind: Hashable {
    case user
    case membership
    case autoRenewal
}

struct MembershipAgreementPage: Identifiable, Hashable {
    let kind: MembershipAgreementKind
    var id: MembershipAgreementKind { kind }

    var url: URL {
        switch kind {
        case .user: return LegalDocuments.termsURL
        case .membership: return LegalDocuments.membershipAgreementURL
        case .autoRenewal: return LegalDocuments.autoRenewalTermsURL
        }
    }

    var title: String {
        switch kind {
        case .user:
            return NSLocalizedString("terms_of_service", value: "用户协议", comment: "")
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
            .appAnalyticsScreen(.legalWebPage)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
