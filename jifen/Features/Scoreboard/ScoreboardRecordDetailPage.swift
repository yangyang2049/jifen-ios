
import SwiftUI

struct ScoreboardRecordDetailPage: View {
    let recordId: String
    
    @Environment(\.presentationMode) var presentationMode
    @State private var record: ScoreboardRecord?
    @State private var isDeleting = false
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                DetailViewNavigationBar(
                    title: "match_detail",
                    onBack: { presentationMode.wrappedValue.dismiss() }
                ) {
                    menu
                }
                
                if isDeleting {
                    deletingView
                } else if let record = record {
                    ScrollView {
                        VStack(spacing: 16) {
                            gameInfoView(record: record)
                            actionsListView(record: record)
                        }
                        .padding()
                    }
                } else {
                    recordNotFoundView
                }
            }
        }
        .onAppear(perform: loadRecord)
        .navigationBarHidden(true)
        .alert(isPresented: $showingDeleteConfirm) {
            Alert(
                title: Text("confirm_delete"),
                message: Text("confirm_delete_record_message"),
                primaryButton: .destructive(Text("delete"), action: deleteRecord),
                secondaryButton: .cancel()
            )
        }
    }
    
    private var menu: some View {
        Menu {
            Button(action: {
                // TODO: Implement share
            }) {
                Label("share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: {
                showingDeleteConfirm = true
            }) {
                Label("delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(Theme.textPrimary)
        }
    }
    
    private var deletingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("deleting_record")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recordNotFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 48))
            Text("record_not_found")
                .font(.headline)
            Text("record_may_deleted")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("\(winnerName) wins")
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
                Text("no_actions_recorded")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(record.actions.indices, id: \.self) { index in
                    actionRow(action: record.actions[index], index: index)
                }
            }
        }
        .padding()
        .background(Theme.surface)
        .cornerRadius(12)
    }
    
    private func actionRow(action: String, index: Int) -> some View {
        HStack {
            Text(action)
                .font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(index % 2 == 0 ? Theme.backgroundColor : Color.clear)
        .cornerRadius(8)
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
        isDeleting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let success = ScoreboardRecordManager.shared.deleteRecord(recordId)
            if success {
                presentationMode.wrappedValue.dismiss()
            } else {
                isDeleting = false
                // show error
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(Theme.textPrimary)
            }
            
            Spacer()
            
            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            
            Spacer()
            
            trailing
        }
        .padding()
        .background(Theme.surface)
    }
}

#Preview {
    // To make this preview work, we need a dummy record.
    // Let's assume we can create one.
    ScoreboardRecordDetailPage(recordId: "dummy-id")
}
