import Foundation
import Testing
import LinkCore

struct LinkEpochMillisecondsStorageTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "LinkEpochMillisecondsStorageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func roundTripsValuesBeyondInt32OnEveryArchitecture() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        // A 32-bit arm64_32 Int traps on this value; the Int64/NSNumber path must not.
        let value: Int64 = 1_792_000_000_123
        #expect(value > Int64(Int32.max))

        LinkEpochMillisecondsStorage.set(value, forKey: "last", in: defaults)

        #expect(LinkEpochMillisecondsStorage.value(forKey: "last", in: defaults) == value)
        #expect((defaults.object(forKey: "last") as? NSNumber)?.int64Value == value)
    }

    @Test func readsLegacyIntegerAndNumberValues() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        // Older builds stored the key through UserDefaults.set(Int) or NSNumber.
        defaults.set(1_700_000_000_000, forKey: "legacy")
        #expect(LinkEpochMillisecondsStorage.value(forKey: "legacy", in: defaults) == 1_700_000_000_000)
        #expect(LinkEpochMillisecondsStorage.value(from: NSNumber(value: Int64.max)) == Int64.max)
        #expect(LinkEpochMillisecondsStorage.value(from: Int(42)) == 42)
        #expect(LinkEpochMillisecondsStorage.value(from: Int64.min) == Int64.min)
    }

    @Test func absentOrNonNumericValueHasNoTimestamp() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(LinkEpochMillisecondsStorage.value(forKey: "missing", in: defaults) == nil)
        defaults.set("not a number", forKey: "text")
        #expect(LinkEpochMillisecondsStorage.value(forKey: "text", in: defaults) == nil)
        #expect(LinkEpochMillisecondsStorage.value(from: nil) == nil)
    }
}

struct LinkTemporaryTransferFileTests {
    private func baseDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkTemporaryTransferFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test func stagedFilesLiveInTheManagedDirectory() throws {
        let base = try baseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let url = try LinkTemporaryTransferFile.makeURL(in: base)
        #expect(LinkTemporaryTransferFile.isManaged(url, in: base))
        #expect(url.deletingLastPathComponent().lastPathComponent == LinkTemporaryTransferFile.directoryName)

        try Data([1, 2, 3]).write(to: url)
        LinkTemporaryTransferFile.removeIfManaged(url, in: base)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func foreignFilesAreNeverDeleted() throws {
        let base = try baseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        // Same file-name prefix outside the managed directory (the old substring
        // check would have deleted this).
        let foreign = base.appendingPathComponent("jifen-link-foreign.jifenlink")
        try Data([1]).write(to: foreign)
        #expect(!LinkTemporaryTransferFile.isManaged(foreign, in: base))
        LinkTemporaryTransferFile.removeIfManaged(foreign, in: base)
        #expect(FileManager.default.fileExists(atPath: foreign.path))

        // A directory that merely carries the managed name is not the managed one.
        let decoy = base.appendingPathComponent("jifen-link-elsewhere", isDirectory: true)
        #expect(!LinkTemporaryTransferFile.isManaged(decoy, in: base))
    }

    @Test func symlinkedBasePathStillMatchesAndRemovesStagedFile() throws {
        let realBase = try baseDirectory()
        let symlinkBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkTemporaryTransferFileTests-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkBase, withDestinationURL: realBase)
        defer {
            try? FileManager.default.removeItem(at: symlinkBase)
            try? FileManager.default.removeItem(at: realBase)
        }

        let staged = try LinkTemporaryTransferFile.makeURL(in: symlinkBase)
        try Data([1, 2, 3]).write(to: staged)
        let realPathURL = LinkTemporaryTransferFile.directory(in: realBase)
            .appendingPathComponent(staged.lastPathComponent)

        #expect(LinkTemporaryTransferFile.isManaged(realPathURL, in: symlinkBase))
        #expect(LinkTemporaryTransferFile.isManaged(staged, in: realBase))

        let traversalURL = LinkTemporaryTransferFile.directory(in: realBase)
            .appendingPathComponent("../escape.jifenlink")
        #expect(!LinkTemporaryTransferFile.isManaged(traversalURL, in: symlinkBase))

        LinkTemporaryTransferFile.removeIfManaged(realPathURL, in: symlinkBase)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}
