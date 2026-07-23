import UIKit
import XCTest

/// Stages review-ready screenshots in the test runner sandbox. The host-side
/// runner exports the kept attachments into the repo's `UITestScreenshots-All/`.
enum UITestScreenshotStore {
    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // Prefer TEST_RUNNER_ prefix (xcodebuild passes these into the XCTest runner).
        if let override = ProcessInfo.processInfo.environment["TEST_RUNNER_UITEST_SCREENSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // UI tests execute inside the simulator and cannot write directly to
        // the host checkout. Keep a writable staging directory for assertions;
        // attachments are exported from the xcresult after the test completes.
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestScreenshots-All", isDirectory: true)
    }

    static var devicePrefix: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    @discardableResult
    static func capture(
        _ app: XCUIApplication,
        name: String,
        testCase: XCTestCase,
        settleNanoseconds: UInt64 = 600_000_000
    ) -> URL {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await Task.sleep(nanoseconds: settleNanoseconds)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)

        let safeName = sanitize(name)
        let reviewName = "\(devicePrefix)_\(safeName)"
        let dir = outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let screenshot = XCUIScreen.main.screenshot()
        let data = reviewReadyPNGData(from: screenshot)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = reviewName
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let fileURL = dir.appendingPathComponent("\(reviewName).png")
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// XCTest can return portrait-sized PNG data while the app is in landscape.
    /// Flatten the device orientation into the bitmap so Finder/Preview shows
    /// scoreboard and timer screenshots upright.
    private static func reviewReadyPNGData(from screenshot: XCUIScreenshot) -> Data {
        let originalData = screenshot.pngRepresentation
        guard
            let source = UIImage(data: originalData),
            let cgImage = source.cgImage
        else {
            return originalData
        }

        let orientation: UIImage.Orientation
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft:
            orientation = .left
        case .landscapeRight:
            orientation = .right
        default:
            return originalData
        }

        let oriented = UIImage(cgImage: cgImage, scale: source.scale, orientation: orientation)
        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale
        let renderer = UIGraphicsImageRenderer(size: oriented.size, format: format)
        let flattened = renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
        return flattened.pngData() ?? originalData
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func resetOutputDirectory() {
        let dir = outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefix = "\(devicePrefix)_"
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in existing where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func writtenFileCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        let prefix = "\(devicePrefix)_"
        return files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".png") }.count
    }

    static func totalWrittenFileCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        return files.filter { $0.hasSuffix(".png") }.count
    }
}
