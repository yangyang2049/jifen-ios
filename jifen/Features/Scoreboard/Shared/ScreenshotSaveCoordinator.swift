//
//  ScreenshotSaveCoordinator.swift
//  jifen
//
//  Shared screenshot capture, add-only Photos authorization and feedback UI.
//

import Combine
import Photos
import SwiftUI
import UIKit

enum ScreenshotPhotoLibraryAccess: Equatable, Sendable {
    case allowed
    case notDetermined
    case denied
}

@MainActor
protocol ScreenshotPhotoLibraryServing: AnyObject {
    func authorizationStatus() -> ScreenshotPhotoLibraryAccess
    func requestAuthorization() async -> ScreenshotPhotoLibraryAccess
    func save(_ image: UIImage) async throws
}

@MainActor
final class SystemScreenshotPhotoLibraryService: ScreenshotPhotoLibraryServing {
    func authorizationStatus() -> ScreenshotPhotoLibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func requestAuthorization() async -> ScreenshotPhotoLibraryAccess {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    func save(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? ScreenshotSaveError.photoLibraryWriteFailed)
                }
            }
        }
    }

    nonisolated private static func map(_ status: PHAuthorizationStatus) -> ScreenshotPhotoLibraryAccess {
        switch status {
        case .authorized, .limited:
            return .allowed
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

private enum ScreenshotSaveError: Error {
    case photoLibraryWriteFailed
}

enum ScreenshotSaveOverlayMode: Equatable {
    case hidden
    case needsSettings
    case retry
    case saved
}

@MainActor
final class ScreenshotSaveCoordinator: ObservableObject {
    static let shared = ScreenshotSaveCoordinator()

    @Published private(set) var overlayMode: ScreenshotSaveOverlayMode = .hidden
    @Published private(set) var image: UIImage?
    @Published private(set) var dialogProgress: Double = 1
    @Published private(set) var savedFeedbackProgress: CGFloat = 0
    @Published private(set) var savedFeedbackOpacity: Double = 1
    @Published private(set) var toastMessage: String?

    private let photoLibrary: ScreenshotPhotoLibraryServing
    private let dialogAutoCloseTime: TimeInterval
    private let feedbackHoldTime: TimeInterval
    private let feedbackAnimationTime: TimeInterval
    private let settingsOpener: @MainActor () -> Void

    private var operationGeneration = 0
    private var processingTask: Task<Void, Never>?
    private var dialogCountdownTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var awaitingSettingsReturn = false

    convenience init() {
        self.init(
            photoLibrary: SystemScreenshotPhotoLibraryService(),
            settingsOpener: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        )
    }

    init(
        photoLibrary: ScreenshotPhotoLibraryServing,
        dialogAutoCloseTime: TimeInterval = 5,
        feedbackHoldTime: TimeInterval = 0.35,
        feedbackAnimationTime: TimeInterval = 0.9,
        settingsOpener: @escaping @MainActor () -> Void
    ) {
        self.photoLibrary = photoLibrary
        self.dialogAutoCloseTime = dialogAutoCloseTime
        self.feedbackHoldTime = feedbackHoldTime
        self.feedbackAnimationTime = feedbackAnimationTime
        self.settingsOpener = settingsOpener
    }

    var isDialogPresented: Bool {
        overlayMode == .needsSettings || overlayMode == .retry
    }

    var primaryButtonTitle: String {
        switch overlayMode {
        case .retry:
            return NSLocalizedString("retry", value: "重试", comment: "Retry screenshot save")
        default:
            return NSLocalizedString("open_settings", value: "去设置", comment: "Open app settings")
        }
    }

    /// Clears any old preview/feedback before the caller hides its own chrome.
    func prepareForCapture() {
        operationGeneration += 1
        processingTask?.cancel()
        processingTask = nil
        cancelPresentationTasks()
        awaitingSettingsReturn = false
        overlayMode = .hidden
        image = nil
        toastMessage = nil
        resetSavedFeedback()
    }

    func captureCurrentWindowAndSubmit() {
        guard let image = captureCurrentWindowImage() else {
            showCaptureFailure()
            return
        }
        submitCapturedImage(image)
    }

    func captureCurrentWindowImage() -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    func submitCapturedImage(_ image: UIImage) {
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            await self?.handleCapturedImage(image)
        }
    }

    /// Async entry point kept internal so the authorization state machine can be tested deterministically.
    func handleCapturedImage(_ image: UIImage) async {
        let generation = beginOperation(with: image)
        await processCurrentImage(generation: generation)
    }

    func performPrimaryAction() {
        switch overlayMode {
        case .needsSettings:
            pauseDialogCountdown()
            awaitingSettingsReturn = true
            overlayMode = .hidden
            settingsOpener()
        case .retry:
            processingTask?.cancel()
            processingTask = Task { [weak self] in
                await self?.retryCurrentScreenshot()
            }
        case .hidden, .saved:
            break
        }
    }

    func retryCurrentScreenshot() async {
        guard let image else { return }
        await handleCapturedImage(image)
    }

    func resumeAfterSettingsIfNeeded() async {
        guard awaitingSettingsReturn, image != nil else { return }
        awaitingSettingsReturn = false
        let generation = operationGeneration
        await processCurrentImage(generation: generation)
    }

    func pauseDialogCountdown() {
        dialogCountdownTask?.cancel()
        dialogCountdownTask = nil
    }

    func cancelCurrentScreenshot() {
        operationGeneration += 1
        processingTask?.cancel()
        processingTask = nil
        cancelPresentationTasks()
        awaitingSettingsReturn = false
        overlayMode = .hidden
        image = nil
        resetSavedFeedback()
    }

    func showCaptureFailure() {
        showToast(NSLocalizedString("screenshot_failed", value: "截图失败", comment: ""))
    }

    private func beginOperation(with image: UIImage) -> Int {
        operationGeneration += 1
        let generation = operationGeneration
        cancelPresentationTasks()
        awaitingSettingsReturn = false
        overlayMode = .hidden
        self.image = image
        toastMessage = nil
        resetSavedFeedback()
        return generation
    }

    private func processCurrentImage(generation: Int) async {
        guard generation == operationGeneration, let image else { return }

        switch photoLibrary.authorizationStatus() {
        case .allowed:
            await save(image, generation: generation)
        case .notDetermined:
            let requestedStatus = await photoLibrary.requestAuthorization()
            guard generation == operationGeneration, !Task.isCancelled else { return }
            if requestedStatus == .allowed {
                await save(image, generation: generation)
            } else {
                presentDialog(.needsSettings, generation: generation)
            }
        case .denied:
            presentDialog(.needsSettings, generation: generation)
        }
    }

    private func save(_ image: UIImage, generation: Int) async {
        do {
            try await photoLibrary.save(image)
            guard generation == operationGeneration, !Task.isCancelled else { return }
            presentSavedFeedback(generation: generation)
        } catch {
            guard generation == operationGeneration, !Task.isCancelled else { return }
            presentDialog(.retry, generation: generation)
        }
    }

    private func presentDialog(_ mode: ScreenshotSaveOverlayMode, generation: Int) {
        guard generation == operationGeneration else { return }
        feedbackTask?.cancel()
        feedbackTask = nil
        overlayMode = mode
        dialogProgress = 1
        startDialogCountdown(generation: generation)
    }

    private func startDialogCountdown(generation: Int) {
        dialogCountdownTask?.cancel()
        let duration = max(0.05, dialogAutoCloseTime)
        let start = Date()
        dialogCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, generation == self.operationGeneration {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = duration - elapsed
                if remaining <= 0 {
                    self.dialogProgress = 0
                    self.cancelCurrentScreenshot()
                    return
                }
                self.dialogProgress = remaining / duration
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func presentSavedFeedback(generation: Int) {
        guard generation == operationGeneration else { return }
        pauseDialogCountdown()
        overlayMode = .saved
        savedFeedbackProgress = 0
        savedFeedbackOpacity = 1

        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.feedbackHoldTime))
            guard !Task.isCancelled, generation == self.operationGeneration else { return }

            let totalDuration = max(0.01, self.feedbackAnimationTime)
            let moveDuration = totalDuration * 0.8
            let fadeDuration = totalDuration - moveDuration

            withAnimation(.easeInOut(duration: moveDuration)) {
                self.savedFeedbackProgress = 1
            }
            try? await Task.sleep(for: .seconds(moveDuration))
            guard !Task.isCancelled, generation == self.operationGeneration else { return }

            withAnimation(.easeOut(duration: fadeDuration)) {
                self.savedFeedbackOpacity = 0
            }
            try? await Task.sleep(for: .seconds(fadeDuration))
            guard !Task.isCancelled, generation == self.operationGeneration else { return }
            self.overlayMode = .hidden
            self.image = nil
            self.showToast(NSLocalizedString("screenshot_saved", value: "截图已保存", comment: ""))
        }
    }

    private func showToast(_ message: String, duration: TimeInterval = 2) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self?.toastMessage == message else { return }
            self?.toastMessage = nil
        }
    }

    private func cancelPresentationTasks() {
        dialogCountdownTask?.cancel()
        dialogCountdownTask = nil
        feedbackTask?.cancel()
        feedbackTask = nil
        toastTask?.cancel()
        toastTask = nil
    }

    private func resetSavedFeedback() {
        savedFeedbackProgress = 0
        savedFeedbackOpacity = 1
    }
}

struct ScreenshotSaveOverlay: View {
    @ObservedObject var coordinator: ScreenshotSaveCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if coordinator.isDialogPresented, let image = coordinator.image {
                permissionDialog(image: image)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if coordinator.overlayMode == .saved, let image = coordinator.image {
                savedThumbnail(image: image)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if let message = coordinator.toastMessage {
                ToastView(message: message)
                    .accessibilityIdentifier("screenshot_save_toast")
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(coordinator.isDialogPresented)
        .animation(.easeInOut(duration: 0.2), value: coordinator.overlayMode)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await coordinator.resumeAfterSettingsIfNeeded()
            }
        }
    }

    private func permissionDialog(image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    coordinator.cancelCurrentScreenshot()
                }

            GeometryReader { proxy in
                let cardWidth = Theme.dialogWidth(
                    availableWidth: proxy.size.width,
                    phonePreferredWidth: 280,
                    padPreferredWidth: 420
                )
                let previewWidth = max(0, cardWidth - 42)
                let previewHeight = min(
                    Theme.usesPadLayout ? 200 : 120,
                    previewWidth * 0.56
                )

                VStack(spacing: 0) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: previewWidth, height: previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("screenshot_preview_image")

                    HStack(spacing: 10) {
                        Button {
                            coordinator.cancelCurrentScreenshot()
                        } label: {
                            Text(NSLocalizedString("cancel", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(uiColor: .label))
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: ScoreboardConstants.minimumTouchTarget
                                )
                        }
                        .buttonStyle(.plain)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("screenshot_cancel_button")

                        Button {
                            coordinator.performPrimaryAction()
                        } label: {
                            Text(coordinator.primaryButtonTitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: ScoreboardConstants.minimumTouchTarget
                                )
                        }
                        .buttonStyle(.plain)
                        .background(Theme.primary)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("screenshot_primary_button")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
                .frame(width: cardWidth)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    screenshotCountdownProgress
                        .padding(.horizontal, 12)
                        .padding(.bottom, 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0).onChanged { _ in
                        coordinator.pauseDialogCountdown()
                    }
                )
                .accessibilityIdentifier("screenshot_permission_dialog")
                .environment(\.colorScheme, .light)
            }
        }
    }

    private var screenshotCountdownProgress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.primary.opacity(0.2))
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: max(0, proxy.size.width * coordinator.dialogProgress))
            }
        }
        .frame(height: 3)
        .accessibilityIdentifier("screenshot_countdown_progress")
    }

    private func savedThumbnail(image: UIImage) -> some View {
        GeometryReader { proxy in
            let progress = reduceMotion
                ? CGFloat(1)
                : min(max(coordinator.savedFeedbackProgress, 0), 1)
            let targetWidth: CGFloat = 120
            let targetHeight: CGFloat = 80
            let preferredInitialWidth: CGFloat = Theme.usesPadLayout ? 320 : 240
            let availableWidth = max(targetWidth, proxy.size.width - 48)
            let availableHeight = max(targetHeight, proxy.size.height - 48)
            let unconstrainedInitialWidth = min(preferredInitialWidth, availableWidth)
            let unconstrainedInitialHeight = unconstrainedInitialWidth * targetHeight / targetWidth
            let initialScale = min(1, availableHeight / unconstrainedInitialHeight)
            let initialWidth = max(targetWidth, unconstrainedInitialWidth * initialScale)
            let initialHeight = max(targetHeight, unconstrainedInitialHeight * initialScale)
            let currentWidth = initialWidth + (targetWidth - initialWidth) * progress
            let currentHeight = initialHeight + (targetHeight - initialHeight) * progress
            let centerY = proxy.size.height / 2
            let targetCenterY = max(targetHeight / 2, proxy.size.height - 100 - targetHeight / 2)
            let currentCenterY = centerY + (targetCenterY - centerY) * progress

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: currentWidth, height: currentHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .position(x: proxy.size.width / 2, y: currentCenterY)
                .opacity(coordinator.savedFeedbackOpacity)
                .accessibilityIdentifier("screenshot_saved_feedback")
        }
    }
}
