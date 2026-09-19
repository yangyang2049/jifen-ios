import SwiftUI

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
            AccountLoginView(
                onOpenLegal: { selectedDetent = .large },
                onOpenPasswordLogin: { selectedDetent = .large }
            )
            .navigationTitle(NSLocalizedString("account_login_title", value: "登录", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
    @State private var showPasswordLogin = false
    var onOpenLegal: () -> Void = {}
    var onOpenPasswordLogin: () -> Void = {}
    #if STAGING
    @State private var showStagingToken = false
    @State private var stagingToken = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AppLogoImage(size: 72)
                    .padding(.top, 12)
                Text(NSLocalizedString("account_login_subtitle", value: "登录后同步常用数据、反馈和实时比分", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                AppleIDButton {
                    Task { await startAppleLogin() }
                }
                .frame(height: 50)
                .disabled(session.isWorking)

                // 对齐安卓 LoginScreen 次按钮：账号密码登录（自测/审核测试用）。
                Button {
                    onOpenPasswordLogin()
                    showPasswordLogin = true
                } label: {
                    Text(NSLocalizedString("me_password_login_entry", value: "账号密码登录", comment: ""))
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.controlBackground))
                }
                .buttonStyle(.plain)
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
            .padding(24)
            // 整栏宽度按 Apple 登录按钮的内部上限收口，同级按钮与输入框一起等宽
            // （和账号密码登录页同一顺序：先内边距再限宽，两页正文宽度才一致）。
            .frame(maxWidth: Theme.authContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationDestination(item: $legalDocument) { document in
            LoginLegalWebPage(document: document)
        }
        .navigationDestination(isPresented: $showPasswordLogin) {
            PasswordLoginView(onOpenLegal: onOpenLegal)
        }
        .onChange(of: agreementAccepted) { _, accepted in
            if accepted { agreementError = nil }
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
        LoginAgreementBar(agreementAccepted: $agreementAccepted) { document in
            onOpenLegal()
            legalDocument = document
        }
    }
}

/// 账号密码登录页（对齐安卓 PasswordLoginScreen）：
/// 邮箱/手机号 + 密码 + 协议勾选，供自测与审核测试使用。
private struct PasswordLoginView: View {
    @Environment(SessionStore.self) private var session
    var onOpenLegal: () -> Void = {}

    @State private var account = ""
    @State private var password = ""
    @State private var agreementAccepted = false
    @State private var localError: String?
    @State private var legalDocument: LoginLegalDocument?
    @FocusState private var focusedField: Field?

    private enum Field { case account, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AppLogoImage(size: 72)
                    .padding(.top, 32)
                Text(NSLocalizedString("me_login_password_title", value: "账号密码登录", comment: ""))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                TextField(
                    NSLocalizedString("me_login_email_placeholder", value: "请输入邮箱或手机号", comment: ""),
                    text: $account
                )
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .account)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputFieldBackground))

                SecureField(
                    NSLocalizedString("me_login_password_placeholder", value: "请输入密码", comment: ""),
                    text: $password
                )
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputFieldBackground))

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if session.isWorking {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 20, height: 20)
                            Text(NSLocalizedString("me_password_login_button_loading", value: "登录中...", comment: ""))
                        } else {
                            Text(NSLocalizedString("me_password_login_button", value: "登录", comment: ""))
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentColor.opacity(session.isWorking ? 0.48 : 1)))
                }
                .buttonStyle(.plain)
                .disabled(session.isWorking)

                LoginAgreementBar(agreementAccepted: $agreementAccepted) { document in
                    onOpenLegal()
                    legalDocument = document
                }

                if let error = localError ?? session.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            // 整栏宽度按 Apple 登录按钮的内部上限收口，同级按钮与输入框一起等宽。
            .frame(maxWidth: Theme.authContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationDestination(item: $legalDocument) { document in
            LoginLegalWebPage(document: document)
        }
        .onAppear { focusedField = .account }
        .onChange(of: account) { _, _ in localError = nil }
        .onChange(of: password) { _, _ in localError = nil }
        .onChange(of: session.isAuthenticated) { _, authenticated in
            // 登录成功后清掉历史错误，避免返回登录主页时残留。
            if authenticated { localError = nil }
        }
    }

    private func submit() async {
        guard !session.isWorking else { return }
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        // 账号允许去掉首尾空白；密码必须原样提交，避免合法密码因客户端改写而无法登录。
        let submittedPassword = password
        if !agreementAccepted {
            localError = NSLocalizedString(
                "account_login_agreement_hint",
                value: "请先阅读并同意用户协议和隐私政策",
                comment: ""
            )
            return
        }
        if trimmedAccount.isEmpty || !PasswordLoginInputValidator.isEmailOrPhoneAccount(trimmedAccount) {
            localError = NSLocalizedString("me_login_enter_email", value: "请输入邮箱或手机号", comment: "")
            return
        }
        if submittedPassword.isEmpty {
            localError = NSLocalizedString("me_login_enter_password", value: "请输入密码", comment: "")
            return
        }
        focusedField = nil
        await session.signInWithEmail(account: trimmedAccount, password: submittedPassword)
    }

}

nonisolated enum PasswordLoginInputValidator {
    /// 对齐安卓 isEmailOrPhoneAccount：包含 @ 视为邮箱，否则按手机号校验。
    static func isEmailOrPhoneAccount(_ value: String) -> Bool {
        if value.contains("@") { return true }
        return value.range(of: #"^\+?[0-9][0-9 -]{5,20}$"#, options: .regularExpression) != nil
    }
}

/// 登录协议勾选条（对齐安卓 LoginAgreementBar），登录主页与密码登录页共用。
private struct LoginAgreementBar: View {
    @Binding var agreementAccepted: Bool
    var onOpen: (LoginLegalDocument) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                agreementAccepted.toggle()
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
                .font(.footnote)
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
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legalButton(_ document: LoginLegalDocument) -> some View {
        Button(document.linkTitle) {
            onOpen(document)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentColor)
        .accessibilityIdentifier("account_login_\(document.rawValue)_link")
    }
}

private struct LoginLegalWebPage: View {
    let document: LoginLegalDocument

    var body: some View {
        AppWebView(url: document.url)
            .background(Theme.backgroundColor)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("account_login_\(document.rawValue)_webview")
    }
}

// 对齐安卓 ProfileScreen（AccountProfileScreens.kt）：
// 头部卡（头像 + 昵称 + 会员徽章）+ 信息卡（昵称/会员身份/账号ID/注册时间/邮箱）+ 未登录登录按钮。
private struct AccountProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showRenameDialog = false
    @State private var showLogoutConfirmation = false
    @State private var showAccountDeletion = false
    @State private var showMembership = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProfileHeaderCard(
                    user: session.user,
                    loggedIn: session.isAuthenticated,
                    isVIP: session.isVIP
                )

                if let moderationLabel = profileModerationLabel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(moderationLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "B45309"))
                        if let reason = profileModerationReason {
                            Text(reason)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "FEF3C7")))
                }

                VStack(spacing: 0) {
                    ProfileNicknameRow(
                        label: NSLocalizedString("me_profile_display_name_label", value: "昵称", comment: ""),
                        value: profileDisplayText,
                        showEdit: session.isAuthenticated && session.user != nil
                    ) {
                        showRenameDialog = true
                    }
                    ProfileThinDivider()
                    if session.isVIP {
                        ProfileInfoRow(
                            label: NSLocalizedString("me_profile_vip_status_label", value: "会员状态", comment: ""),
                            value: profileMembershipLabel(session.user, isVIP: true),
                            valueColor: Theme.accentColor,
                            showChevron: true
                        ) { showMembership = true }
                    } else {
                        ProfileInfoRow(
                            label: NSLocalizedString("me_profile_vip_status_label", value: "会员状态", comment: ""),
                            value: profileMembershipLabel(session.user, isVIP: false),
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
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))
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
                    // 退出登录保持中性色（对齐安卓 DropdownMenuItem textPrimary，不用 destructive 红色）。
                    Button {
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
                        Label {
                            Text(NSLocalizedString("account_delete", value: "注销账号", comment: ""))
                        } icon: {
                            Image(uiImage: Theme.redTrashIcon)
                        }
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
        .navigationDestination(isPresented: $showMembership) {
            MembershipView()
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
        .sheet(isPresented: $showRenameDialog) {
            NicknameEditDialog(
                initialName: profileDisplayText,
                onDismiss: { showRenameDialog = false },
                onSubmit: { name in
                    switch await session.updateProfile(name: name) {
                    case .updated:
                        showRenameDialog = false
                        return nil
                    case .submittedForReview:
                        showRenameDialog = false
                        showToastMessage(NSLocalizedString(
                            "me_profile_nickname_review_submitted",
                            value: "昵称已提交审核，审核期间仅自己可见",
                            comment: ""
                        ))
                        return nil
                    case .failed(let message):
                        return message
                    }
                }
            )
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
            Text(logoutConfirmMessage)
        }
    }

    /// 退出登录确认文案：跨设备同步进行中时附加断开同步的说明（对齐安卓/鸿蒙端）。
    private var logoutConfirmMessage: String {
        var message = NSLocalizedString(
            "account_logout_confirm_message",
            value: "确定要退出当前账号吗？",
            comment: ""
        )
        if CloudSyncSession.shared.isActive {
            message += "\n\n" + NSLocalizedString(
                "account_logout_confirm_syncing",
                value: "正在进行跨设备同步，退出登录会断开同步，观看端将无法继续接收比分更新。",
                comment: ""
            )
        }
        return message
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

    /// 按昵称→头像的固定顺序展示，去重但不打乱顺序。
    private func joinedUnique(_ values: [String], separator: String) -> String? {
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: separator)
    }

    private var profileModerationLabel: String? {
        joinedUnique(
            [session.user?.nameVisibilityLabel, session.user?.avatarVisibilityLabel]
                .compactMap { $0?.nilIfBlank },
            separator: " · "
        )
    }

    private var profileModerationReason: String? {
        joinedUnique(
            [session.user?.nameModerationReviewReason, session.user?.avatarModerationReviewReason]
                .compactMap { $0?.nilIfBlank },
            separator: "\n"
        )
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
/// 影响说明卡 + VIP 会员警告卡 + 红色注销按钮 + 系统 Alert 二次确认。
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
        .alert(
            NSLocalizedString("account_deletion_confirm_title", value: "确认注销账号？", comment: ""),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("account_deletion_confirm_action", value: "确认注销", comment: ""), role: .destructive) {
                Task { await submit() }
            }
            Button(NSLocalizedString("account_deletion_confirm_cancel", value: "再想想", comment: ""), role: .cancel) { }
        } message: {
            Text(confirmMessage)
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
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))
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
private func profileMembershipLabel(_ user: AppUser?, isVIP: Bool) -> String {
    guard let user else {
        return isVIP
            ? NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
            : NSLocalizedString("me_profile_basic_badge", value: "普通用户", comment: "")
    }
    guard isVIP else {
        return NSLocalizedString("me_profile_basic_badge", value: "普通用户", comment: "")
    }
    // Only use server membership details when the server itself reports an
    // active membership. A local Apple entitlement otherwise uses a generic
    // VIP label instead of stale/inactive account metadata.
    guard user.isVIP else {
        return NSLocalizedString("me_profile_vip_badge", value: "VIP 会员", comment: "")
    }
    if let summary = user.membership?.identitySummary.nilIfBlank {
        return summary
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
    let isVIP: Bool

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
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.appCardBackground))
    }

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
        .clipShape(Circle())
    }

    private var avatarURL: URL? {
        APIAssetURLResolver.resolve(user?.avatarUrl ?? user?.avatar)
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

/// 修改昵称表单使用系统 Sheet：导航栏左上取消、右上保存，标题用系统默认字号字重。
private struct NicknameEditDialog: View {
    let initialName: String
    let onDismiss: () -> Void
    let onSubmit: (String) async -> String?

    @State private var name = ""
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var failedSubmittedName: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(
                    NSLocalizedString("me_profile_nickname_edit_placeholder", value: "请输入昵称", comment: ""),
                    text: $name
                )
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.inputFieldBackground))
                .submitLabel(.done)
                .onSubmit { Task { await submit() } }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .frame(maxWidth: 400)
            .navigationTitle(NSLocalizedString("me_profile_nickname_edit_title", value: "修改昵称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) {
                        onDismiss()
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        saving
                            ? NSLocalizedString("me_profile_nickname_saving", value: "保存中…", comment: "")
                            : NSLocalizedString("save", value: "保存", comment: "")
                    ) {
                        Task { await submit() }
                    }
                    .disabled(saving || failedSubmittedName == trimmedName)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .onAppear {
            name = initialName
            // 等系统 Sheet 呈现动画完成后再聚焦，避免焦点请求被转场吞掉。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                focused = true
            }
        }
        .onChange(of: name) { _, _ in
            guard failedSubmittedName != nil else { return }
            failedSubmittedName = nil
            errorMessage = nil
        }
    }

    private func submit() async {
        guard !saving else { return }
        let trimmed = trimmedName
        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString("me_profile_nickname_empty", value: "昵称不能为空", comment: "")
            return
        }
        guard trimmed.count <= 20 else {
            errorMessage = NSLocalizedString("me_profile_nickname_length", value: "昵称长度需在 1-20 个字符之间", comment: "")
            return
        }
        guard failedSubmittedName != trimmed else { return }
        errorMessage = nil
        saving = true
        let failureMessage = await onSubmit(trimmed)
        saving = false
        if let failureMessage, !failureMessage.isEmpty {
            errorMessage = failureMessage
            failedSubmittedName = trimmed
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
