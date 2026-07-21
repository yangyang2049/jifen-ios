import SwiftUI
import UIKit

enum RandomTeamAssignment {
    static func teamCountOptions(for playerCount: Int) -> [Int] {
        switch playerCount {
        case 6: return [2, 3]
        case 8: return [2, 4]
        case 9: return [3, 2]
        case 10: return [2, 3]
        default: return [2]
        }
    }

    static func splitLabel(playerCount: Int, teamCount: Int) -> String {
        balancedTeamSizes(playerCount: playerCount, teamCount: teamCount)
            .map(String.init)
            .joined(separator: "+")
    }

    static func balancedTeamSizes(playerCount: Int, teamCount: Int) -> [Int] {
        guard playerCount > 0, teamCount > 0 else { return [] }
        let base = playerCount / teamCount
        let remainder = playerCount % teamCount
        return (0..<teamCount).map { base + ($0 < remainder ? 1 : 0) }
    }

    static func makeAssignments(playerCount: Int, teamCount: Int) -> [Int] {
        var pool: [Int] = []
        for (team, size) in balancedTeamSizes(playerCount: playerCount, teamCount: teamCount).enumerated() {
            pool.append(contentsOf: Array(repeating: team, count: size))
        }
        pool.shuffle()
        return pool
    }
}

struct RandomTeamView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var playerCount = 0
    @State private var teamCount = 2
    @State private var touchedIndices: Set<Int> = []
    @State private var assignments: [Int?] = []
    @State private var flashColors: [Int] = []
    @State private var isAnimating = false
    @State private var showTeamPicker = false
    @State private var pendingPlayerCount = 0
    @State private var animationTask: Task<Void, Never>?

    private let resultColors: [Color] = [
        Color(red: 0.90, green: 0.22, blue: 0.21),
        Color(red: 0.12, green: 0.53, blue: 0.90),
        Color(red: 0.30, green: 0.69, blue: 0.31),
        Color(red: 0.98, green: 0.66, blue: 0.15)
    ]
    private let animationColors: [Color] = [
        Color(hex: "475569"), Color(hex: "4CAF50"), Color(hex: "06B6D4"),
        Color(hex: "10B981"), Color(hex: "8B5CF6"), Color(hex: "EC4899")
    ]

    private var isComplete: Bool {
        !assignments.isEmpty && assignments.allSatisfy { $0 != nil }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                if playerCount == 0 {
                    playerSelection(isPad: UIDevice.current.userInterfaceIdiom == .pad)
                } else {
                    groupingContent(size: proxy.size, isPad: UIDevice.current.userInterfaceIdiom == .pad)
                }
            }
        }
        .navigationTitle(NSLocalizedString("random_team_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            NSLocalizedString("random_team_select_team_count", value: "选择分组数量", comment: ""),
            isPresented: $showTeamPicker,
            titleVisibility: .visible
        ) {
            ForEach(RandomTeamAssignment.teamCountOptions(for: pendingPlayerCount), id: \.self) { option in
                Button(teamOptionLabel(players: pendingPlayerCount, teams: option)) {
                    beginSetup(players: pendingPlayerCount, teams: option)
                }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func playerSelection(isPad: Bool) -> some View {
        VStack(spacing: isPad ? 20 : 14) {
            ForEach(Array([[4, 5], [6, 7], [8, 9], [10]].enumerated()), id: \.offset) { _, row in
                HStack(spacing: isPad ? 20 : 14) {
                    ForEach(row, id: \.self) { count in
                        Button {
                            selectPlayerCount(count)
                        } label: {
                            Text(String(format: NSLocalizedString("players_count_format", comment: ""), count))
                                .font(.system(size: isPad ? 21 : 18, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: isPad ? 64 : 56)
                                .background(Theme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: isPad ? 14 : 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("random_team_players_\(count)")
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity).frame(height: isPad ? 64 : 56)
                    }
                }
            }
        }
        .frame(maxWidth: isPad ? 520 : 380)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupingContent(size: CGSize, isPad: Bool) -> some View {
        let secondaryTitle = NSLocalizedString("random_team_reselect", value: "重新选人数", comment: "")
        let primaryTitle = isComplete
            ? NSLocalizedString("try_again", comment: "")
            : NSLocalizedString("simulate", comment: "")

        return groupingLayout(
            size: size,
            isPad: isPad,
            secondaryTitle: secondaryTitle,
            primaryTitle: primaryTitle
        )
    }

    private func groupingLayout(
        size: CGSize,
        isPad: Bool,
        secondaryTitle: String,
        primaryTitle: String
    ) -> some View {
        VStack(spacing: isPad ? 22 : 14) {
            HStack(spacing: 10) {
                actionButton(
                    secondaryTitle,
                    primary: false,
                    enabled: !isAnimating,
                    action: resetSelection
                )
                actionButton(
                    primaryTitle,
                    primary: isComplete,
                    enabled: !isAnimating,
                    action: performPrimaryAction
                )
            }
            .frame(maxWidth: isPad ? 860 : 560)

            Text(statusText)
                .font(.system(size: isPad ? 20 : 17, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 26)

            randomGrid(size: size, isPad: isPad)
        }
        .padding(.horizontal, isPad ? 48 : 16)
        .padding(.top, isPad ? 18 : 10)
        .padding(.bottom, isPad ? 40 : 20)
        .accessibilityIdentifier("random_team_multitouch_surface")
    }

    private func performPrimaryAction() {
        if isComplete {
            startAnimation()
        } else {
            simulate()
        }
    }

    private func actionButton(_ title: String, primary: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: primary ? .semibold : .regular))
                .foregroundStyle(primary ? Color.white : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(primary ? Theme.primary : Theme.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func randomGrid(size: CGSize, isPad: Bool) -> some View {
        let gap: CGFloat = isPad ? 24 : 16
        let rows = max(1, Int(ceil(Double(playerCount) / 2.0)))
        let maxWidth: CGFloat = isPad ? 900 : 500
        let maxHeight: CGFloat = isPad ? 600 : 520

        return GeometryReader { geometry in
            let availableWidth = min(geometry.size.width, maxWidth)
            let availableHeight = min(geometry.size.height, maxHeight)
            let rowHeight = max(isPad ? 104 : 68, min(isPad ? 180 : 132, (availableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            let gridHeight = rowHeight * CGFloat(rows) + gap * CGFloat(rows - 1)

            ZStack {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible())], spacing: gap) {
                    ForEach(0..<playerCount, id: \.self) { index in
                        playerCard(index: index, isPad: isPad)
                            .frame(height: rowHeight)
                    }
                }
                .frame(width: availableWidth, height: gridHeight)

                if !isAnimating && !isComplete {
                    RandomTeamMultiTouchLayer(
                        playerCount: playerCount,
                        gap: gap,
                        onActiveIndicesChanged: handleActiveTouches
                    )
                    .frame(width: availableWidth, height: gridHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func playerCard(index: Int, isPad: Bool) -> some View {
        let team = assignments.indices.contains(index) ? assignments[index] : nil
        let background: Color = {
            if let team { return resultColors[team % resultColors.count] }
            if isAnimating, flashColors.indices.contains(index) { return animationColors[flashColors[index] % animationColors.count] }
            if touchedIndices.contains(index) { return Theme.primary }
            return Theme.cardBackground
        }()

        return ZStack(alignment: .bottomTrailing) {
            Text("\(index + 1)")
                .font(.system(size: isPad ? 72 : 48, weight: .bold))
                .foregroundStyle(team == nil ? Theme.textSecondary.opacity(0.5) : Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let team {
                Text(teamLetter(team))
                    .font(.system(size: isPad ? 20 : 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(10)
            }
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: isPad ? 24 : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPad ? 24 : 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: isPad ? 3 : 2)
        }
        .animation(.easeInOut(duration: 0.08), value: background)
    }

    private func teamLetter(_ team: Int) -> String {
        guard let scalar = UnicodeScalar(65 + team) else { return "?" }
        return String(Character(scalar))
    }

    private var statusText: String {
        if isAnimating { return NSLocalizedString("grouping_in_progress", comment: "") }
        if isComplete { return NSLocalizedString("grouping_complete", comment: "") }
        return String(
            format: NSLocalizedString("place_fingers_on_blocks", comment: ""),
            touchedIndices.count,
            playerCount
        )
    }

    private func selectPlayerCount(_ count: Int) {
        let options = RandomTeamAssignment.teamCountOptions(for: count)
        if options.count == 1 {
            beginSetup(players: count, teams: options[0])
        } else {
            pendingPlayerCount = count
            showTeamPicker = true
        }
    }

    private func beginSetup(players: Int, teams: Int) {
        playerCount = players
        teamCount = teams
        touchedIndices = []
        assignments = Array(repeating: nil, count: players)
        flashColors = Array(repeating: 0, count: players)
        isAnimating = false
    }

    private func teamOptionLabel(players: Int, teams: Int) -> String {
        let teamLabel = String(format: NSLocalizedString("random_team_team_count_format", value: "%d队", comment: ""), teams)
        return "\(teamLabel) · \(RandomTeamAssignment.splitLabel(playerCount: players, teamCount: teams))"
    }

    private func handleActiveTouches(_ indices: Set<Int>) {
        guard !isAnimating, !isComplete else { return }
        touchedIndices = indices
        if indices.count == playerCount {
            startAnimation()
        }
    }

    private func simulate() {
        guard !isAnimating else { return }
        touchedIndices = Set(0..<playerCount)
        startAnimation()
    }

    private func startAnimation() {
        guard playerCount > 0, !isAnimating else { return }
        animationTask?.cancel()
        assignments = Array(repeating: nil, count: playerCount)
        isAnimating = true
        VibrationManager.shared.vibrateMedium()
        animationTask = Task { @MainActor in
            for _ in 0..<16 {
                guard !Task.isCancelled else { return }
                flashColors = (0..<playerCount).map { _ in Int.random(in: 0..<animationColors.count) }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            let result = RandomTeamAssignment.makeAssignments(playerCount: playerCount, teamCount: teamCount)
            assignments = result.map(Optional.some)
            touchedIndices = []
            isAnimating = false
            VibrationManager.shared.vibrateHeavy()
        }
    }

    private func resetSelection() {
        animationTask?.cancel()
        animationTask = nil
        playerCount = 0
        teamCount = 2
        assignments = []
        touchedIndices = []
        flashColors = []
        isAnimating = false
    }
}

private struct RandomTeamMultiTouchLayer: UIViewRepresentable {
    let playerCount: Int
    let gap: CGFloat
    let onActiveIndicesChanged: (Set<Int>) -> Void

    func makeUIView(context: Context) -> MultiTouchCaptureUIView {
        let view = MultiTouchCaptureUIView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.playerCount = playerCount
        view.gap = gap
        view.onActiveIndicesChanged = onActiveIndicesChanged
        return view
    }

    func updateUIView(_ uiView: MultiTouchCaptureUIView, context: Context) {
        uiView.playerCount = playerCount
        uiView.gap = gap
        uiView.onActiveIndicesChanged = onActiveIndicesChanged
    }
}

private final class MultiTouchCaptureUIView: UIView {
    var playerCount = 0
    var gap: CGFloat = 16
    var onActiveIndicesChanged: ((Set<Int>) -> Void)?
    private var touchIndices: [ObjectIdentifier: Int] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches: touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches: touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        remove(touches: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        remove(touches: touches)
    }

    private func update(touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if let index = index(at: touch.location(in: self)) {
                touchIndices[key] = index
            } else {
                touchIndices.removeValue(forKey: key)
            }
        }
        publish()
    }

    private func remove(touches: Set<UITouch>) {
        touches.forEach { touchIndices.removeValue(forKey: ObjectIdentifier($0)) }
        publish()
    }

    private func publish() {
        onActiveIndicesChanged?(Set(touchIndices.values))
    }

    private func index(at point: CGPoint) -> Int? {
        guard playerCount > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let columns = 2
        let rows = Int(ceil(Double(playerCount) / Double(columns)))
        let cellWidth = (bounds.width - gap) / 2
        let cellHeight = (bounds.height - gap * CGFloat(max(0, rows - 1))) / CGFloat(rows)
        let column = Int(point.x / (cellWidth + gap))
        let row = Int(point.y / (cellHeight + gap))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        let localX = point.x - CGFloat(column) * (cellWidth + gap)
        let localY = point.y - CGFloat(row) * (cellHeight + gap)
        guard localX >= 0, localX <= cellWidth, localY >= 0, localY <= cellHeight else { return nil }
        let index = row * columns + column
        return index < playerCount ? index : nil
    }
}

#Preview {
    NavigationStack { RandomTeamView() }
}
