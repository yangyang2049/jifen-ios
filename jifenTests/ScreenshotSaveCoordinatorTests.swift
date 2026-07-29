import UIKit
import XCTest
@testable import jifen

@MainActor
final class ScreenshotSaveCoordinatorTests: XCTestCase {
    func testAuthorizedCaptureSavesWithoutPermissionDialog() async {
        let photoLibrary = FakeScreenshotPhotoLibraryService(status: .allowed)
        let coordinator = makeCoordinator(photoLibrary: photoLibrary)
        defer { coordinator.cancelCurrentScreenshot() }

        await coordinator.handleCapturedImage(UIImage())

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
        XCTAssertEqual(photoLibrary.requestCount, 1)
        XCTAssertEqual(coordinator.overlayMode, .needsSettings)

        await coordinator.handleCapturedImage(secondImage)

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

        XCTAssertEqual(coordinator.overlayMode, .retry)
        XCTAssertTrue(coordinator.image === pendingImage)
        XCTAssertEqual(photoLibrary.saveAttemptCount, 1)

        photoLibrary.saveError = nil
        await coordinator.retryCurrentScreenshot()

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
        await coordinator.handleCapturedImage(secondImage)

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
