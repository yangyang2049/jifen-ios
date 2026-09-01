import SwiftUI
import WebKit

struct AccountCenterView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView()
            case .signedOut:
                AccountLoginView()
            case .authenticated:
                AccountProfileView()
            }
        }
        .navigationTitle(NSLocalizedString("account_title", value: "账户", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct AccountLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var selectedDetent: PresentationDetent = .height(440)

    var body: some View {
        NavigationStack {
            AccountLoginView(onOpenLegal: { selectedDetent = .large })
                .navigationTitle(NSLocalizedString("account_login_title", value: "登录", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ModalCloseButton { dismiss() }
                    }
                }
        }
        .presentationDetents([.height(440), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .interactiveDismissDisabled(session.isWorking)
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated { dismiss() }
        }
    }
}

private enum LoginLegalDocument: String, Identifiable, Hashable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:
            NSLocalizedString("terms_of_service", value: "用户协议", comment: "")
        case .privacy:
            NSLocalizedString("privacy_policy", value: "隐私政策", comment: "")
        }
    }

    var linkTitle: String {
        switch self {
        case .terms:
            NSLocalizedString("account_login_agreement_terms", value: "《服务条款》", comment: "")
        case .privacy:
            NSLocalizedString("account_login_agreement_privacy", value: "《隐私政策》", comment: "")
        }
    }

    var url: URL {
        switch self {
        case .terms: LegalDocuments.termsURL
        case .privacy: LegalDocuments.privacyURL
        }
    }
}

private struct AccountLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var agreementAccepted = false
    @State private var agreementError: String?
    @State private var legalDocument: LoginLegalDocument?
    var onOpenLegal: () -> Void = {}
    #if STAGING
    @State private var showStagingToken = false
    @State private var stagingToken = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AppLogoImage(size: 72)
                    .padding(.top, 32)
                Text(NSLocalizedString("account_login_subtitle", value: "登录后同步常用数据、反馈和实时比分", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                AppleIDButton {
                    Task { await startAppleLogin() }
                }
                .frame(height: 50)
                .disabled(session.isWorking)

                loginAgreement

                if session.isWorking {
                    ProgressView()
                }

                #if STAGING
                Text(NSLocalizedString("account_staging_apple_note", value: "Staging 连接隔离测试服务器，登录使用真实 Apple 账号。", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if requireAgreement() { showStagingToken = true }
                } label: {
                    Text(NSLocalizedString("staging_token_entry", value: "设置 IAP 测试密钥", comment: ""))
                        .font(.caption)
                }
                #endif

                if let error = agreementError ?? session.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationDestination(item: $legalDocument) { document in
            LoginLegalWebPage(document: document)
        }
        #if STAGING
        .alert(NSLocalizedString("staging_token_title", value: "Staging 临时密钥", comment: ""), isPresented: $showStagingToken) {
            TextField(NSLocalizedString("staging_token_placeholder", value: "输入临时密钥", comment: ""), text: $stagingToken)
                .textInputAutocapitalization(.never)
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("continue", value: "继续", comment: "")) {
                Task {
                    guard requireAgreement() else { return }
                    try? await session.saveStagingToken(stagingToken)
                    await session.signInWithApple()
                }
            }
        } message: {
            Text(NSLocalizedString("staging_token_message", value: "密钥只保存在本机 Keychain，用于受限的 Staging 测试接口。", comment: ""))
        }
        #endif
    }

    private func startAppleLogin() async {
        guard requireAgreement() else { return }
        await session.signInWithApple()
    }

    private func requireAgreement() -> Bool {
        guard agreementAccepted else {
            agreementError = NSLocalizedString(
                "account_login_agreement_hint",
                value: "请先阅读并同意用户协议和隐私政策",
                comment: ""
            )
            return false
        }
        agreementError = nil
        return true
    }

    private var loginAgreement: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                agreementAccepted.toggle()
                if agreementAccepted { agreementError = nil }
            } label: {
                Image(systemName: agreementAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(agreementAccepted ? Color.green : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString(
                "account_login_agreement_toggle",
                value: "同意用户协议和隐私政策",
                comment: ""
            ))
            .accessibilityValue(agreementAccepted ? "1" : "0")

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(
                    "account_login_agreement_prefix",
                    value: "已阅读并同意",
                    comment: ""
                ))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 0) {
                    legalButton(.terms)
                    Text(NSLocalizedString(
                        "account_login_agreement_and",
                        value: "和",
                        comment: ""
                    ))
                    .foregroundStyle(Theme.textSecondary)
                    legalButton(.privacy)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legalButton(_ document: LoginLegalDocument) -> some View {
        Button(document.linkTitle) {
            onOpenLegal()
            legalDocument = document
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentColor)
        .accessibilityIdentifier("account_login_\(document.rawValue)_link")
    }
}

private struct LoginLegalWebPage: View {
    let document: LoginLegalDocument

    var body: some View {
        LoginLegalWebView(url: document.url)
            .background(Theme.backgroundColor)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("account_login_\(document.rawValue)_webview")
    }
}

struct LoginLegalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }
}

// 对齐安卓 ProfileScreen（AccountProfileScreens.kt）：
// 头部卡（头像 + 昵称 + 会员徽章）+ 信息卡（昵称/会员身份/账号ID/注册时间/邮箱）+ 未登录登录按钮。
private struct AccountProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showRenameDialog = false
    @State private var showLogoutConfirmation = false
    @State private var showAccountDeletion = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProfileHeaderCard(
                    user: session.user,
                    loggedIn: session.isAuthenticated
                )

                VStack(spacing: 0) {
                    ProfileNicknameRow(
                        label: NSLocalizedString("me_profile_display_name_label", value: "昵称", comment: ""),
                        value: profileDisplayText,
                        showEdit: session.isAuthenticated && session.user != nil
                    ) {
                        showRenameDialog = true
                    }
                    ProfileThinDivider()
                    if session.user?.isVIP == true {
                        NavigationLink { MembershipView() } label: {
                            ProfileInfoRow(
                                label: NSLocalizedString("me_profile_vip_status_label", value: "会员状态", comment: ""),
                                value: profileMembershipLabel(session.user),
                                valueColor: Theme.accentColor,
                                showChevron: true
                            ) {}
                            .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProfileInfoRow(
                            label: NSLocalizedString("me_profile_vip_status_label", value: "会员状态", comment: ""),
                            value: profileMembershipLabel(session.user),
                            valueColor: Theme.textPrimary,
                            showChevron: false
                        ) {}
                    }
                    ProfileThinDivider()
                    ProfileInfoRow(
                        label: NSLocalizedString("me_profile_account_id", value: "账号 ID", comment: ""),
                        value: displayUserId,
                        showChevron: false
                    ) {
                        copyAccountId()
                    }
                    ProfileThinDivider()
                    ProfileInfoRow(
                        label: NSLocalizedString("me_profile_registered_date_label", value: "注册时间", comment: ""),
                        value: profileRegisteredDate,
                        showChevron: false
                    ) {}
                    ProfileThinDivider()
                    ProfileInfoRow(
                        label: NSLocalizedString("me_profile_email_label", value: "电子邮箱", comment: ""),
                        value: session.user?.email?.nilIfBlank
                            ?? NSLocalizedString("me_profile_email_not_set", value: "无", comment: ""),
                        showChevron: false
                    ) {}
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.appCardBackground))
            }
            .padding(16)
            .frame(maxWidth: Theme.meTabContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("me_profile_title", value: "个人资料", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label(
                            NSLocalizedString("account_logout", value: "退出登录", comment: ""),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                    }
                    Button(role: .destructive) {
                        showAccountDeletion = true
                    } label: {
                        Label(
                            NSLocalizedString("account_delete", value: "删除账户", comment: ""),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(NSLocalizedString("more", value: "更多", comment: ""))
            }
        }
        .navigationDestination(isPresented: $showAccountDeletion) {
            AccountDeletionView()
        }
        .overlay {
            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showRenameDialog {
                NicknameEditDialog(
                    initialName: profileDisplayText,
                    onDismiss: { showRenameDialog = false },
                    onSubmit: { name in
                        let updated = await session.updateProfile(name: name)
                        if updated { showRenameDialog = false }
                        return updated
                    }
                )
            }
        }
        .alert(
            NSLocalizedString("account_logout_confirm_title", value: "退出登录", comment: ""),
            isPresented: $showLogoutConfirmation
        ) {
            Button(NSLocalizedString("account_logout", value: "退出登录", comment: ""), role: .destructive) {
                Task { await session.logout() }
            }
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString(
                "account_logout_confirm_message",
                value: "确定要退出当前账号吗？",
                comment: ""
            ))
        }
    }

    private var profileDisplayText: String {
        guard let user = session.user else {
            return NSLocalizedString("me_account_logged_out", value: "未登录", comment: "")
        }
        return [user.nickname, user.name, user.email, user.id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            .first ?? NSLocalizedString("me_account_logged_in", value: "已登录", comment: "")
    }

    private var displayUserId: String {
        (session.user?.uid?.nilIfBlank ?? session.user?.id.nilIfBlank) ?? "--"
    }

    private var profileRegisteredDate: String {
        guard let createdAt = session.user?.createdAt, createdAt > 0 else { return "--" }
        let millis = createdAt < 10_000_000_000 ? createdAt * 1000 : createdAt
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    }

    private func copyAccountId() {
        let id = displayUserId
        guard id != "--" else { return }
        UIPasteboard.general.string = id
        showToastMessage(NSLocalizedString("me_profile_account_id_copied", value: "账号 ID 已复制", comment: ""))
    }

    private func showToastMessage(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

/// 注销账号页（对齐安卓 AccountDeletionScreen）：
/// 影响说明卡 + VIP 会员警告卡 + 红色注销按钮 + CustomConfirmDialog 二次确认。
struct AccountDeletionView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var submitting = false
    @State private var showConfirm = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    /// 安卓 ToolWhistleRed
    private let whistleRed = Color(hex: "FF3B30")

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if loading {
                ProgressView()
                    .tint(Theme.accentColor)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        impactCard

                        if session.user?.isVIP == true {
                            membershipWarningCard
                        }

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(whistleRed)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }

                        applyButton
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: Theme.meTabContentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(NSLocalizedString("account_deletion_title", value: "注销账号", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await session.reloadProfile()
            loading = false
            if session.user == nil { dismiss() }
        }
        .overlay {
            if showConfirm {
                CustomConfirmDialog(
                    title: NSLocalizedString("account_deletion_confirm_title", value: "确认注销账号？", comment: ""),
                    message: confirmMessage,
                    confirmText: NSLocalizedString("account_deletion_confirm_action", value: "确认注销", comment: ""),
                    cancelText: NSLocalizedString("account_deletion_confirm_cancel", value: "再想想", comment: ""),
                    confirmColor: whistleRed,
                    onConfirm: { Task { await submit() } },
                    onDismiss: { if !submitting { showConfirm = false } }
                )
            }
        }
    }

    private var isVIP: Bool { session.user?.isVIP == true }

    private var confirmMessage: String {
        let base = NSLocalizedString(
            "account_deletion_confirm_message",
            value: "注销后，你的账号和账号相关数据将被删除或匿名化处理，此操作无法恢复。",
            comment: ""
        )
        guard isVIP else { return base }
        return base + "\n\n" + NSLocalizedString(
            "account_deletion_membership_warning",
            value: "当前账号存在有效会员权益（包括月卡、年卡或永久会员）。注销账号将一并删除该会员权益，且不可人工恢复。",
            comment: ""
        )
    }

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("account_deletion_impact_title", value: "注销前请确认", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.bottom, 12)

            impactRow(NSLocalizedString(
                "account_deletion_impact_account",
                value: "你的账号资料和登录身份将被删除或匿名化处理。",
                comment: ""
            ))
            impactRow(NSLocalizedString(
                "account_deletion_impact_feedback",
                value: "你发布的反馈等账号相关内容可能被删除或匿名化处理。",
                comment: ""
            ))
            impactRow(NSLocalizedString(
                "account_deletion_impact_local_data",
                value: "本机计分记录、预约、常用名称和设置不会被删除。",
                comment: ""
            ))
            impactRow(NSLocalizedString(
                "account_deletion_impact_irreversible",
                value: "注销完成后，该账号无法恢复。",
                comment: ""
            ))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.appCardBackground))
    }

    private func impactRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.accentColor)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }

    private var membershipWarningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("account_deletion_membership_warning_title", value: "会员权益提醒", comment: ""))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(whistleRed)
            Text(NSLocalizedString(
                "account_deletion_membership_warning",
                value: "当前账号存在有效会员权益（包括月卡、年卡或永久会员）。注销账号将一并删除该会员权益，且不可人工恢复。",
                comment: ""
            ))
            .font(.system(size: 14))
            .foregroundColor(Theme.textPrimary)
            .lineSpacing(5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(whistleRed.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(whistleRed.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private var applyButton: some View {
        Button {
            showConfirm = true
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 20, height: 20)
                    Text(NSLocalizedString("account_deletion_submitting", value: "提交中...", comment: ""))
                } else {
                    Text(NSLocalizedString("account_deletion_apply", value: "注销账号", comment: ""))
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(whistleRed.opacity(submitting ? 0.48 : 1)))
        }
        .disabled(submitting)
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        let outcome = await session.deleteAccount()
        submitting = false
        guard let outcome else {
            showConfirm = false
            errorMessage = session.lastError ?? NSLocalizedString(
                "account_deletion_failed",
                value: "账号注销失败，请稍后重试",
                comment: ""
            )
            return
        }
        showConfirm = false
        if outcome.success {
            showToast(
                outcome.message ?? (isCompletedStatus(outcome.status)
                    ? NSLocalizedString("account_deletion_success", value: "账号已注销", comment: "")
                    : NSLocalizedString("account_deletion_submitted", value: "注销申请已提交", comment: ""))
            )
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } else {
            let message = outcome.message ?? NSLocalizedString(
                "account_deletion_failed",
                value: "账号注销失败，请稍后重试",
                comment: ""
            )
            errorMessage = message
            showToast(message)
        }
    }

    /// 对齐安卓 isAccountDeletionCompletedStatus。
    private func isCompletedStatus(_ status: String?) -> Bool {
        let normalized = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || ["deleted", "completed", "complete", "success", "succeeded"].contains(normalized)
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }
}

/// 会员状态文案（对齐安卓 profileMembershipLabel）。
private func profileMembershipLabel(_ user: AppUser?) -> String {
    guard let user else {
        return NSLocalizedString("me_profile_basic_badge", value: "普通用户", comment: "")
    }
    if let summary = user.membership?.identitySummary.nilIfBlank {
        return summary
    }
    if !user.isVIP {
        return NSLocalizedString("me_profile_basic_badge", value: "普通用户", comment: "")
    }
    let cycle = [user.membership?.billingCycle, user.plan]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        .first?
        .lowercased()
    switch cycle {
    case "month", "monthly":
        return NSLocalizedString("membership_monthly_plan_title", value: "月卡会员", comment: "")
    case "year", "yearly", "annual":
        return NSLocalizedString("membership_yearly_plan_title", value: "年卡会员", comment: "")
    case "lifetime", "permanent", "permant":
        return NSLocalizedString("membership_lifetime_plan_title", value: "终身会员", comment: "")
    default:
        return NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
    }
}

/// 头部卡（对齐安卓 ProfileHeaderCard）。
private struct ProfileHeaderCard: View {
    let user: AppUser?
    let loggedIn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            avatar
                .padding(.top, 22)
            Text(displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .padding(.top, 12)
            Text(badgeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isVIP ? Theme.accentColor : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isVIP ? Theme.accentColor.opacity(0.12) : Theme.controlBackground
                    )
                )
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.appCardBackground))
    }

    private var isVIP: Bool { user?.isVIP == true }

    private var displayName: String {
        let name = [user?.nickname, user?.name, user?.email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            .first
        if let name { return name }
        return loggedIn
            ? NSLocalizedString("me_account_logged_in", value: "已登录", comment: "")
            : NSLocalizedString("me_account_logged_out", value: "未登录", comment: "")
    }

    private var badgeText: String {
        if isVIP {
            return NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
        }
        return user == nil
            ? NSLocalizedString("me_account_logged_out", value: "未登录", comment: "")
            : NSLocalizedString("me_profile_basic_badge", value: "普通用户", comment: "")
    }

    private var avatarBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color(hex: "CBD5E1")
    }

    @ViewBuilder
    private var avatar: some View {
        let url = avatarURL
        ZStack {
            Circle().fill(Theme.controlBackground)
            if loggedIn, let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ProfileAvatarFallback(displayName: displayName)
                    }
                }
                .clipShape(Circle())
            } else {
                ProfileAvatarFallback(displayName: displayName)
            }
        }
        .frame(width: 72, height: 72)
        .overlay(Circle().strokeBorder(avatarBorderColor, lineWidth: 1.5))
        .clipShape(Circle())
    }

    private var avatarURL: URL? {
        guard let value = (user?.avatarUrl ?? user?.avatar)?.nilIfBlank else { return nil }
        return URL(string: value, relativeTo: APIEnvironment.current.restBaseURL)
    }
}

private struct ProfileAvatarFallback: View {
    let displayName: String

    var body: some View {
        if let initial = displayName.first.map(String.init) {
            Text(initial)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 36))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

/// 信息行（对齐安卓 ProfileInfoRow / ProfileNicknameRow）：
/// 表格布局——左边名称左对齐，右边信息右对齐，两端分别对齐。
private struct ProfileInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var showChevron: Bool
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileNicknameRow: View {
    let label: String
    let value: String
    var showEdit: Bool
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 18)
                    .opacity(showEdit ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!showEdit)
    }
}

private struct ProfileThinDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }
}

/// 修改昵称弹窗（对齐安卓 NicknameEditDialog / CustomPromptDialog）。
private struct NicknameEditDialog: View {
    let initialName: String
    let onDismiss: () -> Void
    let onSubmit: (String) async -> Bool

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture { if !saving { onDismiss() } }
                .transition(.opacity)

            VStack(spacing: 0) {
                Text(NSLocalizedString("me_profile_nickname_edit_title", value: "修改昵称", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)

                TextField(
                    NSLocalizedString("me_profile_nickname_edit_placeholder", value: "请输入昵称", comment: ""),
                    text: $name
                )
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                HStack(spacing: 16) {
                    dialogButton(
                        title: NSLocalizedString("cancel", value: "取消", comment: ""),
                        background: Theme.controlBackground,
                        foreground: Theme.textPrimary
                    ) { onDismiss() }
                    dialogButton(
                        title: saving
                            ? NSLocalizedString("me_profile_nickname_saving", value: "保存中…", comment: "")
                            : NSLocalizedString("save", value: "保存", comment: ""),
                        background: Theme.accentColor,
                        foreground: .white
                    ) { Task { await submit() } }
                    .disabled(saving)
                }
                .padding(.top, 24)
            }
            .padding(24)
            .frame(maxWidth: Theme.usesPadLayout ? 400 : 280)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.25), radius: 8)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .onAppear {
            name = initialName
            // 等弹窗过渡动画（0.2s easeInOut）完成后再聚焦，过早赋值会被动画吞掉
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focused = true
            }
        }
    }

    private func dialogButton(title: String, background: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }

    private func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString("me_profile_nickname_empty", value: "昵称不能为空", comment: "")
            return
        }
        guard trimmed.count <= 20 else {
            errorMessage = NSLocalizedString("me_profile_nickname_length", value: "昵称长度需在 1-20 个字符之间", comment: "")
            return
        }
        errorMessage = nil
        saving = true
        _ = await onSubmit(trimmed)
        saving = false
    }
}
