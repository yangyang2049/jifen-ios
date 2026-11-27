import Foundation

/// Storage for the temporary files handed to `WCSession.transferFile`.
///
/// WatchConnectivity deletes the received copy, not the sender's staging file.
/// The sender owns cleanup: files live in one dedicated directory under the
/// temporary directory, and `didFinish` removes a file only when it is provably
/// inside that directory. Unlike the previous path-substring check this cannot
/// match or delete an unrelated file.
public enum LinkTemporaryTransferFile {
    public static let directoryName = "jifen-link-transfers"

    public static func directory(in base: URL = FileManager.default.temporaryDirectory) -> URL {
        base.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func makeURL(in base: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = directory(in: base)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jifen-link-\(UUID().uuidString).jifenlink")
    }

    public static func isManaged(
        _ url: URL,
        in base: URL = FileManager.default.temporaryDirectory
    ) -> Bool {
        let expected = canonicalDirectoryPath(directory(in: base))
        let actual = canonicalDirectoryPath(url.standardizedFileURL.deletingLastPathComponent())
        return actual == expected
    }

    private static func canonicalDirectoryPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let resolvedParent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return resolvedParent
            .appendingPathComponent(standardized.lastPathComponent, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    /// Removes a staged file, and only a staged file.
    public static func removeIfManaged(
        _ url: URL,
        in base: URL = FileManager.default.temporaryDirectory
    ) {
        guard isManaged(url, in: base) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
