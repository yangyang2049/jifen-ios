import SwiftUI

/// Four stable slots: A1, A2, B1, B2. Singles uses slots 0 and 2.
struct GroupInlineMatchRoster: View {
    let format: GroupFormat
    @Binding var ids: [String]
    let members: [GroupMember]
    var frozen = false
    var frozenSeats: [GroupSeat] = []
    var showSeatLabels = true
    var prominentText = false
    @State private var activeSeat: Int?
    @State private var query = ""
    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = Theme.fontBody2
    @ScaledMetric(relativeTo: .body) private var prominentNameSize: CGFloat = Theme.fontBody1
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = Theme.fontCaption

    private var indices: [Int] { format == .singles ? [0, 2] : [0, 1, 2, 3] }
    private var roster: [GroupMember] { members.filter { $0.status == "active" } }
    private var filtered: [GroupMember] {
        roster.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }
    private func id(at index: Int) -> String { ids.indices.contains(index) ? ids[index] : "" }
    private func badge(_ index: Int) -> String { "\(index < 2 ? "A" : "B")\(index % 2 + 1)" }
    private func snapshot(at index: Int) -> GroupSeat? {
        frozenSeats.first { $0.side == (index < 2 ? "A" : "B") && $0.seat == index % 2 }
    }
    private func member(at index: Int) -> GroupMember? {
        members.first { $0.id == id(at: index) }
    }
    private func name(at index: Int) -> String {
        if frozen, let name = snapshot(at: index)?.displayName, !name.isEmpty { return name }
        if let member = member(at: index) { return member.displayName }
        let memberID = id(at: index)
        guard !memberID.isEmpty else { return groupText("choose_member", "Choose a member") }
        if let snapshot = snapshot(at: index), snapshot.memberId == memberID,
           let displayName = snapshot.displayName, !displayName.isEmpty {
            return displayName
        }
        return groupText("former_member", "Former member")
    }
    private func identity(_ member: GroupMember) -> String? {
        guard roster.filter({ $0.displayName == member.displayName }).count > 1 else { return nil }
        for count in 4...max(4, member.id.count) {
            let suffix = String(member.id.suffix(count))
            if roster.filter({ $0.displayName == member.displayName && $0.id.hasSuffix(suffix) }).count == 1 { return "#" + suffix }
        }
        return "#" + member.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .top, spacing: Theme.padding) {
                seatColumn(side: 0)
                seatColumn(side: 1)
            }
            if !frozen {
                Text(groupText("inline_seat_hint", "Select a seat, then choose a member"))
                    .font(.system(size: badgeSize)).foregroundStyle(Theme.textSecondary)
                if roster.count > 12 {
                    TextField(groupText("search_members", "Search members"), text: $query)
                        .textFieldStyle(.plain).groupAlignedInput()
                        .accessibilityIdentifier("group_inline_member_search")
                }
                GroupMemberPoolLayout(spacing: Theme.xs) {
                    ForEach(filtered) { member in memberToken(member) }
                }
                if roster.isEmpty { Text(groupText("need_members", "Invite friends or add temporary members before starting a match."))
                    .font(.system(size: nameSize)).foregroundStyle(Theme.textSecondary) }
            }
        }
        .onAppear { selectFirstEmpty() }
        .onChange(of: format) { _, _ in selectFirstEmpty() }
        .onChange(of: ids) { _, _ in
            if let activeSeat, !indices.contains(activeSeat) { selectFirstEmpty() }
        }
    }

    private func seatColumn(side: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            ForEach(0..<format.seatsPerSide, id: \.self) { position in
                let index = side * 2 + position
                Button {
                    if !frozen { activeSeat = index }
                } label: {
                    HStack(spacing: Theme.sm) {
                        if !id(at: index).isEmpty {
                            GroupAvatar(name: name(at: index), url: member(at: index)?.avatarUrl, size: 22)
                        } else {
                            Image(systemName: "plus").font(.system(size: Theme.fontBody2))
                                .frame(width: 22, height: 22)
                                .background(Theme.primary.opacity(0.12), in: Circle())
                        }
                        Text(name(at: index)).font(.system(size: prominentText ? prominentNameSize : nameSize))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showSeatLabels { Text(badge(index)).font(.system(size: badgeSize)).foregroundStyle(Theme.textSecondary) }
                    }
                    .padding(Theme.sm).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .foregroundStyle(Theme.textPrimary)
                    .background(!frozen && activeSeat == index ? Theme.primary.opacity(0.12) : GroupEditorColors.input,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(!frozen && activeSeat == index ? Theme.primary : Color(uiColor: .separator), lineWidth: !frozen && activeSeat == index ? 1.5 : 1))
                }
                .buttonStyle(.plain).disabled(frozen)
                .accessibilityIdentifier("group_seat_" + badge(index))
                .accessibilityLabel(badge(index)).accessibilityValue(name(at: index))
                .accessibilityAddTraits(activeSeat == index && !frozen ? .isSelected : [])
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func memberToken(_ member: GroupMember) -> some View {
        let assigned = indices.first { id(at: $0) == member.id }
        return Button { pick(member.id) } label: {
            HStack(spacing: Theme.xs) {
                GroupAvatar(name: member.displayName, url: member.avatarUrl, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName).font(.system(size: prominentText ? prominentNameSize : nameSize, weight: assigned == nil ? .regular : .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let identity = identity(member) { Text(identity).font(.system(size: badgeSize)).foregroundStyle(Theme.textSecondary) }
                }.frame(maxWidth: 130, alignment: .leading)
                if showSeatLabels, let assigned { Text(badge(assigned)).font(.system(size: badgeSize)).foregroundStyle(Theme.primary) }
            }
            .padding(Theme.sm).frame(minWidth: 96, minHeight: 44, alignment: .leading)
            .foregroundStyle(Theme.textPrimary)
            .background(assigned == nil ? GroupEditorColors.control : Theme.primary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(assigned == nil ? Color(uiColor: .separator) : Theme.primary, lineWidth: 1))
        }.buttonStyle(.plain).disabled(assigned == nil && activeSeat == nil)
            .accessibilityIdentifier("group_member_pick_" + member.id)
            .accessibilityAddTraits(assigned == nil ? [] : .isSelected)
    }

    private func selectFirstEmpty() { activeSeat = indices.first { id(at: $0).isEmpty } }
    private func pick(_ memberID: String) {
        var next = Array(ids.prefix(4))
        while next.count < 4 { next.append("") }
        if let assigned = indices.first(where: { next[$0] == memberID }) {
            next[assigned] = ""; activeSeat = assigned
        } else if let activeSeat, indices.contains(activeSeat) {
            next[activeSeat] = memberID
            self.activeSeat = indices.first { next[$0].isEmpty }
        } else { return }
        ids = next
    }
}

/// Intrinsic-width member pills wrap without truncating names to fixed grid columns.
private struct GroupMemberPoolLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 560
        return arrangement(width: width, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrangement(width: bounds.width, subviews: subviews).positions
        for (index, position) in positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.origin.x, y: bounds.minY + position.origin.y),
                                 anchor: .topLeading, proposal: ProposedViewSize(position.size))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var positions: [CGRect] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let measured = ideal.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
            let size = CGSize(width: min(width, measured.width), height: measured.height)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
