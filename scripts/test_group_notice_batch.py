"""Run the production notification methods with a deterministic transport on the host."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "jifen/Features/Groups/GroupRepository.swift").read_text()
methods = []
for name in ("loadNotices", "markNoticeSeen", "markAllNoticesSeen"):
    match = re.search(r"^    (?:@discardableResult )?func " + name + r"\([^\n]*\{[\s\S]*?^    }", source, re.M)
    assert match, name
    methods.append(match.group())

fixture = r'''
import Foundation
struct User { var id: String }
@MainActor final class SessionStore { static let shared = SessionStore(); var user: User? = User(id: "A") }
struct GroupNotification {
    var id: String; var seenAt: Int?
    func isReceipt(for original: Self) -> Bool { id == original.id && seenAt != nil }
}
struct GroupNoticePage { var items: [GroupNotification]; var nextCursor: String?; var unreadCount: Int }
enum GroupFlowError: Error { case repeatedCursor, invalidReceipt, rateLimited }
func groupErrorMessage(_ error: Error) -> String { String(describing: error) }
struct Receipts {
    var values = [String: Int]()
    mutating func record(_ notice: GroupNotification) { values[notice.id] = notice.seenAt }
    func applying(to notice: GroupNotification) -> GroupNotification { .init(id: notice.id, seenAt: values[notice.id] ?? notice.seenAt) }
    func staleUnreadCount(in rows: [GroupNotification]) -> Int { rows.filter { $0.seenAt == nil && values[$0.id] != nil }.count }
}
struct Cache { var notices: [GroupNotification]?; var unreadCount: Int? }
@MainActor final class Repository {
    var marks = [String](); var pages = [String]()
    var onMark: ((String) async throws -> GroupNotification)?
    var onPage: ((String?) throws -> GroupNoticePage)?
    func write<T>(_ path: String) async throws -> T {
        let id = path.split(separator: "/").dropLast().last.map(String.init)!
        marks.append(id)
        let result = try await onMark?(id) ?? GroupNotification(id: id, seenAt: 9)
        return result as! T
    }
    func read<T>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let cursor = query.first { $0.name == "cursor" }?.value
        pages.append(cursor ?? "first")
        return try onPage!(cursor) as! T
    }
}
@MainActor final class Subject {
    var repository = Repository(); var enabled = true; var accountID: String? = "A"; var identityRevision = 1
    var notices = [GroupNotification(id: "n", seenAt: nil)]; var unreadCount = 1
    var noticesMarkingAll = false; var noticesLoading = false; var noticeCursor: String?
    var noticeRequest = 0; var noticeError: String?; var confirmedSeen = Receipts(); var cache = Cache()
    var hasMoreNotices: Bool { noticeCursor != nil }
    func matchesIdentity(_ id: String, revision: Int) -> Bool { accountID == id && identityRevision == revision }
    func saveCache() {}
'''

tests = r'''
}
@main struct Main {
    @MainActor static func main() async {
        let failed = Subject()
        failed.repository.onMark = { _ in throw GroupFlowError.rateLimited }
        await failed.markAllNoticesSeen()
        precondition(failed.repository.marks == ["n"] && failed.unreadCount == 1)
        precondition(failed.noticeError != nil && !failed.noticesMarkingAll)
        failed.repository.onMark = nil
        await failed.markAllNoticesSeen()
        precondition(failed.unreadCount == 0 && failed.noticeError == nil)

        let invalid = Subject()
        invalid.repository.onMark = { _ in GroupNotification(id: "wrong", seenAt: 9) }
        await invalid.markAllNoticesSeen()
        precondition(invalid.repository.marks.count == 1 && invalid.unreadCount == 1 && invalid.noticeError != nil)

        let rows = (0..<251).map { GroupNotification(id: String($0), seenAt: nil) }
        let many = Subject(); many.notices = Array(rows.prefix(50)); many.unreadCount = 251; many.noticeCursor = "50"
        many.repository.onPage = { cursor in
            let offset = Int(cursor!)!
            return GroupNoticePage(items: Array(rows.dropFirst(offset).prefix(50)),
                nextCursor: offset + 50 < 251 ? String(offset + 50) : nil, unreadCount: 251)
        }
        await many.markAllNoticesSeen()
        precondition(many.repository.marks.count == 251 && many.notices.count == 251 && many.unreadCount == 0)
        precondition(!many.noticesMarkingAll)

        let failedPage = Subject(); failedPage.noticeCursor = "next"; failedPage.unreadCount = 2
        failedPage.repository.onPage = { _ in throw GroupFlowError.rateLimited }
        await failedPage.markAllNoticesSeen()
        precondition(failedPage.repository.pages == ["next"] && failedPage.unreadCount == 1)
        precondition(failedPage.noticeError != nil && !failedPage.noticesMarkingAll)

        let changed = Subject()
        changed.repository.onMark = { id in
            changed.accountID = "B"; changed.identityRevision += 1
            SessionStore.shared.user = User(id: "B")
            changed.notices = [GroupNotification(id: "B-notice", seenAt: nil)]
            changed.noticesMarkingAll = false // sessionDidChange resets account-owned state
            return GroupNotification(id: id, seenAt: 9)
        }
        await changed.markAllNoticesSeen()
        precondition(changed.repository.marks == ["n"] && changed.notices[0].seenAt == nil)
        SessionStore.shared.user = User(id: "A")

        let coalesced = Subject()
        var pending: CheckedContinuation<GroupNotification, Never>?
        coalesced.repository.onMark = { _ in await withCheckedContinuation { pending = $0 } }
        let first = Task { await coalesced.markAllNoticesSeen() }
        while pending == nil { await Task.yield() }
        await coalesced.markAllNoticesSeen()
        precondition(coalesced.repository.marks.count == 1)
        pending!.resume(returning: GroupNotification(id: "n", seenAt: 9))
        await first.value
        precondition(!coalesced.noticesMarkingAll)

        let cycle = Subject(); cycle.noticeCursor = "a"
        cycle.repository.onPage = { cursor in GroupNoticePage(items: [], nextCursor: cursor == "a" ? "b" : "a", unreadCount: 0) }
        await cycle.markAllNoticesSeen()
        precondition(cycle.repository.pages == ["a", "b"] && cycle.noticeError != nil)

        let empty = Subject(); empty.noticeCursor = "a"; empty.unreadCount = 2
        empty.repository.onPage = { cursor in GroupNoticePage(
            items: cursor == "a" ? [] : [GroupNotification(id: "last", seenAt: nil)],
            nextCursor: cursor == "a" ? "b" : nil, unreadCount: 1) }
        await empty.markAllNoticesSeen()
        precondition(empty.repository.marks == ["n", "last"] && empty.unreadCount == 0)
        print("Group notice production-method regressions: PASS (8 cases)")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="jifen-notice-tests-") as directory:
    script = Path(directory) / "NoticeTests.swift"
    binary = Path(directory) / "NoticeTests"
    script.write_text(fixture + "\n".join(methods) + tests)
    subprocess.run(["swiftc", "-parse-as-library", str(script), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
