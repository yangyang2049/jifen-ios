//
//  HomeTab.swift
//  jifen
//
//  Home tab with recent activity
//

import SwiftUI

struct HomeTab: View {
    @State private var viewModel = ScoreboardRecordsViewModel.shared
    @State private var scoreboardRecords: [ScoreboardRecordSummary] = []
    @State private var listenerId: UUID?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recent Activity Section
                buildRecentActivitySection()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.backgroundColor)
        .onAppear {
            // Register listener
            listenerId = viewModel.addListener {
                updateScoreboardRecords()
            }
            // Load records
            updateScoreboardRecords()
        }
        .onDisappear {
            // Remove listener
            if let id = listenerId {
                viewModel.removeListener(id)
                listenerId = nil
            }
        }
        .onChange(of: viewModel.records) { oldValue, newValue in
            // Update when records change
            scoreboardRecords = newValue
        }
    }
    
    // MARK: - Recent Activity Section
    
    @ViewBuilder
    private func buildRecentActivitySection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("最近活动")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                
                Spacer()
                
                // Navigation button
                Button(action: {
                    // TODO: Navigate to recent activity page
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textPrimary)
                }
                .frame(width: 32, height: 32)
            }
            
            // Records list or empty state
            if scoreboardRecords.isEmpty {
                buildEmptyState()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(scoreboardRecords.prefix(3))) { record in
                        buildScoreboardRecordEntry(record)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private func buildEmptyState() -> some View {
        VStack(spacing: 24) {
            Text("🧘‍♂️")
                .font(.system(size: 72))
            
            Text("暂无最近记录")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Scoreboard Record Entry
    
    @ViewBuilder
    private func buildScoreboardRecordEntry(_ record: ScoreboardRecordSummary) -> some View {
        HStack(spacing: 12) {
            // Game icon
            Text(record.gameType.icon)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(Color.clear)
            
            // Middle info
            VStack(alignment: .leading, spacing: 4) {
                // Team names and score
                Text("\(record.team1Name) vs \(record.team2Name)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                
                // Time and duration
                HStack(spacing: 8) {
                    Text(record.time)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    
                    if let duration = record.duration {
                        Text(formatScoreboardDuration(duration))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // Score display
            Text("\(record.team1FinalScore) - \(record.team2FinalScore)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }
    
    // MARK: - Helper Methods
    
    private func updateScoreboardRecords() {
        scoreboardRecords = viewModel.getRecords()
    }
}

#Preview {
    HomeTab()
}
