import Foundation
import PersistenceCore
import Testing

@Test func resumeSessionRetentionUsesAnExactFortyEightHourBoundary() {
    let policy = ResumeSessionRetentionPolicy.fortyEightHours
    let startedAt: Int64 = 1_000_000
    let boundary = startedAt + 48 * 60 * 60 * 1_000

    #expect(!policy.isExpired(
        startedAtEpochMilliseconds: startedAt,
        nowEpochMilliseconds: boundary
    ))
    #expect(policy.isExpired(
        startedAtEpochMilliseconds: startedAt,
        nowEpochMilliseconds: boundary + 1
    ))
}

@Test func resumeSessionRetentionDoesNotExpireFutureStartTimes() {
    let policy = ResumeSessionRetentionPolicy.fortyEightHours

    #expect(!policy.isExpired(
        startedAtEpochMilliseconds: 2_000,
        nowEpochMilliseconds: 1_000
    ))
}

@Test func resumeSessionRepositoryClearRemovesIndexedAndOrphanedFiles() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ResumeSessionClearTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sessions = root.appendingPathComponent("sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    try Data("orphan".utf8).write(
        to: sessions.appendingPathComponent("orphan.json"),
        options: .atomic
    )
    try Data("corrupted-index".utf8).write(
        to: root.appendingPathComponent("resume-index.json"),
        options: .atomic
    )

    let repository = ResumeSessionRepository(rootURL: root)
    try await repository.clear()

    #expect(!FileManager.default.fileExists(atPath: root.path))
    let entries = try await repository.entries()
    #expect(entries.isEmpty)

    // Clearing again must stay safe after the root has already disappeared.
    try await repository.clear()
}
