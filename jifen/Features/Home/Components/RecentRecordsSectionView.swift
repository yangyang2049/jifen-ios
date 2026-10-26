import SwiftUI

/// One row layout for Home, Records and My Records, including cloud records.
struct RecordListRow: View {
    let record: RecordListPresentation
    var isEditMode = false

    var body: some View {
        HStack(spacing: 12) {
            if let gameType = record.gameType {
                recordGameIcon(gameType: gameType, isSyncedFromWatch: record.isSyncedFromWatch)
            } else {
                Image(systemName: "sportscourt")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
            }

            if record.participantCount >= 3 && !Theme.usesPadLayout {
                VStack(alignment: .leading, spacing: 4) {
                    if let score = record.score { recordScore(score) }
                    recordLabels(record)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                recordLabels(record)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let score = record.score { recordScore(score).layoutPriority(1) }
            }

            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
    }

    private func recordLabels(_ record: RecordListPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title)
                .font(.system(size: Theme.fontBody2, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(record.names == nil ? 1 : 2)
            if let names = record.names {
                Text(names)
                    .font(.system(size: Theme.fontCaption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(record.time).fixedSize()
                if let duration = record.duration { Text(formatDuration(duration)).fixedSize() }
                if let project = record.project { Text(project).lineLimit(1) }
            }
            .font(.system(size: Theme.fontCaption))
            .foregroundStyle(Theme.textSecondary)
            if record.isLegacyNineBall {
                Text(NineBallRecordRuleVersionPolicy.legacyLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func recordScore(_ score: String) -> some View {
        Text(score)
            .font(.system(size: Theme.fontBody1, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    /// Game icon with optional Watch-sync corner badge (aligned with HarmonyOS RecordsTab).
    private func recordGameIcon(gameType: GameType, isSyncedFromWatch: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AppCatalogIcon(gameType: gameType, size: 30)
                .frame(width: 40, height: 40)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            if isSyncedFromWatch {
                Image(systemName: "applewatch")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textOnPrimary)
                    .padding(3)
                    .background(Circle().fill(Theme.accentColor))
                    .offset(x: 2, y: 2)
                    .accessibilityLabel(NSLocalizedString(
                        "record_detail_synced_from_watch_badge",
                        value: "手表记录已同步",
                        comment: ""
                    ))
            }
        }
        .frame(width: 40, height: 40)
    }

}

struct RecentRowView: View {
    let activity: RecordsTabRecordItem
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                switch activity {
                case .scoreboard(let record): ScoreboardRecordDetailPage(recordId: record.id)
                case .timer(let record): TimerRecordDetailPage(recordId: record.id)
                case .cloud(let record):
                    if record.origin.sourceSystem == "group",
                       let result = try? JSONDecoder().decode(GroupResult.self, from: JSONEncoder().encode(record.nativePayload)) {
                        GroupResultDetailView(initial: result)
                    } else {
                        PersonalCloudRecordDetailView(record: record)
                    }
                }
            } label: {
                RecordListRow(record: activity.presentation)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recent_record_\(activity.id)")
            if !isLast {
                Divider().overlay(Theme.homeNeutralCardDivider).padding(.leading, 52)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - RecentRecordsSectionView
struct RecentRecordsSectionView: View {
    var records: [RecordsTabRecordItem] = []
    /// When set, "View all records" switches to Records tab instead of navigating to RecentActivityPage.
    var onViewAllTapped: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) { // Column()
            // Container
            VStack(spacing: 0) { // Column()
                if records.isEmpty {
                    // Empty State
                    VStack(spacing: Theme.md) { // Column({ space: 16 })
                        EmptyStateCourtIcon(size: 48, color: Theme.homeNeutralCardTextTertiary)
                        
                        Text(NSLocalizedString("home_no_records", comment: "No recent records text"))
                            .font(.system(size: Theme.fontBody2)) // fontSize(14)
                            .foregroundColor(Theme.homeNeutralCardTextSecondary)
                            // .margin({ top: 16 }) -> handled by VStack spacing
                    }
                    .frame(maxWidth: .infinity) // width('100%')
                    .frame(height: 200) // height(200)
                    // .justifyContent(FlexAlign.Center) .alignItems(HorizontalAlign.Center) -> handled by frame alignment
                } else {
                    // List
                    VStack(spacing: 0) { // Column({ space: 0 })
                        ForEach(records) { record in
                            RecentRowView(
                                activity: record,
                                isLast: false // No longer the last since we have the view all records row
                            )
                        }

                        // View all records: switch to Records tab or navigate to RecentActivityPage
                        if let onViewAllTapped = onViewAllTapped {
                            Button(action: onViewAllTapped) {
                                Text(NSLocalizedString("home_view_all_records", comment: "View all records button"))
                                    .font(.system(size: Theme.fontBody2, weight: .medium))
                                    .foregroundColor(Theme.homeNeutralCardTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, Theme.sm)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(CardButtonStyle())
                        } else {
                            NavigationLink(destination: RecentActivityPage()) {
                                Text(NSLocalizedString("home_view_all_records", comment: "View all records button"))
                                    .font(.system(size: Theme.fontBody2, weight: .medium))
                                    .foregroundColor(Theme.homeNeutralCardTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, Theme.sm)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity) // width('100%')
            .padding(Theme.md) // padding(20)
            .background(Theme.homeNeutralCardBackground)
            .cornerRadius(Theme.lg) // borderRadius(24) // Theme.lg is 24
            .shadow(color: Theme.lightModeShadow(0.05), radius: 2, x: 0, y: 1) // shadow
        }
    }
}
