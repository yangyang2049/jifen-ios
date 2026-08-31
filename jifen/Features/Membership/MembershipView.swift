import StoreKit
import SwiftUI

// 对齐安卓 MembershipCenterScreen（AccountMembershipScreens.kt）：
// Hero 头部 → VIP 时横幅 + 身份面板 → 权益标题 + 权益列表 → 方案卡 → 底部购买栏。
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
            if !isVIP {
                purchaseBottomBar
            }
        }
        .task {
            await manager.loadProducts()
            await session.reloadProfile()
        }
        .navigationDestination(item: $agreementPage) { page in
            MembershipAgreementWebPage(url: page.url)
        }
        .sheet(isPresented: $showLoginSheet) {
            AccountLoginSheet()
        }
    }

    private var isVIP: Bool { session.user?.isVIP == true }

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

    private var selectedProduct: Product? {
        orderedProducts.first { $0.id == selectedProductID } ?? orderedProducts.first
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
                .foregroundColor(Color(uiColor: .tertiaryLabel))
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
        let membership = session.user?.membership
        return VStack(spacing: 10) {
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
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.appCardBackground))
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

    // MARK: - 方案卡（对齐安卓 MembershipLifetimePlanCard，扩展为 月/年/终身 三卡选择）

    @ViewBuilder
    private var planCards: some View {
        if manager.products.isEmpty {
            Group {
                if manager.didLoadProducts {
                    Text(NSLocalizedString("membership_store_unavailable", value: "Apple 内购暂不可用", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(NSLocalizedString("membership_loading_products", value: "正在读取 App Store 商品…", comment: ""))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(orderedProducts, id: \.id) { product in
                    planCard(product)
                }
            }
            .padding(.top, 16)
        }
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
                        .foregroundColor(Theme.accentColor)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    Text(product.displayPrice)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

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
                            topTrailingRadius: 18
                        )
                        .fill(Theme.accentColor)
                    )
            }
            .frame(height: 128)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.accentColor.opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Theme.accentColor : Theme.divider, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func planInfo(for id: String) -> (title: String, subtitle: String, badge: String) {
        switch id {
        case StoreKitPurchaseManager.monthlyProductID:
            return (
                NSLocalizedString("membership_monthly_plan_title", value: "月卡会员", comment: ""),
                NSLocalizedString("membership_monthly_subtitle", value: "自动续订，可随时取消", comment: ""),
                NSLocalizedString("membership_monthly_badge", value: "月卡", comment: "")
            )
        case StoreKitPurchaseManager.yearlyProductID:
            return (
                NSLocalizedString("membership_yearly_plan_title", value: "年卡会员", comment: ""),
                NSLocalizedString("membership_yearly_subtitle", value: "自动续订，可随时取消", comment: ""),
                NSLocalizedString("membership_yearly_badge", value: "年卡", comment: "")
            )
        default:
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

            if !session.isAuthenticated {
                Text(NSLocalizedString("vip_login_hint", value: "购买前请先登录账号", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
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

    private var agreementRow: some View {
        HStack(spacing: 2) {
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

            Text(NSLocalizedString("vip_lifetime_agreement_prefix", value: "已阅读并同意", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .onTapGesture { acceptedTerms.toggle() }

            Text(NSLocalizedString("vip_membership_agreement_link", value: "《会员协议》", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.accentColor)
                .lineLimit(1)
                .onTapGesture { agreementPage = MembershipAgreementPage() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if agreementHint {
                Text(NSLocalizedString("vip_agreement_hint", value: "请阅读并同意会员协议", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.leading, 8)
            }
        }
    }

    private func startPurchase() async {
        guard let product = selectedProduct else { return }
        if !session.isAuthenticated {
            showLoginSheet = true
            return
        }
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

/// 会员协议网页（对齐安卓 LegalConfig.MEMBERSHIP_AGREEMENT_URL）。
struct MembershipAgreementPage: Identifiable, Hashable {
    let id = UUID()
    var url: URL { LegalDocuments.membershipAgreementURL }
}

private struct MembershipAgreementWebPage: View {
    let url: URL

    var body: some View {
        LoginLegalWebView(url: url)
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("vip_membership_agreement_title", value: "会员协议", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
