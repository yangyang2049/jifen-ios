import Combine
import Foundation
import PersistenceCore
import ScoreCore
import SessionCore

@MainActor
final class V2SessionRecordsViewModel: ObservableObject {
    struct Record: Identifiable {
        let entry: SessionArchiveEntry
        let scoreText: String?

        var id: UUID { entry.sessionId }
        var gameName: String { entry.gameType.v2DisplayName }
        var teamsText: String {
            let names = entry.participants.map(\.name).filter { !$0.isEmpty }
            return names.count >= 2 ? "\(names[0]) vs \(names[1])" : names.joined(separator: " vs ")
        }
        var timestamp: TimeInterval { TimeInterval(entry.updatedAtEpochMilliseconds) / 1_000 }
        var dateString: String {
            Self.dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }
        var timeText: String {
            Self.timeFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter
        }()
    }

    @Published private(set) var records: [Record] = []
    @Published private(set) var isLoading = false

    private let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let index = SessionArchiveIndex(fileURL: applicationSupport.appendingPathComponent("jifen-v2/session-index.json"))
        Task {
            let entries = (try? await index.entries()) ?? []
            let loaded = entries.map { entry in
                Record(entry: entry, scoreText: Self.scoreText(for: entry, applicationSupport: applicationSupport))
            }
            records = loaded
            isLoading = false
        }
    }

    func delete(_ record: Record) {
        let index = SessionArchiveIndex(fileURL: applicationSupport.appendingPathComponent("jifen-v2/session-index.json"))
        let snapshotURL = applicationSupport.appendingPathComponent("jifen-v2").appendingPathComponent(record.entry.snapshotPath)
        Task {
            try? FileManager.default.removeItem(at: snapshotURL)
            try? await index.remove(sessionId: record.entry.sessionId)
            records.removeAll { $0.id == record.id }
        }
    }

    func clearAll() {
        let allRecords = records
        records = []
        let index = SessionArchiveIndex(fileURL: applicationSupport.appendingPathComponent("jifen-v2/session-index.json"))
        Task {
            for record in allRecords {
                let snapshotURL = applicationSupport.appendingPathComponent("jifen-v2").appendingPathComponent(record.entry.snapshotPath)
                try? FileManager.default.removeItem(at: snapshotURL)
                try? await index.remove(sessionId: record.entry.sessionId)
            }
        }
    }

    private static func scoreText(for entry: SessionArchiveEntry, applicationSupport: URL) -> String? {
        let url = applicationSupport.appendingPathComponent("jifen-v2").appendingPathComponent(entry.snapshotPath)
        guard let data = try? Data(contentsOf: url) else { return nil }

        switch entry.gameType {
        case .basketball, .threeBasketball:
            guard let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: data) else { return nil }
            return "\(session.state.leftScore) : \(session.state.rightScore)"
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles, .volleyball, .airVolleyball, .beachVolleyball:
            guard let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data) else { return nil }
            return "\(session.state.leftPoints) : \(session.state.rightPoints)"
        default:
            return nil
        }
    }
}

private extension ScoreCore.GameType {
    var v2DisplayName: String {
        switch self {
        case .basketball: return "篮球"
        case .threeBasketball: return "篮球 3x3"
        case .pingpong, .pingpongDoubles: return "乒乓球"
        case .badminton, .badmintonDoubles: return "羽毛球"
        case .pickleball, .pickleballDoubles: return "匹克球"
        case .volleyball: return "排球"
        case .airVolleyball: return "气排球"
        case .beachVolleyball: return "沙滩排球"
        case .tennis, .tennisDoubles: return "网球"
        default: return rawValue
        }
    }
}
