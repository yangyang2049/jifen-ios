import SwiftUI
import AVFoundation
import PhotosUI
import Vision
import VisionKit
import CoreImage.CIFilterBuiltins

/// 小组扫码与网页扫码登录共用的统一扫码 Sheet：大 Bottom Sheet、左上关闭、
/// 居中小标题、右上相册入口（对齐安卓统一扫码器的分工——这里只负责采集
/// 二维码内容：相机实时扫描或从相册选图识别；解析与业务处理由调用方完成）。
struct QRScanSheet: View {
    var hint: String
    /// 调用方在处理上一条结果（如登录请求进行中）时暂停扫描。
    var paused: Bool = false
    var feedback: String? = nil
    var onRetry: (() -> Void)? = nil
    /// 一张图片可能包含多个二维码，优先选择调用方能处理的内容。
    var prefersPhotoValue: (String) -> Bool = { _ in true }
    var onValue: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var photo: PhotosPickerItem?
    @State private var decodingPhoto = false
    @State private var albumMissedQR = false
    @State private var isActive = true
    /// 相机权限状态：未决定时先走系统弹窗（文案来自 NSCameraUsageDescription），
    /// 被拒后给出「去设置」入口——此前这里只有一行文字，用户没有可点的补救动作。
    @State private var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
            && cameraAuthorization == .authorized
    }

    private var canOpenCameraSettings: Bool {
        DataScannerViewController.isSupported && cameraAuthorization == .denied
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                if cameraAvailable {
                    QRDataScannerView(paused: paused || decodingPhoto) { value in
                        guard isActive, !paused, !decodingPhoto else { return }
                        onValue(value)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 相机铺满整张 Sheet（延伸到导航栏背后），避免顶部露出系统白边。
                    .ignoresSafeArea()
                    // 顶部暗渐变衬托导航栏白色控件，类似系统相机的做法。
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 132)
                            .frame(maxWidth: .infinity)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
                } else {
                    ContentUnavailableView {
                        Label(groupText("camera_unavailable", "Camera unavailable"), systemImage: "camera")
                    } description: {
                        VStack(spacing: 12) {
                            if canOpenCameraSettings {
                                Text(groupText("camera_hint", "Allow camera access in Settings, or choose a photo."))
                                Button(NSLocalizedString("open_settings", value: "Settings", comment: "Open app settings")) {
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    UIApplication.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.primary)
                                .accessibilityIdentifier("qr_scan_open_settings")
                            } else {
                                Text(groupText("album", "Choose photo"))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { hintBanner }
            .overlay { if decodingPhoto { ProgressView().controlSize(.large).tint(cameraAvailable ? .white : Theme.textPrimary) } }
            .navigationTitle(groupText("scan", "Scan QR code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(cameraAvailable ? ColorScheme.dark : nil, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { ModalCloseButton(tint: cameraAvailable ? .white : Theme.textPrimary) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Image(systemName: "photo").foregroundStyle(cameraAvailable ? .white : Theme.textPrimary)
                    }
                    .disabled(paused || decodingPhoto)
                    .accessibilityLabel(groupText("album", "Choose photo"))
                    .accessibilityIdentifier("group_scan_photo")
                }
            }
            .onAppear { isActive = true }
            .onDisappear { isActive = false }
            .onChange(of: photo) { _, item in Task { await decodePhoto(item) } }
            // 首次进入按需触发系统权限弹窗（用途文案由 Info.plist 提供）；从设置返回时重新读取状态。
            .task { await prepareCameraAccess() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video) }
            }
        }
    }

    // 底部提示横幅：相机画面上的通栏渐变（沿用扫码登录页样式），文字保持在安全区内。
    private var hintBanner: some View {
        VStack(spacing: 8) {
            Text(bannerText)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("qr_scan_hint")
            if feedback != nil, let onRetry {
                Button(NSLocalizedString("retry", value: "Try again", comment: ""), action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.top, 46)
        .padding(.bottom, 30)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var bannerText: String {
        if let feedback { return feedback }
        return albumMissedQR
            ? NSLocalizedString("qr_scan_album_not_found", tableName: "QRScan", value: "No QR code found. Choose another image or scan with the camera.", comment: "")
            : hint
    }

    /// 只在「尚未询问」时触发系统弹窗；已被拒绝时不再重复请求，改为展示「去设置」。
    private func prepareCameraAccess() async {
        guard DataScannerViewController.isSupported else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorization = granted ? .authorized : .denied
        default:
            cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func decodePhoto(_ item: PhotosPickerItem?) async {
        guard let item, !paused, !decodingPhoto else { return }
        decodingPhoto = true
        defer { decodingPhoto = false; photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                albumMissedQR = isActive
                return
            }
            let candidates = await Task.detached(priority: .userInitiated) { QRPhotoDecoder.candidates(in: data) }.value
            guard isActive else { return }
            if let raw = QRPhotoDecoder.preferredCandidate(from: candidates, matching: prefersPhotoValue) {
                albumMissedQR = false
                onValue(raw)
            } else {
                albumMissedQR = true
            }
        } catch {
            guard isActive else { return }
            albumMissedQR = true
        }
    }
}

/// 从静态图片里解出二维码内容（Vision 优先；模拟器缺推理运行时时退回 CPU 检测器）。
nonisolated enum QRPhotoDecoder {
    static func preferredCandidate(from candidates: [String], matching predicate: (String) -> Bool) -> String? {
        // 没有可识别内容时仍交给业务层首个结果，保留无效/过期等原有错误提示。
        candidates.first(where: predicate) ?? candidates.first
    }

    static func candidates(in data: Data) -> [String] {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        var candidates: [String] = []
        do {
            try VNImageRequestHandler(data: data).perform([request])
            candidates = request.results?.compactMap(\.payloadStringValue) ?? []
        } catch {
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

struct QRDataScannerView: UIViewControllerRepresentable {
    var paused: Bool
    var onValue: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if paused { controller.stopScanning() } else if !controller.isScanning { try? controller.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onValue: onValue) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onValue: (String) -> Void
        init(onValue: @escaping (String) -> Void) { self.onValue = onValue }
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard case .barcode(let barcode) = addedItems.first,
                  let value = barcode.payloadStringValue
            else { return }
            onValue(value)
        }
    }
}
