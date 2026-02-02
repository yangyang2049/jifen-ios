//
//  RecordsTab.swift
//  jifen
//
//  Dedicated Records tab - scoreboard records list, aligned with Watch.
//

import SwiftUI

struct RecordsTab: View {
    @StateObject private var viewModel = ScoreboardRecordsViewModel.shared

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.records.isEmpty {
                    loadingView
                } else if viewModel.records.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("tab_records", comment: "Records"))
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .onAppear {
                viewModel.refreshRecords()
            }
        }
        .accentColor(Theme.accentColor)
    }

    private var loadingView: some View {
        VStack(spacing: Theme.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accentColor))
                .scaleEffect(1.2)
            Text(NSLocalizedString("loading", comment: "Loading"))
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.lg) {
            Text("📝")
                .font(.system(size: 56))
            Text(NSLocalizedString("home_no_records", comment: "No recent records"))
                .font(.system(size: Theme.fontBody1, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.groupedRecords) { group in
                    Section {
                        ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                            NavigationLink(destination: ScoreboardRecordDetailPage(recordId: record.id)) {
                                recordRow(record)
                            }
                            .buttonStyle(.plain)
                            if index < group.records.count - 1 {
                                Divider()
                                    .overlay(Theme.homeOverlayBorder)
                                    .padding(.leading, 56)
                            }
                        }
                    } header: {
                        sectionHeader(displayDate: group.displayDate)
                    }
                }
            }
            .padding(.horizontal, Theme.lg)
            .padding(.bottom, Theme.lg)
        }
    }

    private func sectionHeader(displayDate: String) -> some View {
        HStack {
            Text(displayDate)
                .font(.system(size: Theme.fontCaption, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.vertical, Theme.sm)
        .padding(.horizontal, Theme.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.backgroundColor)
    }

    private func recordRow(_ record: ScoreboardRecordSummary) -> some View {
        HStack(spacing: 0) {
            Text(record.gameType.icon)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.trailing, Theme.sm)

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text("\(record.team1Name) vs \(record.team2Name)")
                    .font(.system(size: Theme.fontBody2, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Text(record.time)
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(record.team1FinalScore) : \(record.team2FinalScore)")
                .font(.system(size: Theme.fontBody1, weight: .bold))
                .foregroundColor(Theme.accentColor)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.leading, Theme.sm)
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.sm)
    }
}

#Preview {
    RecordsTab()
}
