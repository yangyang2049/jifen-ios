import XCTest
@testable import jifen

final class RandomTeamAssignmentTests: XCTestCase {
    func testTeamCountOptionsMatchCrossPlatformBehavior() {
        XCTAssertEqual(RandomTeamAssignment.teamCountOptions(for: 4), [2])
        XCTAssertEqual(RandomTeamAssignment.teamCountOptions(for: 6), [2, 3])
        XCTAssertEqual(RandomTeamAssignment.teamCountOptions(for: 8), [2, 4])
        XCTAssertEqual(RandomTeamAssignment.teamCountOptions(for: 9), [3, 2])
        XCTAssertEqual(RandomTeamAssignment.teamCountOptions(for: 10), [2, 3])
    }

    func testAssignmentsAreBalancedAndComplete() {
        for players in 4...10 {
            for teams in RandomTeamAssignment.teamCountOptions(for: players) {
                let result = RandomTeamAssignment.makeAssignments(playerCount: players, teamCount: teams)
                XCTAssertEqual(result.count, players)
                XCTAssertTrue(result.allSatisfy { 0..<(teams) ~= $0 })
                let counts = (0..<teams).map { team in result.filter { $0 == team }.count }
                XCTAssertLessThanOrEqual((counts.max() ?? 0) - (counts.min() ?? 0), 1)
            }
        }
    }
}
