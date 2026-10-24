import Observation
import SwiftUI

nonisolated func bindingText(_ key: String, bundle: Bundle = .main) -> String {
    bundle.localizedString(forKey: "wechat_binding_" + key, value: nil, table: "WechatBinding")
}

struct WechatBindingPromptSheet: View {
    var onBind: () -> Void
    var onLater: () -> Void
    @ScaledMetric(relativeTo: .body) private var bodySize = Theme.fontBody1

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image("WechatLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                Text(bindingText("upgrade_title").replacingOccurrences(of: "，", with: "，\n"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 16)
                    .accessibilityIdentifier("wechat_binding_prompt_title")
                Text(bindingText("upgrade_body"))
                    .font(.system(size: bodySize))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(5)
                    .padding(.top, 20)
                Button(action: onBind) {
                    Text(bindingText("bind_now"))
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Theme.textOnPrimary)
                        .background(Theme.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
                .accessibilityIdentifier("wechat_binding_prompt_bind")
                Button(action: onLater) {
                    Text(bindingText("later"))
                        .font(.system(size: bodySize))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.dialogControlBackground, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .accessibilityIdentifier("wechat_binding_prompt_later")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(400), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.dialogSurfaceBackground)
        .presentationSizing(.form)
    }
}

nonisolated enum AccountLoginMethodText {
    static func joined(_ providers: [String], bundle: Bundle = .main) -> String {
        var seen = Set<String>()
        return providers.compactMap { provider -> String? in
            let normalized = provider == "huawei_android" ? "huawei" : provider
            guard seen.insert(normalized).inserted else { return nil }
            switch normalized {
            case "apple": return "Apple"
            case "wechat": return bindingText("wechat", bundle: bundle)
            case "huawei": return bindingText("huawei", bundle: bundle)
            case "email", "password": return bindingText("password", bundle: bundle)
            case "google": return "Google"
            default: return nil
            }
        }.joined(separator: " / ")
    }

    static func normalized(_ provider: String) -> String {
        provider == "huawei_android" ? "huawei" : provider
    }

    /// 资料页「登录方式」行（方案二）：当前会话的登录方式置前并标注（当前），
    /// 其余方式跟随；旧令牌推断不出当前方式时返回 nil，回退为普通列表。
    static func currentFirstText(_ bindings: WechatBindingStatus) -> Text? {
        guard let sessionProvider = bindings.sessionProvider,
              bindings.providers.contains(normalized(sessionProvider)) else { return nil }
        let current = joined([normalized(sessionProvider)])
        let rest = joined(bindings.providers.filter { normalized($0) != normalized(sessionProvider) })
        let marker = NSLocalizedString("wechat_binding_login_current", tableName: "WechatBinding", comment: "")
        let head = Text(current).foregroundColor(Theme.accentColor) + Text(marker)
        return rest.isEmpty ? head : head + Text(" · " + rest)
    }
}

@MainActor @Observable
final class WechatBindingFlowModel {
    enum Stage { case authorizing, found, options, preview, working, success }
    private enum Action: Equatable { case prepare, preview, confirm }
    var stage: Stage = .authorizing
    var mode: AccountLinkMode = .merge
    var masterUserID = ""
    var accounts: AccountLinkAccounts?
    var preview: AccountLinkPreview?
    var errorMessage: String?
    var busy = false
    var cancelled = false
    var canRetry = true
    private let service: WechatBindingService
    private let authorizer: any WechatBindingAuthorizing
    private let commonData: CommonDataCloudSyncManager
    private let beginBinding: @MainActor (SessionStore) async throws -> WechatBindingSessionContext
    private var context: WechatBindingSessionContext?
    private var attempt: WechatBindingAttempt?
    private var ticket: String?
    private var confirmationRequestID: String?
    private var pendingAction: Action = .prepare
    private var confirmationInFlight = false
    private var hasStarted = false
    private var closed = false
    private var completed = false
    private var needsAuthorization = false

    init(service: WechatBindingService = WechatBindingService(),
         authorizer: (any WechatBindingAuthorizing)? = nil,
         commonData: CommonDataCloudSyncManager? = nil,
         beginBinding: (@MainActor (SessionStore) async throws -> WechatBindingSessionContext)? = nil) {
        self.service = service
        self.authorizer = authorizer ?? ProductionWechatAuthProvider.shared
        self.commonData = commonData ?? .shared
        self.beginBinding = beginBinding ?? { try await $0.beginWechatBinding() }
    }

    func start(session: SessionStore) async {
        guard !hasStarted, !closed else { return }
        hasStarted = true
        busy = true
        defer { busy = false }
        #if DEBUG
        if WechatBindingFixture.enabled {
            accounts = WechatBindingFixture.accounts
            masterUserID = WechatBindingFixture.accounts.current.id
            stage = .options
            return
        }
        #endif
        do {
            let context = try await beginBinding(session)
            self.context = context
            // Dismissal may finish while the session context is still being
            // created. Release that late context before starting authorization.
            guard !closed, !Task.isCancelled else {
                await session.endWechatBinding(context)
                self.context = nil
                return
            }
            try await authorize(session: session)
        } catch { handle(error) }
    }

    private func authorize(session: SessionStore) async throws {
        guard let context else { throw CancellationError() }
        guard !CloudSyncSession.shared.isActive else { throw LocalBindingError.activeSession }
        guard !GroupStore.shared.mutating else { throw LocalBindingError.activeSession }
        guard GroupStore.shared.uploads.isEmpty else { throw LocalBindingError.pendingUploads }
        busy = true
        stage = .authorizing
        defer { busy = false }
        try await session.validateWechatBinding(context)
        let code = try await authorizer.authorizeForBinding()
        try await session.validateWechatBinding(context)
        attempt = WechatBindingAttempt(code: code, authRevision: context.authRevision)
        needsAuthorization = false
        try await prepare(session: session)
    }

    private func prepare(session: SessionStore) async throws {
        guard let attempt, let context else { throw CancellationError() }
        pendingAction = .prepare
        try await session.validateWechatBinding(context)
        let result = try await service.prepare(attempt)
        try await session.validateWechatBinding(context)
        if result.status == "bound", let status = result.bindings {
            try await session.updateWechatBinding(status, context: context)
            completed = true
            stage = .success
        } else if let ticket = result.ticket, let accounts = result.accounts {
            self.ticket = ticket
            self.accounts = accounts
            masterUserID = accounts.current.id
            stage = .found
        } else { throw APIClientError.invalidResponse }
    }

    func showOptions() { stage = .options }
    func back() { preview = nil; confirmationRequestID = nil; stage = .options }

    func loadPreview(session: SessionStore) async {
        #if DEBUG
        if WechatBindingFixture.enabled {
            preview = WechatBindingFixture.preview(mode: mode, master: masterUserID)
            stage = .preview
            return
        }
        #endif
        guard !busy, !closed, let ticket, let context else { return }
        busy = true
        pendingAction = .preview
        defer { busy = false }
        do {
            try await session.validateWechatBinding(context)
            guard !closed else { throw CancellationError() }
            try await commonData.pauseForAccountLink(context: context)
            guard !closed else {
                await commonData.cancelAccountLink(context: context)
                throw CancellationError()
            }
            try await session.validateWechatBinding(context)
            let value = try await service.preview(ticket: ticket, mode: mode, masterUserID: masterUserID)
            try await session.validateWechatBinding(context)
            guard value.masterUserId == masterUserID, value.mode == mode else { throw APIClientError.invalidResponse }
            preview = value
            confirmationRequestID = UUID().uuidString
            stage = .preview
        } catch { handle(error) }
    }

    func confirm(session: SessionStore, recovering: Bool = false) async {
        #if DEBUG
        if WechatBindingFixture.enabled {
            guard preview?.canSubmit == true else { return }
            session.installWechatBindingFixture(masterUserID: masterUserID)
            stage = .success
            return
        }
        #endif
        guard !busy, !closed, let context, let ticket, let preview, preview.canSubmit,
              let requestID = confirmationRequestID else { return }
        busy = true
        pendingAction = .confirm
        confirmationInFlight = true
        stage = .working
        defer { busy = false; confirmationInFlight = false }
        do {
            if !recovering { try await session.validateWechatBinding(context) }
            let result: AccountLinkResponse
            if recovering {
                let receipt = try await service.recover(requestID: requestID, ticket: ticket)
                if receipt.status == "completed" { result = receipt }
                else {
                    try await session.validateWechatBinding(context)
                    result = try await service.confirm(ticket: ticket, previewToken: preview.previewToken, requestID: requestID)
                }
            } else {
                result = try await service.confirm(ticket: ticket, previewToken: preview.previewToken, requestID: requestID)
            }
            guard let auth = result.authentication, let bindings = result.bindings else { throw APIClientError.invalidResponse }
            try await session.applyLinkedAccount(auth, bindings: bindings, context: context)
            completed = true
            stage = .success
        } catch { handle(error) }
        if closed {
            busy = false
            confirmationInFlight = false
            await close(session: session)
        }
    }

    func retry(session: SessionStore) async {
        guard !closed else { return }
        errorMessage = nil
        if needsAuthorization {
            busy = true
            defer { busy = false }
            do { try await authorize(session: session) } catch { handle(error) }
            return
        }
        switch pendingAction {
        case .prepare:
            busy = true
            defer { busy = false }
            do {
                if attempt == nil { try await authorize(session: session) }
                else { try await prepare(session: session) }
            } catch { handle(error) }
        case .preview: await loadPreview(session: session)
        case .confirm: await confirm(session: session, recovering: true)
        }
    }

    func close(session: SessionStore) async {
        closed = true
        // A committed confirmation must finish installing its new credentials
        // and cloud baseline even if another window removes this sheet.
        if confirmationInFlight { return }
        guard let context else { return }
        self.context = nil
        await commonData.cancelAccountLink(context: context)
        await session.endWechatBinding(context)
        attempt = nil
        ticket = nil
    }

    private func handle(_ error: Error) {
        busy = false
        if error is CancellationError || (error as? WechatAuthError) == .cancelled {
            cancelled = true
            return
        }
        canRetry = true
        if let authError = error as? WechatAuthError {
            errorMessage = authError.localizedDescription
            return
        }
        if error is CommonDataAccountLinkError {
            errorMessage = bindingText("quota")
            canRetry = false
            return
        }
        if let local = error as? LocalBindingError {
            errorMessage = bindingText(local == .activeSession ? "active_session" : "pending_uploads")
            canRetry = false
            return
        }
        if case .server(_, let code, _, _) = error as? APIClientError {
            switch code {
            case "LINK_PREVIEW_STALE":
                stage = .options
                preview = nil
                confirmationRequestID = nil
                pendingAction = .preview
                errorMessage = bindingText("preview_stale")
            case "LINK_EXPIRED", "LINK_TICKET_EXPIRED", "WECHAT_AUTHORIZATION_FAILED":
                attempt = nil
                ticket = nil
                needsAuthorization = true
                errorMessage = bindingText("authorization_expired")
            case "ACCOUNT_MERGE_NOT_AVAILABLE", "BINDING_DISABLED":
                canRetry = false
                errorMessage = bindingText("unavailable")
            case "BINDING_SESSION_UNSUPPORTED":
                canRetry = false
                errorMessage = bindingText("sign_in_again")
            default: errorMessage = bindingText("failed")
            }
        } else if error as? APIClientError == .sessionExpired || error as? APIClientError == .unauthorized {
            canRetry = pendingAction == .confirm
            errorMessage = bindingText(canRetry ? "recover_result" : "sign_in_again")
        } else {
            errorMessage = bindingText(pendingAction == .confirm ? "recover_result" : "failed")
        }
    }

    private enum LocalBindingError: Error, Equatable { case activeSession, pendingUploads }
}

struct WechatBindingSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model = WechatBindingFlowModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .disabled(model.busy)
                    .padding(20)
                    .frame(maxWidth: Theme.authContentMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("wechat_binding_content")
            .background(Theme.backgroundColor)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.stage == .preview {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(bindingText("back")) { model.back() }.disabled(model.busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { Task { await close() } }.disabled(model.busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
        .interactiveDismissDisabled(model.busy)
        .task { await model.start(session: session) }
        .onChange(of: model.cancelled) { _, value in if value { Task { await close() } } }
        .onDisappear { Task { await model.close(session: session) } }
        .alert(bindingText("error_title"), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.canRetry {
                Button(bindingText("retry")) { Task { await model.retry(session: session) } }
                Button(bindingText("cancel"), role: .cancel) { Task { await close() } }
            } else {
                Button(bindingText("okay"), role: .cancel) { Task { await close() } }
            }
        } message: { Text(model.errorMessage ?? "") }
        .accessibilityIdentifier("wechat_binding_sheet")
    }

    private var title: String {
        switch model.stage {
        case .found, .options: return bindingText("link_title")
        case .preview: return bindingText("preview_title")
        case .success: return bindingText("success_title")
        default: return bindingText("bind")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .authorizing, .working:
            VStack(spacing: 16) {
                ProgressView()
                Text(bindingText(model.stage == .working ? "working" : "authorizing"))
                    .font(.headline)
                Text(bindingText("wait"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        case .found:
            Text(bindingText("found_title")).font(.title2.bold())
            Text(bindingText("found_body")).font(.subheadline).foregroundStyle(.secondary)
            if let accounts = model.accounts {
                accountCard(accounts.current, selected: false)
                accountCard(accounts.wechat, selected: false)
            }
        case .options:
            Text(bindingText("mode_title")).font(.headline)
            modeCard(.merge, title: "merge", detail: "merge_detail")
            modeCard(.keep, title: "keep", detail: "keep_detail")
            VStack(alignment: .leading, spacing: 6) {
                Text(bindingText("master_title")).font(.headline)
                Text(bindingText("master_detail")).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            if let accounts = model.accounts {
                Button { model.masterUserID = accounts.current.id } label: {
                    accountCard(accounts.current, selected: model.masterUserID == accounts.current.id)
                }.buttonStyle(.plain).accessibilityIdentifier("wechat_binding_master_current")
                    .accessibilityValue(model.masterUserID == accounts.current.id ? "1" : "0")
                Button { model.masterUserID = accounts.wechat.id } label: {
                    accountCard(accounts.wechat, selected: model.masterUserID == accounts.wechat.id)
                }.buttonStyle(.plain).accessibilityIdentifier("wechat_binding_master_wechat")
                    .accessibilityValue(model.masterUserID == accounts.wechat.id ? "1" : "0")
            }
            Text(bindingText("membership_rule")).font(.footnote).foregroundStyle(.secondary)
        case .preview:
            if let preview = model.preview {
                accountCard(preview.masterAccount, selected: false)
                VStack(spacing: 0) {
                    fact("mode_title", bindingText(preview.mode == .merge ? "merge" : "keep"))
                    fact("membership", membership(preview.summary.assets.membership))
                    fact("groups", amount(preview.summary.groups.groupCount))
                    fact("names", amount(preview.summary.assets.commonNameCount))
                    fact("places", amount(preview.summary.assets.commonPlaceCount))
                    fact("records", amount(preview.summary.groups.recordCount))
                    fact("login_after", AccountLoginMethodText.joined(preview.accounts.current.providers + preview.accounts.wechat.providers))
                }
                .background(Theme.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
                if preview.summary.assets.showsAutomaticRenewalWarning {
                    notice(bindingText("automatic_renewal_warning"), warning: true)
                        .accessibilityIdentifier("wechat_binding_automatic_renewal_warning")
                }
                if preview.mode == .merge { notice(bindingText("group_merge")) }
                if (preview.summary.groups.selfMatchCount ?? 0) > 0 { notice(bindingText("self_match")) }
                if preview.mode == .keep { notice(bindingText("keep_warning"), warning: true) }
                ForEach(Array(preview.blockers.enumerated()), id: \.offset) { _, blocker in
                    notice(blockerMessage(blocker), warning: true)
                }
                Text(bindingText("cloud_scope")).font(.footnote).foregroundStyle(.secondary)
            }
        case .success:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.accentColor)
                Text(bindingText("success_title")).font(.title2.bold())
                Text(bindingText("success_body")).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 16)
            VStack(spacing: 0) {
                fact("retained_account", session.user?.uid ?? session.user?.id ?? "—")
                fact("login_after", AccountLoginMethodText.joined(session.wechatBindingStatus?.providers ?? []))
            }.background(Theme.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private var footer: some View {
        if model.stage != .authorizing && model.stage != .working {
            VStack(spacing: 10) {
                Button {
                    switch model.stage {
                    case .found: model.showOptions()
                    case .options: Task { await model.loadPreview(session: session) }
                    case .preview: Task { await model.confirm(session: session) }
                    case .success: Task { await close() }
                    default: break
                    }
                } label: {
                    HStack {
                        if model.busy { ProgressView().tint(.white) }
                        Text(footerTitle).fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).frame(minHeight: 46)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accentColor)
                .disabled(model.busy || (model.stage == .preview && model.preview?.canSubmit != true))
                .accessibilityIdentifier("wechat_binding_primary")
                if model.stage == .preview {
                    Text(bindingText("confirm_detail")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: Theme.authContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
                // 与会员页底部一致的渐隐：滚动内容在接近固定按钮区时淡出。
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Theme.backgroundColor.opacity(0), Theme.backgroundColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 28)
                    .offset(y: -28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }

    private var footerTitle: String {
        switch model.stage {
        case .found: return bindingText("continue")
        case .options: return bindingText("next")
        case .preview: return bindingText("confirm")
        default: return bindingText("okay")
        }
    }

    private func accountCard(_ account: AccountLinkAccount, selected: Bool) -> some View {
        HStack(spacing: 12) {
            if model.stage == .options {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? Theme.accentColor : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.name ?? bindingText("default_name")).font(.headline).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    loginMethodBadge(account.providers)
                }
                Text("ID " + account.uid).font(.footnote).foregroundStyle(.secondary)
                if let membership = account.membership, membership.isActive {
                    Text(membership.localizedTitle()).font(.caption).foregroundStyle(Theme.accentColor)
                }
                if let counts = account.counts {
                    Text("\(bindingText("groups")) \(counts.groups) · \(bindingText("names")) \(counts.commonNames) · \(bindingText("records")) \(counts.records)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.accentColor.opacity(0.08) : Theme.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.accentColor : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// 登录方式角标：昵称行右上方的胶囊（HTML Demo 选定方案），字号比原信息行大一号。
    private func loginMethodBadge(_ providers: [String]) -> some View {
        HStack(spacing: 4) {
            providerIcon(providers.first)
            Text(AccountLoginMethodText.joined(providers))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    @ViewBuilder private func providerIcon(_ provider: String?) -> some View {
        switch provider {
        case "apple":
            Image(systemName: "apple.logo").font(.system(size: 13, weight: .semibold))
        case "wechat":
            Image("WechatLogo").resizable().scaledToFit().frame(width: 14, height: 14)
        default:
            EmptyView()
        }
    }

    private func modeCard(_ mode: AccountLinkMode, title: String, detail: String) -> some View {
        Button { model.mode = mode } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.mode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.mode == mode ? Theme.accentColor : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(bindingText(title)).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(bindingText(detail)).font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14)
                .background(model.mode == mode ? Theme.accentColor.opacity(0.08) : Theme.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.mode == mode ? Theme.accentColor : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("wechat_binding_mode_" + mode.rawValue)
            .accessibilityValue(model.mode == mode ? "1" : "0")
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(bindingText(label)).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline).padding(13)
    }

    private func notice(_ message: String, warning: Bool = false) -> some View {
        Text(message).font(.footnote).foregroundStyle(warning ? Color.orange : Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Theme.appCardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func amount(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func membership(_ value: AccountLinkPreview.Membership?) -> String {
        guard let value else { return bindingText("free") }
        let title = MembershipDisplayText.title(billingCycle: value.billingCycle)
        if let expiry = value.expiresAt, let date = APIDateParser.date(from: expiry) {
            return title + " · " + date.formatted(date: .numeric, time: .omitted)
        }
        return value.tier == "free" || value.tier == "FREE" ? bindingText("free") : title
    }

    private func blockerMessage(_ blocker: AccountLinkPreview.Blocker) -> String {
        switch blocker.code {
        case "OWNER_TRANSFER_REQUIRED", "SOURCE_OWNS_GROUPS", "SOURCE_GROUP_OWNER", "KEEP_SOURCE_IS_OWNER": return bindingText("owner_blocked")
        case "ACTIVE_LIVE_MATCH", "ACCOUNT_MERGE_GAME_IN_PROGRESS", "ACTIVE_MATCH", "ACTIVE_SESSION", "ACTIVE_SYNC_SESSION": return bindingText("active_session")
        case "ACCOUNT_MERGE_LINEUP_CONFLICT", "ACCOUNT_MERGE_FUTURE_SEAT_CONFLICT", "FUTURE_SEAT_CONFLICT", "FUTURE_SESSION_CONFLICT": return bindingText("future_seats")
        case "COMMON_DATA_QUOTA_EXCEEDED", "COMMON_DATA_LIMIT", "COMMON_DATA_LIMIT_EXCEEDED", "COMMON_DATA_QUOTA": return bindingText("quota")
        default:
            if Bundle.main.preferredLocalizations.first == "zh-Hans" { return blocker.message }
            return bindingText("blocked")
        }
    }

    private func close() async { await model.close(session: session); dismiss() }
}
