import Foundation

// MARK: - UNO round total (Android MultiScoreViewModel.addUnoRoundScore)

public enum UnoRoundScore {
    public static func total(number: Int, action20: Int, wild40: Int, wild50: Int) -> Int {
        max(0, number) + max(0, action20) * 20 + max(0, wild40) * 40 + max(0, wild50) * 50
    }
}

// MARK: - Doudizhu settle (one winner or one loser, zero-sum for 3/4 players)

public enum DoudizhuSettlement {
    /// Returns zero-sum deltas for 3/4 players. A valid round has either one
    /// winner (landlord wins) or one loser (the farmers win).
    public static func deltas(winners: [Bool], baseScore: Int, multiplierPower: Int) -> [Int]? {
        guard (3 ... 4).contains(winners.count) else { return nil }
        let winnerCount = winners.filter(\.self).count
        guard winnerCount == 1 || winnerCount == winners.count - 1 else { return nil }
        let unit = max(0, baseScore) * (1 << max(0, multiplierPower))
        let opposingCount = winners.count - 1
        let winnerDelta = winnerCount == 1 ? unit * opposingCount : unit
        let loserDelta = winnerCount == 1 ? -unit : -unit * opposingCount
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
