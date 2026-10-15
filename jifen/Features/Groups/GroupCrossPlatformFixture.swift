import Foundation

@MainActor func groupCaptureCommonNames() -> [String] {
    #if DEBUG
    if GroupCaptureFixture.enabled, let data = try? GroupCaptureFixture.dataset() { return data.commonNames }
    #endif
    return CommonNamesManager.shared.getNames(type: .player)
}

@MainActor func groupCaptureCommonPlaces() -> [CommonPlace]? {
    #if DEBUG
    if GroupCaptureFixture.enabled && GroupCaptureFixture.nativeScene == "activity-place" { return [] }
    #endif
    return nil
}

#if DEBUG
import CryptoKit
import PersistenceCore
import ScoreCore
import SessionCore

nonisolated enum GroupCaptureFailure: LocalizedError {
    case invalidFixture(String)
    case unsupportedRead(String)
    case writeForbidden(String)
    case networkForbidden(String)
    var errorDescription: String? {
        switch self {
        case .invalidFixture(let value): "Capture fixture rejected: \(value)"
        case .unsupportedRead(let value): "Capture endpoint missing: \(value)"
        case .writeForbidden(let value): "Capture writes disabled: \(value)"
        case .networkForbidden(let value): "Capture network disabled: \(value)"
        }
    }
}

nonisolated struct GroupCaptureDataset: Decodable, Sendable {
    struct Account: Decodable, Sendable { var id: String; var name: String }
    var id: String
    var referenceTime: Int64
    var account: Account
    var listGroupIds: [String]
    var groups: [ScoreGroup]
    var members: [GroupMember]
    var results: [GroupResult]
    var activities: [GroupActivity]
    var activityLineup: GroupActivityLineup
    var trainingPlans: [GroupTrainingPlan]
    var notices: [GroupNotification]
    var leaveNotices: [GroupLeaveNotice]
    var trainingNotices: [GroupTrainingNotice]
    var capabilities: GroupCapabilities
    var commonNames: [String]
    var commonPlaces: [String]
}

/// Read-only screenshot transport. Unknown endpoints and every write fail locally, never falling through.
nonisolated enum GroupCaptureFixture {
    private struct NoticeResponse: Encodable { var items: [GroupNotification]; var nextCursor: String?; var unreadCount: Int }
    private struct PreviewResponse: Encodable { var groupNo: String; var name: String; var description: String; var sport: GroupSport; var memberCount: Int; var joinPolicy: String; var availability: String; var groupType: String?; var groupId: String; var status: String; var memberLimit: Int }
    static let canonicalHash = "021b1d8d4714984bb9deddbbc3dccb50c468ff21cec49055ddef947e342e7a47"
    static let adapterHash = "117c3bf1e14c1deebd1b86d63156d931f9413942ebedc76ca92b9f6157dc6817"
    private static let embeddedBase64 = "eyJhY2NlcHRhbmNlU3RhdHVzIjoiYWNjZXB0ZWQgZm9yIGNhcHR1cmUgcHJlcGFyYXRpb24iLCJhY2NvdW50Ijp7ImlkIjoiY29tcGFyZS1hY2NvdW50IiwibmFtZSI6Iua8lOekuui0puWPtyJ9LCJhY3Rpdml0aWVzIjpbeyJjYXBhY2l0eSI6MTIsImNvbXBsZXRlZFNlc3Npb25Db3VudCI6MCwiY3JlYXRlZEF0IjoxNzkxODY0MDAwMDAwLCJjcmVhdG9yTWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMCIsImZvcm1hdCI6ImRvdWJsZXMiLCJnYW1lSWQiOiIiLCJncm91cElkIjoic2VlZF9ncm91cF9iYWRtaW50b24iLCJpZCI6ImNvbXBhcmVfYWN0aXZpdHlfbXVsdGkiLCJtYXRjaE1vZGUiOiJtdWx0aSIsIm5vdGUiOiLoh6rluKbnkIPmi43vvIzotLnnlKggQUEiLCJwbGFjZSI6Iua7qOaxn+S9k+iCsuS4reW/gyIsInJlZ2lzdGVyZWRNZW1iZXJJZHMiOlsic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzAiLCJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMSIsInNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8yIiwic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzMiXSwicmVnaXN0cmF0aW9uQ2xvc2VzQXQiOjE3OTIyMTMyMDAwMDAsInJldmlzaW9uIjoxLCJzZXNzaW9uQ291bnQiOjIsInN0YXJ0ZWRHYW1lQ291bnQiOjAsInN0YXJ0c0F0IjoxNzkyMjE2ODAwMDAwLCJzdGF0dXMiOiJyZWNydWl0aW5nIiwidGl0bGUiOiLlkajlha3lj4zmiZPlj4vosIrotZsifV0sImFjdGl2aXR5TGluZXVwIjp7ImFjdGl2aXR5SWQiOiJjb21wYXJlX2FjdGl2aXR5X211bHRpIiwiY2FuTWFuYWdlIjp0cnVlLCJtYXRjaE1vZGUiOiJtdWx0aSIsInJldmlzaW9uIjoxLCJzZXNzaW9uTWludXRlcyI6MzAsInNlc3Npb25zIjpbeyJhY3Rpdml0eUlkIjoiY29tcGFyZV9hY3Rpdml0eV9tdWx0aSIsImNvdXJ0IjoiMyDlj7flnLoiLCJlbmRzQXQiOjE3OTIyMTg2MDAwMDAsImZvcm1hdCI6ImRvdWJsZXMiLCJncm91cElkIjoic2VlZF9ncm91cF9iYWRtaW50b24iLCJpZCI6ImNvbXBhcmVfYWN0aXZpdHlfc2Vzc2lvbl8xIiwiaXNGcm96ZW4iOmZhbHNlLCJteVNpZGUiOiJBIiwibmVlZHNMaW5ldXAiOmZhbHNlLCJvcmRlck5vIjoxLCJyZXN1bHRJZCI6IiIsInNlYXRzIjpbeyJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuaIkSIsIm1lbWJlcklkIjoic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzAiLCJzZWF0IjowLCJzaWRlIjoiQSJ9LHsiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmnajmiawiLCJtZW1iZXJJZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8xIiwic2VhdCI6MSwic2lkZSI6IkEifSx7ImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi6ZmI6bmPIiwibWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMiIsInNlYXQiOjAsInNpZGUiOiJCIn0seyJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6Iuael+WQryIsIm1lbWJlcklkIjoic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzMiLCJzZWF0IjoxLCJzaWRlIjoiQiJ9XSwic3RhcnRlZEdhbWVJZCI6IiIsInN0YXJ0c0F0IjoxNzkyMjE2ODAwMDAwLCJzdGF0dXMiOiJzY2hlZHVsZWQifSx7ImFjdGl2aXR5SWQiOiJjb21wYXJlX2FjdGl2aXR5X211bHRpIiwiY291cnQiOiIzIOWPt+WcuiIsImVuZHNBdCI6MTc5MjIyMjIwMDAwMCwiZm9ybWF0IjoiZG91YmxlcyIsImdyb3VwSWQiOiJzZWVkX2dyb3VwX2JhZG1pbnRvbiIsImlkIjoiY29tcGFyZV9hY3Rpdml0eV9zZXNzaW9uXzIiLCJpc0Zyb3plbiI6ZmFsc2UsIm15U2lkZSI6IkEiLCJuZWVkc0xpbmV1cCI6ZmFsc2UsIm9yZGVyTm8iOjIsInJlc3VsdElkIjoiIiwic2VhdHMiOlt7ImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5oiRIiwibWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMCIsInNlYXQiOjAsInNpZGUiOiJBIn0seyJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuadqOaJrCIsIm1lbWJlcklkIjoic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzEiLCJzZWF0IjoxLCJzaWRlIjoiQSJ9LHsiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLpmYjpuY8iLCJtZW1iZXJJZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8yIiwic2VhdCI6MCwic2lkZSI6IkIifSx7ImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5p6X5ZCvIiwibWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMyIsInNlYXQiOjEsInNpZGUiOiJCIn1dLCJzdGFydGVkR2FtZUlkIjoiIiwic3RhcnRzQXQiOjE3OTIyMjA0MDAwMDAsInN0YXR1cyI6InNjaGVkdWxlZCJ9XX0sImNhcGFiaWxpdGllcyI6eyJhY3Rpdml0eU1lbWJlclNlc3Npb25NYXgiOjgsImFjdGl2aXR5U2Vzc2lvbk1heCI6MTAwLCJkZXNjcmlwdGlvbk1heCI6MjAwLCJncm91cE5vTGVuZ3RoIjo4LCJncm91cFR5cGVzIjpbInBlZXIiLCJjb2FjaGluZyJdLCJtZW1iZXJMaW1pdERlZmF1bHQiOjMwLCJtZW1iZXJMaW1pdE1heCI6NTAsIm5hbWVNYXgiOjI0LCJuYW1lTWluIjoyLCJydWxlU2NoZW1hVmVyc2lvbiI6MSwic3BvcnRzIjpbeyJkZWZhdWx0UnVsZXMiOnsiZ2FtZXNQZXJTZXQiOjYsIm1hdGNoQ29tcGxldGlvbk1vZGUiOiJiZXN0X29mIiwibWF4U2V0cyI6MywicG9pbnRDYXAiOjMwLCJwb2ludHNUb1dpblNldCI6MjEsInNldFNjb3JpbmdNb2RlIjoicmVndWxhciIsInNwb3J0IjoiYmFkbWludG9uIiwidGllQnJlYWtQb2ludHMiOjcsInVzZVJhbGx5U2NvcmluZyI6ZmFsc2UsInVzZXNOb0FkU2NvcmluZyI6ZmFsc2UsInZlcnNpb24iOjEsIndpbkJ5VHdvIjp0cnVlfSwicnVsZU9wdGlvbnMiOnsiZ2FtZXNQZXJTZXQiOls0LDZdLCJtYXRjaENvbXBsZXRpb25Nb2RlcyI6WyJiZXN0X29mIiwicGxheV9hbGwiXSwibWF4U2V0cyI6WzEsMyw1XSwicG9pbnRzVG9XaW5TZXQiOls3LDExLDE1LDIxXSwic2V0U2NvcmluZ01vZGVzIjpbInJlZ3VsYXIiLCJ0aWVicmVha19vbmx5Il0sInRpZUJyZWFrUG9pbnRzIjpbNywxMF0sInVzZVJhbGx5U2NvcmluZyI6W2ZhbHNlLHRydWVdLCJ1c2VzTm9BZFNjb3JpbmciOltmYWxzZSx0cnVlXSwid2luQnlUd28iOlt0cnVlLGZhbHNlXX0sInNwb3J0IjoiYmFkbWludG9uIiwic3VwcG9ydHNDdXN0b21SdWxlcyI6dHJ1ZX0seyJkZWZhdWx0UnVsZXMiOnsiZ2FtZXNQZXJTZXQiOjYsIm1hdGNoQ29tcGxldGlvbk1vZGUiOiJiZXN0X29mIiwibWF4U2V0cyI6NSwicG9pbnRDYXAiOm51bGwsInBvaW50c1RvV2luU2V0IjoxMSwic2V0U2NvcmluZ01vZGUiOiJyZWd1bGFyIiwic3BvcnQiOiJ0YWJsZV90ZW5uaXMiLCJ0aWVCcmVha1BvaW50cyI6NywidXNlUmFsbHlTY29yaW5nIjpmYWxzZSwidXNlc05vQWRTY29yaW5nIjpmYWxzZSwidmVyc2lvbiI6MSwid2luQnlUd28iOnRydWV9LCJydWxlT3B0aW9ucyI6eyJnYW1lc1BlclNldCI6WzQsNl0sIm1hdGNoQ29tcGxldGlvbk1vZGVzIjpbImJlc3Rfb2YiLCJwbGF5X2FsbCJdLCJtYXhTZXRzIjpbMSwzLDVdLCJwb2ludHNUb1dpblNldCI6WzcsMTEsMTUsMjFdLCJzZXRTY29yaW5nTW9kZXMiOlsicmVndWxhciIsInRpZWJyZWFrX29ubHkiXSwidGllQnJlYWtQb2ludHMiOls3LDEwXSwidXNlUmFsbHlTY29yaW5nIjpbZmFsc2UsdHJ1ZV0sInVzZXNOb0FkU2NvcmluZyI6W2ZhbHNlLHRydWVdLCJ3aW5CeVR3byI6W3RydWUsZmFsc2VdfSwic3BvcnQiOiJ0YWJsZV90ZW5uaXMiLCJzdXBwb3J0c0N1c3RvbVJ1bGVzIjp0cnVlfSx7ImRlZmF1bHRSdWxlcyI6eyJnYW1lc1BlclNldCI6NiwibWF0Y2hDb21wbGV0aW9uTW9kZSI6ImJlc3Rfb2YiLCJtYXhTZXRzIjozLCJwb2ludENhcCI6bnVsbCwicG9pbnRzVG9XaW5TZXQiOjYsInNldFNjb3JpbmdNb2RlIjoicmVndWxhciIsInNwb3J0IjoidGVubmlzIiwidGllQnJlYWtQb2ludHMiOjcsInVzZVJhbGx5U2NvcmluZyI6ZmFsc2UsInVzZXNOb0FkU2NvcmluZyI6ZmFsc2UsInZlcnNpb24iOjEsIndpbkJ5VHdvIjp0cnVlfSwicnVsZU9wdGlvbnMiOnsiZ2FtZXNQZXJTZXQiOls0LDZdLCJtYXRjaENvbXBsZXRpb25Nb2RlcyI6WyJiZXN0X29mIiwicGxheV9hbGwiXSwibWF4U2V0cyI6WzEsMyw1XSwicG9pbnRzVG9XaW5TZXQiOls3LDExLDE1LDIxXSwic2V0U2NvcmluZ01vZGVzIjpbInJlZ3VsYXIiLCJ0aWVicmVha19vbmx5Il0sInRpZUJyZWFrUG9pbnRzIjpbNywxMF0sInVzZVJhbGx5U2NvcmluZyI6W2ZhbHNlLHRydWVdLCJ1c2VzTm9BZFNjb3JpbmciOltmYWxzZSx0cnVlXSwid2luQnlUd28iOlt0cnVlLGZhbHNlXX0sInNwb3J0IjoidGVubmlzIiwic3VwcG9ydHNDdXN0b21SdWxlcyI6dHJ1ZX0seyJkZWZhdWx0UnVsZXMiOnsiZ2FtZXNQZXJTZXQiOjYsIm1hdGNoQ29tcGxldGlvbk1vZGUiOiJiZXN0X29mIiwibWF4U2V0cyI6MywicG9pbnRDYXAiOm51bGwsInBvaW50c1RvV2luU2V0IjoxMSwic2V0U2NvcmluZ01vZGUiOiJyZWd1bGFyIiwic3BvcnQiOiJwaWNrbGViYWxsIiwidGllQnJlYWtQb2ludHMiOjcsInVzZVJhbGx5U2NvcmluZyI6ZmFsc2UsInVzZXNOb0FkU2NvcmluZyI6ZmFsc2UsInZlcnNpb24iOjEsIndpbkJ5VHdvIjp0cnVlfSwicnVsZU9wdGlvbnMiOnsiZ2FtZXNQZXJTZXQiOls0LDZdLCJtYXRjaENvbXBsZXRpb25Nb2RlcyI6WyJiZXN0X29mIiwicGxheV9hbGwiXSwibWF4U2V0cyI6WzEsMyw1XSwicG9pbnRzVG9XaW5TZXQiOls3LDExLDE1LDIxXSwic2V0U2NvcmluZ01vZGVzIjpbInJlZ3VsYXIiLCJ0aWVicmVha19vbmx5Il0sInRpZUJyZWFrUG9pbnRzIjpbNywxMF0sInVzZVJhbGx5U2NvcmluZyI6W2ZhbHNlLHRydWVdLCJ1c2VzTm9BZFNjb3JpbmciOltmYWxzZSx0cnVlXSwid2luQnlUd28iOlt0cnVlLGZhbHNlXX0sInNwb3J0IjoicGlja2xlYmFsbCIsInN1cHBvcnRzQ3VzdG9tUnVsZXMiOnRydWV9XSwic3VwcG9ydHNBY3Rpdml0eUxpbmV1cCI6dHJ1ZSwic3VwcG9ydHNEcmF3cyI6dHJ1ZSwidHJhaW5pbmdNZW1iZXJTZXNzaW9uTWF4Ijo4LCJ0cmFpbmluZ1Nlc3Npb25NYXgiOjEyfSwiY29tbW9uTmFtZXMiOlsi5p6X5Li5Iiwi6LCM6b6ZIiwi5byg5qWgIiwi546L5pmoIl0sImNvbW1vblBsYWNlcyI6WyLmu6jmsZ/kvZPogrLkuK3lv4MiLCLmu6jmsZ/kvZPogrLkuK3lv4MgMiDlj7fppoYiXSwiZ3JvdXBzIjpbeyJhY3RpdmVNZW1iZXJDb3VudDMwZCI6NCwiY3JlYXRlZEF0IjoxNzg2NjgwMDAwMDAwLCJjdXJyZW50TW9udGhNYXRjaENvdW50IjoxLCJkZXNjcmlwdGlvbiI6IuWRqOacq+e+veavm+eQg+eIseWlveiAhe+8jOaWsOaJi+WPi+Wlve+8jOS7peWPjOaJk+S4uuS4u++8jOi0ueeUqCBBQeOAgiIsImdyb3VwTm8iOiI4MjYwMzE1OCIsImdyb3VwVHlwZSI6InBlZXIiLCJpZCI6InNlZWRfZ3JvdXBfYmFkbWludG9uIiwiaXNDb2FjaCI6ZmFsc2UsImpvaW5Qb2xpY3kiOiJhcHByb3ZhbCIsIm1lbWJlckNvdW50Ijo2LCJtZW1iZXJMaW1pdCI6MzAsIm15Um9sZSI6Im93bmVyIiwibmFtZSI6IuWRqOWFree+veavm+eQgyIsIm93bmVyTWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMCIsInJldmlzaW9uIjo0LCJzcG9ydCI6ImJhZG1pbnRvbiIsInN0YXR1cyI6ImFjdGl2ZSIsInVwZGF0ZWRBdCI6MTc5MTY5MTIwMDAwMH0seyJhY3RpdmVNZW1iZXJDb3VudDMwZCI6MCwiY3JlYXRlZEF0IjoxNzg5MjcyMDAwMDAwLCJjdXJyZW50TW9udGhNYXRjaENvdW50IjowLCJkZXNjcmlwdGlvbiI6IuW3peS9nOaXpeaZmuS4iue7g+eQg++8jOWcuuWcsOWcqOa7qOaxn+S9k+iCsuS4reW/g+OAgiIsImdyb3VwTm8iOiI4MjYwMzE1OSIsImdyb3VwVHlwZSI6InBlZXIiLCJpZCI6InNlZWRfZ3JvdXBfcGlja2xlYmFsbCIsImlzQ29hY2giOmZhbHNlLCJqb2luUG9saWN5Ijoib3BlbiIsIm1lbWJlckNvdW50Ijo0LCJtZW1iZXJMaW1pdCI6MzAsIm15Um9sZSI6Im1lbWJlciIsIm5hbWUiOiLlkajkuInljLnlhYvnkIPlsI/pmJ8iLCJvd25lck1lbWJlcklkIjoic2VlZF9tX3NlZWRfZ3JvdXBfcGlja2xlYmFsbF8wIiwicmV2aXNpb24iOjQsInNwb3J0IjoicGlja2xlYmFsbCIsInN0YXR1cyI6ImFjdGl2ZSIsInVwZGF0ZWRBdCI6MTc5MTQzMjAwMDAwMH0seyJhY3RpdmVNZW1iZXJDb3VudDMwZCI6MCwiY3JlYXRlZEF0IjoxNzkwMTM2MDAwMDAwLCJjdXJyZW50TW9udGhNYXRjaENvdW50IjowLCJkZXNjcmlwdGlvbiI6IuWRqOacq+ehrOWcsO+8jOWPjOaJk+S4uuS4u++8jOasoui/juW4puaci+WPi+adpeOAgiIsImdyb3VwTm8iOiI4MjYwMzE2MCIsImdyb3VwVHlwZSI6InBlZXIiLCJpZCI6InNlZWRfZ3JvdXBfdGVubmlzIiwiaXNDb2FjaCI6ZmFsc2UsImpvaW5Qb2xpY3kiOiJhcHByb3ZhbCIsIm1lbWJlckNvdW50Ijo0LCJtZW1iZXJMaW1pdCI6MzAsIm15Um9sZSI6ImFkbWluIiwibmFtZSI6Iue9keeQg+e7g+S5oOe7hCIsIm93bmVyTWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF90ZW5uaXNfMCIsInJldmlzaW9uIjo0LCJzcG9ydCI6InRlbm5pcyIsInN0YXR1cyI6ImFjdGl2ZSIsInVwZGF0ZWRBdCI6MTc5MTc3NzYwMDAwMH0seyJhY3RpdmVNZW1iZXJDb3VudDMwZCI6MCwiY3JlYXRlZEF0IjoxNzg2NjgwMDAwMDAwLCJjdXJyZW50TW9udGhNYXRjaENvdW50IjowLCJkZXNjcmlwdGlvbiI6IuWfuuacrOatpeazleS4juWPjOaJk+i9rui9rO+8jOaVmee7g+e7n+S4gOaOkuacn+OAgiIsImdyb3VwTm8iOiI4MjYwMzE2MSIsImdyb3VwVHlwZSI6ImNvYWNoaW5nIiwiaWQiOiJjb21wYXJlX2dyb3VwX3RyYWluaW5nIiwiaXNDb2FjaCI6dHJ1ZSwiam9pblBvbGljeSI6ImFwcHJvdmFsIiwibWVtYmVyQ291bnQiOjMsIm1lbWJlckxpbWl0IjozMCwibXlSb2xlIjoib3duZXIiLCJuYW1lIjoi5ZGo5pyr57695q+b55CD6K6t57uD6JClIiwib3duZXJNZW1iZXJJZCI6ImNvbXBhcmUtY29hY2giLCJyZXZpc2lvbiI6NCwic3BvcnQiOiJiYWRtaW50b24iLCJzdGF0dXMiOiJhY3RpdmUiLCJ1cGRhdGVkQXQiOjE3OTE2OTEyMDAwMDB9XSwiaG9zQ2FwdHVyZVNjb3BlIjoiVGVzdC1vbmx5IHJlZmVyZW5jZS10aW1lIGFkYXB0ZXI7IHByb2R1Y3Rpb24gY2xvY2sgYW5kIGdlbmVyYXRlZCBpbnRlcm5hbCBJRHMgcmVtYWluIHVuY2hhbmdlZC4gRXhhY3QgZGlzcGxheWVkIGRhdGVzIGFuZCBzdGFibGUgZ3JvdXAgbnVtYmVycyBhcmUgcGFpcmVkIGZvciBjYXB0dXJlLiIsImlkIjoiZ3JvdXAtY3Jvc3MtcGxhdGZvcm0tcGhvbmUtMjAyNjEwMTMtdjEiLCJpc1Byb3Bvc2VkIjpmYWxzZSwibGVhdmVOb3RpY2VzIjpbXSwibGlzdEdyb3VwSWRzIjpbInNlZWRfZ3JvdXBfdGVubmlzIiwic2VlZF9ncm91cF9iYWRtaW50b24iLCJzZWVkX2dyb3VwX3BpY2tsZWJhbGwiXSwibWVtYmVycyI6W3siYWNjb3VudElkIjoiY29tcGFyZS1hY2NvdW50IiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmiJEiLCJncm91cElkIjoic2VlZF9ncm91cF9iYWRtaW50b24iLCJpZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8wIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc4ODQwODAwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoib3duZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6InNlZWRfYWNjX3l5IiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmnajmiawiLCJncm91cElkIjoic2VlZF9ncm91cF9iYWRtaW50b24iLCJpZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8xIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc4ODQ5NDQwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoiYWRtaW4iLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6InNlZWRfYWNjX2NwIiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLpmYjpuY8iLCJncm91cElkIjoic2VlZF9ncm91cF9iYWRtaW50b24iLCJpZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8yIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc4ODU4MDgwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiJzZWVkX2FjY19scSIsImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5p6X5ZCvIiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfYmFkbWludG9uIiwiaWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMyIsImlzVmlwIjpmYWxzZSwiam9pbmVkQXQiOjE3ODg2NjcyMDAwMDAsImtpbmQiOiJhY2NvdW50Iiwicm9sZSI6Im1lbWJlciIsInN0YXR1cyI6ImFjdGl2ZSJ9LHsiYWNjb3VudElkIjoic2VlZF9hY2NfeGIiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuWwj+WMlyIsImdyb3VwSWQiOiJzZWVkX2dyb3VwX2JhZG1pbnRvbiIsImlkIjoic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzQiLCJpc1ZpcCI6ZmFsc2UsImpvaW5lZEF0IjoxNzg4NzUzNjAwMDAwLCJraW5kIjoiYWNjb3VudCIsInJvbGUiOiJtZW1iZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6IiIsImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi6Zi/TWF5IiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfYmFkbWludG9uIiwiaWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fNSIsImlzVmlwIjpmYWxzZSwiam9pbmVkQXQiOjE3ODg4NDAwMDAwMDAsImtpbmQiOiJ0ZW1wb3JhcnkiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiJjb21wYXJlLWFjY291bnQiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuaIkSIsImdyb3VwSWQiOiJjb21wYXJlX2dyb3VwX3RyYWluaW5nIiwiaWQiOiJjb21wYXJlLWNvYWNoIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc5MTg2NDAwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoib3duZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6ImNvbXBhcmUtc3R1ZGVudC1hY2NvdW50IiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLlsI/mnpciLCJncm91cElkIjoiY29tcGFyZV9ncm91cF90cmFpbmluZyIsImlkIjoiY29tcGFyZS1zdHVkZW50IiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc5MTg2NDAwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiIiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuWwj+mZiCIsImdyb3VwSWQiOiJjb21wYXJlX2dyb3VwX3RyYWluaW5nIiwiaWQiOiJjb21wYXJlLXRyYWluaW5nLWd1ZXN0IiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc5MTg2NDAwMDAwMCwia2luZCI6InRlbXBvcmFyeSIsInJvbGUiOiJtZW1iZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6InNlZWRfYWNjX3l5MiIsImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5p2o5omsIiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfdGVubmlzIiwiaWQiOiJzZWVkX21fc2VlZF9ncm91cF90ZW5uaXNfMCIsImlzVmlwIjpmYWxzZSwiam9pbmVkQXQiOjE3ODg0MDgwMDAwMDAsImtpbmQiOiJhY2NvdW50Iiwicm9sZSI6Im93bmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiJjb21wYXJlLWFjY291bnQiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuaIkSIsImdyb3VwSWQiOiJzZWVkX2dyb3VwX3Rlbm5pcyIsImlkIjoic2VlZF9tX3NlZWRfZ3JvdXBfdGVubmlzXzEiLCJpc1ZpcCI6ZmFsc2UsImpvaW5lZEF0IjoxNzg4NDk0NDAwMDAwLCJraW5kIjoiYWNjb3VudCIsInJvbGUiOiJhZG1pbiIsInN0YXR1cyI6ImFjdGl2ZSJ9LHsiYWNjb3VudElkIjoic2VlZF9hY2NfbHEyIiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmnpflkK8iLCJncm91cElkIjoic2VlZF9ncm91cF90ZW5uaXMiLCJpZCI6InNlZWRfbV9zZWVkX2dyb3VwX3Rlbm5pc18yIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc4ODU4MDgwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiJzZWVkX2FjY19jcDIiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IumZiOm5jyIsImdyb3VwSWQiOiJzZWVkX2dyb3VwX3Rlbm5pcyIsImlkIjoic2VlZF9tX3NlZWRfZ3JvdXBfdGVubmlzXzMiLCJpc1ZpcCI6ZmFsc2UsImpvaW5lZEF0IjoxNzg4NjY3MjAwMDAwLCJraW5kIjoiYWNjb3VudCIsInJvbGUiOiJtZW1iZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6InNlZWRfYWNjX2x3IiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLogIHnjosiLCJncm91cElkIjoic2VlZF9ncm91cF9waWNrbGViYWxsIiwiaWQiOiJzZWVkX21fc2VlZF9ncm91cF9waWNrbGViYWxsXzAiLCJpc1ZpcCI6ZmFsc2UsImpvaW5lZEF0IjoxNzg4NDA4MDAwMDAwLCJraW5kIjoiYWNjb3VudCIsInJvbGUiOiJvd25lciIsInN0YXR1cyI6ImFjdGl2ZSJ9LHsiYWNjb3VudElkIjoiY29tcGFyZS1hY2NvdW50IiwiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmiJEiLCJncm91cElkIjoic2VlZF9ncm91cF9waWNrbGViYWxsIiwiaWQiOiJzZWVkX21fc2VlZF9ncm91cF9waWNrbGViYWxsXzEiLCJpc1ZpcCI6ZmFsc2UsImpvaW5lZEF0IjoxNzg4NDk0NDAwMDAwLCJraW5kIjoiYWNjb3VudCIsInJvbGUiOiJtZW1iZXIiLCJzdGF0dXMiOiJhY3RpdmUifSx7ImFjY291bnRJZCI6InNlZWRfYWNjX3hiMiIsImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5bCP5YyXIiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfcGlja2xlYmFsbCIsImlkIjoic2VlZF9tX3NlZWRfZ3JvdXBfcGlja2xlYmFsbF8yIiwiaXNWaXAiOmZhbHNlLCJqb2luZWRBdCI6MTc4ODU4MDgwMDAwMCwia2luZCI6ImFjY291bnQiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn0seyJhY2NvdW50SWQiOiIiLCJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuS4tOaXtueQg+WPiyIsImdyb3VwSWQiOiJzZWVkX2dyb3VwX3BpY2tsZWJhbGwiLCJpZCI6InNlZWRfbV9zZWVkX2dyb3VwX3BpY2tsZWJhbGxfMyIsImlzVmlwIjpmYWxzZSwiam9pbmVkQXQiOjE3ODg2NjcyMDAwMDAsImtpbmQiOiJ0ZW1wb3JhcnkiLCJyb2xlIjoibWVtYmVyIiwic3RhdHVzIjoiYWN0aXZlIn1dLCJub3RpY2VzIjpbeyJjcmVhdGVkQXQiOjE3OTE4NjA0MDAwMDAsImdyb3VwSWQiOiJzZWVkX2dyb3VwX2JhZG1pbnRvbiIsImdyb3VwTmFtZSI6IuWRqOWFree+veavm+eQgyIsImlkIjoiY29tcGFyZS1ub3RpY2UtMSIsImtpbmQiOiJhY3Rpdml0eV9jcmVhdGVkIiwicmVhc29uIjoiIiwicmVzb3VyY2VJZCI6ImNvbXBhcmVfYWN0aXZpdHlfbXVsdGkiLCJzZWVuQXQiOm51bGwsInRpdGxlIjoi5ZGo5YWt5Y+M5omT5Y+L6LCK6LWbIn1dLCJvcmlnaW4iOiJOYW1lcy9JRHMvZ3JvdXAgbnVtYmVycyBhbmQgYmFzZWxpbmUgcmVzdWx0IGZyb20gSGFybW9ueU9TIE1vY2tHcm91cFJlcG9zaXRvcnkuYnVpbGRTZWVkOyBmaXhlZCBkYXRlcyBhbmQgdHJhaW5pbmcvbGluZXVwIHRha2VuIGZyb20gSE9TIEdyb3VwQnVzaW5lc3NTY2VuYXJpb3MgY29uY2VwdHMuIEFuZHJvaWQgZXhpc3RpbmcgZml4dHVyZXMgYXJlIGZyYWdtZW50ZWQgYW5kIGFyZSBub3QgY2Fub25pY2FsLiIsInJlZmVyZW5jZUlzbyI6IjIwMjYtMTAtMTNUMTI6MDA6MDArMDg6MDAiLCJyZWZlcmVuY2VUaW1lIjoxNzkxODY0MDAwMDAwLCJyZXF1aXJlc0FkYXB0ZXJzIjpbIkFkZCBjb21wbGV0ZSB0ZW5uaXMvcGlja2xlYmFsbCByb3N0ZXIgaWYgdGhvc2UgZGV0YWlsIHBhZ2VzIGFyZSBjYXB0dXJlZDsgbGlzdCBzdW1tYXJpZXMgc3VmZmljZSBmb3IgbGlzdCBiYXNlbGluZS4iLCJHcm91cCBydWxlcyBkZWZhdWx0IGJhZG1pbnRvbjIxL21heFNldHMzLCBUVDExL21heFNldHM1LCB0ZW5uaXMvcGlja2xlYmFsbCBmcm9tIGN1cnJlbnQgQW5kcm9pZCBjYXBhYmlsaXRpZXMuIiwiU3RhdGUgc2NlbmFyaW9zIG92ZXJyaWRlIHJvbGUvc3RhdHVzLCBuZXZlciBmb3JrIGRpc3BsYXllZCBjb3B5IG9yIHJlZHJhdyBVSS4iLCJIT1MgY3VycmVudCBEYXRlLm5vdyBhbmQgZ2VuZXJhdGVkIElEcyBtdXN0IGJlIHJlcGxhY2VkIHdpdGhpbiB0ZXN0LW9ubHkgY2FwdHVyZSBmaXh0dXJlLiIsIk5ldyBmb3JtIGRhdGUgZGVmYXVsdHMgbmVlZCBVSSBpbnRlcmFjdGlvbiB0byBmaXhlZCBkYXRlIG9yIGlzb2xhdGVkIHRlc3Qgc3RhdGU7IGNhcHR1cmUgbWFuaWZlc3QgbXVzdCBub3QgY2xhaW0gdGltZSBmcm96ZW4gZ2xvYmFsbHkuIl0sInJlc3VsdHMiOlt7ImFjdGl2aXR5SWQiOiIiLCJiZXN0T2YiOjMsImNvbmZpcm1lZEJ5TWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMiIsImNyZWF0ZWRBdCI6MTc5MTYxMjAwMDAwMCwiZm9ybWF0IjoiZG91YmxlcyIsImdhbWVJZCI6InNlZWRfZ2FtZV8xIiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfYmFkbWludG9uIiwiaWQiOiJzZWVkX3Jlc3VsdF8xIiwib3V0Y29tZSI6IndpbiIsInBhcnRpY2lwYW50cyI6W3siYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmiJEiLCJtZW1iZXJJZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8wIiwic2VhdCI6MCwic2lkZSI6IkEifSx7ImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5p2o5omsIiwibWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMSIsInNlYXQiOjEsInNpZGUiOiJBIn0seyJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IumZiOm5jyIsIm1lbWJlcklkIjoic2VlZF9tX3NlZWRfZ3JvdXBfYmFkbWludG9uXzIiLCJzZWF0IjowLCJzaWRlIjoiQiJ9LHsiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmnpflkK8iLCJtZW1iZXJJZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8zIiwic2VhdCI6MSwic2lkZSI6IkIifV0sInBsYXllZEF0IjoxNzkxNjEyMDAwMDAwLCJyZWFzb24iOiIiLCJyZXZpc2lvbiI6MiwicnVsZXMiOnsiZ2FtZXNQZXJTZXQiOjYsIm1hdGNoQ29tcGxldGlvbk1vZGUiOiJiZXN0X29mIiwibWF4U2V0cyI6MywicG9pbnRDYXAiOjMwLCJwb2ludHNUb1dpblNldCI6MjEsInNldFNjb3JpbmdNb2RlIjoicmVndWxhciIsInNwb3J0IjoiYmFkbWludG9uIiwidGllQnJlYWtQb2ludHMiOjcsInVzZVJhbGx5U2NvcmluZyI6ZmFsc2UsInVzZXNOb0FkU2NvcmluZyI6ZmFsc2UsInZlcnNpb24iOjEsIndpbkJ5VHdvIjp0cnVlfSwic2V0U2NvcmUiOnsiYSI6MiwiYiI6MX0sInNldHMiOlt7ImEiOjIxLCJiIjoxOH0seyJhIjoxNywiYiI6MjF9LHsiYSI6MjEsImIiOjE5fV0sInNvdXJjZSI6Im1hbnVhbCIsInNwb3J0IjoiYmFkbWludG9uIiwic3RhdHVzIjoiY29uZmlybWVkIiwic3VibWl0dGVyTWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fMCIsIndpbm5lclNpZGUiOiJBIn0seyJhY3Rpdml0eUlkIjoiIiwiYmVzdE9mIjozLCJjYW5BdXRob3JpdHlDb25maXJtIjpmYWxzZSwiY29uZmlybWVkQnlNZW1iZXJJZCI6IiIsImNyZWF0ZWRBdCI6MTc5MTg0MjQwMDAwMCwiZm9ybWF0Ijoic2luZ2xlcyIsImdhbWVJZCI6InNlZWRfZ2FtZV8yIiwiZ3JvdXBJZCI6InNlZWRfZ3JvdXBfYmFkbWludG9uIiwiaWQiOiJzZWVkX3Jlc3VsdF8yIiwib3V0Y29tZSI6IndpbiIsInBhcnRpY2lwYW50cyI6W3siYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmiJEiLCJtZW1iZXJJZCI6InNlZWRfbV9zZWVkX2dyb3VwX2JhZG1pbnRvbl8wIiwic2VhdCI6MCwic2lkZSI6IkEifSx7ImF2YXRhclVybCI6IiIsImRpc3BsYXlOYW1lIjoi5bCP5YyXIiwibWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fNCIsInNlYXQiOjAsInNpZGUiOiJCIn1dLCJwbGF5ZWRBdCI6MTc5MTg0MjQwMDAwMCwicmVhc29uIjoiIiwicmV2aXNpb24iOjEsInJ1bGVzIjp7ImdhbWVzUGVyU2V0Ijo2LCJtYXRjaENvbXBsZXRpb25Nb2RlIjoiYmVzdF9vZiIsIm1heFNldHMiOjMsInBvaW50Q2FwIjozMCwicG9pbnRzVG9XaW5TZXQiOjIxLCJzZXRTY29yaW5nTW9kZSI6InJlZ3VsYXIiLCJzcG9ydCI6ImJhZG1pbnRvbiIsInRpZUJyZWFrUG9pbnRzIjo3LCJ1c2VSYWxseVNjb3JpbmciOmZhbHNlLCJ1c2VzTm9BZFNjb3JpbmciOmZhbHNlLCJ2ZXJzaW9uIjoxLCJ3aW5CeVR3byI6dHJ1ZX0sInNldFNjb3JlIjp7ImEiOjIsImIiOjB9LCJzZXRzIjpudWxsLCJzb3VyY2UiOiJtYW51YWwiLCJzcG9ydCI6ImJhZG1pbnRvbiIsInN0YXR1cyI6InBlbmRpbmdfY29uZmlybWF0aW9uIiwic3VibWl0dGVyTWVtYmVySWQiOiJzZWVkX21fc2VlZF9ncm91cF9iYWRtaW50b25fNCIsIndpbm5lclNpZGUiOiJBIn1dLCJ0aW1lem9uZSI6IkFzaWEvU2hhbmdoYWkiLCJ0cmFpbmluZ05vdGljZXMiOltdLCJ0cmFpbmluZ1BsYW5zIjpbeyJjYW5jZWxSZWFzb24iOiIiLCJjcmVhdGVkQXQiOjE3OTE4NjQwMDAwMDAsImNyZWF0b3JNZW1iZXJJZCI6ImNvbXBhcmUtY29hY2giLCJlbmRzQXQiOjE3OTIzMDg2MDAwMDAsImdyb3VwSWQiOiJjb21wYXJlX2dyb3VwX3RyYWluaW5nIiwiaWQiOiJjb21wYXJlX3RyYWluaW5nX3BsYW4iLCJteVNlc3Npb25Db3VudCI6MSwibm90ZSI6IuWFiOeDrei6qyAxMCDliIbpkp/vvIzlho3liIbnu4Tlr7nnu4PjgIIiLCJwbGFjZSI6Iua7qOaxn+S9k+iCsuS4reW/gyAyIOWPt+mmhiIsInBsYWNlTG9ja2VkIjpmYWxzZSwicHVibGlzaGVkQXQiOjE3OTE4NjQwMDAwMDAsInJldmlzaW9uIjoxLCJzZXNzaW9uQ291bnQiOjIsInNlc3Npb25NaW51dGVzIjozMCwic2Vzc2lvbnMiOlt7ImNvdXJ0IjoiMiDlj7flnLoiLCJlbmRzQXQiOjE3OTIzMDUwMDAwMDAsImZvcm1hdCI6InNpbmdsZXMiLCJncm91cElkIjoiY29tcGFyZV9ncm91cF90cmFpbmluZyIsImlkIjoiY29tcGFyZV90cmFpbmluZ19zZXNzaW9uXzEiLCJteVNpZGUiOiJBIiwib3JkZXJObyI6MSwicGxhbklkIjoiY29tcGFyZV90cmFpbmluZ19wbGFuIiwicmVzdWx0SWQiOiIiLCJzZWF0cyI6W3siYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLmiJEiLCJtZW1iZXJJZCI6ImNvbXBhcmUtY29hY2giLCJzZWF0IjowLCJzaWRlIjoiQSJ9LHsiYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLlsI/mnpciLCJtZW1iZXJJZCI6ImNvbXBhcmUtc3R1ZGVudCIsInNlYXQiOjAsInNpZGUiOiJCIn1dLCJzdGFydGVkR2FtZUlkIjoiIiwic3RhcnRzQXQiOjE3OTIzMDMyMDAwMDAsInN0YXR1cyI6InNjaGVkdWxlZCJ9LHsiY291cnQiOiIyIOWPt+WcuiIsImVuZHNBdCI6MTc5MjMwODYwMDAwMCwiZm9ybWF0Ijoic2luZ2xlcyIsImdyb3VwSWQiOiJjb21wYXJlX2dyb3VwX3RyYWluaW5nIiwiaWQiOiJjb21wYXJlX3RyYWluaW5nX3Nlc3Npb25fMiIsIm15U2lkZSI6bnVsbCwib3JkZXJObyI6MiwicGxhbklkIjoiY29tcGFyZV90cmFpbmluZ19wbGFuIiwicmVzdWx0SWQiOiIiLCJzZWF0cyI6W3siYXZhdGFyVXJsIjoiIiwiZGlzcGxheU5hbWUiOiLlsI/mnpciLCJtZW1iZXJJZCI6ImNvbXBhcmUtc3R1ZGVudCIsInNlYXQiOjAsInNpZGUiOiJBIn0seyJhdmF0YXJVcmwiOiIiLCJkaXNwbGF5TmFtZSI6IuWwj+mZiCIsIm1lbWJlcklkIjoiY29tcGFyZS10cmFpbmluZy1ndWVzdCIsInNlYXQiOjAsInNpZGUiOiJCIn1dLCJzdGFydGVkR2FtZUlkIjoiIiwic3RhcnRzQXQiOjE3OTIzMDY4MDAwMDAsInN0YXR1cyI6InNjaGVkdWxlZCJ9XSwic3RhcnRzQXQiOjE3OTIzMDMyMDAwMDAsInN0YXR1cyI6InB1Ymxpc2hlZCIsInRyYWluaW5nRGF0ZSI6MTc5MjI1MjgwMDAwMCwid2FybmluZ3MiOltdfV19"
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-UITestGroupsCrossPlatform") }
    static func argument(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.arguments
        guard let index = values.firstIndex(of: key), index + 1 < values.count else { return nil }
        return values[index + 1]
    }
    static var scene: String { argument("-GroupCaptureScene") ?? "list" }
    static let reportAliases: [String: String] = [
        "create-approval-selected": "create-approval-selected",
        "inventory-management-actions": "admin",
        "inventory-member-actions": "member-actions",
        "inventory-result-actions": "result-actions",
        "inventory-edit-group": "dialog-edit-group",
        "inventory-edit-group-conflict": "group-conflict",
        "inventory-transfer-picker": "dialog-transfer-owner",
        "inventory-transfer-confirm": "transfer-selected",
        "inventory-member-report": "dialog-report",
        "inventory-visitor-report": "visitor-report",
        "inventory-dissolve-confirm": "dialog-dissolve",
        "inventory-archive-confirm": "dialog-archive",
        "inventory-leave-group-confirm": "dialog-leave",
        "inventory-temporary-members": "dialog-temporary-member",
        "inventory-common-name-import": "dialog-common-name-import",
        "inventory-rename-temporary-member": "member-rename",
        "inventory-remove-member-confirm": "member-remove",
        "inventory-approve-join-confirm": "request-approve",
        "inventory-reject-join-confirm": "request-reject",
        "inventory-training-cancel": "training-cancel",
        "inventory-training-leave": "training-leave",
        "inventory-result-authority-confirm-detail": "result-authority",
        "inventory-result-normal-confirm-detail": "result-normal",
        "inventory-result-void-detail-pending": "result-void-pending",
        "inventory-result-void-detail-confirmed": "result-void-confirmed",
        "inventory-result-authority-confirm-list": "records-authority",
        "inventory-result-void-list": "result-void-list",
        "inventory-upload-discard-confirm": "upload-discard",
        "inventory-activity-date-time": "activity-date",
        "inventory-activity-registration-deadline": "activity-deadline",
        "inventory-activity-common-places": "activity-place",
        "inventory-activity-cancel": "activity-cancel",
        "inventory-activity-abandon": "activity-abandon",
        "inventory-registration-draft-discard": "registration-draft",
        "activity-registration-draft-discard": "registration-draft",
        "inventory-result-played-at": "result-date",
        "inventory-result-save-draft-return": "result-draft-return",
        "inventory-result-abandon": "result-abandon",
        "inventory-lineup-clock": "lineup-clock",
        "inventory-lineup-finish": "lineup-finish",
        "inventory-lineup-reload-confirm": "lineup-conflict-reload",
        "inventory-training-sequence-preview": "training-shift-preview",
        "inventory-training-date-picker": "training-date",
        "inventory-training-clock-picker": "training-clock",
        "inventory-training-conflict-review": "training-conflict",
        "inventory-activity-conflict-review": "activity-conflict",
    ]
    static var nativeScene: String { reportAliases[scene] ?? scene }
    private static let conflictState = GroupCaptureConflictState()
    static var conflictRevealed: Bool { conflictState.read() }
    static func rejectWrite(_ path: String) throws -> Never {
        let expected: String?
        switch nativeScene {
        case "group-conflict": expected = "/seed_group_badminton"
        case "activity-conflict": expected = "/seed_group_badminton/activities/compare_activity_multi"
        case "lineup-conflict-reload": expected = "/seed_group_badminton/activities/compare_activity_multi/lineup"
        case "training-conflict": expected = "/compare_group_training/training-plans/compare_training_plan"
        default: expected = nil
        }
        if path == expected {
            conflictState.reveal()
            throw APIClientError.server(status: 409, code: "REVISION_CONFLICT", message: nil, nextAvailableAt: nil)
        }
        throw GroupCaptureFailure.writeForbidden(path)
    }

    // Fresh submitResult creation time is wall clock, pinned once per independently launched capture scene.
    private static let scenarioCreatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    static var referenceDate: Date { Date(timeIntervalSince1970: Double(referenceTime) / 1000) }
    static var referenceTime: Int64 { Int64(argument("-GroupCaptureNow") ?? "") ?? 1791864000000 }
    static var accountID: String { ["student", "training-leave", "training-notices"].contains(nativeScene) ? "compare-student-account" : "compare-account" }
    static var accountName: String { accountID == "compare-account" ? "演示账号" : "小林" }
    static var sourceHash: String { argument("-GroupCaptureSourceHash") ?? "unbound" }
    static var trainingScene: Bool { ["coach", "student", "training-plan", "training-plan-create", "training-plan-edit", "training-plan-review", "training-plan-frozen", "training-shift-preview", "training-date", "training-clock", "training-cancel", "training-leave", "training-notices", "training-conflict"].contains(nativeScene) }
    static var groupID: String {
        if ["request-approve", "request-reject"].contains(nativeScene) { return "compare_group_approval" }
        return nativeScene == "detail-empty" ? "compare_group_empty" : trainingScene ? "compare_group_training" : "seed_group_badminton"
    }
    static var metadata: String { "scene=\(scene);canonical=\(canonicalHash);adapter=\(adapterHash);referenceTime=\(referenceTime);transport=strict-offline;source=\(sourceHash)" }

    static func dataset() throws -> GroupCaptureDataset {
        guard enabled else { throw GroupCaptureFailure.invalidFixture("mode not enabled") }
        guard argument("-GroupCaptureDataHash") == canonicalHash else { throw GroupCaptureFailure.invalidFixture("canonical hash mismatch") }
        let payload: Data
        if let supplied = ProcessInfo.processInfo.environment["GROUP_CAPTURE_FIXTURE_JSON"] { payload = Data(supplied.utf8) }
        else if let data = Data(base64Encoded: embeddedBase64) { payload = data }
        else { throw GroupCaptureFailure.invalidFixture("embedded data") }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        guard digest == adapterHash else { throw GroupCaptureFailure.invalidFixture("adapted payload hash mismatch") }
        var value = try JSONDecoder().decode(GroupCaptureDataset.self, from: payload)
        guard value.referenceTime == referenceTime else { throw GroupCaptureFailure.invalidFixture("clock mismatch") }
        // Scenario variants match HOS prepareGroupScenario; the shared canonical base stays unchanged.
        if ["join", "join-approval", "visitor-report"].contains(nativeScene), let baseline = value.groups.first(where: { $0.sport == .pickleball }) {
            var visitor = baseline
            visitor.id = "compare_visitor_group"; visitor.groupNo = "82603162"
            visitor.name = "滨江周末球友"; visitor.description = "欢迎爱好者加入一起练球。"
            visitor.joinPolicy = nativeScene == "join-approval" ? "approval" : "open"
            visitor.ownerMemberId = "compare_visitor_owner"; visitor.memberCount = 1; visitor.myRole = nil
            visitor.createdAt = referenceTime; visitor.updatedAt = referenceTime; visitor.revision = 1
            value.groups.append(visitor)
            value.members.append(.init(id: visitor.ownerMemberId, groupId: visitor.id, kind: "account", role: "owner", status: "active", displayName: "我", accountId: "fixture-host-account", joinedAt: referenceTime))
        }
        if nativeScene == "detail-empty", let baseline = value.groups.first(where: { $0.id == "seed_group_badminton" }) {
            var empty = baseline
            empty.id = "compare_group_empty"; empty.groupNo = "82603163"
            empty.name = "新建球友组"; empty.description = ""; empty.joinPolicy = "open"
            empty.ownerMemberId = "compare_empty_owner"; empty.memberCount = 1
            empty.currentMonthMatchCount = 0; empty.activeMemberCount30d = 0
            empty.createdAt = referenceTime; empty.updatedAt = referenceTime; empty.revision = 1
            value.groups.append(empty)
            value.members.append(.init(id: empty.ownerMemberId, groupId: empty.id, kind: "account", role: "owner", status: "active", displayName: "我", accountId: accountID, joinedAt: referenceTime))
        }
        if let index = value.groups.firstIndex(where: { $0.id == groupID }) {
            if nativeScene == "detail-admin" || nativeScene == "detail-member" || nativeScene == "dialog-leave" {
                let role = nativeScene == "detail-admin" ? "admin" : "member"
                value.groups[index].myRole = role
                value.groups[index].ownerMemberId = "seed_m_seed_group_badminton_1"
                for i in value.members.indices where value.members[i].groupId == groupID {
                    if value.members[i].accountId == accountID { value.members[i].role = role }
                    else if value.members[i].id == "seed_m_seed_group_badminton_1" { value.members[i].role = "owner" }
                }
            }
            if ["detail-archived", "share-readonly", "dialog-restore"].contains(nativeScene) { value.groups[index].status = "archived" }
            if nativeScene == "detail-dissolving" { value.groups[index].status = "dissolving" }
            if ["student", "training-leave", "training-notices"].contains(nativeScene) { value.groups[index].isCoach = false; value.groups[index].myRole = "member" }
        }
        if nativeScene == "result-detail-pending" { value.results = value.results.filter { $0.status == "pending_confirmation" } }
        if nativeScene == "result-detail-voided", !value.results.isEmpty { value.results[0].status = "voided"; value.results[0].reason = "重复记录" }
        applyExpansionVariants(&value)
        // Mirror the production listResults API (createdAt DESC, id DESC); cache and public reads share this order.
        value.results.sort { left, right in left.createdAt == right.createdAt ? left.id > right.id : left.createdAt > right.createdAt }
        try validateExpansionState(value)
        return value
    }


    private static func applyExpansionVariants(_ value: inout GroupCaptureDataset) {
        let activityFrozen = ["lineup-frozen", "lineup-correction", "result-frozen", "result-abandon"].contains(nativeScene)
        if activityFrozen, !value.activityLineup.sessions.isEmpty, !value.activities.isEmpty {
            value.activityLineup.sessions[0].startedGameId = "compare_frozen_activity_game"
            value.activityLineup.sessions[0].isFrozen = true
            value.activityLineup.sessions[0].status = "in_progress"
            value.activities[0].startedGameCount = 1
            value.activities[0].status = "in_progress"
            if nativeScene == "lineup-correction" {
                value.activities[0].status = "completed"
                value.activityLineup.sessions[0].status = "cancelled"
                value.activityLineup.sessions[0].canCorrectResult = true
                value.activityLineup.canManage = false
                value.activityLineup.sessions[0].frozenGameId = "compare_frozen_activity_game"
                value.activityLineup.sessions[0].resultId = ""
                if value.activityLineup.sessions.count > 1 { value.activityLineup.sessions[1].status = "cancelled" }
                if var result = value.results.first {
                    let row = value.activityLineup.sessions[0]
                    result.id = "compare_correction_result"; result.activityId = row.activityId; result.activitySessionId = row.id
                    result.gameId = "compare_frozen_activity_game"; result.status = "voided"; result.reason = "比分待核对"
                    result.format = row.format; result.participants = row.seats; result.playedAt = referenceTime; result.createdAt = referenceTime
                    result.setScore = .init(a: 2, b: 1); result.sets = nil
                    value.results.append(result)
                }
            }
        }
        if nativeScene == "activity-abandon", var activity = value.activities.first {
            activity.id = "compare_single_activity"; activity.title = "单场计分续局"
            activity.startsAt = referenceTime + 86400000; activity.registrationClosesAt = activity.startsAt
            activity.matchMode = "single"; activity.format = .singles; activity.capacity = 6
            activity.registeredMemberIds = ["seed_m_seed_group_badminton_0", "seed_m_seed_group_badminton_1"]
            activity.status = "in_progress"; activity.gameId = "compare_capture_single_game"; activity.note = ""
            activity.sessionCount = nil; activity.completedSessionCount = nil; activity.startedGameCount = nil
            value.activities = [activity]
        }
        if nativeScene == "training-plan-frozen", !value.trainingPlans.isEmpty, !value.trainingPlans[0].sessions.isEmpty {
            value.trainingPlans[0].sessions[0].startedGameId = "compare_frozen_training_game"
            value.trainingPlans[0].placeLocked = true
        }
        if ["member-actions", "member-rename", "member-remove", "dialog-temporary-member", "dialog-common-name-import"].contains(nativeScene) {
            if let index = value.members.firstIndex(where: { $0.id == "seed_m_seed_group_badminton_5" }) { value.members[index].displayName = "临时球友 小陈" }
            if let index = value.members.firstIndex(where: { $0.id == "seed_m_seed_group_badminton_4" }) { value.members[index].status = "removed"; value.members[index].removedAt = referenceTime }
            value.members.append(.init(id: "compare-extra-temporary", groupId: "seed_group_badminton", kind: "temporary", role: "member", status: "active", displayName: "临时球友 小林", accountId: "", joinedAt: referenceTime))
        }
        if ["request-approve", "request-reject"].contains(nativeScene), var group = value.groups.first(where: { $0.id == "seed_group_badminton" }) {
            group.id = "compare_group_approval"; group.groupNo = "82603164"
            group.name = "待审批羽毛球组"; group.description = "申请加入需组长审批。"
            group.joinPolicy = "approval"; group.ownerMemberId = "compare_approval_owner"; group.memberCount = 1
            group.currentMonthMatchCount = 0; group.activeMemberCount30d = 0
            group.createdAt = referenceTime; group.updatedAt = referenceTime; group.revision = 1
            value.groups.append(group); value.listGroupIds.insert(group.id, at: 0)
            value.members.append(.init(id: group.ownerMemberId, groupId: group.id, kind: "account", role: "owner", status: "active", displayName: "我", accountId: accountID, joinedAt: referenceTime))
        }
        let authority = ["result-authority", "records-authority", "result-void-pending", "result-void-confirmed"].contains(nativeScene)
        if authority, let base = value.results.first, let rules = value.capabilities.sport(.badminton)?.defaultRules {
            let names = ["场边球友甲", "场边球友乙"]
            let members = names.enumerated().map { index, name in GroupMember(id: "compare-result-temporary-\(index)", groupId: groupID, kind: "temporary", role: "member", status: "active", displayName: name, accountId: "", joinedAt: referenceTime) }
            value.members.append(contentsOf: members)
            var result = base
            result.id = "compare_authority_result"; result.activityId = ""; result.gameId = ""
            result.format = .singles; result.status = nativeScene == "result-void-confirmed" ? "confirmed" : "pending_confirmation"
            result.setScore = .init(a: 2, b: 1); result.sets = [.init(a: 21, b: 18), .init(a: 19, b: 21), .init(a: 21, b: 16)]
            result.participants = members.enumerated().map { index, member in .init(memberId: member.id, side: index == 0 ? "A" : "B", seat: 0, displayName: member.displayName) }
            result.rules = rules; result.bestOf = rules.maxSets; result.playedAt = referenceTime - 3600000
            result.createdAt = scenarioCreatedAt; result.revision = 1; result.source = "manual"; result.reason = ""
            result.submitterMemberId = "seed_m_seed_group_badminton_0"
            result.confirmedByMemberId = result.status == "confirmed" ? result.submitterMemberId : ""
            result.canAuthorityConfirm = true
            if result.status == "confirmed" { result.revision = 2; result.confirmationMode = "owner_authority" }
            value.results.insert(result, at: 0)
            if let index = value.groups.firstIndex(where: { $0.id == groupID }) { value.groups[index].memberCount = value.members.filter { $0.groupId == groupID && $0.status == "active" }.count }
        }
        if nativeScene == "result-normal", let base = value.results.first, let rules = value.capabilities.sport(.badminton)?.defaultRules {
            var result = base
            result.id = "compare_normal_result"; result.activityId = ""; result.gameId = ""; result.format = .singles
            result.status = "pending_confirmation"; result.setScore = .init(a: 2, b: 1); result.sets = nil
            result.participants = [GroupSeat(memberId: "seed_m_seed_group_badminton_2", side: "A", seat: 0, displayName: "陈鹏"), GroupSeat(memberId: "seed_m_seed_group_badminton_0", side: "B", seat: 0, displayName: "我")]
            result.submitterMemberId = "seed_m_seed_group_badminton_2"; result.confirmedByMemberId = ""
            result.rules = rules; result.bestOf = rules.maxSets; result.canAuthorityConfirm = false
            result.playedAt = referenceTime - 3600000; result.createdAt = scenarioCreatedAt; result.revision = 1
            value.results.insert(result, at: 0)
        }
        if nativeScene == "detail-dissolving", let index = value.groups.firstIndex(where: { $0.id == groupID }) { value.groups[index].dissolveAt = referenceTime + 7 * 86400000 }
        if nativeScene == "lineup-finish", !value.activities.isEmpty {
            value.activities[0].status = "in_progress"
            value.activities[0].completedSessionCount = value.activityLineup.sessions.count
            for index in value.activityLineup.sessions.indices {
                var row = value.activityLineup.sessions[index]
                row.status = "completed"; row.isFrozen = true; row.resultId = "compare_finished_result_\(index + 1)"; row.frozenGameId = "compare_finished_game_\(index + 1)"
                value.activityLineup.sessions[index] = row
                if var result = value.results.first {
                    result.id = row.resultId!; result.activityId = row.activityId; result.activitySessionId = row.id
                    result.gameId = row.frozenGameId!; result.format = row.format; result.participants = row.seats
                    result.status = "pending_confirmation"; result.confirmedByMemberId = ""; result.canAuthorityConfirm = false
                    result.playedAt = referenceTime; result.createdAt = referenceTime; result.setScore = .init(a: 2, b: 0); result.sets = nil
                    value.results.append(result)
                }
            }
        }
        if conflictRevealed {
            if nativeScene == "group-conflict", let index = value.groups.firstIndex(where: { $0.id == groupID }) { value.groups[index].name += "（云端）"; value.groups[index].joinPolicy = "open"; value.groups[index].revision += 1 }
            if nativeScene == "activity-conflict", !value.activities.isEmpty { value.activities[0].title += "（云端）"; value.activities[0].revision += 1 }
            if nativeScene == "lineup-conflict-reload", !value.activityLineup.sessions.isEmpty { value.activityLineup.sessions[value.activityLineup.sessions.count - 1].court += " · 云端"; value.activityLineup.revision += 1 }
            if nativeScene == "training-conflict", !value.trainingPlans.isEmpty { value.trainingPlans[0].note += " 云端已调整。"; value.trainingPlans[0].revision += 1 }
        }
        // Actor-specific training fields and summaries are fixture facts, using the accepted reference date.
        for index in value.trainingPlans.indices {
            let member = value.members.first { $0.groupId == value.trainingPlans[index].groupId && $0.accountId == accountID && $0.status == "active" }
            var count = 0
            for row in value.trainingPlans[index].sessions.indices {
                let side = value.trainingPlans[index].sessions[row].seats.first { $0.memberId == member?.id }?.side
                value.trainingPlans[index].sessions[row].mySide = side
                if side != nil { count += 1 }
            }
            value.trainingPlans[index].mySessionCount = count
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let monthStart = Int64((calendar.dateInterval(of: .month, for: referenceDate)?.start ?? referenceDate).timeIntervalSince1970 * 1000)
        for index in value.groups.indices {
            let confirmed = value.results.filter { $0.groupId == value.groups[index].id && $0.status == "confirmed" }
            value.groups[index].currentMonthMatchCount = confirmed.filter { $0.playedAt >= monthStart && $0.playedAt <= referenceTime }.count
            value.groups[index].activeMemberCount30d = Set(confirmed.filter { $0.playedAt >= referenceTime - 30 * 86400000 && $0.playedAt <= referenceTime }.flatMap { $0.participants.map(\.memberId) }).count
        }
    }

    private struct GameResponse: Encodable {
        var gameId: String; var groupId: String; var activityId: String; var clientSessionId: String
        var format: GroupFormat; var state: String; var rules: GroupMatchRules; var participants: [GroupSeat]
        var trainingSessionId: String?; var activitySessionId: String?; var creatorMemberId: String
    }
    private static func validateExpansionState(_ value: GroupCaptureDataset) throws {
        func require(_ condition: Bool, _ field: String) throws {
            guard condition else { throw GroupCaptureFailure.invalidFixture("scenario field mismatch: " + field) }
        }
        if ["student", "training-leave", "training-notices"].contains(nativeScene), let plan = value.trainingPlans.first {
            try require(plan.mySessionCount == 2 && plan.sessions.map(\.mySide) == ["B", "A"], "student training sides/count")
        }
        if nativeScene == "training-notices" { try require(value.trainingNotices.isEmpty, "empty training inbox") }
        if nativeScene == "lineup-correction", let row = value.activityLineup.sessions.first {
            try require(!value.activityLineup.canManage && row.status == "cancelled" && (row.resultId ?? "").isEmpty && row.canCorrectResult == true, "voided lineup state")
            try require(try game("compare_frozen_activity_game", value: value).state == "submitted", "submitted game")
        }
        if nativeScene == "activity-abandon", let activity = value.activities.first {
            try require(activity.matchMode == "single" && activity.format == .singles && activity.capacity == 6 && activity.registeredMemberIds.count == 2 && activity.startsAt == referenceTime + 86400000, "single activity resume")
        }
        if ["request-approve", "request-reject"].contains(nativeScene) {
            try require(value.members.filter { $0.groupId == groupID && $0.status == "active" }.count == 1, "approval owner")
            try require(value.groups.contains { $0.id == "seed_group_badminton" && $0.name == "周六羽毛球" }, "canonical peer preserved")
            try require(value.notices.contains { $0.id == "compare-notice-1" && $0.groupId == "seed_group_badminton" }, "canonical notice preserved")
        }
        if ["result-detail", "result-detail-confirmed", "result-detail-pending", "result-detail-voided"].contains(nativeScene) || ["result-authority", "result-normal", "result-void-pending", "result-void-confirmed", "result-void-list", "result-actions"].contains(nativeScene) {
            try require(value.results.contains { $0.groupId == groupID && $0.id == resultDetailID }, "explicit target result: " + resultDetailID)
        }
        if nativeScene == "result-void-confirmed", let result = value.results.first(where: { $0.id == resultDetailID }), let group = value.groups.first(where: { $0.id == groupID }) {
            try require(result.status == "confirmed" && result.revision == 2 && result.confirmationMode == "owner_authority", "authority confirmation")
            try require(value.results.filter { $0.groupId == groupID && $0.status == "confirmed" }.count == 2 && group.currentMonthMatchCount == 2 && group.activeMemberCount30d == 6, "authority statistics")
        }
    }
    static var resultDetailID: String {
        switch nativeScene {
        case "result-authority", "result-void-pending", "result-void-confirmed": "compare_authority_result"
        case "result-normal": "compare_normal_result"
        case "result-detail-pending", "result-actions", "result-void-list": "seed_result_2"
        default: "seed_result_1"
        }
    }
    private static func game(_ id: String, value: GroupCaptureDataset) throws -> GameResponse {
        guard let rules = value.capabilities.sport(.badminton)?.defaultRules else { throw GroupCaptureFailure.invalidFixture("frozen rules unavailable") }
        if id == "compare_capture_single_game", let activity = value.activities.first(where: { $0.gameId == id }) {
            let participants = activity.registeredMemberIds.enumerated().map { index, memberID in GroupSeat(memberId: memberID, side: index == 0 ? "A" : "B", seat: 0, displayName: value.members.first { $0.id == memberID }?.displayName) }
            return .init(gameId: id, groupId: activity.groupId, activityId: activity.id, clientSessionId: "fixture-single-resume", format: .singles, state: "started", rules: rules, participants: participants, trainingSessionId: nil, activitySessionId: nil, creatorMemberId: activity.creatorMemberId)
        }
        if id == "compare_frozen_activity_game" || id.hasPrefix("compare_finished_game_"), let row = value.activityLineup.sessions.first(where: { $0.gameID == id }) {
            return .init(gameId: id, groupId: row.groupId, activityId: row.activityId, clientSessionId: "fixture-launch-" + row.id, format: row.format, state: nativeScene == "lineup-correction" || nativeScene == "lineup-finish" ? "submitted" : "started", rules: rules, participants: row.seats, trainingSessionId: nil, activitySessionId: row.id, creatorMemberId: "seed_m_seed_group_badminton_0")
        }
        if id == "compare_frozen_training_game", let row = value.trainingPlans.first?.sessions.first, row.startedGameId == id {
            return .init(gameId: id, groupId: row.groupId, activityId: "", clientSessionId: "fixture-training-launch", format: row.format, state: "started", rules: rules, participants: row.seats, trainingSessionId: row.id, activitySessionId: nil, creatorMemberId: "compare-coach")
        }
        throw GroupCaptureFailure.unsupportedRead("game:" + id)
    }

    @MainActor static func prepareNativeResume() async throws {
        guard enabled else { throw GroupCaptureFailure.invalidFixture("resume fixture outside capture") }
        let repository = ResumeSessionRepository()
        let capturedGames: Set<String> = ["compare_capture_single_game", "compare_frozen_activity_game"]
        for row in try await repository.liveEntries() {
            if let context = GroupLocalPersistence.shared.context(sessionID: row.sessionId.uuidString),
               context.accountID == "compare-account", context.groupID == "seed_group_badminton",
               let gameID = context.gameID, capturedGames.contains(gameID) {
                try await repository.remove(sessionId: row.sessionId)
                try GroupLocalPersistence.shared.removeCaptureContext(sessionID: row.sessionId.uuidString, gameID: gameID)
            }
        }
        guard ["activity-abandon", "result-abandon"].contains(nativeScene) else { return }
        let value = try dataset()
        let snapshot = try game(nativeScene == "activity-abandon" ? "compare_capture_single_game" : "compare_frozen_activity_game", value: value)
        let a = snapshot.participants.filter { $0.side == "A" }.sorted { $0.seat < $1.seat }
        let b = snapshot.participants.filter { $0.side == "B" }.sorted { $0.seat < $1.seat }
        let left = a.compactMap(\.displayName).joined(separator: " / ")
        let right = b.compactMap(\.displayName).joined(separator: " / ")
        let doubles = snapshot.format == .doubles
        let seats = doubles ? [a[0], b[0], a[1], b[1]] : snapshot.participants
        let positions = ["left-top", "right-top", "left-bottom", "right-bottom"]
        let participants: [SessionParticipant] = seats.enumerated().map { index, seat in
            .init(id: doubles ? positions[index] : (seat.side == "A" ? TeamID.team0.rawValue : TeamID.team1.rawValue), name: seat.displayName ?? "", role: doubles ? "player" : "team")
        }
        let seed = RallySessionStore(leftName: left, rightName: right, gameType: doubles ? .badmintonDoubles : .badminton,
                                     rules: snapshot.rules.setup(format: snapshot.format).badmintonRules, participants: participants)
        var state = seed.state; state.leftPoints = 7; state.rightPoints = 4
        let native = RallySessionStore(gameType: seed.gameType, state: state, participants: participants)
        let context = GroupMatchContext(accountID: accountID, groupID: snapshot.groupId,
            groupName: value.groups.first { $0.id == snapshot.groupId }?.name ?? "", activityID: snapshot.activityId,
            gameID: snapshot.gameId, clientSessionID: snapshot.clientSessionId, format: snapshot.format,
            rules: snapshot.rules, participants: snapshot.participants, trainingSessionID: nil, activitySessionID: snapshot.activitySessionId)
        try GroupLocalPersistence.shared.saveContext(context, sessionID: native.sessionId.uuidString)
        let saved: Bool = await withCheckedContinuation { continuation in
            native.persistSnapshot { continuation.resume(returning: $0) }
        }
        guard saved,
              let persisted = try await repository.loadResumeBundle(sessionId: native.sessionId,
                as: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self),
              persisted.currentSession.state.leftPoints == 7, persisted.currentSession.state.rightPoints == 4 else {
            throw GroupCaptureFailure.invalidFixture("native 7:4 resume snapshot did not persist")
        }
        let live = try await repository.liveEntries()
        let persistedContext = GroupLocalPersistence.shared.context(sessionID: native.sessionId.uuidString)
        guard live.contains(where: { $0.sessionId == native.sessionId }),
              persistedContext?.accountID == accountID, persistedContext?.groupID == snapshot.groupId,
              persistedContext?.gameID == snapshot.gameId else {
            throw GroupCaptureFailure.invalidFixture("native resume live index or group context did not persist")
        }
    }

    static func pendingRequests() -> [GroupJoinRequest] {
        guard ["request-approve", "request-reject"].contains(nativeScene) else { return [] }
        return [.init(id: "compare_join_request", groupId: groupID, groupNo: "82603164", groupName: "待审批羽毛球组", sport: .badminton, accountId: "fixture-applicant-account", displayName: "林晨", status: "pending", message: "我每周末都有空，希望一起练球。", createdAt: referenceTime, decidedAt: nil)]
    }
    static func pendingUploads() -> [GroupPendingUpload] {
        guard nativeScene == "upload-discard", let value = try? dataset(), let rules = value.capabilities.sport(.badminton)?.defaultRules else { return [] }
        let seats = value.members.filter { $0.groupId == groupID }.prefix(2).enumerated().map { index, member in GroupSeat(memberId: member.id, side: index == 0 ? "A" : "B", seat: 0, displayName: member.displayName) }
        let body = GroupResultBody(gameId: nil, clientSessionId: "fixture-pending-upload", clientRecordId: nil, activityId: nil, format: .singles, bestOf: rules.maxSets, rules: rules, setScore: .init(a: 2, b: 0), sets: nil, playedAt: referenceTime, source: "manual", participants: seats)
        return [.init(id: "fixture-pending-upload", accountID: accountID, groupID: groupID, key: "fixture-pending-upload", body: body, failure: "INVALID_SET_SCORE", failureCode: "INVALID_SET_SCORE", attempts: 0)]
    }

    static func makeCache() throws -> GroupAccountCache {
        let data = try dataset()
        var cache = GroupAccountCache()
        cache.groups = data.listGroupIds.compactMap { id in data.groups.first { $0.id == id } }
        cache.capabilities = data.capabilities; cache.notices = data.notices
        cache.unreadCount = data.notices.filter { $0.seenAt == nil }.count
        cache.syncedAt = referenceDate
        for group in data.groups {
            let results = data.results.filter { $0.groupId == group.id }
            let confirmed = results.filter { $0.status == "confirmed" }
            let plans = data.trainingPlans.filter { $0.groupId == group.id }
            let stats = GroupStats(confirmedMatchCount: confirmed.count, currentMonthMatchCount: group.currentMonthMatchCount ?? 0, activeMemberCount30d: group.activeMemberCount30d ?? 0, lastCompletedAt: confirmed.map(\.playedAt).max() ?? 0)
            cache.details[group.id] = GroupDetailCache(group: group, members: data.members.filter { $0.groupId == group.id && $0.status == "active" }, activities: data.activities.filter { $0.groupId == group.id }, results: results, rankings: try rankings(group.id, format: .singles), stats: stats, nextCursor: nil, syncedAt: referenceDate, trainingPlans: plans, leaveNotices: data.leaveNotices.filter { $0.groupId == group.id }, pendingResults: results.filter { $0.status == "pending_confirmation" }, removedMembers: data.members.filter { $0.groupId == group.id && $0.status == "removed" }, trainingNotices: data.trainingNotices.filter { $0.groupId == group.id }, activityLineups: group.id == "seed_group_badminton" ? [data.activityLineup.activityId: data.activityLineup] : [:])
        }
        for id in cache.details.keys {
            for format in GroupFormat.allCases {
                cache.details[id]?.setRankings(try rankings(id, format: format), format: format)
            }
        }
        return cache
    }

    static func rankings(_ groupID: String, format: GroupFormat) throws -> [GroupRanking] {
        let data = try dataset()
        let results = data.results.filter { $0.groupId == groupID && $0.status == "confirmed" && $0.format == format }
        var rows: [GroupRanking] = []
        for member in data.members.filter({ $0.groupId == groupID && $0.status == "active" }) {
            let played = results.filter { $0.participants.contains { $0.memberId == member.id } }
            guard !played.isEmpty else { continue }
            var wins = 0, losses = 0, draws = 0, won = 0, lost = 0
            for result in played {
                let side = result.participants.first { $0.memberId == member.id }!.side
                let a = side == "A" ? result.setScore.a : result.setScore.b
                let b = side == "A" ? result.setScore.b : result.setScore.a
                won += a; lost += b
                if a > b { wins += 1 } else if a < b { losses += 1 } else { draws += 1 }
            }
            rows.append(.init(memberId: member.id, displayName: member.displayName, games: played.count, wins: wins, losses: losses, draws: draws, setsWon: won, setsLost: lost, winRateText: "\(Int((Double(wins) / Double(played.count) * 100).rounded()))%", rank: 0))
        }
        rows.sort { $0.wins != $1.wins ? $0.wins > $1.wins : $0.memberId < $1.memberId }
        for index in rows.indices { rows[index].rank = index + 1 }
        return rows
    }

    static func read<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]) throws -> T {
        let value = try dataset()
        let parts = path.split(separator: "/").map(String.init)
        let payload: Data
        func encoded<U: Encodable>(_ object: U) throws -> Data { try JSONEncoder().encode(object) }
        func page<U: Codable & Sendable>(_ items: [U]) throws -> Data { try encoded(GroupPage(items: items, nextCursor: nil)) }
        if parts.isEmpty { payload = try page(value.listGroupIds.compactMap { id in value.groups.first { $0.id == id } }) }
        else if path == "/capabilities" { payload = try encoded(value.capabilities) }
        else if path == "/join-requests/mine" { payload = try page([GroupJoinRequest]()) }
        else if path == "/notices" {
            payload = try encoded(NoticeResponse(items: value.notices, nextCursor: nil, unreadCount: value.notices.filter { $0.seenAt == nil }.count))
        } else if parts.count == 3, parts[0] == "by-number", parts[2] == "preview", let group = value.groups.first(where: { $0.groupNo == parts[1] }) {
            payload = try encoded(PreviewResponse(groupNo: group.groupNo, name: group.name, description: group.description, sport: group.sport, memberCount: group.memberCount ?? 0, joinPolicy: group.joinPolicy, availability: group.isActive ? "available" : "archived", groupType: group.groupType, groupId: group.id, status: group.status, memberLimit: group.memberLimit))
        } else if parts.count == 3, parts[0] == "by-number", parts[2] == "report", value.groups.contains(where: { $0.groupNo == parts[1] }) {
            payload = Data("{\"report\":null}".utf8)
        } else if let group = value.groups.first(where: { $0.id == parts[0] }) {
            let resource = parts.count > 1 ? parts[1] : ""
            if parts.count == 1 { payload = try encoded(group) }
            else if resource == "members" { payload = try page(value.members.filter { $0.groupId == group.id && $0.status == (query.first { $0.name == "status" }?.value ?? "active") }) }
            else if resource == "join-requests" { payload = try page(pendingRequests().filter { $0.groupId == group.id }) }
            else if resource == "games", parts.count == 3 { let snapshot = try game(parts[2], value: value); guard snapshot.groupId == group.id else { throw GroupCaptureFailure.unsupportedRead(path) }; payload = try encoded(snapshot) }
            else if resource == "activities", parts.count == 2 { payload = try page(value.activities.filter { $0.groupId == group.id }) }
            else if resource == "activities", parts.count == 3, let activity = value.activities.first(where: { $0.groupId == group.id && $0.id == parts[2] }) { payload = try encoded(activity) }
            else if resource == "activities", parts.count == 4, parts[3] == "lineup", parts[2] == value.activityLineup.activityId { payload = try encoded(value.activityLineup) }
            else if resource == "results", parts.count == 3, let result = value.results.first(where: { $0.groupId == group.id && $0.id == parts[2] }) { payload = try encoded(result) }
            else if resource == "results", parts.count == 2 {
                let format = query.first { $0.name == "format" }?.value
                let status = query.first { $0.name == "status" }?.value
                let member = query.first { $0.name == "memberId" }?.value
                payload = try page(value.results.filter { result in result.groupId == group.id && (format == nil || result.format.rawValue == format) && (status == nil || result.status == status) && (member == nil || result.participants.contains { $0.memberId == member }) })
            } else if resource == "rankings" { payload = try page(rankings(group.id, format: GroupFormat(rawValue: query.first { $0.name == "format" }?.value ?? "singles") ?? .singles)) }
            else if resource == "training-plans", parts.count == 2 { payload = try page(value.trainingPlans.filter { $0.groupId == group.id }) }
            else if resource == "training-plans", parts.count == 3, let plan = value.trainingPlans.first(where: { $0.groupId == group.id && $0.id == parts[2] }) { payload = try encoded(plan) }
            else if resource == "leave-notices" { payload = try page(value.leaveNotices.filter { $0.groupId == group.id }) }
            else if resource == "training-notices" { payload = try page(value.trainingNotices.filter { $0.groupId == group.id }) }
            else if resource == "stats", let stats = try makeCache().details[group.id]?.stats { payload = try encoded(stats) }
            else { throw GroupCaptureFailure.unsupportedRead(path) }
        } else { throw GroupCaptureFailure.unsupportedRead(path) }
        return try JSONDecoder().decode(T.self, from: payload)
    }
}
/// Process-local concurrent snapshot simulation. No capture write can reach storage or a remote server.
private nonisolated final class GroupCaptureConflictState: @unchecked Sendable {
    private let lock = NSLock()
    private var revealed = false
    func read() -> Bool { lock.lock(); defer { lock.unlock() }; return revealed }
    func reveal() { lock.lock(); defer { lock.unlock() }; revealed = true }
}
#endif
