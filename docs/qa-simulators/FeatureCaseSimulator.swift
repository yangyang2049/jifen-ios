import Foundation

struct CaseFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct FeatureCaseSimulator {
    private typealias AsyncCase = () async throws -> Void

    static func main() async {
        var passed = 0
        var failed = 0

        await run("Schedule: 普通流转 + 极端 limit") {
            resetSchedule()

            let now = Date()
            let pendingSoon = LocalBooking(
                id: "booking.pending.soon",
                sportType: .badminton,
                dateTime: now.addingTimeInterval(40 * 60),
                durationMinutes: 90,
                location: "A馆",
                reminderMinutes: [],
                status: .pending
            )
            let pendingLater = LocalBooking(
                id: "booking.pending.later",
                sportType: .basketball,
                dateTime: now.addingTimeInterval(140 * 60),
                durationMinutes: 60,
                location: "B馆",
                reminderMinutes: [],
                status: .pending
            )
            let completed = LocalBooking(
                id: "booking.completed",
                sportType: .tennis,
                dateTime: now.addingTimeInterval(-200 * 60),
                durationMinutes: 120,
                location: "C馆",
                reminderMinutes: [],
                status: .completed
            )

            try expect(LocalBookingManager.shared.upsertBooking(pendingLater), "upsert pendingLater should succeed")
            try expect(LocalBookingManager.shared.upsertBooking(completed), "upsert completed should succeed")
            try expect(LocalBookingManager.shared.upsertBooking(pendingSoon), "upsert pendingSoon should succeed")

            let pending = LocalBookingManager.shared.getBookings(status: .pending)
            try expectEqual(pending.count, 2, "pending count should be 2")

            let upcoming = LocalBookingManager.shared.getUpcomingPendingBookings(limit: 2)
            try expectEqual(upcoming.count, 2, "upcoming pending count should be 2")
            try expectEqual(upcoming.first?.id, pendingSoon.id, "upcoming should be sorted by nearest time asc")

            try expectEqual(LocalBookingManager.shared.getUpcomingPendingBookings(limit: 0).count, 0, "limit 0 should return empty")
            try expectEqual(LocalBookingManager.shared.getUpcomingPendingBookings(limit: -1).count, 0, "negative limit should return empty")

            try expect(LocalBookingManager.shared.cancelBooking(pendingSoon.id), "cancel should succeed")
            let cancelled = LocalBookingManager.shared.getBooking(by: pendingSoon.id)
            try expectEqual(cancelled?.status, .cancelled, "status should become cancelled")

            try expect(LocalBookingManager.shared.deleteBooking(completed.id), "delete should succeed")
            try expect(!LocalBookingManager.shared.deleteBooking(completed.id), "deleting same id again should fail")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("CommonNames: 单个/批量/上限/去重") {
            resetCommonNames()

            let added = try CommonNamesManager.shared.addName("  Team Alpha  ", type: .team)
            try expectEqual(added, "Team Alpha", "single add should trim spaces")

            do {
                _ = try CommonNamesManager.shared.addName("team alpha", type: .team)
                throw CaseFailure(description: "duplicate add should throw")
            } catch CommonNamesError.duplicateName {
                // expected
            }

            try CommonNamesManager.shared.updateName(oldName: "Team Alpha", newName: "Team Beta", type: .team)
            try expectEqual(CommonNamesManager.shared.getNames(type: .team).first, "Team Beta", "update should take effect")

            let batch = CommonNamesManager.shared.addNamesBatch(
                ["Real Madrid", "real madrid", "Alpha   Beta", "", " Alpha Beta "],
                type: .team
            )
            try expectEqual(batch.added, 2, "batch should add unique normalized names only")
            try expect(batch.skipped >= 2, "batch should skip duplicates/empty names")

            let many = (1...60).map { "P\($0)" }
            _ = CommonNamesManager.shared.addNamesBatch(many, type: .player)
            let players = CommonNamesManager.shared.getNames(type: .player)
            try expectEqual(players.count, 50, "player names should cap at 50")

            await CommonNamesManager.shared.recordUsage("P10", .player)
            try expectEqual(CommonNamesManager.shared.getNames(type: .player).first, "P10", "record usage should move name to top")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("BatchParser: 空格名与混合分隔符") {
            let parsed1 = CommonNamesBatchParser.parse("Real Madrid\nFC Barcelona")
            try expectEqual(parsed1, ["Real Madrid", "FC Barcelona"], "names with spaces should stay intact")

            let parsed2 = CommonNamesBatchParser.parse("A,B，C；D、E")
            try expectEqual(parsed2, ["A", "B", "C", "D", "E"], "mixed separators should split correctly")

            let parsed3 = CommonNamesBatchParser.parse(" A  \n a \nB ")
            try expectEqual(parsed3, ["A", "B"], "parser should normalize spaces and dedupe by case-insensitive key")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("Scoreboard: 草稿覆盖 + 上限 + 排序") {
            resetScoreboard()

            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                makeScoreboardRecord(id: "finished.1", offsetMinutes: -10, status: .finished)
            )
            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                makeScoreboardRecord(id: "draft.1", offsetMinutes: -5, status: .draft)
            )
            try expectEqual(ScoreboardRecordManager.shared.getUnfinishedRecordId(), "draft.1", "unfinished id should be draft.1")

            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                makeScoreboardRecord(id: "draft.2", offsetMinutes: -3, status: .draft)
            )
            try expectEqual(ScoreboardRecordManager.shared.getUnfinishedRecordId(), "draft.2", "new draft should replace previous draft id")
            try expect(ScoreboardRecordManager.shared.getRecordById("draft.1") == nil, "previous draft should be removed")

            try expect(ScoreboardRecordManager.shared.discardUnfinishedRecord(), "discard unfinished should succeed")
            try expect(ScoreboardRecordManager.shared.getUnfinishedRecordId() == nil, "unfinished id should be cleared")

            for index in 0..<1005 {
                try ScoreboardRecordManager.shared.saveScoreboardRecord(
                    makeScoreboardRecord(
                        id: "bulk.\(index)",
                        offsetMinutes: -index,
                        status: .finished
                    )
                )
            }

            let all = ScoreboardRecordManager.shared.loadAllRecords()
            try expectEqual(all.count, 1000, "records should cap at 1000")
            if all.count >= 2 {
                try expect(all[0].startTime >= all[1].startTime, "records should stay sorted by startTime desc")
            }
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("Timer: 去重更新 + 上限 + 删除返回值") {
            resetTimer()

            for index in 0..<502 {
                let record = GameRecordSummary(
                    id: "timer.\(index)",
                    gameType: .stopwatch,
                    timestamp: Date().addingTimeInterval(TimeInterval(index)).timeIntervalSince1970,
                    duration: TimeInterval(index)
                )
                TimerRecordManager.shared.addRecord(record)
            }
            try expectEqual(TimerRecordManager.shared.getRecords().count, 500, "timer records should cap at 500")

            let updated = GameRecordSummary(
                id: "timer.100",
                gameType: .stopwatch,
                timestamp: Date().addingTimeInterval(9_999).timeIntervalSince1970,
                duration: 9_999
            )
            TimerRecordManager.shared.addRecord(updated)
            try expectEqual(TimerRecordManager.shared.getRecords().first?.id, "timer.100", "duplicate id should move to top")

            try expect(!TimerRecordManager.shared.deleteRecord("not-found"), "delete non-existent timer record should return false")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("Tools(积分表): 排名与持久化") {
            resetPointsTable()

            let record = PointsTableRecord(
                id: "pt.1",
                name: "周赛",
                teams: [
                    PointsTableTeam(name: "B队", played: 3, win: 2, draw: 0, loss: 1),
                    PointsTableTeam(name: "A队", played: 3, win: 2, draw: 0, loss: 1),
                    PointsTableTeam(name: "C队", played: 3, win: 1, draw: 2, loss: 0)
                ]
            )
            let standings = record.standings()
            try expectEqual(standings.count, 3, "standings count should be 3")
            try expectEqual(standings[0].team.name, "A队", "same points should sort by name asc")
            try expectEqual(standings[1].team.name, "B队", "same points secondary order should follow name asc")

            PointsTableStorage.save([record])
            let loaded = PointsTableStorage.load()
            try expectEqual(loaded.count, 1, "storage should load saved records")
            try expectEqual(loaded.first?.id, "pt.1", "loaded record id should match")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        await run("Settings清理流程: 记录/预约/常用名称清空") {
            resetAll()

            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                makeScoreboardRecord(id: "clear.score", offsetMinutes: -2, status: .finished)
            )
            TimerRecordManager.shared.addRecord(
                GameRecordSummary(id: "clear.timer", gameType: .counter, timestamp: Date().timeIntervalSince1970, duration: 3)
            )
            _ = try CommonNamesManager.shared.addName("队伍1", type: .team)
            _ = LocalBookingManager.shared.upsertBooking(
                LocalBooking(
                    id: "clear.booking",
                    sportType: .football,
                    dateTime: Date().addingTimeInterval(3600),
                    durationMinutes: 60,
                    location: "D馆",
                    reminderMinutes: [],
                    status: .pending
                )
            )

            ScoreboardRecordManager.shared.clearAllRecords()
            _ = TimerRecordManager.shared.clearAllRecords()
            _ = LocalBookingManager.shared.clearAllBookings()
            CommonNamesManager.shared.clearNames(type: .team)
            CommonNamesManager.shared.clearNames(type: .player)

            try expectEqual(ScoreboardRecordManager.shared.loadAllRecords().count, 0, "scoreboard records should be cleared")
            try expectEqual(TimerRecordManager.shared.getRecords().count, 0, "timer records should be cleared")
            try expectEqual(LocalBookingManager.shared.getAllBookings().count, 0, "bookings should be cleared")
            try expectEqual(CommonNamesManager.shared.getNames(type: .team).count, 0, "team names should be cleared")
            try expectEqual(CommonNamesManager.shared.getNames(type: .player).count, 0, "player names should be cleared")
        } onPassed: {
            passed += 1
        } onFailed: {
            failed += 1
        }

        print("=== Feature Case Simulation Summary ===")
        print("Passed: \(passed)")
        print("Failed: \(failed)")
        exit(failed == 0 ? 0 : 1)
    }

    private static func run(
        _ name: String,
        _ body: AsyncCase,
        onPassed: () -> Void,
        onFailed: () -> Void
    ) async {
        do {
            try await body()
            print("PASS | \(name)")
            onPassed()
        } catch {
            print("FAIL | \(name) | \(error)")
            onFailed()
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CaseFailure(description: message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        if actual != expected {
            throw CaseFailure(description: "\(message). actual=\(actual), expected=\(expected)")
        }
    }

    private static func resetAll() {
        resetSchedule()
        resetCommonNames()
        resetScoreboard()
        resetTimer()
        resetPointsTable()
    }

    private static func resetSchedule() {
        _ = LocalBookingManager.shared.clearAllBookings()
    }

    private static func resetCommonNames() {
        CommonNamesManager.shared.clearNames(type: .team)
        CommonNamesManager.shared.clearNames(type: .player)
    }

    private static func resetScoreboard() {
        ScoreboardRecordManager.shared.clearAllRecords()
    }

    private static func resetTimer() {
        _ = TimerRecordManager.shared.clearAllRecords()
    }

    private static func resetPointsTable() {
        PointsTableStorage.save([])
    }

    private static func makeScoreboardRecord(id: String, offsetMinutes: Int, status: ScoreboardRecordStatus) -> ScoreboardRecord {
        let start = Date().addingTimeInterval(TimeInterval(offsetMinutes * 60))
        return ScoreboardRecord(
            id: id,
            gameType: .badminton,
            startTime: start,
            endTime: start.addingTimeInterval(20 * 60),
            duration: 20 * 60,
            team1Name: "左队",
            team2Name: "右队",
            team1FinalScore: 21,
            team2FinalScore: 18,
            winner: "left",
            actions: ["left+1", "right+1"],
            totalScoreChanges: 2,
            status: status
        )
    }
}
