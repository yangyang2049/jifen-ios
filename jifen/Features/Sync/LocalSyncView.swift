import CoreImage.CIFilterBuiltins
import AVFoundation
import LinkCore
import SwiftUI
import Vision
import VisionKit

struct LocalSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = LocalPeerRoomManager.shared
    @ObservedObject private var coordinator = LocalScoreboardSyncCoordinator.shared
    @State private var joinCode = ""
    @State private var selectedRole: SyncParticipantRole = .display
    @State private var displayName = ""
    @State private var showScanner = false
    @State private var showScannerUnavailableAlert = false

    init(initialJoinCode: String? = nil) {
        _joinCode = State(initialValue: initialJoinCode ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                switch manager.phase {
                case .idle, .failed:
                    landingContent
                default:
                    roomContent
                }
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("sync_title", value: "局域网同步", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("close", value: "关闭", comment: "")) { dismiss() }
                }
            }
        }
        .task {
            if displayName.isEmpty {
                displayName = (try? await AnonymousIdentityProvider.shared.currentIdentity().displayName) ?? ""
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRCodeScannerView { value in
                    if let code = Self.joinCode(from: value) {
                        joinCode = code
                        showScanner = false
                        Task { await manager.joinRoom(code: code, role: selectedRole) }
                    }
                }
                .ignoresSafeArea()
                .navigationTitle(NSLocalizedString("sync_scan_qr", value: "扫描同步二维码", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("cancel", comment: "")) { showScanner = false }
                    }
                }
            }
        }
        .alert(NSLocalizedString("sync_camera_unavailable_title", value: "无法使用相机", comment: ""), isPresented: $showScannerUnavailableAlert) {
            Button(NSLocalizedString("ok", value: "确定", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("settings", value: "设置", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: {
            Text(NSLocalizedString("sync_camera_unavailable_message", value: "请在系统设置中允许相机权限，或使用 6 位同步码加入。", comment: ""))
        }
    }

    private var landingContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 24)

                Text(NSLocalizedString("sync_description", value: "同一局域网内最多连接 8 台设备。主控负责规则计算，副控发送操作，展示端只显示比分。", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                settingsCard {
                    TextField(NSLocalizedString("sync_device_name", value: "设备昵称", comment: ""), text: $displayName)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { _ = try? await AnonymousIdentityProvider.shared.updateDisplayName(displayName) } }

                    Divider()

                    Button {
                        Task {
                            _ = try? await AnonymousIdentityProvider.shared.updateDisplayName(displayName)
                            await manager.createRoom()
                        }
                    } label: {
                        Label(NSLocalizedString("sync_create_room", value: "创建同步房间", comment: ""), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                settingsCard {
                    Picker(NSLocalizedString("sync_join_role", value: "加入角色", comment: ""), selection: $selectedRole) {
                        Text(NSLocalizedString("sync_role_controller", value: "副控端", comment: "")).tag(SyncParticipantRole.remoteController)
                        Text(NSLocalizedString("sync_role_display", value: "展示端", comment: "")).tag(SyncParticipantRole.display)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        TextField(NSLocalizedString("sync_short_code", value: "6 位同步码", comment: ""), text: $joinCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .onChange(of: joinCode) { _, value in
                                joinCode = String(value.filter(\.isNumber).prefix(6))
                            }
                        Button {
                            openScanner()
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 22))
                        }
                        .accessibilityLabel(NSLocalizedString("sync_scan_qr", value: "扫描同步二维码", comment: ""))
                    }

                    Button {
                        Task {
                            _ = try? await AnonymousIdentityProvider.shared.updateDisplayName(displayName)
                            await manager.joinRoom(code: joinCode, role: selectedRole)
                        }
                    } label: {
                        Text(NSLocalizedString("sync_join_room", value: "加入房间", comment: ""))
                            .font(.headline)
                            .foregroundStyle(joinCode.count == 6 ? Color.white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(joinCode.count == 6 ? Theme.primary : Theme.controlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(joinCode.count != 6)
                }

                if let error = manager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: 620)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var roomContent: some View {
        if manager.localRole == .hostController {
            hostRoomContent
        } else {
            participantContent
        }
    }

    private var hostRoomContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let room = manager.room, let url = manager.shareURL {
                    settingsCard {
                        Text(NSLocalizedString("sync_room_code", value: "同步码", comment: ""))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                        Text(room.shortCode)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .frame(maxWidth: .infinity)
                        if let image = QRCodeImageGenerator.image(for: url.absoluteString) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 190, height: 190)
                                .frame(maxWidth: .infinity)
                        }
                        ShareLink(item: url) {
                            Label(NSLocalizedString("share", value: "分享", comment: ""), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !manager.pendingJoinRequests.isEmpty {
                    settingsCard {
                        Text(NSLocalizedString("sync_pending_requests", value: "待批准", comment: ""))
                            .font(.headline)
                        ForEach(manager.pendingJoinRequests) { request in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.identity.displayName)
                                    Text(roleName(request.role))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Button(NSLocalizedString("reject", value: "拒绝", comment: ""), role: .destructive) { manager.reject(request) }
                                Button(NSLocalizedString("approve", value: "允许", comment: "")) { manager.approve(request) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                participantList
                leaveButton
            }
            .frame(maxWidth: 620)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var participantContent: some View {
        VStack(spacing: 0) {
            if let message = coordinator.connectionMessage {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.18))
            }
            if let state = coordinator.displayState {
                LocalScoreboardDisplayView(
                    state: state,
                    canControl: manager.localRole == .remoteController,
                    onIntent: coordinator.sendIntent
                )
            } else {
                ContentUnavailableView(
                    NSLocalizedString("sync_waiting_scoreboard", value: "等待主控打开计分板", comment: ""),
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(NSLocalizedString("sync_waiting_snapshot", value: "连接成功后，比分会自动显示在这里。", comment: ""))
                )
            }
            leaveButton.padding(18)
        }
    }

    private var participantList: some View {
        settingsCard {
            HStack {
                Text(NSLocalizedString("sync_participants", value: "已连接设备", comment: ""))
                    .font(.headline)
                Spacer()
                Text("\(manager.participants.count)/\(RealtimeSyncProtocol.maximumParticipants)")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(manager.participants) { participant in
                HStack {
                    Image(systemName: participant.role == .display ? "display" : "hand.tap")
                    VStack(alignment: .leading) {
                        Text(participant.displayName)
                        Text(roleName(participant.role))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 8, height: 8)
                    if manager.localRole == .hostController && participant.role != .hostController {
                        Button(role: .destructive) { manager.removeParticipant(participant) } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                }
            }
        }
    }

    private var leaveButton: some View {
        Button(role: .destructive) {
            manager.stop()
        } label: {
            Text(manager.localRole == .hostController
                 ? NSLocalizedString("sync_end_room", value: "结束房间", comment: "")
                 : NSLocalizedString("sync_leave_room", value: "退出房间", comment: ""))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(18)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func roleName(_ role: SyncParticipantRole) -> String {
        switch role {
        case .hostController: NSLocalizedString("sync_role_host", value: "主控端", comment: "")
        case .remoteController: NSLocalizedString("sync_role_controller", value: "副控端", comment: "")
        case .display: NSLocalizedString("sync_role_display", value: "展示端", comment: "")
        }
    }

    private func openScanner() {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            showScannerUnavailableAlert = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    showScanner = granted
                    showScannerUnavailableAlert = !granted
                }
            }
        case .denied, .restricted:
            showScannerUnavailableAlert = true
        @unknown default:
            showScannerUnavailableAlert = true
        }
    }

    static func joinCode(from scannedValue: String) -> String? {
        if let url = URL(string: scannedValue),
           url.scheme == "jifen",
           url.host == "sync",
           url.path == "/join",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           code.count == 6 {
            return code
        }
        let digits = scannedValue.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
    }
}

private struct LocalScoreboardDisplayView: View {
    let state: LocalScoreboardDisplayState
    let canControl: Bool
    let onIntent: (LocalScoreboardIntent) -> Void

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                layout {
                    team(name: state.leftName, score: state.leftScore, detail: state.leftDetail, color: Color(red: 0.64, green: 0.08, blue: 0.10), side: .left)
                    team(name: state.rightName, score: state.rightScore, detail: state.rightDetail, color: Color(red: 0.04, green: 0.25, blue: 0.55), side: .right)
                }
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 8)
                if let keyPoint = state.keyPoint, keyPoint.isRenderable {
                    keyPointBadge(keyPoint, size: proxy.size)
                }
            }
        }
    }

    private enum Side { case left, right }

    private func keyPointBadge(_ keyPoint: LocalScoreboardKeyPoint, size: CGSize) -> some View {
        let midX = size.width / 2
        let innerGap: CGFloat = 12
        let badgeHalfWidth: CGFloat = 28
        let largeWindow = min(size.width, size.height) >= 600
        return Text(keyPointLabel(keyPoint.kind))
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Color(hex: "111111"))
            .frame(width: 56, height: 28)
            .background(keyPointBackground(keyPoint.kind), in: RoundedRectangle(cornerRadius: 7))
            .position(
                x: midX + (keyPoint.side == .left ? -(innerGap + badgeHalfWidth) : innerGap + badgeHalfWidth),
                y: ScoreboardServeGeometry.keyPointBadgeCenterY(
                    height: size.height,
                    doublesTopRow: nil,
                    largeWindow: largeWindow
                )
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier("local_scoreboard_key_point_badge")
    }

    private func keyPointLabel(_ kind: LocalScoreboardKeyPoint.Kind) -> String {
        if kind == .match {
            return NSLocalizedString("scoreboard_key_point_match", value: "MP", comment: "Match point")
        }
        if state.gameID.hasPrefix("tennis") {
            return NSLocalizedString("scoreboard_key_point_set", value: "SP", comment: "Set point")
        }
        if state.gameID == "volleyball" || state.gameID == "air_volleyball" || state.gameID == "beach_volleyball" {
            return NSLocalizedString("scoreboard_key_point_volleyball_set", value: "SP", comment: "Volleyball set point")
        }
        return NSLocalizedString("scoreboard_key_point_game", value: "GP", comment: "Game point")
    }

    private func keyPointBackground(_ kind: LocalScoreboardKeyPoint.Kind) -> Color {
        kind == .set && state.gameID.hasPrefix("tennis") ? Color(hex: "FFB340") : Color(hex: "FFD60A")
    }

    private func team(name: String, score: String, detail: String?, color: Color, side: Side) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(name).font(.system(size: 24, weight: .semibold)).lineLimit(1)
            Text(score).font(.system(size: 112, weight: .bold, design: .rounded)).minimumScaleFactor(0.35).lineLimit(1)
            if let detail { Text(detail).font(.title3).foregroundStyle(.white.opacity(0.75)) }
            if canControl {
                HStack(spacing: 14) {
                    Button { onIntent(side == .left ? .subtractLeft : .subtractRight) } label: { Image(systemName: "minus") }
                    Button { onIntent(side == .left ? .addLeft : .addRight) } label: { Image(systemName: "plus") }
                }
                .font(.title2.bold())
                .buttonStyle(.bordered)
                .tint(.white)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
    }
}

private enum QRCodeImageGenerator {
    static func image(for value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output.transformed(by: .init(scaleX: 10, y: 10)), from: output.extent.applying(.init(scaleX: 10, y: 10))) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

@available(iOS 16.0, *)
private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onResult: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onResult: (String) -> Void
        init(onResult: @escaping (String) -> Void) { self.onResult = onResult }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                onResult(value)
            }
        }
    }
}
