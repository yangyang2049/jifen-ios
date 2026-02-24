
import SwiftUI

struct ScoreboardRecordDetailPage: View {
    let recordId: String
    @Environment(\.dismiss) private var dismiss

    @State private var record: ScoreboardRecord?
    @State private var isDeleting = false
    @State private var showDeleteSuccessToast = false
    @State private var showingDeleteConfirm = false
    @State private var shareFileURL: URL?
    @State private var showingShareSheet = false
    @State private var isPreparingShare = false
    @State private var sharePrepareStartTime: Date?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                if isDeleting {
                    deletingView
                } else if let record = record {
                    ScrollView {
                        VStack(spacing: 16) {
                            gameInfoView(record: record)
                            actionsListView(record: record)
                        }
                        .padding()
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    recordNotFoundView
                }
                if isPreparingShare {
                    preparingShareOverlay
                }
                if showDeleteSuccessToast {
                    ToastView(message: NSLocalizedString("record_deleted", value: "已删除", comment: ""))
                        .transition(.opacity)
                }
            }
        }
        .navigationTitle(NSLocalizedString("match_detail", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menu
            }
        }
        .onAppear(perform: loadRecord)
        .alert(isPresented: $showingDeleteConfirm) {
            Alert(
                title: Text(LocalizedStringKey("confirm_delete")),
                message: Text(LocalizedStringKey("confirm_delete_record_message")),
                primaryButton: .destructive(Text(LocalizedStringKey("delete")), action: deleteRecord),
                secondaryButton: .cancel(Text(LocalizedStringKey("cancel")))
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareFileURL {
                ShareActivityView(activityItems: [url], onDismiss: {
                    try? FileManager.default.removeItem(at: url)
                    shareFileURL = nil
                    showingShareSheet = false
                })
            }
        }
    }
    
    private var menu: some View {
        Menu {
            if record != nil {
                Button(action: handleShare) {
                    Label(NSLocalizedString("share", comment: ""), systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive, action: {
                showingDeleteConfirm = true
            }) {
                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var deletingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.textPrimary)
            Text(NSLocalizedString("deleting_record", value: "正在删除记录...", comment: ""))
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recordNotFoundView: some View {
        VStack(spacing: 16) {
            EmptyStateCourtIcon(size: 48)
            Text("record_not_found")
                .font(.headline)
            Text("record_may_deleted")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preparingShareOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text(NSLocalizedString("share_preparing", comment: "Preparing sharing..."))
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
    }
    
    private func gameInfoView(record: ScoreboardRecord) -> some View {
        VStack(spacing: 16) {
            // Game Type
            HStack {
                Text(record.gameType.icon)
                    .font(.system(size: 36))
                Text(record.gameType.displayName)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            // Scores
            HStack(alignment: .center, spacing: 16) {
                VStack {
                    Text(record.team1Name)
                        .font(.headline)
                    Text("\(record.team1FinalScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(record.winner == "left" ? .green : Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                
                Text("-")
                    .font(.largeTitle)
                
                VStack {
                    Text(record.team2Name)
                        .font(.headline)
                    Text("\(record.team2FinalScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(record.winner == "right" ? .green : Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Winner
            if let winner = record.winner {
                let winnerName = winner == "left" ? record.team1Name : record.team2Name
                Text(String(format: NSLocalizedString("game_winner_format", comment: ""), winnerName))
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            // Details
            VStack(spacing: 8) {
                detailRow(label: "date", value: formatDate(record.startTime))
                detailRow(label: "record_start_time", value: formatTime(record.startTime))
                if let endTime = record.endTime {
                    detailRow(label: "record_end_time", value: formatTime(endTime))
                }
                if let duration = record.duration {
                    detailRow(label: "record_duration", value: formatScoreboardDuration(duration))
                }
            }
            .padding()
            .background(Theme.surface)
            .cornerRadius(12)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    private func actionsListView(record: ScoreboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("match_record")
                .font(.headline)
                .padding(.horizontal)

            if record.actions.isEmpty {
                VStack(spacing: 8) {
                    EmptyStateCourtIcon(size: 36)
                    Text("no_actions_recorded")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                // Create a timeline view of scoring actions
                scoringTimelineView(record: record)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func scoringTimelineView(record: ScoreboardRecord) -> some View {
        // Create array of scoring events first
        let scoringEvents = createScoringEvents(from: record)

        return VStack(spacing: 8) {
            ForEach(scoringEvents.indices, id: \.self) { index in
                let event = scoringEvents[index]
                scoringActionRow(
                    timestamp: formatElapsedTime(event.timestamp, from: record.startTime),
                    action: event.action,
                    score: event.score,
                    index: index
                )
            }
        }
    }

    private func createScoringEvents(from record: ScoreboardRecord) -> [(timestamp: Date, action: String, score: String)] {
        var events: [(timestamp: Date, action: String, score: String)] = []
        var leftSets = 0
        var rightSets = 0
        var currentSetLeftScore = 0
        var currentSetRightScore = 0

        // Add game start event
        events.append((
            timestamp: record.startTime,
            action: NSLocalizedString("game_started", comment: ""),
            score: "0-0"
        ))

        for action in record.actions {
            if action.contains("left +") {
                currentSetLeftScore += 1
                let actionText = getScoringActionText(for: record.gameType, teamName: record.team1Name, points: 1)
                let displayScore = formatScore(leftScore: currentSetLeftScore, rightScore: currentSetRightScore, gameType: record.gameType)
                events.append((
                    timestamp: record.startTime,
                    action: actionText,
                    score: displayScore
                ))

                // Check for set completion
                if shouldAddSetEndEvent(leftScore: currentSetLeftScore, rightScore: currentSetRightScore) {
                    if currentSetLeftScore > currentSetRightScore {
                        leftSets += 1
                    }
                    let setNumber = leftSets + rightSets
                    events.append((
                        timestamp: record.startTime,
                        action: getSetEndText(setNumber: setNumber, winner: currentSetLeftScore > currentSetRightScore ? record.team1Name : record.team2Name),
                        score: "\(leftSets)-\(rightSets)"
                    ))
                    // Reset for next set
                    currentSetLeftScore = 0
                    currentSetRightScore = 0
                }

            } else if action.contains("right +") {
                currentSetRightScore += 1
                let actionText = getScoringActionText(for: record.gameType, teamName: record.team2Name, points: 1)
                let displayScore = formatScore(leftScore: currentSetLeftScore, rightScore: currentSetRightScore, gameType: record.gameType)
                events.append((
                    timestamp: record.startTime,
                    action: actionText,
                    score: displayScore
                ))

                // Check for set completion
                if shouldAddSetEndEvent(leftScore: currentSetLeftScore, rightScore: currentSetRightScore) {
                    if currentSetRightScore > currentSetLeftScore {
                        rightSets += 1
                    }
                    let setNumber = leftSets + rightSets
                    events.append((
                        timestamp: record.startTime,
                        action: getSetEndText(setNumber: setNumber, winner: currentSetRightScore > currentSetLeftScore ? record.team2Name : record.team1Name),
                        score: "\(leftSets)-\(rightSets)"
                    ))
                    // Reset for next set
                    currentSetLeftScore = 0
                    currentSetRightScore = 0
                }
            }
        }

        // Add game end event if the game finished
        if record.endTime != nil {
            events.append((
                timestamp: record.endTime!,
                action: NSLocalizedString("game_ended", comment: ""),
                score: "\(record.team1FinalScore)-\(record.team2FinalScore)"
            ))
        }

        return events
    }

    private func getScoringActionText(for gameType: GameType, teamName: String, points: Int) -> String {
        switch gameType {
        case .pingpong, .badminton, .tennis:
            return "\(teamName) 得分"
        case .basketball:
            return "\(teamName) +\(points)"
        case .football:
            return "\(teamName) 进球"
        case .volleyball:
            return "\(teamName) +\(points)"
        default:
            return "\(teamName) +\(points)"
        }
    }

    private func shouldAddSetEndEvent(leftScore: Int, rightScore: Int) -> Bool {
        // More accurate badminton set end detection
        // A set ends when:
        // 1. One player reaches 21 points (or 30 in deciding set)
        // 2. Has at least 2 points advantage over opponent
        // OR
        // 1. One player reaches 30 points in deciding set
        // 2. Has at least 1 point advantage

        let maxScore = max(leftScore, rightScore)
        let minScore = min(leftScore, rightScore)
        let scoreDiff = maxScore - minScore

        // For deciding set (3rd set in best of 3), max is 30 points
        if maxScore >= 30 {
            return scoreDiff >= 1
        }

        // For normal sets, need 21+ points and 2+ point advantage
        if maxScore >= 21 {
            return scoreDiff >= 2
        }

        return false
    }

    private func getSetEndText(setNumber: Int, winner: String) -> String {
        return String(format: NSLocalizedString("set_end_winner_format", comment: ""), setNumber, winner)
    }

    private func scoringActionRow(timestamp: String, action: String, score: String, index: Int) -> some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(timestamp)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 50, alignment: .leading)

            // Action
            Text(action)
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            // Score
            Text(score)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(Theme.primary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(index % 2 == 0 ? Theme.backgroundColor.opacity(0.3) : Color.clear)
        .cornerRadius(6)
    }

    private func formatElapsedTime(_ eventTime: Date, from startTime: Date) -> String {
        let elapsed = eventTime.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)

        if let day = components.day, day > 0 {
            return "\(day)d ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m ago"
        } else {
            return "now"
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
    
    private func loadRecord() {
        self.record = ScoreboardRecordManager.shared.getRecordById(recordId)
    }
    
    private func deleteRecord() {
        showingDeleteConfirm = false
        isDeleting = true
        DispatchQueue.main.async {
            let success = ScoreboardRecordManager.shared.deleteRecord(recordId)
            isDeleting = false
            if success {
                ScoreboardRecordsViewModel.shared.refreshRecords()
                showDeleteSuccessToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            }
        }
    }
    
    private static let sharePreparingMinDuration: TimeInterval = 2.0

    private func handleShare() {
        guard let record = record else { return }
        guard #available(iOS 16.0, *) else { return }
        isPreparingShare = true
        sharePrepareStartTime = Date()
        DispatchQueue.main.async {
            let card = RecordDetailShareCardView(record: record)
                .frame(width: 600, height: 640)
            let renderer = ImageRenderer(content: card)
            renderer.scale = UIScreen.main.scale
            guard let image = renderer.uiImage,
                  image.size.width > 0, image.size.height > 0,
                  let data = image.pngData() else {
                isPreparingShare = false
                sharePrepareStartTime = nil
                return
            }
            let fileName = "share_record_\(record.id).png"
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            let startedAt = sharePrepareStartTime ?? Date()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try data.write(to: tmpURL)
                } catch {
                    DispatchQueue.main.async {
                        isPreparingShare = false
                        sharePrepareStartTime = nil
                    }
                    return
                }
                DispatchQueue.main.async {
                    shareFileURL = tmpURL
                    sharePrepareStartTime = nil
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let delay = max(0.25, Self.sharePreparingMinDuration - elapsed)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        isPreparingShare = false
                        showingShareSheet = true
                    }
                }
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM-dd"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatScore(leftScore: Int, rightScore: Int, gameType: GameType) -> String {
        switch gameType {
        case .tennis:
            return formatTennisScore(leftScore: leftScore, rightScore: rightScore)
        default:
            // For other sports, just display regular numbers
            return "\(leftScore)-\(rightScore)"
        }
    }

    private func formatTennisScore(leftScore: Int, rightScore: Int) -> String {
        func tennisScoreDisplay(_ score: Int) -> String {
            switch score {
            case 0:
                return "0"
            case 1:
                return "15"
            case 2:
                return "30"
            default:
                return "40"
            }
        }

        return "\(tennisScoreDisplay(leftScore))-\(tennisScoreDisplay(rightScore))"
    }
}

// MARK: - Navigation Bar Back Button Handling
struct DetailViewNavigationBar<TrailingContent: View>: View {
    @Environment(\.presentationMode) var presentationMode
    let title: String
    let onBack: () -> Void
    let trailing: TrailingContent

    init(title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> TrailingContent) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack {
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(Theme.textPrimary.opacity(0.8))
                }
            }

            Spacer()

            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            trailing
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Share Card (rendered to image for sharing)
private struct RecordDetailShareCardView: View {
    let record: ScoreboardRecord

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(record.gameType.icon)
                    .font(.system(size: 36))
                Text(record.gameType.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            HStack(alignment: .center, spacing: 16) {
                VStack {
                    Text(record.team1Name)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text("\(record.team1FinalScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(record.winner == "left" ? .green : Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)

                Text("-")
                    .font(.largeTitle)
                    .foregroundColor(Theme.textSecondary)

                VStack {
                    Text(record.team2Name)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text("\(record.team2FinalScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(record.winner == "right" ? .green : Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }

            if let winner = record.winner {
                let winnerName = winner == "left" ? record.team1Name : record.team2Name
                Text(String(format: NSLocalizedString("game_winner_format", comment: ""), winnerName))
                    .font(.headline)
                    .foregroundColor(.green)
            }

            VStack(spacing: 8) {
                shareDetailRow(label: "date", value: Self.formatDate(record.startTime))
                shareDetailRow(label: "record_start_time", value: Self.formatTime(record.startTime))
                if let endTime = record.endTime {
                    shareDetailRow(label: "record_end_time", value: Self.formatTime(endTime))
                }
                if let duration = record.duration {
                    shareDetailRow(label: "record_duration", value: formatScoreboardDuration(duration))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .cornerRadius(12)

            shareCardAppFooter
        }
        .padding(24)
        .background(Theme.backgroundColor)
    }

    private var shareCardAppFooter: some View {
        HStack(spacing: 10) {
            Image("ShareCardAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "iScore")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func shareDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textPrimary)
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM-dd"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Share Sheet
private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { onDismiss?() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    // To make this preview work, we need a dummy record.
    // Let's assume we can create one.
    ScoreboardRecordDetailPage(recordId: "dummy-id")
}
