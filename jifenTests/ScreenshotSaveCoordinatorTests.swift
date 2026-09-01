import UIKit
import XCTest
@testable import jifen

@MainActor
final class ScreenshotSaveCoordinatorTests: XCTestCase {
    /// 轮询等待异步保存/授权流程落地（处理 task 在 MainActor 上的调度延迟）。
    private func waitForOverlay(
        _ coordinator: ScreenshotSaveCoordinator,
        _ mode: ScreenshotSaveOverlayMode,
        timeout: TimeInterval = 2
    ) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if coordinator.overlayMode == mode { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 新流程（对齐安卓）：截屏 → 预览卡 → 关闭后才进入保存/授权流程。
    private func dismissPreviewAndProcess(_ coordinator: ScreenshotSaveCoordinator) {
        coordinator.closePreviewAndContinue()
    }

    func testAuthorizedCaptureSavesWithoutPermissionDialog() async {
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .allowed)
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(UIImage())
        XCTAssertEqual(coordinator.overlayMode, .preview)
        XCTAssertEqual(photoLibrary.requestCount, 0)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 0)

        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .saved)

        XCTAssertEqual(photoLibrary.requestCount, 0)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 1)
        XCTAssertEqual(coordinator.overlayMode, .saved)
        XCTAssertFalse(coordinator.isDialogPresented)
    }

    func testNotDeterminedPermissionIsRequestedOnceThenSavesWhenGranted() async {
        let photoLibrary = FakeScreenshotPhotoLibraryService(
            status: .notDetermined,
            requestedStatus: .allowed
        )
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(UIImage())
        XCTAssertEqual(coordinator.overlayMode, .preview)

        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .saved)

        XCTAssertEqual(photoLibrary.requestCount, 1)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 1)
        XCTAssertEqual(coordinator.overlayMode, .saved)
    }

    func testDeniedPermissionShowsSettingsDialogEveryTimeWithoutRequestingAgain() async {
        let firstImage = UIImage()
        let secondImage = UIImage()
        let photoLibrary = FakeScreenshotPhotoLibraryService(
            status: .notDetermined,
            requestedStatus: .denied
        )
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(firstImage)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .needsSettings)
        XCTAssertEqual(photoLibrary.requestCount, 1)
        XCTAssertEqual(coordinator.overlayMode, .needsSettings)

        await coordinator.handleCapturedImage(secondImage)
        XCTAssertEqual(coordinator.overlayMode, .preview)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .needsSettings)

        XCTAssertEqual(photoLibrary.requestCount, 1)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 0)
        XCTAssertEqual(coordinator.overlayMode, .needsSettings)
        XCTAssertTrue(coordinator.image === secondImage)
    }

    func testReturningFromSettingsSavesPendingImageAfterAuthorization() async {
        var didOpenSettings = false
        let pendingImage = UIImage()
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .denied)
        let coordinator = makeCoordinator(photoLibrary: photoLibrary) {
            didOpenSettings = true
        }
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(pendingImage)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .needsSettings)
        coordinator.performPrimaryAction()

        XCTAssertTrue(didOpenSettings)
        XCTAssertEqual(coordinator.overlayMode, .hidden)

        photoLibrary.status = .allowed
        await coordinator.resumeAfterSettingsIfNeeded()

        XCTAssertEqual(photoLibrary.saveAttemptCount, 1)
        XCTAssertTrue(photoLibrary.savedImages.first === pendingImage)
        XCTAssertEqual(coordinator.overlayMode, .saved)
    }

    func testSaveFailureKeepsImageAndRetrySucceeds() async {
        let pendingImage = UIImage()
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .allowed)
        photoLibrary.saveError = TestScreenshotSaveError.failed
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(pendingImage)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .retry)

        XCTAssertEqual(coordinator.overlayMode, .retry)
        XCTAssertTrue(coordinator.image === pendingImage)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 1)

        photoLibrary.saveError = nil
        await coordinator.retryCurrentScreenshot()
        XCTAssertEqual(coordinator.overlayMode, .preview)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .saved)

        XCTAssertEqual(photoLibrary.saveAttemptCount, 2)
        XCTAssertEqual(photoLibrary.savedImages.count, 1)
        XCTAssertTrue(photoLibrary.savedImages.first === pendingImage)
        XCTAssertEqual(coordinator.overlayMode, .saved)
    }

    func testConsecutiveCapturesReplaceFeedbackWithLatestImage() async {
        let firstImage = UIImage()
        let secondImage = UIImage()
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .allowed)
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(firstImage)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .saved)

        await coordinator.handleCapturedImage(secondImage)
        XCTAssertEqual(coordinator.overlayMode, .preview)
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .saved)

        XCTAssertEqual(photoLibrary.saveAttemptCount, 2)
        XCTAssertEqual(photoLibrary.savedImages.count, 2)
        XCTAssertTrue(photoLibrary.savedImages.last === secondImage)
        XCTAssertTrue(coordinator.image === secondImage)
        XCTAssertEqual(coordinator.overlayMode, .saved)
    }

    func testPausingDialogStopsAutoCloseCountdown() async {
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .denied)
        let coordinator = ScreenshotSaveCoordinator(
            photoLibrary: photoLibrary,
            dialogAutoCloseTime: 0.05,
            feedbackHoldTime: 60,
            feedbackAnimationTime: 0.01,
            settingsOpener: {}
        )
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(UIImage())
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .needsSettings)
        coordinator.pauseDialogCountdown()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.overlayMode, .needsSettings)
        XCTAssertNotNil(coordinator.image)
    }

    func testDialogAutoClosesWhenCountdownIsNotPaused() async {
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .denied)
        let coordinator = ScreenshotSaveCoordinator(
            photoLibrary: photoLibrary,
            dialogAutoCloseTime: 0.05,
            feedbackHoldTime: 60,
            feedbackAnimationTime: 0.01,
            settingsOpener: {}
        )
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(UIImage())
        dismissPreviewAndProcess(coordinator)
        await waitForOverlay(coordinator, .needsSettings)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.overlayMode, .hidden)
        XCTAssertNil(coordinator.image)
    }

    private func makeCoordinator(
        photoLibrary: FakeScreenshotPhotoLibraryService,
        settingsOpener: @escaping @MainActor () -> Void = {}
    ) -> ScreenshotSaveCoordinator {
        ScreenshotSaveCoordinator(
            photoLibrary: photoLibrary,
            dialogAutoCloseTime: 60,
            feedbackHoldTime: 60,
            feedbackAnimationTime: 0.01,
            settingsOpener: settingsOpener
        )
    }
}

@MainActor
private final class FakeScreenshotPhotoLibraryService: ScreenshotPhotoLibraryServing {
    var status: ScreenshotPhotoLibraryAccess
    var requestedStatus: ScreenshotPhotoLibraryAccess
    var saveError: Error?
    private(set) var requestCount = 0
    private(set) var saveAttemptCount = 0
    private(set) var savedImages: [UIImage] = []

    init(
        status: ScreenshotPhotoLibraryAccess,
        requestedStatus: ScreenshotPhotoLibraryAccess = .denied
    ) {
        self.status = status
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() -> ScreenshotPhotoLibraryAccess {
        status
    }

    func requestAuthorization() async -> ScreenshotPhotoLibraryAccess {
        requestCount += 1
        status = requestedStatus
        return requestedStatus
    }

    func save(_ image: UIImage) async throws {
        saveAttemptCount += 1
        if let saveError {
            throw saveError
        }
        savedImages.append(image)
    }
}

private enum TestScreenshotSaveError: Error {
    case failed
}
