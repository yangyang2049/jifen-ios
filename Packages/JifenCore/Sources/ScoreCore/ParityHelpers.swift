import Foundation

// MARK: - UNO round total (Android MultiScoreViewModel.addUnoRoundScore)

public enum UnoRoundScore {
    public static func total(number: Int, action20: Int, wild40: Int, wild50: Int) -> Int {
        max(0, number) + max(0, action20) * 20 + max(0, wild40) * 40 + max(0, wild50) * 50
    }
}

// MARK: - Doudizhu settle (1 winner → +2x/−x/−x; 2 winners → +x/+x/−2x)

public enum DoudizhuSettlement {
    /// Returns per-player deltas for 3 players, or nil if winner count is not 1 or 2.
    public static func deltas(winners: [Bool], baseScore: Int, multiplierPower: Int) -> [Int]? {
        guard winners.count == 3 else { return nil }
        let winnerCount = winners.filter(\.self).count
        guard winnerCount == 1 || winnerCount == 2 else { return nil }
        let unit = max(0, baseScore) * (1 << max(0, multiplierPower))
        let winnerDelta = winnerCount == 1 ? unit * 2 : unit
        let loserDelta = winnerCount == 1 ? -unit : -unit * 2
        return winners.map { $0 ? winnerDelta : loserDelta }
    }
}

// MARK: - Archery next set first shooter (Android/HOS nextStartingShooter)

public enum ArcheryShooterRules {
    /// Next set first shooter = side with fewer set points; tie keeps opening shooter.
    public static func nextStartingIsLeft(
        leftSetPoints: Int,
        rightSetPoints: Int,
        openingIsLeft: Bool
    ) -> Bool {
        if leftSetPoints < rightSetPoints { return true }
        if rightSetPoints < leftSetPoints { return false }
        return openingIsLeft
    }
}
