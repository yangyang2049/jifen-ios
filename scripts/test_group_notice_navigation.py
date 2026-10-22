"""Run the production notification target policy without a simulator or network."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
fixture = r'''
import Foundation
struct GroupNotification { var kind: String; var resourceId: String? }
@main struct NoticeNavigationChecks {
    static func main() {
        for kind in ["activity_created", "activity_changed", "activity_cancelled"] {
            precondition(GroupNoticeTarget.resolve(kind: kind, resourceID: " activity ") == .activity("activity"))
        }
        for kind in ["result_pending", "result_confirmed", "result_voided"] {
            precondition(GroupNoticeTarget.resolve(kind: kind, resourceID: "result") == .result("result"))
        }
        for kind in ["join_requested", "role_changed", "ownership_transferred"] {
            precondition(GroupNoticeTarget.resolve(kind: kind, resourceID: "request") == .group(tab: 3))
        }
        for kind in ["member_removed", "join_rejected"] {
            precondition(GroupNotification(kind: kind, resourceId: "old").navigationTarget == .message)
        }
        for id in [nil, "", " \n"] as [String?] {
            precondition(GroupNoticeTarget.resolve(kind: "activity_changed", resourceID: id) == .group(tab: 0))
            precondition(GroupNoticeTarget.resolve(kind: "result_pending", resourceID: id) == .group(tab: 0))
        }
        for kind in ["join_approved", "future_kind", "activity_future_kind", "result_future_kind"] {
            precondition(GroupNoticeTarget.resolve(kind: kind, resourceID: "id") == .group(tab: 0))
        }
        precondition(GroupNoticeTarget.resolve(kind: "training_changed", resourceID: "plan") == .group(tab: 1))
    }
}
'''
with tempfile.TemporaryDirectory(prefix="jifen-notice-navigation-") as directory:
    runner = Path(directory) / "Checks.swift"
    binary = Path(directory) / "checks"
    runner.write_text(fixture)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                    str(root / "jifen/Features/Groups/GroupNoticeTarget.swift"),
                    str(runner), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print("Notification destination checks passed.")
