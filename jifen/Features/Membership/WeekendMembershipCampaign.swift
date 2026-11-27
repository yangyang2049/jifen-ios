import Foundation
import OSLog
import RevenueCat
import RevenueCatUI
import StoreKit
import SwiftUI

@MainActor
enum WeekendMembershipCampaign {
    static let placement = "weekend_membership"
    static let previewOffering = "weekend_lifetime_preview"
    static let hasOpenedKey = "weekend_membership_has_opened_app"
    private static let lastShownKey = "weekend_membership_last_shown_at"
    private static let previewLastShownKey = "weekend_membership_preview_last_shown_at"
    private(set) static var isReturningLaunch = false

    static func recordLaunch(defaults: UserDefaults = .standard) {
        // Existing installations recorded legal acceptance before this campaign had a launch flag.
        if defaults.object(forKey: hasOpenedKey) != nil {
            isReturningLaunch = defaults.bool(forKey: hasOpenedKey)
        } else {
            isReturningLaunch = defaults.string(forKey: LegalConsent.acceptedVersionKey) != nil
        }
        defaults.set(true, forKey: hasOpenedKey)
        #if DEBUG
        if isAutomaticPreview && ProcessInfo.processInfo.arguments.contains("-ResetWeekendMembershipPreview") {
            defaults.removeObject(forKey: previewLastShownKey)
        }
        #endif
    }

    static var isManualPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PreviewWeekendMembership")
        #else
        false
        #endif
    }

    private static var isAutomaticPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PreviewWeekendMembershipAutomatically")
        #else
        false
        #endif
    }

    static var isPreview: Bool { isManualPreview || isAutomaticPreview }

    static var now: Date {
        #if DEBUG
        if isAutomaticPreview {
            let seconds = UserDefaults.standard.double(forKey: "weekend_membership_preview_date")
            if seconds.isFinite && seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        }
        #endif
        return .now
    }

    static var usesSimplifiedChinese: Bool {
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return locale.language.languageCode?.identifier == "zh" && !ChineseScript.isTraditional(locale: locale)
    }

    private static var presentationHistoryKey: String {
        isAutomaticPreview ? previewLastShownKey : lastShownKey
    }

    static func canPresent(at date: Date) -> Bool {
        let lastShownAt = UserDefaults.standard.object(forKey: presentationHistoryKey) as? Date
        return WeekendMembershipSchedule.canPresent(at: date, lastShownAt: lastShownAt)
    }

    static func reservePresentation(at date: Date) -> Bool {
        guard canPresent(at: date) else { return false }
        UserDefaults.standard.set(date, forKey: presentationHistoryKey)
        return true
    }

    static var mode: RevenueCatMembership.Mode? { RevenueCatMembership.configuration?.mode }

    static func loadOffering() async throws -> Offering? {
        guard let mode else {
            RevenueCatMembership.logger.error("Weekend membership is missing a valid public SDK key.")
            return nil
        }
        let identity = RevenueCatMembership.identity(for: .shared)
        guard let offerings = try await RevenueCatMembership.withPurchases(for: identity, { purchases in
            try await purchases.offerings()
        }) else { return nil }

        let offering = isPreview
            ? offerings.offering(identifier: previewOffering)
            : offerings.currentOffering(forPlacement: placement)
        guard let offering else {
            RevenueCatMembership.logger.notice("Weekend membership offering was not assigned.")
            return nil
        }
        guard WeekendMembershipSchedule.matchesPaywall(
            hasPaywall: offering.hasPaywall,
            packageCount: offering.availablePackages.count,
            lifetimeProductID: offering.lifetime?.storeProduct.productIdentifier,
            expectedProductID: mode == .appStore ? StoreKitPurchaseManager.lifetimeProductID : "lifetime"
        ) else {
            RevenueCatMembership.logger.error("Weekend membership offering has a missing paywall or an unexpected lifetime package.")
            return nil
        }
        guard isAvailable(offering, at: now) else {
            RevenueCatMembership.logger.info("Weekend membership offering is disabled or outside its configured window.")
            return nil
        }
        return offering
    }

    static func isAvailable(_ offering: Offering, at date: Date) -> Bool {
        if isManualPreview { return true }
        if isAutomaticPreview { return WeekendMembershipSchedule.isActive(at: date) }
        return WeekendMembershipSchedule.isOfferingEnabled(offering.metadata, at: date)
    }
}

struct WeekendMembershipEntry: View {
    let isHomeVisible: Bool
    let hasPlayed: Bool

    private struct PresentedPaywall: Identifiable {
        let offering: Offering
        var id: String { offering.identifier }
    }

    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var manager = StoreKitPurchaseManager.shared
    @State private var presentedPaywall: PresentedPaywall?
    @State private var acceptedTerms = false
    @State private var showTermsReminder = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    #if DEBUG
    @State private var previewOffering: Offering?
    @State private var previewMessage: String?
    #endif

    private var hasLifetime: Bool {
        let membership = session.user?.membership
        let cycle = membership?.billingCycle.lowercased()
        let hasAccountLifetime = membership?.isActive == true
            && ["lifetime", "permanent", "permant"].contains(cycle ?? "")
        return hasAccountLifetime || (manager.hasLocalEntitlement && manager.localEntitlementExpirationDate == nil)
    }

    private var canOffer: Bool {
        guard isHomeVisible, session.state != .restoring else { return false }
        if WeekendMembershipCampaign.isManualPreview { return true }
        return AppStore.canMakePayments && !purchaseIsInProgress
            && WeekendMembershipCampaign.isReturningLaunch && hasPlayed && !hasLifetime
            && WeekendMembershipCampaign.usesSimplifiedChinese
            && WeekendMembershipCampaign.canPresent(at: WeekendMembershipCampaign.now)
    }

    private var purchaseIsInProgress: Bool {
        switch manager.state {
        case .loading, .purchasing, .pending: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if WeekendMembershipCampaign.isManualPreview, let previewOffering, canOffer {
                Button {
                    guard canOffer, !purchaseIsInProgress else { return }
                    present(previewOffering)
                } label: {
                    HStack(spacing: Theme.md) {
                        Image(systemName: "star.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.primary)
                            .accessibilityHidden(true)
                        Text(NSLocalizedString("weekend_membership_preview_title", value: "周末会员弹窗测试", comment: ""))
                            .font(.system(size: Theme.fontBody1, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.sm)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(Theme.md)
                    .frame(minHeight: 44)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_weekend_membership")
                .padding(.top, Theme.sectionSpacing)
            }
            if WeekendMembershipCampaign.isPreview, let previewMessage {
                Text(previewMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("weekend_membership_preview_status")
                    .padding(.top, Theme.sectionSpacing)
            }
            #endif
        }
        .task(id: canOffer) {
            guard canOffer, presentedPaywall == nil else { return }
            if !WeekendMembershipCampaign.isPreview {
                await manager.refreshLocalEntitlement()
                guard canOffer, !Task.isCancelled else { return }
            }
            do {
                let next = try await WeekendMembershipCampaign.loadOffering()
                guard canOffer, !Task.isCancelled else { return }
                #if DEBUG
                previewMessage = next == nil ? "周末会员预览尚未配置 SDK Key 或专用 Offering。" : nil
                if WeekendMembershipCampaign.isManualPreview {
                    previewOffering = next
                    return
                }
                #endif
                guard let next else { return }
                let now = WeekendMembershipCampaign.now
                guard WeekendMembershipCampaign.isAvailable(next, at: now),
                      WeekendMembershipCampaign.reservePresentation(at: now) else { return }
                present(next)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                RevenueCatMembership.logger.error("Could not load the weekend membership offering (code: \((error as NSError).code)).")
                #if DEBUG
                previewOffering = nil
                previewMessage = "周末会员预览加载失败，请检查网络和 RevenueCat 配置。"
                #endif
            }
        }
        .sheet(item: $presentedPaywall) { paywall in
            VStack(spacing: 0) {
                if WeekendMembershipCampaign.mode == .testStore {
                    PaywallView(offering: paywall.offering, displayCloseButton: true)
                        .onPurchaseInitiated(verifyTermsBeforePurchase)
                } else {
                    PaywallView(
                        offering: paywall.offering,
                        displayCloseButton: true,
                        performPurchaseWithContext: { context in
                            await purchase(context.package, in: paywall.offering)
                        },
                        performRestore: { await restorePurchases() }
                    )
                    .onPurchaseInitiated(verifyTermsBeforePurchase)
                }
                agreement
                Button {
                    guard !isRestoring else { return }
                    isRestoring = true
                    Task {
                        let result = await restorePurchases()
                        restoreMessage = result.error?.localizedDescription ?? (result.success
                            ? NSLocalizedString("membership_restore_done", value: "恢复购买完成", comment: "")
                            : NSLocalizedString("weekend_membership_restore_empty", value: "未找到可恢复的终身会员购买", comment: ""))
                        isRestoring = false
                    }
                } label: {
                    Text(NSLocalizedString("membership_restore", value: "恢复购买", comment: ""))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentColor)
                .background(Theme.cardBackground)
                .disabled(isRestoring || purchaseIsInProgress)
                .accessibilityIdentifier("weekend_membership_restore")
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(520), .large])
            .alert(
                NSLocalizedString("vip_agreement_hint", value: "请阅读并同意会员协议", comment: ""),
                isPresented: $showTermsReminder
            ) { Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {} }
            .alert(
                restoreMessage ?? "",
                isPresented: Binding(
                    get: { restoreMessage != nil },
                    set: { if !$0 { restoreMessage = nil } }
                )
            ) { Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {} }
        }
    }

    private func present(_ offering: Offering) {
        acceptedTerms = false
        presentedPaywall = PresentedPaywall(offering: offering)
    }

    private var agreement: some View {
        let label = NSLocalizedString("vip_agreement_plain_prefix", value: "已阅读并同意", comment: "")
        var terms = AttributedString(label)
        terms.foregroundColor = Theme.textSecondary
        if !session.isAuthenticated {
            var userAgreement = AttributedString(
                NSLocalizedString("vip_user_agreement_link", value: "《用户协议》", comment: "")
            )
            userAgreement.link = LegalDocuments.termsURL
            terms += userAgreement
        }
        var membershipAgreement = AttributedString(
            NSLocalizedString("vip_membership_agreement_link", value: "《会员协议》", comment: "")
        )
        membershipAgreement.link = LegalDocuments.membershipAgreementURL
        terms += membershipAgreement

        return HStack(spacing: 2) {
            Button {
                acceptedTerms.toggle()
            } label: {
                Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(acceptedTerms ? Theme.accentColor : Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(acceptedTerms ? .isSelected : [])
            .accessibilityIdentifier("weekend_membership_accept_terms")

            Text(terms)
                .font(.footnote)
                .tint(Theme.accentColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.md)
        .padding(.vertical, Theme.xs)
        .background(Theme.cardBackground)
    }

    private func verifyTermsBeforePurchase(_: Package, resume: ResumeAction) {
        resume(shouldProceed: acceptedTerms && !isRestoring)
        if !acceptedTerms { showTermsReminder = true }
    }

    private func purchase(_ package: Package, in offering: Offering) async -> (userCancelled: Bool, error: Error?) {
        guard WeekendMembershipCampaign.isAvailable(offering, at: WeekendMembershipCampaign.now),
              package.storeProduct.productIdentifier == StoreKitPurchaseManager.lifetimeProductID,
              let product = package.storeProduct.sk2Product,
              !hasLifetime,
              manager.state != .pending
        else { return (false, CampaignPurchaseError.unavailable) }
        await manager.purchase(product)
        switch manager.state {
        case .succeeded:
            return (false, nil)
        case .cancelled:
            return (true, nil)
        default:
            return (false, CampaignPurchaseError.storeKit(manager.message))
        }
    }

    private func restorePurchases() async -> (success: Bool, error: Error?) {
        if WeekendMembershipCampaign.mode == .testStore {
            do {
                let info = try await RevenueCatMembership.withPurchases(for: .anonymous) { purchases in
                    try await purchases.restorePurchases()
                }
                return (info?.allPurchasedProductIdentifiers.contains("lifetime") == true, nil)
            } catch {
                return (false, error)
            }
        }
        await manager.restorePurchases()
        guard manager.state == .succeeded else {
            return (false, CampaignPurchaseError.storeKit(manager.message))
        }
        return (hasLifetime, nil)
    }
}

private enum CampaignPurchaseError: LocalizedError {
    case unavailable
    case storeKit(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("membership_load_empty", value: "暂时无法购买，请稍后再试", comment: "")
        case .storeKit(let message):
            return message ?? NSLocalizedString("membership_load_empty", value: "暂时无法购买，请稍后再试", comment: "")
        }
    }
}
