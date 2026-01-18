import SwiftUI

// MARK: - RecentActivity Models (already defined in HomeModels.swift, import here for convenience)
// These models are expected to be available through the module import
// import jifen.Features.Home.Models // Or just `import jifen` if public

// MARK: - RecentRowView
struct RecentRowView: View {
    let activity: RecentActivity
    let isLast: Bool
    var isDarkTheme: Bool

    var body: some View {
        VStack(spacing: 0) { // Column()
            if activity.activityType == .timer {
                buildTimerItem()
            } else {
                buildScoreboardItem()
            }

            // Divider
            if !isLast {
                Divider()
                    .overlay(isDarkTheme ? Theme.homeOverlayBorder : Theme.homeDividerLight) // color(this.isDarkTheme ? Colors.homeOverlayBorder : Colors.homeDividerLight)
                    .padding(.horizontal, 0)
            }
        }
        .frame(maxWidth: .infinity) // width('100%')
    }

    @ViewBuilder
    private func buildTimerItem() -> some View {
        NavigationLink(destination: TimerRecordDetailPage(recordId: activity.id)) {
            HStack(spacing: 0) { // Row()
                // Left: Game Icon
                buildGameIcon(activity.gameType)
                .padding(.trailing, Theme.sm) // margin({ left: 12 }) (approximated)

                // Middle Info
                HStack(spacing: 0) { // Row()
                    Text(formatTime(activity.timestamp))
                        .font(.system(size: Theme.fontBody2)) // fontSize(14)
                        .foregroundColor(Theme.textPrimary)

                    if !activity.description.isEmpty {
                        Text(activity.description)
                            .font(.system(size: Theme.fontCaption)) // fontSize(12)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, Theme.md) // margin({ left: 16 })
                    }

                    Spacer() // Blank()
                }
                .frame(maxWidth: .infinity, alignment: .leading) // width('100%'), layoutWeight(1)
                // .margin({ left: 12 }) -> moved to padding on buildGameIcon

                // Right: Chevron
                Image(systemName: "chevron.right") // Image($r('app.media.chevron_forward'))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(Theme.textSecondary) // Assuming default color
                    .padding(.leading, Theme.sm) // margin({ left: 12 })
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .padding(.horizontal, Theme.xs) // padding({ left: 4, right: 4
            .padding(.vertical, Theme.sm) // top: 12, bottom: 12
        }
        .buttonStyle(CardButtonStyle()) // Use custom button style for interaction feedback
    }

    @ViewBuilder
    private func buildScoreboardItem() -> some View {
        NavigationLink(destination: ScoreboardRecordDetailPage(recordId: activity.id)) {
            HStack(spacing: 0) { // Row()
                // Left: Game Emoji Icon
                Text(activity.gameType.icon) // Text(GameTypeIcons[this.activity.gameType] || '🎮')
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)
                    .multilineTextAlignment(.center) // textAlign(TextAlign.Center)
                    .minimumScaleFactor(0.5)
                    .padding(.trailing, Theme.sm) // margin({ left: 12 }) (approximated)

                // Middle Info
                HStack(spacing: 0) { // Row()
                    VStack(alignment: .leading, spacing: Theme.xs) { // Column({ space: 4 })
                        // Game Name
                        Text(activity.title) // Text(this.activity.title || getGameName(this.activity.gameType))
                            .font(.system(size: Theme.fontBody2, weight: .medium)) // fontSize(14), fontWeight(FontWeight.Medium)
                            .foregroundColor(Theme.textPrimary)

                        HStack(spacing: Theme.sm) { // Row({ space: 8 })
                            Text(formatTime(activity.timestamp))
                                .font(.system(size: Theme.fontCaption)) // fontSize(12)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // alignItems(HorizontalAlign.Start), width('100%'), layoutWeight(1)

                    // Score Display
                    VStack(alignment: .trailing, spacing: 0) { // Column({ space: 4 })
                        if !activity.description.isEmpty {
                            Text(activity.description)
                                .font(.system(size: Theme.fontBody1, weight: .bold)) // fontSize(16), fontWeight(FontWeight.Bold)
                                .foregroundColor(Theme.primary) // Colors.primary
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing) // alignItems(HorizontalAlign.End)
                }
                .frame(maxWidth: .infinity, alignment: .leading) // width('100%'), layoutWeight(1)
                // .margin({ left: 12 }) -> moved to padding on game icon

                // Right: Chevron
                Image(systemName: "chevron.right") // Image($r('app.media.chevron_forward'))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(Theme.textSecondary) // Assuming default color
                    .padding(.leading, Theme.sm) // margin({ left: 12 })
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .padding(.horizontal, 0) // padding({ left: 0, right: 0
            .padding(.vertical, Theme.sm) // top: 12, bottom: 12
        }
        .buttonStyle(CardButtonStyle()) // Use custom button style for interaction feedback
    }

    @ViewBuilder
    private func buildGameIcon(_ gameType: GameType) -> some View {
        Text(gameType.icon)
            .font(.system(size: 24))
            .frame(width: 32, height: 32)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
    }

    private func formatTime(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let now = Date()
        let calendar = Calendar.current
        
        let dateFormatter = DateFormatter()
        
        // If today, show HH:MM
        if calendar.isDateInToday(date) {
            dateFormatter.dateFormat = "HH:mm"
            return dateFormatter.string(from: date)
        }
        
        // Else show "昨天" or date
        if calendar.isDateInYesterday(date) {
            return NSLocalizedString("home_yesterday", comment: "Yesterday")
        }
        
        // Other dates display MM-DD
        dateFormatter.dateFormat = "MM-dd"
        return dateFormatter.string(from: date)
    }
}

// MARK: - RecentRecordsSectionView
struct RecentRecordsSectionView: View {
    var records: [RecentActivity] = []
    var isDarkTheme: Bool = false

    var body: some View {
        VStack(spacing: 0) { // Column()
            // Container
            VStack(spacing: 0) { // Column()
                if records.isEmpty {
                    // Empty State
                    VStack(spacing: Theme.md) { // Column({ space: 16 })
                        Text("🧘") // Text('🧘')
                            .font(.system(size: 48))
                        
                        Text(NSLocalizedString("home_no_records", comment: "No recent records text"))
                            .font(.system(size: Theme.fontBody2)) // fontSize(14)
                            .foregroundColor(isDarkTheme ? Theme.homeTextDisabledDark : Theme.homeTextDisabledLight)
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
                                isLast: records.last?.id == record.id, // Check if it's the last record
                                isDarkTheme: isDarkTheme
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity) // width('100%')
            .padding(Theme.md) // padding(20)
            .background(.ultraThinMaterial) // Apply glassmorphism effect here
            .cornerRadius(Theme.lg) // borderRadius(24) // Theme.lg is 24
            .shadow(color: isDarkTheme ? .clear : Theme.homeShadowLight, radius: isDarkTheme ? 0 : 2, x: 0, y: isDarkTheme ? 0 : 1) // shadow
            
            // Footer Button - Plain Text Style
            if !records.isEmpty { // if (this.records.length > 0)
                NavigationLink(destination: RecentActivityPage()) {
                    Text(NSLocalizedString("home_view_all_records", comment: "View all records button"))
                        .font(.system(size: Theme.fontBody2, weight: .bold)) // fontSize(14), fontWeight(FontWeight.Bold)
                        .foregroundColor(Theme.primary) // Colors.primary
                        .frame(maxWidth: .infinity) // width('100%'), textAlign(TextAlign.Center)
                        .padding(.vertical, Theme.sm) // padding({ top: 12, bottom: 12 })
                        .padding(.top, Theme.md) // margin({ top: 20 })
                }
            }
        }
    }
}
