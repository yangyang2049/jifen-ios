//
//  PointsTableView.swift
//  jifen
//
//  积分表工具：列表 + 详情/编辑，本地持久化。
//

import SwiftUI

struct PointsTableView: View {
    @State private var records: [PointsTableRecord] = PointsTableStorage.load()
    @State private var path = NavigationPath()

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
                        NavigationLink(value: record) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.name)
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                Text("\(record.teams.count) \(NSLocalizedString("points_table_teams", value: "支队伍", comment: ""))")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
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
                    path.append(newRecord)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(for: PointsTableRecord.self) { record in
            PointsTableDetailView(
                record: binding(for: record),
                onDelete: {
                    records.removeAll { $0.id == record.id }
                    save()
                    path.removeLast()
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

// MARK: - Detail & Edit

struct PointsTableDetailView: View {
    @Binding var record: PointsTableRecord
    var onDelete: () -> Void
    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var showAddTeam: Bool = false
    @State private var newTeamName: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                if isEditingName {
                    HStack {
                        TextField(NSLocalizedString("points_table_name", value: "名称", comment: ""), text: $editedName)
                            .textFieldStyle(.roundedBorder)
                        Button(NSLocalizedString("confirm", comment: "Confirm")) {
                            record.name = editedName.isEmpty ? record.name : editedName
                            isEditingName = false
                        }
                    }
                } else {
                    Button {
                        editedName = record.name
                        isEditingName = true
                    } label: {
                        HStack {
                            Text(record.name)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("points_table_name", value: "名称", comment: ""))
            }
            .listRowBackground(Theme.cardBackground)

            Section {
                ForEach(record.standings(), id: \.team.id) { item in
                    NavigationLink {
                        PointsTableTeamEditView(
                            team: bindingForTeam(id: item.team.id),
                            allTeams: record.teams
                        )
                    } label: {
                        HStack {
                            Text("\(item.rank)")
                                .frame(width: 28, alignment: .leading)
                                .foregroundColor(Theme.textSecondary)
                            Text(item.team.name)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("\(item.team.played)")
                                .frame(width: 32, alignment: .center)
                            Text("\(item.team.win)")
                                .frame(width: 32, alignment: .center)
                            Text("\(item.team.draw)")
                                .frame(width: 32, alignment: .center)
                            Text("\(item.team.loss)")
                                .frame(width: 32, alignment: .center)
                            Text("\(item.team.points)")
                                .frame(width: 36, alignment: .trailing)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                    }
                    .listRowBackground(Theme.cardBackground)
                }
                .onDelete(perform: deleteTeamsByStandingsOffsets)
                Button {
                    newTeamName = ""
                    showAddTeam = true
                } label: {
                    Label(NSLocalizedString("points_table_add_team", value: "添加队伍", comment: ""), systemImage: "plus.circle")
                        .foregroundColor(Theme.accentColor)
                }
                .listRowBackground(Theme.cardBackground)
            } header: {
                HStack(spacing: 0) {
                    Text(NSLocalizedString("points_table_rank", value: "排名", comment: ""))
                        .frame(width: 28, alignment: .leading)
                    Text(NSLocalizedString("points_table_team", value: "队伍", comment: ""))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(NSLocalizedString("points_table_played", value: "赛", comment: ""))
                        .frame(width: 32, alignment: .center)
                    Text(NSLocalizedString("points_table_win", value: "胜", comment: ""))
                        .frame(width: 32, alignment: .center)
                    Text(NSLocalizedString("points_table_draw", value: "平", comment: ""))
                        .frame(width: 32, alignment: .center)
                    Text(NSLocalizedString("points_table_loss", value: "负", comment: ""))
                        .frame(width: 32, alignment: .center)
                    Text(NSLocalizedString("points_table_points", value: "积分", comment: ""))
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            }
            .listRowBackground(Theme.cardBackground)

            Section {
                Button(role: .destructive, action: {
                    onDelete()
                }) {
                    Text(NSLocalizedString("points_table_delete", value: "删除此积分表", comment: ""))
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor)
        .sheet(isPresented: $showAddTeam) {
            NavigationStack {
                Form {
                    TextField(NSLocalizedString("points_table_team_name", value: "队伍名称", comment: ""), text: $newTeamName)
                }
                .navigationTitle(NSLocalizedString("points_table_add_team", value: "添加队伍", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("cancel", comment: "Cancel")) { showAddTeam = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("confirm", comment: "Confirm")) {
                            let name = newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                record.teams.append(PointsTableTeam(name: name))
                                showAddTeam = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func bindingForTeam(id: UUID) -> Binding<PointsTableTeam> {
        Binding(
            get: { record.teams.first(where: { $0.id == id }) ?? PointsTableTeam(name: "") },
            set: { newValue in
                guard let i = record.teams.firstIndex(where: { $0.id == id }) else { return }
                var r = record
                r.teams[i] = newValue
                record = r
            }
        )
    }

    private func deleteTeamsByStandingsOffsets(at offsets: IndexSet) {
        let standings = record.standings()
        let idsToRemove = Set(offsets.map { standings[$0].team.id })
        record.teams.removeAll { idsToRemove.contains($0.id) }
    }
}

struct PointsTableTeamEditView: View {
    @Binding var team: PointsTableTeam
    let allTeams: [PointsTableTeam]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("points_table_team_name", value: "队伍名称", comment: ""), text: $team.name)
            }
            Section(header: Text(NSLocalizedString("points_table_stats", value: "数据", comment: ""))) {
                Stepper(value: $team.played, in: 0...999) {
                    HStack {
                        Text(NSLocalizedString("points_table_played", value: "赛", comment: ""))
                        Spacer()
                        Text("\(team.played)")
                    }
                }
                Stepper(value: $team.win, in: 0...999) {
                    HStack {
                        Text(NSLocalizedString("points_table_win", value: "胜", comment: ""))
                        Spacer()
                        Text("\(team.win)")
                    }
                }
                Stepper(value: $team.draw, in: 0...999) {
                    HStack {
                        Text(NSLocalizedString("points_table_draw", value: "平", comment: ""))
                        Spacer()
                        Text("\(team.draw)")
                    }
                }
                Stepper(value: $team.loss, in: 0...999) {
                    HStack {
                        Text(NSLocalizedString("points_table_loss", value: "负", comment: ""))
                        Spacer()
                        Text("\(team.loss)")
                    }
                }
            }
            Section {
                HStack {
                    Text(NSLocalizedString("points_table_points", value: "积分", comment: ""))
                    Spacer()
                    Text("\(team.points)")
                        .fontWeight(.medium)
                }
            }
        }
        .navigationTitle(team.name.isEmpty ? NSLocalizedString("points_table_edit_team", value: "编辑队伍", comment: "") : team.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PointsTableView()
    }
}
