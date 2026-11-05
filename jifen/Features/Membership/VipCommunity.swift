import SwiftUI
import StoreKit
import CoreImage.CIFilterBuiltins
import UIKit
import CryptoKit

func vipCommunityText(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, tableName: "VIPCommunity", value: fallback, comment: "")
}
@MainActor @Observable final class VipCommunityAvailability {
    static let shared = VipCommunityAvailability()
    var enabled = true
    var isPresenting = false
}
nonisolated struct VipCommunityConfig: Decodable, Identifiable, Sendable {
    var enabled: Bool
    var eligible: Bool
    var shouldPrompt: Bool
    var campaignId: String?
    var identityKey: String?
    var joinUrl: String?
    var title: String?
    var message: String?
    var titleEn: String?
    var messageEn: String?
    var id: String { "\(identityKey ?? ""):\(campaignId ?? "")" }
    var validatedURL: URL? {
        guard let value = joinUrl, let url = URL(string: value), url.scheme == "https",
              url.host == "work.weixin.qq.com", url.user == nil, url.password == nil, url.port == nil,
              url.path.range(of: "^/gm/[a-zA-Z0-9_-]+$", options: .regularExpression) != nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
nonisolated private struct VipCommunityRequest: Encodable, Sendable {
    var signedTransactionInfo: String?
    var campaignId: String?
    var identityKey: String?
}
@MainActor private enum VipCommunityPresentation {
    struct StoreProof {
        let jws: String
        let localIdentity: String
        func key(campaign: String) -> String { "vip.community.store.\(localIdentity):\(campaign)" }
    }
    static var owner: UUID?
    static func localKey(_ config: VipCommunityConfig) -> String { "vip.community.shown.\(config.id)" }
    static func proof() async -> StoreProof? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               StoreKitPurchaseManager.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil, !transaction.isUpgraded,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                let digest = SHA256.hash(data: Data(String(transaction.originalID).utf8))
                return StoreProof(jws: result.jwsRepresentation, localIdentity: digest.map { String(format: "%02x", $0) }.joined())
            }
        }
        return nil
    }
}
struct VipCommunityInvitationModifier: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    var active: Bool = true
    var manualRequest: Int = 0
    @State private var owner = UUID()
    @State private var invitation: VipCommunityConfig?
    @State private var invitationRevision: UInt64?
    @State private var invitationStoreKey: String?
    @State private var lastManualRequest = 0
    @State private var errorMessage: String?
    @State private var pageVisible = false
    private var taskKey: String { "\(session.user?.id ?? "guest"):\(session.user?.isVIP == true):\(session.state):\(session.isWorking):\(session.isVIP):\(active):\(scenePhase):\(manualRequest):\(pageVisible)" }
    func body(content: Content) -> some View {
        content
            .onAppear { pageVisible = true }
            .task(id: taskKey) { await offer() }
            .onChange(of: session.user?.id) { _, _ in close() }
            .onChange(of: session.isVIP) { _, vip in if !vip { close() } }
            .onDisappear { pageVisible = false; close() }
            .sheet(item: $invitation, onDismiss: { release() }) { config in
                VipCommunitySheet(config: config).onAppear {
                    UserDefaults.standard.set(true, forKey: VipCommunityPresentation.localKey(config))
                    if let invitationStoreKey { UserDefaults.standard.set(true, forKey: invitationStoreKey) }
                    Task { await acknowledge(config, revision: invitationRevision) }
                }
            }
            .alert(vipCommunityText("unavailable", "The VIP group is temporarily unavailable. Please try again later."), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button(vipCommunityText("ok", "OK"), role: .cancel) { errorMessage = nil } }
    }
    @MainActor private func offer() async {
        guard pageVisible, active, scenePhase == .active, session.state != .restoring, !session.isWorking,
              session.isVIP, invitation == nil else { return }
        let manual = manualRequest > lastManualRequest
        lastManualRequest = manualRequest
        let accountID = session.user?.id
        let revision = await AuthTokenStore.shared.authSessionRevision()
        do {
            let proof = await VipCommunityPresentation.proof()
            let jws = session.isAuthenticated && session.user?.isVIP == true ? nil : proof?.jws
            try Task.checkCancellation()
            let config: VipCommunityConfig = try await APIClient.shared.request(
                "/api/vip/community/access", method: .post,
                body: VipCommunityRequest(signedTransactionInfo: jws), requiresAuth: session.isAuthenticated,
                timeout: 10, retries: 0, expectedAuthRevision: revision
            )
            try Task.checkCancellation()
            let currentRevision = await AuthTokenStore.shared.authSessionRevision()
            guard accountID == session.user?.id, revision == currentRevision,
                  session.isVIP, active, pageVisible else { return }
            VipCommunityAvailability.shared.enabled = config.enabled
            guard config.enabled, config.eligible, config.validatedURL != nil, config.campaignId != nil, config.identityKey != nil else {
                if manual { errorMessage = "unavailable" }; return
            }
            let storeKey = config.campaignId.flatMap { proof?.key(campaign: $0) }
            let seen = UserDefaults.standard.bool(forKey: VipCommunityPresentation.localKey(config)) ||
                (storeKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false)
            if !manual, seen, config.shouldPrompt { await acknowledge(config, revision: revision); return }
            guard manual || (config.shouldPrompt && !seen && !AppReviewPrompt.requestedThisLaunch),
                  !session.presentsWechatUpgradePrompt, VipCommunityPresentation.owner == nil else { return }
            VipCommunityPresentation.owner = owner
            VipCommunityAvailability.shared.isPresenting = true
            invitationRevision = revision
            invitationStoreKey = storeKey
            invitation = config
        } catch is CancellationError { }
        catch {
            let currentRevision = await AuthTokenStore.shared.authSessionRevision()
            if manual && !Task.isCancelled && active && pageVisible && scenePhase == .active &&
                accountID == session.user?.id && revision == currentRevision { errorMessage = "unavailable" }
        }
    }
    @MainActor private func acknowledge(_ config: VipCommunityConfig, revision: UInt64?) async {
        let currentRevision = await AuthTokenStore.shared.authSessionRevision()
        guard session.isVIP, session.isAuthenticated, session.user?.isVIP == true,
              let revision, revision == currentRevision else { return }
        // Local StoreKit proof does not force sign-in or claim a purchase on an account.
        let _: EmptyResponse? = try? await APIClient.shared.request(
            "/api/vip/community/shown", method: .post,
            body: VipCommunityRequest(campaignId: config.campaignId, identityKey: config.identityKey), requiresAuth: true,
            timeout: 8, retries: 0, expectedAuthRevision: revision
        )
    }
    @MainActor private func release() {
        if VipCommunityPresentation.owner == owner {
            VipCommunityPresentation.owner = nil
            VipCommunityAvailability.shared.isPresenting = false
        }
    }
    @MainActor private func close() { invitation = nil; release() }
}
struct VipCommunityEntryBanner: View {
    var enabled: Bool
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image("ic_vip_community").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 30, height: 30).foregroundStyle(Theme.accentColor)
                    .frame(width: 46, height: 46)
                    .background(Theme.tintedFill(Theme.accentColor, lightAlpha: 0.12, darkAlpha: 0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(vipCommunityText("entry", "VIP community"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(vipCommunityText("entry_summary", "Share tips · Send feedback"))
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(Theme.tintedFill(Theme.accentColor, lightAlpha: 0.08, darkAlpha: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.55)
    }
}

private struct VipCommunitySheet: View {
    let config: VipCommunityConfig
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var status: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    /// 初始档位固定为小面板。显式 selection 才能保证首页自动弹出（首次提示）与会员页手动弹出
    /// 呈现同一高度；只给 detents 时，跟随首次布局弹出的那次可能落到大档位。
    @State private var detent: PresentationDetent = .height(540)
    private var wechatURL: URL? { URL(string: "weixin://") }
    private var hasWeChat: Bool { wechatURL.map { UIApplication.shared.canOpenURL($0) } ?? false }
    private var qrImage: UIImage? {
        guard let url = config.validatedURL else { return nil }
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(url.absoluteString.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        let size = CGSize(width: cgImage.width + 96, height: cgImage.height + 96)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cgImage).draw(at: CGPoint(x: 48, y: 48))
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(vipCommunityText("join_title", "Join the VIP community"))
                    .font(.title3.bold()).multilineTextAlignment(.center).padding(.horizontal, 24)
                Text(vipCommunityText("description", "Share tips, report issues, and suggest improvements."))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let image = qrImage {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 198, height: 198)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(status ?? vipCommunityText("scan_next", "After saving, select it from the album in WeChat Scan."))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        guard !saving else { return }
                        saveTask = Task { await save(image) }
                    } label: {
                        HStack(spacing: 8) {
                            if saving { ProgressView().tint(Theme.actionForeground(on: Theme.accentColor)) }
                            else { Image(systemName: "square.and.arrow.down") }
                            Text(saving ? vipCommunityText("saving", "Saving…") :
                                    (hasWeChat ? vipCommunityText("save_open_wechat", "Save and open WeChat") : vipCommunityText("save", "Save QR code")))
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(Theme.accentColor).foregroundStyle(Theme.actionForeground(on: Theme.accentColor))
                    .disabled(saving)
                }
                if let url = config.validatedURL {
                    Button(vipCommunityText("open_web", "Open group webpage")) {
                        openURL(url) { opened in
                            if !opened { status = vipCommunityText("unavailable", "The VIP group is temporarily unavailable. Please try again later.") }
                        }
                    }
                    .font(.subheadline).foregroundStyle(Theme.accentColor).disabled(saving)
                }
            }.padding(24).padding(.top, 16).frame(maxWidth: 440).frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            // 与其它弹窗共用关闭控件：13pt 图标 + 32pt 圆底在这类白色面板上偏小，
            // 统一到 ModalCloseButton(.standalone) 的 17pt 图标与 44pt 命中区。
            ModalCloseButton(placement: .standalone) { dismiss() }
                .accessibilityLabel(vipCommunityText("close", "Close"))
                .padding(8)
        }
        .tint(Theme.accentColor)
        .presentationDetents([.height(540), .large], selection: $detent).presentationDragIndicator(.visible)
        .onDisappear { saveTask?.cancel() }
    }
    @MainActor private func save(_ image: UIImage) async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        let photos = SystemScreenshotPhotoLibraryService()
        let authorization = photos.authorizationStatus() == .notDetermined ? await photos.requestAuthorization() : photos.authorizationStatus()
        guard !Task.isCancelled else { return }
        guard authorization == .allowed else { status = vipCommunityText("photos_denied", "Allow adding photos in Settings to save the QR code."); return }
        do {
            try await photos.save(image)
            guard !Task.isCancelled else { return }
            status = vipCommunityText("scan_saved", "Saved. Select it from the album in WeChat Scan.")
            if hasWeChat, let wechatURL {
                let opened = await UIApplication.shared.open(wechatURL)
                if !opened { status = vipCommunityText("saved_wechat_unavailable", "QR code saved. Unable to open WeChat; try the group webpage.") }
            }
        } catch is CancellationError { }
        catch { status = vipCommunityText("save_failed", "Unable to save. Please try again.") }
    }
}
extension View {
    func vipCommunityInvitation(active: Bool = true, manualRequest: Int = 0) -> some View {
        modifier(VipCommunityInvitationModifier(active: active, manualRequest: manualRequest))
    }
}
