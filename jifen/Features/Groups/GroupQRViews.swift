import SwiftUI
import PhotosUI
import Vision
import VisionKit
import CoreImage.CIFilterBuiltins

struct GroupJoinView: View {
    private enum InputField: Hashable { case number, message }
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var number = ""
    @State private var message = ""
    @FocusState private var focusedInput: InputField?
    @State private var preview: GroupPreview?
    @State private var previewRevision = 0
    @State private var joinedID: String?
    @State private var waiting = false
    @State private var busy = false
    @State private var scanner = false
    @State private var login = false
    @State private var loginTarget: String?
    @State private var reporting = false
    @State private var submitting = false
    @State private var photoGeneration = 0
    @State private var key = UUID().uuidString
    @State private var photo: PhotosPickerItem?
    @State private var localError: String?
    init(initialGroupNo: String = "", onStart: @escaping (GameType, SportsSetupResult, String) -> Void) {
        self.onStart = onStart
        _number = State(initialValue: GroupInvitationLink.validNumber(initialGroupNo) ? initialGroupNo : "")
    }
    var body: some View {
        NavigationStack {
            Group {
                if let joinedID { GroupDetailView(groupID: joinedID, onStart: onStart) }
                else { Form {
                Section {
                    TextField(groupText("number", "6–8 digit group number"), text: $number).keyboardType(.numberPad).focused($focusedInput, equals: .number).accessibilityIdentifier("group_number")
                    HStack {
                        Button { scanner = true } label: { Label(groupText("scan", "Scan QR code"), systemImage: "qrcode.viewfinder") }
                        PhotosPicker(selection: $photo, matching: .images) { Label(groupText("album", "Choose photo"), systemImage: "photo") }
                    }.buttonStyle(.borderless)
                    Button(groupText("preview", "Preview group")) { focusedInput = nil; Task { await loadPreview() } }.disabled(busy || !GroupQRPayload.validNumber(number))
                }
                if let preview {
                    Section {
                        Text(preview.name).font(.headline).accessibilityIdentifier("group_preview_name")
                        Text(preview.description)
                        if preview.groupType == "coaching" { Text(groupText("coaching", "Coaching group")).foregroundStyle(Theme.primary) }
                        Text("#\(preview.groupNo) · \(preview.memberCount) " + groupText("members", "members"))
                        Text(preview.joinPolicy == "approval" ? groupText("approval", "Approval required") : groupText("open", "Anyone with the number can join"))
                        if waiting || preview.effectiveAvailability == "pending_approval" {
                            Label(groupText("pending_approval", "Waiting for approval"), systemImage: "hourglass")
                            if let requestID = preview.requestId { Button(groupText("withdraw", "Withdraw request"), role: .destructive) { Task { if await store.perform({ try await store.repository.action("/join-requests/\(requestID)/withdraw") }) { waiting = false; await loadPreview(); await store.refresh() } } }.disabled(busy) }
                        }
                        else if preview.effectiveAvailability == "already_member" {
                            Text(groupText("already_member", "You are already a member."))
                            Button(groupText("open_group", "Open group")) {
                                Task {
                                    await store.refresh()
                                    joinedID = preview.groupId ?? store.groups.first(where: { $0.groupNo == preview.groupNo })?.id
                                }
                            }
                        }
                        else if preview.effectiveAvailability == "available" {
                            if preview.joinPolicy == "approval" { TextField(groupText("join_message", "Message to the group (optional)"), text: $message).focused($focusedInput, equals: .message).accessibilityIdentifier("group_join_message") }
                            Button(groupText("confirm_join", "Join this group")) { if SessionStore.shared.isAuthenticated { Task { await join() } } else { loginTarget = number; login = true } }.disabled(busy || preview.groupNo != number || !(store.capabilities?.allows("join_group") ?? true))
                        } else if preview.effectiveAvailability == "not_found" {
                            GroupNotice(text: groupText("lookup_not_found", "Group not found, check the number"))
                        } else { GroupNotice(text: groupText("unavailable", "This group cannot accept new members.")) }
                        if preview.hasPendingRequest && preview.effectiveAvailability != "pending_approval", let requestID = preview.requestId {
                            Button(groupText("withdraw", "Withdraw request"), role: .destructive) { Task { if await store.perform({ try await store.repository.action("/join-requests/\(requestID)/withdraw") }) { waiting = false; await loadPreview(); await store.refresh() } } }.disabled(busy)
                        }
                    }
                }
                if let preview, preview.availability != "not_found", SessionStore.shared.isAuthenticated { Button(groupText("report", "Report group"), role: .destructive) { reporting = true } }
                if let error = localError ?? store.error { GroupNotice(text: error) }
                if busy { ProgressView() }
            }.scrollDismissesKeyboard(.interactively)
                }
            }
            .disabled(submitting).interactiveDismissDisabled(submitting)
            .navigationTitle(joinedID == nil ? groupText("join", "Join group") : "").groupAdaptiveOrientation()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("done", value: "完成", comment: "")) { focusedInput = nil }
                        .tint(Theme.primary).accessibilityIdentifier("group_keyboard_done")
                }
            }
            .sheet(isPresented: $scanner) { NavigationStack { GroupScannerView { raw in scanner = false; receive(raw) } } }
            .sheet(isPresented: $reporting) { GroupPreviewReportView(groupNo: number) }
            .sheet(isPresented: $login, onDismiss: { if SessionStore.shared.isAuthenticated { Task { await store.refresh(); await loadPreview(); if loginTarget == number, preview?.effectiveAvailability == "available", preview?.groupNo == number { await join() }; loginTarget = nil } } }) { AccountLoginSheet() }

            .onChange(of: number) { _, value in previewRevision &+= 1; photoGeneration += 1; busy = false; if preview?.groupNo != value { preview = nil }; waiting = false; message = ""; localError = nil; loginTarget = nil; key = UUID().uuidString }
            .onChange(of: store.identityRevision) { _, _ in
                previewRevision &+= 1; busy = false; preview = nil; waiting = false; joinedID = nil; localError = nil; key = UUID().uuidString
                if GroupQRPayload.validNumber(number) { Task { await loadPreview() } }
            }
            .onChange(of: message) { _,_ in key = UUID().uuidString }
            .onChange(of: photo) { _, item in Task { await decodePhoto(item) } }
            .task { if GroupQRPayload.validNumber(number) { await loadPreview() } }
        }
    }
    private func receive(_ raw: String) {
        guard let code = GroupQRPayload.parse(raw) else { localError = groupText("invalid_qr", "This is not a valid group QR code."); return }
        number = code; Task { await loadPreview() }
    }
    private func loadPreview() async {
        let requestedNumber = number, accountRevision = store.identityRevision
        previewRevision &+= 1; let requestRevision = previewRevision
        busy = true; defer { if previewRevision == requestRevision { busy = false } }; localError = nil
        let authenticated = SessionStore.shared.isAuthenticated
        do {
            let loaded: GroupPreview = try await store.repository.read("/by-number/\(requestedNumber)/preview", authenticated: authenticated)
            guard number == requestedNumber, previewRevision == requestRevision, store.identityRevision == accountRevision else { return }
            preview = loaded; waiting = loaded.effectiveAvailability == "pending_approval"
        } catch {
            if number == requestedNumber, previewRevision == requestRevision, store.identityRevision == accountRevision { localError = groupErrorMessage(error) }
        }
    }
    private func join() async {
        guard preview?.groupNo == number, preview?.effectiveAvailability == "available", message.unicodeScalars.count <= 200 else { return }
        busy = true; submitting = true; defer { busy = false; submitting = false }
        guard let accountID = store.accountID else { return }
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
            guard let raw = candidates.first(where: { GroupQRPayload.parse($0) != nil }) else { throw GroupFormError.invalidQR }
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
    var onValue: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paused = false
    var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRDataScannerView(paused: paused) { value in guard !paused else { return }; paused = true; onValue(value) }
            } else { ContentUnavailableView(groupText("camera_unavailable", "Camera unavailable"), systemImage: "camera", description: Text(groupText("camera_hint", "Allow camera access in Settings, or choose a photo."))) }
        }.navigationTitle(groupText("scan", "Scan QR code"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() } } }
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
                VStack(spacing: 4) {
                    Text(group.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                    Text(String(format: groupText("share_no", "Group No. %@"), group.groupNo))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity)
                if let image = qrImage { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: min(300, max(120, geometry.size.height * 0.45))).background(.white).accessibilityLabel(groupText("group_qr", "Group QR code")).accessibilityIdentifier("group_qr") }
                if shareError == nil { Text(canInvite ? groupText(group.joinPolicy == "open" ? "qr_direct_hint" : "qr_hint", "Scan to preview and join.") : groupText("unavailable", "This group cannot accept new members.")).multilineTextAlignment(.center).font(.footnote).foregroundStyle(Theme.textSecondary) }
                if let shareError { GroupNotice(text: shareError) }
                if canInvite, let url = GroupInvitationLink.joinURL(groupNo: group.groupNo) {
                    ShareLink(item: url, subject: Text(group.name), message: Text("\(group.name)\n#\(group.groupNo)")) {
                        Label(groupText("audit_ui_share_invitation", "Share invitation"), systemImage: "link")
                    }
                    .accessibilityIdentifier("group_share_invitation_link")
                    if let card = inviteCard {
                        ShareLink(item: Image(uiImage: card), preview: SharePreview(group.name, image: Image(uiImage: card))) { Label(groupText("audit_ui_share_qr", "Share QR code"), systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("group_share_invitation_card")
                    } else if livePreview != nil {
                        // 对齐安卓 shareGroupQr 失败路径：卡片合成失败要可感知，而不是按钮悄悄消失。
                        GroupNotice(text: groupText("audit_ui_share_failed", "Sharing failed. Try again."))
                    }
                } else if livePreview != nil {
                    // 对齐安卓：不可加入时仍可把小组号以文案形式分享出去。
                    ShareLink(item: String(format: groupText("audit_ui_group_number_message", "Group: %@\nGroup number: %@ (not accepting members)"), group.name, group.groupNo)) {
                        Label(groupText("audit_ui_share_number", "Share group number"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("group_share_number")
                }
                Button(groupText("copy_number", "Copy group number")) { UIPasteboard.general.string = group.groupNo }
            }.padding(24).frame(maxWidth: .infinity)
        }
        }.navigationTitle(groupText("group_qr", "Group QR code")).navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
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
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(GroupQRPayload.encode(number).utf8)
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
