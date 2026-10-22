import SwiftUI

/// Android's ranking card: one horizontally scrollable table keeps all six statistics aligned.
struct GroupRankingTable: View {
    let rows: [GroupRanking]
    let members: [GroupMember]
    let myMemberID: String?
    let groupID: String
    let format: GroupFormat
    @ScaledMetric(relativeTo: .subheadline) private var identityWidth: CGFloat = 184
    @ScaledMetric(relativeTo: .subheadline) private var columnMinimum: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 24
    @State private var availableWidth: CGFloat = 0

    private var headers: [String] {
        [groupText("ranking_games", "P"), groupText("ranking_wins", "W"),
         groupText("ranking_losses", "L"), groupText("ranking_draws", "D"),
         groupText("ranking_sets", "Sets"), groupText("ranking_rate", "Win rate")]
    }
    private func cells(_ row: GroupRanking) -> [String] {
        [String(row.games), String(row.wins), String(row.losses), String(row.draws ?? 0),
         "\(row.setsWon)-\(row.setsLost)", row.qualifiedWinRate ?? groupText("ranking_insufficient_matches", "Too few matches")]
    }
    private var widths: [CGFloat] {
        let bodyFont = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.bold)
        let headerFont = UIFont.preferredFont(forTextStyle: .caption2).withWeight(.semibold)
        return headers.indices.map { index in
            let heading = (headers[index] as NSString).size(withAttributes: [.font: headerFont]).width
            let value = rows.map { (cells($0)[index] as NSString).size(withAttributes: [.font: bodyFont]).width }.max() ?? 0
            return max(columnMinimum, max(heading, value) + 8)
        }
    }
    var body: some View {
        let columnWidths = widths
        GroupSurface {
            Text(String(format: groupText("ranking_title", "%@ rankings"), groupText("filter_" + format.rawValue, format.title)))
                .font(GroupTypography.body.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("").frame(minWidth: identityWidth, maxWidth: .infinity)
                        ForEach(headers.indices, id: \.self) { index in
                            Text(headers[index]).font(GroupTypography.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).frame(width: columnWidths[index], alignment: .trailing)
                        }
                    }.padding(.vertical, Theme.xs)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let rank = row.rank > 0 ? row.rank : index + 1
                        NavigationLink {
                            GroupMemberResultsView(groupID: groupID, memberID: row.memberId, name: row.name, format: format)
                        } label: {
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Text(String(rank)).font(GroupTypography.caption.bold())
                                        .foregroundStyle(rank <= 3 ? Theme.primary : Theme.textSecondary)
                                        .frame(width: badgeSize, height: badgeSize)
                                        .background((rank <= 3 ? Theme.primary : Theme.textSecondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    GroupAvatar(name: row.name, url: members.first { $0.id == row.memberId }?.avatarUrl, size: 24)
                                    Text(row.name + (!row.memberId.isEmpty && row.memberId == myMemberID ? groupText("ranking_me_suffix", " (me)") : ""))
                                        .font(GroupTypography.body.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }.frame(minWidth: identityWidth, maxWidth: .infinity, alignment: .leading)
                                ForEach(headers.indices, id: \.self) { column in
                                    let highlighted = column == 5 && rank <= 3 && row.qualifiedWinRate != nil
                                    Text(cells(row)[column]).font(GroupTypography.body.weight(highlighted ? .bold : .regular))
                                        .foregroundStyle(highlighted ? Theme.primary : Theme.textPrimary).lineLimit(1)
                                        .frame(width: columnWidths[column], alignment: .trailing)
                                }
                            }.padding(.vertical, Theme.sm).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("group_rank_row_" + row.memberId)
                    }
                }.frame(minWidth: max(availableWidth, identityWidth + columnWidths.reduce(0, +)))
            }.accessibilityIdentifier("group_rank_table")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = max(0, $0 - 32) }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: pointSize)
    }
}
