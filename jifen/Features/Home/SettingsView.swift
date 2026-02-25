import SwiftUI

private enum AppSupportURLs {
    static let support = "https://douhua.fan/jifenqi/contact"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var vibrationEnabled: Bool = PreferencesManager.shared.vibrationEnabled
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Settings sections
                        VStack(spacing: 24) {
                            // Data Section
                            SettingsSection(title: NSLocalizedString("settings_data", value: "数据", comment: "Data")) {
                                VStack(spacing: 0) {
                                    NavigationLink {
                                        CommonNamesManagementView()
                                    } label: {
                                        HStack {
                                            Image(systemName: "person.2.fill")
                                                .foregroundColor(Theme.accentColor)
                                                .frame(width: 24, height: 24)
                                            Text(NSLocalizedString("common_names_manage", value: "常用名称管理", comment: "Manage common names"))
                                                .foregroundColor(Theme.textPrimary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                        .padding(.leading, 56)

                                    Button {
                                        showClearConfirm = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "trash")
                                                .foregroundColor(Theme.accentColor)
                                                .frame(width: 24, height: 24)
                                            Text(NSLocalizedString("clear_data", comment: "Clear data"))
                                                .foregroundColor(Theme.textPrimary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Accessibility Section
                            SettingsSection(title: NSLocalizedString("accessibility", comment: "Accessibility")) {
                                VStack(spacing: 0) {
                                    ToggleRow(
                                        title: NSLocalizedString("vibration", comment: "Vibration"),
                                        isOn: $vibrationEnabled,
                                        icon: "waveform"
                                    )
                                    .onChange(of: vibrationEnabled) { _, new in
                                        PreferencesManager.shared.vibrationEnabled = new
                                    }
                                }
                            }

                            // About Section
                            SettingsSection(title: NSLocalizedString("about", comment: "About")) {
                                VStack(spacing: 0) {
                                    if let url = URL(string: AppSupportURLs.support) {
                                        LinkRow(
                                            title: NSLocalizedString("support_contact", comment: "Support & Contact"),
                                            icon: "envelope.fill",
                                            url: url
                                        )
                                    }
                                    InfoRow(
                                        title: NSLocalizedString("version", comment: "Version"),
                                        value: getAppVersion(),
                                        icon: "info.circle.fill"
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings", comment: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
            .onAppear {
                vibrationEnabled = PreferencesManager.shared.vibrationEnabled
            }
            .alert(NSLocalizedString("clear_data", comment: ""), isPresented: $showClearConfirm) {
                Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
                Button(NSLocalizedString("clear_data", comment: ""), role: .destructive) {
                    ScoreboardRecordManager.shared.clearAllRecords()
                    _ = TimerRecordManager.shared.clearAllRecords()
                    _ = LocalBookingManager.shared.clearAllBookings()
                    CommonNamesManager.shared.clearNames(type: .team)
                    CommonNamesManager.shared.clearNames(type: .player)
                    ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
                    TimerRecordsViewModel.shared.loadFromStorage()
                }
            } message: {
                Text(NSLocalizedString("clear_all_records_message", comment: ""))
            }
        }
    }

    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return version
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 4)

            content
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.accentColor)
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.accentColor)
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Text(value)
                .foregroundColor(Theme.textSecondary)
                .font(.system(size: Theme.fontBody2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct LinkRow: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.accentColor)
                    .frame(width: 24, height: 24)

                Text(title)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct CommonNamesManagementView: View {
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isNameEditorFocused: Bool
    @State private var selectedType: NameType = .team
    @State private var teamNames: [String] = []
    @State private var playerNames: [String] = []
    @State private var showClearTypeConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showNameEditorSheet = false
    @State private var showBatchAddSheet = false
    @State private var pendingDeleteName: String?
    @State private var editingOriginalName: String?
    @State private var nameEditorInput: String = ""
    @State private var batchAddInput: String = ""
    @State private var batchAddType: NameType = .team
    @State private var toastMessage: String = ""
    @State private var showToast = false

    private let commonNamesManager = CommonNamesManager.shared

    private var currentNames: [String] {
        selectedType == .team ? teamNames : playerNames
    }

    private var currentTypeTitle: String {
        selectedType == .team
            ? NSLocalizedString("common_names_team", value: "队伍名称", comment: "Team names category")
            : NSLocalizedString("common_names_player", value: "选手名称", comment: "Player names category")
    }

    private var nameEditorTitle: String {
        editingOriginalName == nil
            ? NSLocalizedString("common_names_add", value: "添加", comment: "Add")
            : NSLocalizedString("common_names_edit_title", value: "编辑名称", comment: "Edit name")
    }

    private var namePlaceholder: String {
        selectedType == .team
            ? NSLocalizedString("common_names_team_placeholder", value: "输入队伍名称", comment: "Team name placeholder")
            : NSLocalizedString("common_names_player_placeholder", value: "输入选手名称", comment: "Player name placeholder")
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()

            VStack(spacing: 16) {
                Picker("", selection: $selectedType) {
                    Text(NSLocalizedString("common_names_team", value: "队伍名称", comment: "Team names category"))
                        .tag(NameType.team)
                    Text(NSLocalizedString("common_names_player", value: "选手名称", comment: "Player names category"))
                        .tag(NameType.player)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button {
                        openAddNameSheet()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text(NSLocalizedString("common_names_add", value: "添加", comment: "Add"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.homeCardDark)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        openBatchAddSheet()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.badge.plus")
                            Text(NSLocalizedString("common_names_batch_add", value: "批量添加", comment: "Batch add"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.homeCardDark)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                if !currentNames.isEmpty {
                    Button {
                        showClearTypeConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .foregroundColor(Theme.accentColor)
                            Text(NSLocalizedString("common_names_clear_current", value: "清空当前分类", comment: "Clear current name category"))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.homeCardDark)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if currentNames.isEmpty {
                    VStack {
                        Spacer()
                        VStack(spacing: Theme.sm) {
                            EmptyStateCourtIcon(size: 44)
                            Text(NSLocalizedString("common_names_empty", value: "暂无常用名称", comment: ""))
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(currentNames, id: \.self) { name in
                                HStack(spacing: 12) {
                                    Text(name)
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        openEditNameSheet(name: name)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundColor(Theme.accentColor)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        pendingDeleteName = name
                                        showDeleteConfirm = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Theme.homeCardDark)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .transition(.opacity)
                        .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle(NSLocalizedString("common_names_manage", value: "常用名称管理", comment: "Manage common names"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadNames()
        }
        .alert(
            NSLocalizedString("common_names_clear_current", value: "清空当前分类", comment: "Clear current name category"),
            isPresented: $showClearTypeConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("clear", value: "清空", comment: "Clear"), role: .destructive) {
                commonNamesManager.clearNames(type: selectedType)
                reloadNames()
            }
        } message: {
            Text(String(format: NSLocalizedString(
                "common_names_clear_current_message",
                value: "将清空%@的所有常用名称，此操作无法撤销。",
                comment: "Clear current category message"
            ), currentTypeTitle))
        }
        .alert(
            NSLocalizedString("delete", value: "删除", comment: "Delete"),
            isPresented: $showDeleteConfirm,
            presenting: pendingDeleteName
        ) { name in
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("delete", value: "删除", comment: "Delete"), role: .destructive) {
                removeName(name)
            }
        } message: { name in
            Text(String(format: NSLocalizedString(
                "common_names_delete_message",
                value: "确认删除“%@”？",
                comment: "Confirm delete name message"
            ), name))
        }
        .sheet(isPresented: $showNameEditorSheet) {
            NavigationStack {
                ZStack {
                    Theme.backgroundColor.ignoresSafeArea()
                    VStack(spacing: 16) {
                        TextField(namePlaceholder, text: $nameEditorInput)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textPrimary)
                            .focused($isNameEditorFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Theme.homeCardDark)
                            .cornerRadius(10)

                        Spacer()
                    }
                    .padding(16)
                }
                .navigationTitle(nameEditorTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "Cancel")) {
                            closeNameEditor()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editingOriginalName == nil
                               ? NSLocalizedString("add", value: "添加", comment: "Add")
                               : NSLocalizedString("save", value: "保存", comment: "Save")) {
                            submitNameEditor()
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isNameEditorFocused = true
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBatchAddSheet) {
            NavigationStack {
                ZStack {
                    Theme.backgroundColor.ignoresSafeArea()
                    VStack(spacing: 12) {
                        Picker("", selection: $batchAddType) {
                            Text(NSLocalizedString("common_names_team", value: "队伍名称", comment: "Team names category"))
                                .tag(NameType.team)
                            Text(NSLocalizedString("common_names_player", value: "选手名称", comment: "Player names category"))
                                .tag(NameType.player)
                        }
                        .pickerStyle(.segmented)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $batchAddInput)
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textPrimary)
                                .padding(8)
                                .frame(minHeight: 220)
                                .scrollContentBackground(.hidden)
                                .background(Theme.homeCardDark)
                                .cornerRadius(10)

                            if batchAddInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(NSLocalizedString(
                                    "common_names_batch_hint",
                                    value: "每行一个名称，或用逗号分隔",
                                    comment: "Batch input hint"
                                ))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                }
                .navigationTitle(NSLocalizedString("common_names_batch_add", value: "批量添加", comment: "Batch add"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "Cancel")) {
                            closeBatchAddSheet()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(NSLocalizedString("add", value: "添加", comment: "Add")) {
                            submitBatchAdd()
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func reloadNames() {
        teamNames = commonNamesManager.getNames(type: .team)
        playerNames = commonNamesManager.getNames(type: .player)
    }

    private func removeName(_ name: String) {
        commonNamesManager.removeName(name, type: selectedType)
        reloadNames()
        showMessage(NSLocalizedString("common_names_deleted", value: "已删除", comment: "Deleted common name"))
    }

    private func openAddNameSheet() {
        editingOriginalName = nil
        nameEditorInput = ""
        showNameEditorSheet = true
    }

    private func openEditNameSheet(name: String) {
        editingOriginalName = name
        nameEditorInput = name
        showNameEditorSheet = true
    }

    private func closeNameEditor() {
        isNameEditorFocused = false
        showNameEditorSheet = false
        editingOriginalName = nil
        nameEditorInput = ""
    }

    private func submitNameEditor() {
        do {
            if let oldName = editingOriginalName {
                try commonNamesManager.updateName(oldName: oldName, newName: nameEditorInput, type: selectedType)
                showMessage(NSLocalizedString("common_names_updated", value: "已更新", comment: "Updated common name"))
            } else {
                _ = try commonNamesManager.addName(nameEditorInput, type: selectedType)
                showMessage(NSLocalizedString("common_names_added", value: "已添加", comment: "Added common name"))
            }
            reloadNames()
            closeNameEditor()
        } catch {
            let fallback = editingOriginalName == nil
                ? NSLocalizedString("common_names_add_failed", value: "添加失败", comment: "Add common name failed")
                : NSLocalizedString("common_names_update_failed", value: "更新失败", comment: "Update common name failed")
            handleCommonNameError(error, fallback: fallback)
        }
    }

    private func openBatchAddSheet() {
        batchAddType = selectedType
        batchAddInput = ""
        showBatchAddSheet = true
    }

    private func closeBatchAddSheet() {
        showBatchAddSheet = false
        batchAddInput = ""
    }

    private func submitBatchAdd() {
        let names = parseBatchInput(batchAddInput)
        guard !names.isEmpty else {
            showMessage(NSLocalizedString("common_names_batch_empty", value: "请输入至少一个有效名称", comment: "Batch add empty input"))
            return
        }

        let result = commonNamesManager.addNamesBatch(names, type: batchAddType)
        reloadNames()
        closeBatchAddSheet()
        let format = NSLocalizedString(
            "common_names_batch_result",
            value: "已添加 %d 个，跳过 %d 个",
            comment: "Batch add result"
        )
        showMessage(String(format: format, result.added, result.skipped))
    }

    private func parseBatchInput(_ text: String) -> [String] {
        CommonNamesBatchParser.parse(text)
    }

    private func handleCommonNameError(_ error: Error, fallback: String) {
        if let commonError = error as? CommonNamesError {
            switch commonError {
            case .emptyName:
                showMessage(NSLocalizedString("common_names_empty_name", value: "名称不能为空", comment: "Common name is empty"))
                return
            case .duplicateName:
                showMessage(NSLocalizedString("common_names_already_exists", value: "该名称已存在", comment: "Common name already exists"))
                return
            case .nameNotFound:
                showMessage(fallback)
                return
            }
        }
        showMessage(fallback)
    }

    private func showMessage(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
}



#Preview {
    SettingsView()
}
