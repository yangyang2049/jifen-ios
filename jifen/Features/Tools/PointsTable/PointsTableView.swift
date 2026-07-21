//
//  PointsTableView.swift
//  jifen
//
//  积分表工具：列表 + 详情/编辑，本地持久化。
//  详情对齐鸿蒙/安卓：列对齐、右上角菜单（编辑/删除）、页内全量编辑。
//

import SwiftUI

struct PointsTableView: View {
    @State private var records: [PointsTableRecord] = PointsTableStorage.load()
    @State private var selectedRecord: PointsTableRecord?

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: Theme.sm) {
                    EmptyStateCourtIcon(size: 44)
                    Text(NSLocalizedString("points_table_empty", value: "暂无积分表", comment: ""))
                        .font(.system(size: Theme.fontBody1, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Text(NSLocalizedString("points_table_empty_hint", value: "点击右上角 + 创建", comment: ""))
                        .font(.system(size: Theme.fontBody2))
                        .foregroundColor(Theme.textSecondary.opacity(0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(records) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.name)
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                Text("\(record.teams.count) \(NSLocalizedString("points_table_teams", value: "支队伍", comment: ""))")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.cardBackground)
                        .listRowSeparatorTint(Theme.textSecondary.opacity(0.3))
                    }
                    .onDelete(perform: deleteRecords)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("points_table_title", value: "积分表", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let newRecord = PointsTableRecord(
                        name: NSLocalizedString("points_table_new_name", value: "新积分表", comment: ""),
                        teams: [
                            PointsTableTeam(name: NSLocalizedString("points_table_team_a", value: "甲", comment: "")),
                            PointsTableTeam(name: NSLocalizedString("points_table_team_b", value: "乙", comment: "")),
                            PointsTableTeam(name: NSLocalizedString("points_table_team_c", value: "丙", comment: ""))
                        ]
                    )
                    records.append(newRecord)
                    save()
                    selectedRecord = newRecord
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(item: $selectedRecord) { record in
            PointsTableDetailView(
                record: binding(for: record),
                onDelete: {
                    records.removeAll { $0.id == record.id }
                    save()
                    selectedRecord = nil
                }
            )
        }
        .onAppear {
            records = PointsTableStorage.load()
        }
    }

    private func binding(for record: PointsTableRecord) -> Binding<PointsTableRecord> {
        Binding(
            get: { records.first(where: { $0.id == record.id }) ?? record },
            set: { newValue in
                if let i = records.firstIndex(where: { $0.id == record.id }) {
                    records[i] = newValue
                    save()
                }
            }
        )
    }

    private func deleteRecords(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        PointsTableStorage.save(records)
    }
}

// MARK: - Shared column metrics (header + rows share the same widths)

private enum PointsTableColumns {
    static let rank: CGFloat = 36
    static let played: CGFloat = 36
    static let stat: CGFloat = 40
    static let points: CGFloat = 44
    static let delete: CGFloat = 40
    static let spacing: CGFloat = 4
}

// MARK: - Detail

struct PointsTableDetailView: View {
    @Binding var record: PointsTableRecord
    var onDelete: () -> Void

    @State private var isEditMode = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteTeamID: UUID?
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var pendingDeleteResetTask: Task<Void, Never>?

    private static let redTrashIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let base = UIImage(systemName: "trash", withConfiguration: config) ?? UIImage()
        return base.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nameSection
                tableCard
                if isEditMode {
                    addTeamButton
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(record.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .primaryAction) {
                if isEditMode {
                    Button(NSLocalizedString("done", value: "完成", comment: "")) {
                        finishEditing()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
                } else {
                    Menu {
                        Button {
                            isEditMode = true
                        } label: {
                            Label(NSLocalizedString("edit", value: "编辑", comment: ""), systemImage: "pencil")
                        }
                        Button(role: .destructive, action: { showDeleteConfirm = true }) {
                            // Menu ignores SwiftUI foregroundStyle on symbols; bake red into the image.
                            Label {
                                Text(NSLocalizedString("delete", value: "删除", comment: ""))
                            } icon: {
                                Image(uiImage: Self.redTrashIcon)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(NSLocalizedString("operations", value: "操作", comment: ""))
                }
            }
        }
        .alert(
            NSLocalizedString("points_table_delete_confirm_title", value: "删除此积分表？", comment: ""),
            isPresented: $showDeleteConfirm
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                // Only clear selection; onDelete already pops detail back to the list.
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("points_table_delete_confirm_message", value: "删除后无法恢复", comment: ""))
        }
        .overlay(alignment: .bottom) {
            if showToast {
                ToastView(message: toastMessage)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .onDisappear {
            pendingDeleteResetTask?.cancel()
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("points_table_name", value: "名称", comment: ""))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            if isEditMode {
                TextField(
                    NSLocalizedString("points_table_name", value: "名称", comment: ""),
                    text: Binding(
                        get: { record.name },
                        set: { record.name = $0 }
                    )
                )
                .font(.system(size: 17, weight: .medium))
                .padding(14)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(record.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var tableCard: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider().overlay(Theme.divider)

            ForEach(Array(displayTeams.enumerated()), id: \.element.id) { index, team in
                if isEditMode {
                    editRow(team: team)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    let rank = record.standings().first(where: { $0.team.id == team.id })?.rank ?? (index + 1)
                    readOnlyRow(rank: rank, team: team)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                if index < displayTeams.count - 1 {
                    Divider().overlay(Theme.divider.opacity(0.6))
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Edit mode keeps original order so typing doesn't reshuffle rows; view mode uses standings order.
    private var displayTeams: [PointsTableTeam] {
        if isEditMode {
            return record.teams
        }
        return record.standings().map(\.team)
    }

    private var headerRow: some View {
        HStack(spacing: PointsTableColumns.spacing) {
            columnLabel(NSLocalizedString("points_table_rank", value: "排名", comment: ""), width: PointsTableColumns.rank)
            Text(NSLocalizedString("points_table_team", value: "队伍", comment: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if !isEditMode {
                columnLabel(NSLocalizedString("points_table_played", value: "赛", comment: ""), width: PointsTableColumns.played)
            }
            columnLabel(NSLocalizedString("points_table_win", value: "胜", comment: ""), width: PointsTableColumns.stat)
            columnLabel(NSLocalizedString("points_table_draw", value: "平", comment: ""), width: PointsTableColumns.stat)
            columnLabel(NSLocalizedString("points_table_loss", value: "负", comment: ""), width: PointsTableColumns.stat)
            if !isEditMode {
                columnLabel(NSLocalizedString("points_table_points", value: "积分", comment: ""), width: PointsTableColumns.points)
            } else {
                Color.clear.frame(width: PointsTableColumns.delete)
            }
        }
    }

    private func readOnlyRow(rank: Int, team: PointsTableTeam) -> some View {
        HStack(spacing: PointsTableColumns.spacing) {
            columnValue("\(rank)", width: PointsTableColumns.rank, secondary: true)
            Text(team.name)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            columnValue("\(team.win + team.draw + team.loss)", width: PointsTableColumns.played)
            columnValue("\(team.win)", width: PointsTableColumns.stat)
            columnValue("\(team.draw)", width: PointsTableColumns.stat)
            columnValue("\(team.loss)", width: PointsTableColumns.stat)
            columnValue("\(team.points)", width: PointsTableColumns.points, emphasis: true)
        }
    }

    private func editRow(team: PointsTableTeam) -> some View {
        let isPendingDelete = pendingDeleteTeamID == team.id
        return HStack(spacing: PointsTableColumns.spacing) {
            let rank = (record.teams.firstIndex(where: { $0.id == team.id }) ?? 0) + 1
            columnValue("\(rank)", width: PointsTableColumns.rank, secondary: true)

            TextField(
                NSLocalizedString("points_table_team_name", value: "队伍名称", comment: ""),
                text: teamNameBinding(id: team.id)
            )
            .font(.subheadline)
            .foregroundStyle(Theme.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            statField(value: winBinding(id: team.id))
            statField(value: drawBinding(id: team.id))
            statField(value: lossBinding(id: team.id))

            Button {
                requestDeleteTeam(id: team.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isPendingDelete ? Color(hex: "FF3B30") : Theme.textSecondary)
                    .frame(width: PointsTableColumns.delete, height: 36)
                    .background(
                        Circle()
                            .fill(isPendingDelete ? Color(hex: "FF3B30").opacity(0.18) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func statField(value: Binding<Int>) -> some View {
        TextField(
            "0",
            value: value,
            format: .number
        )
        .keyboardType(.numberPad)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.primary)
        .multilineTextAlignment(.center)
        .frame(width: PointsTableColumns.stat)
        .padding(.vertical, 6)
        .background(Theme.controlBackground.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var addTeamButton: some View {
        Button(action: addTeam) {
            Label(
                NSLocalizedString("points_table_add_team", value: "添加队伍", comment: ""),
                systemImage: "plus.circle.fill"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func columnLabel(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: width, alignment: .center)
    }

    private func columnValue(_ text: String, width: CGFloat, secondary: Bool = false, emphasis: Bool = false) -> some View {
        Text(text)
            .font(.subheadline.weight(emphasis ? .semibold : .regular))
            .foregroundStyle(secondary ? Theme.textSecondary : Theme.textPrimary)
            .frame(width: width, alignment: .center)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: - Bindings

    private func teamIndex(id: UUID) -> Int? {
        record.teams.firstIndex(where: { $0.id == id })
    }

    private func teamNameBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { record.teams.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                guard let i = teamIndex(id: id) else { return }
                var teams = record.teams
                teams[i].name = newValue
                record.teams = teams
            }
        )
    }

    private func winBinding(id: UUID) -> Binding<Int> {
        Binding(
            get: { record.teams.first(where: { $0.id == id })?.win ?? 0 },
            set: { newValue in
                guard let i = teamIndex(id: id) else { return }
                var teams = record.teams
                teams[i].setWin(newValue)
                record.teams = teams
            }
        )
    }

    private func drawBinding(id: UUID) -> Binding<Int> {
        Binding(
            get: { record.teams.first(where: { $0.id == id })?.draw ?? 0 },
            set: { newValue in
                guard let i = teamIndex(id: id) else { return }
                var teams = record.teams
                teams[i].setDraw(newValue)
                record.teams = teams
            }
        )
    }

    private func lossBinding(id: UUID) -> Binding<Int> {
        Binding(
            get: { record.teams.first(where: { $0.id == id })?.loss ?? 0 },
            set: { newValue in
                guard let i = teamIndex(id: id) else { return }
                var teams = record.teams
                teams[i].setLoss(newValue)
                record.teams = teams
            }
        )
    }

    // MARK: - Actions

    private func finishEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        pendingDeleteTeamID = nil
        isEditMode = false
    }

    private func addTeam() {
        let index = record.teams.count
        let namesZh = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let namesEn = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
        let isChinese = Locale.current.identifier.hasPrefix("zh")
        let pool = isChinese ? namesZh : namesEn
        let suffix = NSLocalizedString("points_table_team_suffix", value: "队", comment: "")
        let name: String
        if index < pool.count {
            name = "\(pool[index])\(suffix)"
        } else {
            name = "\(NSLocalizedString("points_table_new_team", value: "新队伍", comment: "")) \(index + 1)"
        }
        record.teams = record.teams + [PointsTableTeam(name: name)]
    }

    private func requestDeleteTeam(id: UUID) {
        if record.teams.count <= 2 {
            presentToast(NSLocalizedString("points_table_min_teams", value: "至少保留 2 支队伍", comment: ""))
            return
        }
        if pendingDeleteTeamID != id {
            pendingDeleteTeamID = id
            presentToast(NSLocalizedString("points_table_tap_again_to_delete_team", value: "再点一次删除该队伍", comment: ""))
            pendingDeleteResetTask?.cancel()
            pendingDeleteResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled, pendingDeleteTeamID == id {
                    pendingDeleteTeamID = nil
                }
            }
            return
        }
        pendingDeleteResetTask?.cancel()
        pendingDeleteTeamID = nil
        var teams = record.teams
        teams.removeAll { $0.id == id }
        record.teams = teams
        presentToast(NSLocalizedString("points_table_team_deleted_toast", value: "已删除队伍", comment: ""))
    }

    private func presentToast(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showToast = false }
        }
    }
}

#Preview {
    NavigationStack {
        PointsTableView()
    }
}
