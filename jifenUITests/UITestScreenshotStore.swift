import XCTest

/// Saves UI screenshots under `UITestScreenshots/` at the repo root.
enum UITestScreenshotStore {
    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // jifenUITests/<file> → repo root
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // jifenUITests
            .deletingLastPathComponent() // repo
        return repoRoot.appendingPathComponent("UITestScreenshots", isDirectory: true)
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
        let dir = outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = safeName
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        let fileURL = dir.appendingPathComponent("\(safeName).png")
        let data = screenshot.pngRepresentation
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
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
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func writtenFileCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
        return files.filter { $0.hasSuffix(".png") }.count
    }
}
