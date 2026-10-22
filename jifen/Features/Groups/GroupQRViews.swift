import SwiftUI
import PhotosUI
import Vision
import VisionKit
import CoreImage.CIFilterBuiltins

struct GroupJoinView: View {
    private enum InputField: Hashable { case number, message }
    private enum Sheet: String, Identifiable {
        case scanner, report, login
        var id: String { rawValue }
    }
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var usesParentNavigation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var store = GroupStore.shared
    @State private var number = ""
    @State private var message = ""
    @FocusState private var focusedInput: InputField?
    @State private var preview: GroupPreview?
    @State private var previewRevision = 0
    @State private var joinedID: String?
    @State private var waiting = false
    @State private var busy = false
    @State private var sheet: Sheet?
    @State private var submitting = false
    @State private var photoGeneration = 0
    @State private var key = UUID().uuidString
    @State private var photo: PhotosPickerItem?
    @State private var localError: String?
    /// 邀请链接带号进入：已是成员时直接进详情，不停留加入页（对齐微信「已在群聊直接进群」）。
    @State private var seededEntry = false
    @State private var seededAutoOpened = false
    init(initialGroupNo: String = "", onStart: @escaping (GameType, SportsSetupResult, String) -> Void, usesParentNavigation: Bool = false) {
        self.onStart = onStart
        self.usesParentNavigation = usesParentNavigation
        _number = State(initialValue: GroupInvitationLink.validNumber(initialGroupNo, capabilities: GroupStore.shared.capabilities) ? initialGroupNo : "")
        _seededEntry = State(initialValue: GroupInvitationLink.validNumber(initialGroupNo, capabilities: GroupStore.shared.capabilities))
    }
    var body: some View {
        if usesParentNavigation { destination }
        else { NavigationStack { destination } }
    }
    private var previewTaskID: String {
        "\(number):\(store.identityRevision):\(session.isAuthenticated):\(session.user?.id ?? "")"
    }
    @ViewBuilder private var destination: some View {
        if let joinedID { GroupDetailView(groupID: joinedID, onStart: onStart, welcomeBack: preview?.effectiveAvailability == "already_member") }
        else { editor }
    }
    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                if !seededEntry {
                    Button { focusedInput = nil; sheet = .scanner } label: {
                        HStack(spacing: Theme.spacing) {
                            Image(systemName: "qrcode.viewfinder").font(.system(size: Theme.fontH3)).foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                Text(groupText("scan", "Scan QR code")).font(.system(size: Theme.fontBody2, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text(groupText("join_scan_hint", "Scan a group QR code")).font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                        }.padding(Theme.md).frame(minHeight: 64)
                            .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("group_join_scan")
                    HStack(spacing: Theme.md) {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 1)
                        Text(groupText("join_number_separator", "Or enter a group number"))
                            .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 1)
                    }.accessibilityIdentifier("group_join_number_separator")
                }
                TextField("", text: $number, prompt: Text(groupText("number", "6–8 digit group number"))
                    .font(.system(size: Theme.fontBody1, weight: .regular))).keyboardType(.numberPad)
                    .font(.system(size: Theme.fontH3, weight: .semibold)).monospacedDigit().multilineTextAlignment(.center)
                    .accessibilityLabel(groupText("number", "6–8 digit group number"))
                    .padding(Theme.md).frame(minHeight: 56)
                    .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
                    .focused($focusedInput, equals: .number).accessibilityIdentifier("group_number")
                Text(groupText("join_number_hint", "6–8 digits. Ask the group owner."))
                    .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if let preview { previewCard(preview) }
                if let error = localError ?? store.error { GroupNotice(text: error) }
                if busy { ProgressView().frame(maxWidth: .infinity) }
            }.padding(Theme.padding).frame(maxWidth: 720).expandedPhonePageContent(existingHorizontalInset: Theme.padding).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Theme.backgroundColor)
            .disabled(submitting).interactiveDismissDisabled(submitting)
            // This public invitation page survives sign-in; account-only detail pages keep their boundary.
            .navigationTitle(groupText("join", "Join group")).navigationBarTitleDisplayMode(.inline)
            .groupAdaptiveOrientation().toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(usesParentNavigation && submitting)
            .toolbar {
                if !usesParentNavigation { ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("done", value: "完成", comment: "")) { focusedInput = nil }
                        .tint(Theme.primary).accessibilityIdentifier("group_keyboard_done")
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .scanner:
                    NavigationStack { GroupScannerView(photo: $photo) { raw in sheet = nil; receive(raw) } }
                case .report:
                    GroupPreviewReportView(groupNo: number)
                case .login:
                    AccountLoginSheet()
                }
            }
            #if DEBUG
            .overlay(alignment: .bottom) {
                if GroupJoinAuthUITestFixture.enabled {
                    Color.clear.frame(width: 1, height: 1).accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("group_join_auth_fixture").accessibilityLabel("group_join_auth_fixture")
                        .accessibilityValue(GroupJoinAuthUITestFixture.shared.metadata).allowsHitTesting(false)
                }
            }
            #endif

            .onChange(of: number) { _, _ in seededEntry = false; message = "" }
            .onChange(of: previewTaskID) { _, _ in
                previewRevision &+= 1; busy = false; preview = nil; waiting = false; joinedID = nil; localError = nil; key = UUID().uuidString
                photoGeneration += 1; photo = nil; seededAutoOpened = false
                if sheet == .report { sheet = nil }
            }
            .onChange(of: message) { _,_ in key = UUID().uuidString }
            .onChange(of: photo) { _, item in if item != nil { sheet = nil; Task { await decodePhoto(item) } } }
            .task(id: previewTaskID) {
                guard GroupQRPayload.validNumber(number, capabilities: store.capabilities) else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                await loadPreview()
            }
    }
    private func previewCard(_ preview: GroupPreview) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if preview.effectiveAvailability == "not_found" {
                GroupNotice(text: groupText("lookup_not_found", "Group not found, check the number"))
            } else {
                HStack(alignment: .center, spacing: Theme.spacing) {
                    if let sport = preview.sport { AppCatalogIcon(gameType: sport.gameType, size: 40) }
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text(preview.name).font(.system(size: Theme.fontBody1, weight: .semibold)).lineLimit(2).accessibilityIdentifier("group_preview_name")
                        Text([preview.sport?.title, groupMemberCountText(preview.memberCount), GroupQRPayload.formatted(preview.groupNo)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(GroupStatusText.joinAvailability(waiting ? "pending_approval" : preview.effectiveAvailability))
                        .font(.system(size: Theme.fontCaption, weight: .medium)).foregroundStyle(!waiting && preview.effectiveAvailability == "available" ? Theme.primary : Theme.textSecondary)
                        .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                        .background(Theme.tintedFill(!waiting && preview.effectiveAvailability == "available" ? Theme.primary : Theme.textSecondary, lightAlpha: 0.10, darkAlpha: 0.16), in: Capsule())
                        .accessibilityIdentifier("group_join_availability")
                    if session.isAuthenticated {
                        Menu {
                            Button(groupText("report", "Report group")) { sheet = .report }
                                .accessibilityIdentifier("group_join_preview_report")
                        } label: {
                            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                                .foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).disabled(busy)
                            .accessibilityLabel(NSLocalizedString("more", comment: ""))
                            .accessibilityIdentifier("group_join_preview_more")
                    }
                }
                if !preview.description.isEmpty { Text(preview.description).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary) }
                if preview.groupType == "coaching" { Text(groupText("coaching", "Coaching group")).font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary) }
                if waiting || preview.effectiveAvailability == "pending_approval" {
                    if let requestID = preview.requestId { Button(groupText("withdraw", "Withdraw request"), role: .destructive) { Task { if await store.perform({ try await store.repository.action("/join-requests/\(requestID)/withdraw") }) { waiting = false; await loadPreview(); await store.refresh() } } }.disabled(busy) }
                } else if preview.effectiveAvailability == "already_member" {
                    Button(groupText("open_group", "Open group")) {
                        Task { await store.refresh(); joinedID = preview.groupId ?? store.groups.first(where: { $0.groupNo == preview.groupNo })?.id }
                    }
                } else if preview.effectiveAvailability == "available" {
                    if preview.joinPolicy == "approval" { TextField(groupText("join_message", "Message to the group (optional)"), text: $message).font(.system(size: Theme.fontBody2)).tint(Theme.primary)
                        .padding(.horizontal, 14).padding(.vertical, Theme.spacing).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(GroupEditorColors.insetInput, in: RoundedRectangle(cornerRadius: 12)).focused($focusedInput, equals: .message).accessibilityIdentifier("group_join_message") }
                    Button(groupText(preview.joinPolicy == "approval" ? "request_join" : "confirm_join", preview.joinPolicy == "approval" ? "Request to join" : "Join")) {
                        Task { await join() }
                    }.disabled(busy || !GroupInputValidation.validText(message, maximum: GroupInputValidation.joinMessageMax) || preview.groupNo != number || !(store.capabilities?.allows("join_group") ?? true))
                        .accessibilityIdentifier("group_join_submit")
                } else { GroupNotice(text: groupText("unavailable", "This group cannot accept new members.")) }
                if preview.hasPendingRequest && preview.effectiveAvailability != "pending_approval", let requestID = preview.requestId {
                    Button(groupText("withdraw", "Withdraw request"), role: .destructive) { Task { if await store.perform({ try await store.repository.action("/join-requests/\(requestID)/withdraw") }) { waiting = false; await loadPreview(); await store.refresh() } } }.disabled(busy)
                }
            }
        }.padding(Theme.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(GroupAlignedActionStyle())
    }
    private func receive(_ raw: String) {
        guard let code = GroupQRPayload.parse(raw, capabilities: store.capabilities) else { localError = groupText("invalid_qr", "This is not a valid group QR code."); return }
        if number == code { Task { await loadPreview() } } else { number = code }
    }
    private func loadPreview() async {
        let requestedNumber = number, requestedSession = previewTaskID
        previewRevision &+= 1; let requestRevision = previewRevision
        busy = true; defer { if previewRevision == requestRevision { busy = false } }; localError = nil
        let authenticated = session.isAuthenticated
        do {
            let loaded: GroupPreview = try await store.repository.read("/by-number/\(requestedNumber)/preview", authenticated: authenticated)
            guard previewTaskID == requestedSession, previewRevision == requestRevision, !Task.isCancelled else { return }
            preview = loaded; waiting = loaded.effectiveAvailability == "pending_approval"
            if seededEntry, !seededAutoOpened, loaded.effectiveAvailability == "already_member" {
                // 与「打开小组」按钮同一条路径：先刷新成员列表，再按 groupId / 号码兜底定位。
                seededAutoOpened = true
                await store.refresh()
                guard previewTaskID == requestedSession, previewRevision == requestRevision, !Task.isCancelled else { return }
                if let groupID = loaded.groupId ?? store.groups.first(where: { $0.groupNo == loaded.groupNo })?.id {
                    joinedID = groupID
                }
            }
        } catch {
            if previewTaskID == requestedSession, previewRevision == requestRevision, !Task.isCancelled { localError = groupErrorMessage(error) }
        }
    }
    private func join() async {
        guard !busy, !submitting, sheet == nil,
              preview?.groupNo == number, preview?.effectiveAvailability == "available",
              GroupInputValidation.validText(message, maximum: GroupInputValidation.joinMessageMax),
              store.capabilities?.allows("join_group") ?? true else { return }
        guard session.isAuthenticated else {
            focusedInput = nil
            photoGeneration += 1; photo = nil
            sheet = .login
            return
        }
        // 只要求账号已就绪；账号与当前登录身份是否一致由 store.perform 内部校验并给出
        // 可见错误。这里若再静默 return，刚登录后身份尚未同步时点「加入」会毫无反应。
        guard let accountID = store.accountID else { return }
        busy = true; submitting = true; defer { busy = false; submitting = false }
        let accountRevision = store.identityRevision, requestedNumber = number
        let requestMessage = message, requestKey = key
        let success = await store.perform {
            let outcome: GroupJoinOutcome = try await store.repository.write("/by-number/\(requestedNumber)/join", body: GroupActionBody(message: requestMessage), key: requestKey)
            guard store.matchesIdentity(accountID, revision: accountRevision), number == requestedNumber else { return }
            if let groupID = outcome.groupId, outcome.kind != "pending" { joinedID = groupID } else { waiting = true }
        }
        if success { await store.refresh(); if waiting { await loadPreview() } }
    }
    private func decodePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoGeneration += 1; let generation = photoGeneration, identity = store.identityRevision, inputRevision = previewRevision
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard photoGeneration == generation, store.identityRevision == identity, previewRevision == inputRevision, !submitting else { return }
            let candidates = await Task.detached(priority: .userInitiated) { GroupPhotoQRDecoder.candidates(in: data) }.value
            guard photoGeneration == generation, store.identityRevision == identity, previewRevision == inputRevision, !submitting else { return }
            guard let raw = candidates.first(where: { GroupQRPayload.parse($0, capabilities: store.capabilities) != nil }) else { throw GroupFormError.invalidQR }
            receive(raw)
        } catch { if photoGeneration == generation, store.identityRevision == identity, previewRevision == inputRevision { localError = groupErrorMessage(error) } }
        if photoGeneration == generation { photo = nil }
    }
}

private nonisolated enum GroupPhotoQRDecoder {
    static func candidates(in data: Data) -> [String] {
    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
    var candidates: [String] = []
    do {
        try VNImageRequestHandler(data: data).perform([request])
        candidates = request.results?.compactMap(\.payloadStringValue) ?? []
    } catch {
        // The simulator can lack Vision's inference runtime; use the CPU QR detector.
        if let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
           let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                     context: CIContext(options: [.useSoftwareRenderer: true]),
                                     options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) {
            candidates = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        }
    }
        return candidates
    }
}

struct GroupScannerView: View {
    @Binding var photo: PhotosPickerItem?
    var onValue: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paused = false
    var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRDataScannerView(paused: paused) { value in guard !paused else { return }; paused = true; onValue(value) }
            } else { ContentUnavailableView(groupText("camera_unavailable", "Camera unavailable"), systemImage: "camera", description: Text(groupText("camera_hint", "Allow camera access in Settings, or choose a photo."))) }
        }.navigationTitle(groupText("scan", "Scan QR code"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                        .accessibilityLabel(groupText("album", "Choose photo")).accessibilityIdentifier("group_scan_photo")
                }
            }
    }
}

struct GroupShareView: View {
    let group: ScoreGroup
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage?
    @State private var livePreview: GroupPreview?
    @State private var shareError: String?
    @State private var inviteCard: UIImage?
    private var approval: Bool { livePreview.map { $0.joinPolicy == "approval" } ?? false }
    private var canInvite: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return group.isActive && group.joinPolicy != "closed" }
        #endif
        return livePreview.map(GroupPermissions.canInvite) ?? false
    }
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 20) {
                // 对齐安卓：小组名与小组号合成一个安静的标题块，不再分散在二维码上下。
                VStack(spacing: Theme.xs) {
                    Text(group.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                    Text(String(format: groupText("share_no", "Group No. %@"), group.groupNo))
                        .font(GroupTypography.body.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity)
                if let image = qrImage { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: min(300, max(120, geometry.size.height * 0.45))).background(.white).accessibilityLabel(groupText("group_qr", "Group QR code")).accessibilityIdentifier("group_qr") }
                if shareError == nil { Text(canInvite ? (group.joinPolicy == "open" ? groupText("qr_join_short", "Scan to join") : groupText("qr_apply_short", "Scan to request to join") + " · " + groupText("pending_approval", "Awaiting approval")) : groupText("unavailable", "This group cannot accept new members.")).multilineTextAlignment(.center).font(GroupTypography.body).foregroundStyle(Theme.textSecondary) }
                if let shareError { GroupNotice(text: shareError) }
                if canInvite, let url = GroupInvitationLink.joinURL(groupNo: group.groupNo, capabilities: GroupStore.shared.capabilities) {
                    ShareLink(item: url, subject: Text(group.name), message: Text(GroupInvitationText.message(group: group, capabilities: GroupStore.shared.capabilities))) {
                        Text(groupText("audit_ui_share_invitation", "Share invitation")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GroupAlignedActionStyle()).accessibilityIdentifier("group_share_invitation_link")
                    if let card = inviteCard {
                        ShareLink(item: Image(uiImage: card), subject: Text(group.name), message: Text(GroupInvitationText.message(group: group, capabilities: GroupStore.shared.capabilities)), preview: SharePreview(group.name, image: Image(uiImage: card))) { Text(groupText("audit_ui_share_qr", "Share QR code")).frame(maxWidth: .infinity) }
                            .buttonStyle(GroupAlignedActionStyle(secondary: true, secondaryForeground: Theme.textPrimary)).accessibilityIdentifier("group_share_invitation_card")
                    } else if livePreview != nil {
                        // 对齐安卓 shareGroupQr 失败路径：卡片合成失败要可感知，而不是按钮悄悄消失。
                        GroupNotice(text: groupText("audit_ui_share_failed", "Sharing failed. Try again."))
                    }
                } else if livePreview != nil {
                    // 对齐安卓：不可加入时仍可把小组号以文案形式分享出去。
                    ShareLink(item: String(format: groupText("audit_ui_group_number_message", "Group: %@\nGroup number: %@ (not accepting members)"), group.name, group.groupNo)) {
                        Label(groupText("audit_ui_share_number", "Share group number"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(GroupAlignedActionStyle(secondary: true, secondaryForeground: Theme.textPrimary))
                    .accessibilityIdentifier("group_share_number")
                }
            }.padding(Theme.lg).expandedPhonePageContent(existingHorizontalInset: Theme.lg).frame(maxWidth: .infinity)
        }
        }.background(Theme.backgroundColor)
            .navigationTitle(groupText("group_qr", "Group QR code")).navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return }
                #endif
                let store = GroupStore.shared; let revision = store.identityRevision
                do {
                    let preview: GroupPreview = try await store.repository.read("/by-number/\(group.groupNo)/preview", authenticated: SessionStore.shared.isAuthenticated)
                    guard store.identityRevision == revision else { return }
                    livePreview = preview
                    // 合成 720×920 卡片有开销，只在预览就绪后做一次，不放进 body。
                    inviteCard = GroupInviteCard.image(name: group.name, groupNo: group.groupNo, approval: preview.joinPolicy == "approval")
                } catch { if store.identityRevision == revision { shareError = groupErrorMessage(error) } }
            }
    }
    private var qrImage: UIImage? { GroupQRCode.image(group.groupNo) }
}

struct GroupQRCode: View {
    var number: String
    var size: CGFloat
    var body: some View {
        if let image = Self.image(number) { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: size, height: size) }
    }
    static func image(_ number: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(GroupQRPayload.encode(number, capabilities: GroupStore.shared.capabilities).utf8)
        // 对齐安卓 ErrorCorrectionLevel.H：中心要盖住一块 App 图标，必须把容错提到 30%。
        filter.correctionLevel = "H"
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        let size: CGFloat = 640, quiet: CGFloat = 64
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: size, height: size)); context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cg).draw(in: CGRect(x: quiet, y: quiet, width: size - quiet * 2, height: size - quiet * 2))
            // 把圆角 App 图标烤进位图，屏上预览与导出的卡片才不会两个样。
            guard let icon = appIcon else { return }
            let iconSize = size * 0.18, inset = (size - iconSize) / 2, radius = iconSize * 0.25, padding = size * 0.015
            let bounds = CGRect(x: inset, y: inset, width: iconSize, height: iconSize)
            context.cgContext.interpolationQuality = .high
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bounds.insetBy(dx: -padding, dy: -padding), cornerRadius: radius + padding).fill()
            UIBezierPath(roundedRect: bounds, cornerRadius: radius).addClip()
            icon.draw(in: bounds)
            context.cgContext.resetClip()
        }
    }
    /// iOS 拿不到 AppIcon 图集里的图（只有 macOS 可以），退回到项目内的 AppLogo，
    /// 与安卓读取 `mipmap/ic_launcher` 是同一个角色。
    static let appIcon: UIImage? = {
        if let logo = UIImage(named: "AppLogo") { return logo }
        for key in ["CFBundleIcons~ipad", "CFBundleIcons"] {
            let files = (Bundle.main.infoDictionary?[key] as? [String: Any])
                .flatMap { $0["CFBundlePrimaryIcon"] as? [String: Any] }
                .flatMap { $0["CFBundleIconFiles"] as? [String] }
            if let file = files?.last, let image = UIImage(named: file) { return image }
        }
        return nil
    }()
}

/// 对齐安卓 `buildGroupInviteBitmap`：分享出去的是一张固定 720×920 的品牌卡片，
/// 颜色与坐标直接照搬安卓实现，不随深浅色模式变化。
enum GroupInviteCard {
    static let size = CGSize(width: 720, height: 920)
    private static let headerBottom: CGFloat = 176
    private static let headerFill = UIColor(red: 238 / 255, green: 248 / 255, blue: 239 / 255, alpha: 1)
    private static let titleInk = UIColor(red: 23 / 255, green: 61 / 255, blue: 33 / 255, alpha: 1)
    private static let numberInk = UIColor(red: 72 / 255, green: 120 / 255, blue: 83 / 255, alpha: 1)
    private static let footerInk = UIColor(red: 95 / 255, green: 107 / 255, blue: 100 / 255, alpha: 1)
    private static let brandInk = UIColor(red: 43 / 255, green: 51 / 255, blue: 46 / 255, alpha: 1)
    private static let titleBaseline: CGFloat = 76
    private static let numberBaseline: CGFloat = 126
    private static let codeFrame = CGRect(x: 85, y: 195, width: 550, height: 550)
    private static let footerCenterY: CGFloat = 842
    private static let brandIcon: CGFloat = 40
    private static let brandGap: CGFloat = 12
    private static let margin: CGFloat = 54
    private static let textWidth: CGFloat = 660

    static func image(name: String, groupNo: String, approval: Bool) -> UIImage? {
        guard let code = GroupQRCode.image(groupNo) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            headerFill.setFill(); context.fill(CGRect(x: 0, y: 0, width: size.width, height: headerBottom))

            let titleFont = UIFont.boldSystemFont(ofSize: 38), numberFont = UIFont.systemFont(ofSize: 25, weight: .medium)
            draw(name, baseline: titleBaseline, centerX: size.width / 2, width: textWidth, font: titleFont, color: titleInk)
            draw(String(format: groupText("share_no", "Group No. %@"), groupNo), baseline: numberBaseline, centerX: size.width / 2,
                 width: textWidth, font: numberFont, color: numberInk)

            context.cgContext.interpolationQuality = .high
            code.draw(in: codeFrame)

            let footerFont = UIFont.systemFont(ofSize: 27, weight: .medium)
            let instruction = groupText(approval ? "qr_apply_short" : "qr_join_short", approval ? "Scan to request to join" : "Scan to join")
            draw(instruction, baseline: baseline(centeringTextOf: footerFont, at: footerCenterY), x: margin, width: textWidth,
                 font: footerFont, color: footerInk)

            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "iScoreboard"
            let brandFont = UIFont.systemFont(ofSize: 25, weight: .medium)
            let brandWidth = (appName as NSString).size(withAttributes: [.font: brandFont]).width
            let iconLeft = size.width - margin - brandIcon - brandGap - brandWidth
            if let icon = GroupQRCode.appIcon {
                context.cgContext.interpolationQuality = .high
                UIBezierPath(roundedRect: CGRect(x: iconLeft, y: footerCenterY - brandIcon / 2, width: brandIcon, height: brandIcon),
                              cornerRadius: 10).addClip()
                icon.draw(in: CGRect(x: iconLeft, y: footerCenterY - brandIcon / 2, width: brandIcon, height: brandIcon))
                context.cgContext.resetClip()
            }
            draw(appName, baseline: baseline(centeringTextOf: brandFont, at: footerCenterY), x: iconLeft + brandIcon + brandGap,
                 width: brandWidth + 1, font: brandFont, color: brandInk)
        }
    }

    /// 安卓 `Canvas.drawText` 的 y 是基线，而 AppKit/UIKit 的 `draw(at:)` 要的是顶边，这里做换算。
    private static func baseline(centeringTextOf font: UIFont, at centerY: CGFloat) -> CGFloat {
        centerY + (font.ascender - font.descender) / 2
    }
    private static func draw(_ text: String, baseline: CGFloat, centerX: CGFloat, width: CGFloat, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        draw(text, baseline: baseline, x: centerX - size.width / 2, width: width, font: font, color: color)
    }
    private static func draw(_ text: String, baseline: CGFloat, x: CGFloat, width: CGFloat, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        (text as NSString).draw(with: CGRect(x: x, y: baseline - font.ascender, width: width, height: font.lineHeight),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }
}
