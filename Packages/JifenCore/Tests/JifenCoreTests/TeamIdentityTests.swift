import Testing
@testable import ScoreCore

@Suite("Team identity chain")
struct TeamIdentityTests {
    @Test
    func legacyWinnerTokensMapToTeamID() {
        #expect(TeamID.fromLegacyWinnerToken("left") == .team0)
        #expect(TeamID.fromLegacyWinnerToken("red") == .team0)
        #expect(TeamID.fromLegacyWinnerToken("team_0") == .team0)
        #expect(TeamID.fromLegacyWinnerToken("right") == .team1)
        #expect(TeamID.fromLegacyWinnerToken("blue") == .team1)
        #expect(TeamID.fromLegacyWinnerToken("team_1") == .team1)
        #expect(TeamID.fromLegacyWinnerToken(nil) == nil)
    }

    @Test
    func team0ScreenSideBridgesSidesSwapped() {
        var layout = TeamScreenLayout()
        #expect(layout.sidesSwapped == false)
        #expect(layout.screenSide(of: .team0) == .left)
        #expect(layout.teamID(on: .right) == .team1)
        layout.exchangeSides()
        #expect(layout.team0ScreenSide == .right)
        #expect(layout.sidesSwapped == true)
        #expect(TeamScreenLayout(sidesSwapped: true).team0ScreenSide == .right)
    }

    @Test
    func screenTapMapsToIdentityEngineSide() {
        let normal = TeamScreenLayout()
        #expect(normal.engineSide(onScreen: .left) == .left)
        #expect(normal.engineSide(onScreen: .right) == .right)
        #expect(TeamScreenLayout.identityEngineSide(for: .team0) == .left)

        let swapped = TeamScreenLayout(sidesSwapped: true)
        #expect(swapped.teamID(on: .left) == .team1)
        #expect(swapped.engineSide(onScreen: .left) == .right)
        #expect(swapped.engineSide(onScreen: .right) == .left)
        #expect(swapped.geometricSide(for: .team0, sidesSwappedInEngine: true) == .left)
    }
}
