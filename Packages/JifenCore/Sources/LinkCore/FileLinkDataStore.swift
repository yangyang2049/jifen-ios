import Foundation
import PersistenceCore

/// Application-wide storage root abstraction (D3). The default implementation
/// points at the app sandbox `Application Support/jifen-watch-v1/`; switching to
/// an App Group container later only means injecting a different `rootURL` —
/// no call site changes. M1 deliberately adds **no** entitlements.
public protocol AppStorageContainer: Sendable {
    var rootURL: URL { get }
    func subdirectory(_ name: String) -> URL
}

public struct DefaultAppStorageContainer: AppStorageContainer {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Creates the directory on first access so writers never need mkdir calls.
    public func subdirectory(_ name: String) -> URL {
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Thread-safe key→file store implementing `LinkDataStore` on disk. Keys are
/// mapped to safe file names (anything outside `[A-Za-z0-9_-]` becomes
/// percent-escaped hex) and every write is atomic, so a crash never leaves a
/// half-written blob. Use `setOrThrow`/`removeOrThrow` on paths that must
/// verify persistence before the caller ACKs or advances state.
public final class FileLinkDataStore: @unchecked Sendable, LinkDataStore {
    private let directoryURL: URL
    private let lock = NSLock()

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func data(forKey key: String) -> Data? {
        try? dataOrThrow(forKey: key)
    }

    /// Distinguishes an absent value from a read failure at a durability boundary.
    public func dataOrThrow(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try Data(contentsOf: Self.fileURL(directory: directoryURL, key: key))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func set(_ data: Data, forKey key: String) {
        _ = try? setOrThrow(data, forKey: key)
    }

    public func removeObject(forKey key: String) {
        _ = try? removeOrThrow(forKey: key)
    }

    /// Atomic write that surfaces the error — callers that must prove
    /// persistence (terminal outbox) use this. Signature matches the
    /// `LinkDataStore` requirement exactly so existential calls reach here.
    public func setOrThrow(_ data: Data, forKey key: String) throws {
        let url = Self.fileURL(directory: directoryURL, key: key)
        lock.lock()
        defer { lock.unlock() }
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public func removeOrThrow(forKey key: String) throws -> Bool {
        let url = Self.fileURL(directory: directoryURL, key: key)
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    public func allKeys() -> [String] {
        (try? allKeysOrThrow()) ?? []
    }

    func allKeysOrThrow() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
            .compactMap(Self.key(fromFileName:))
    }

    // MARK: - Safe file-name mapping

    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    static func safeFileName(for key: String) -> String {
        let scalars = key.unicodeScalars.map { scalar -> String in
            allowedCharacters.contains(scalar) ? String(scalar) : "\(String(format: "%%%02X", scalar.value))"
        }
        let joined = scalars.joined()
        return joined.isEmpty ? "_" : String(joined.prefix(180))
    }

    static func key(fromFileName name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        let base = String(name.dropLast(".json".count))
        guard !base.isEmpty else { return nil }
        return base.removingPercentEncoding
    }

    static func fileURL(directory: URL, key: String) -> URL {
        directory.appendingPathComponent(safeFileName(for: key) + ".json")
    }
}

public extension FileLinkDataStore {
    /// Phone-side default: `Application Support/WatchLink/` in the app sandbox.
    /// Fresh-start storage for the (never-shipped) link protocol context,
    /// terminal outbox and retired-session ledger — no legacy migration.
    static func phoneWatchLinkDefault() -> FileLinkDataStore {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchLink", isDirectory: true)
        return FileLinkDataStore(directoryURL: directory)
    }
}
