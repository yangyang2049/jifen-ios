import SwiftUI

struct CommonNamesManagementView: View {
    @FocusState private var isEditorFocused: Bool

    @State private var selectedType: NameType = .player
    @State private var teamNames: [String] = []
    @State private var playerNames: [String] = []
    @State private var searchText = ""
    @State private var isEditMode = false
    @State private var selectedNames: Set<String> = []

    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var showClearConfirm = false
    @State private var showBatchDeleteConfirm = false

    @State private var addInput = ""
    @State private var addType: NameType = .player
    @State private var editingOriginalName: String?
    @State private var editInput = ""

    @State private var toastMessage = ""
    @State private var showToast = false

    private let manager = CommonNamesManager.shared

    private var currentNames: [String] {
        selectedType == .team ? teamNames : playerNames
    }

    private var filteredNames: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return currentNames }
        return currentNames.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentTypeTitle: String {
        selectedType == .team
            ? NSLocalizedString("common_names_team", value: "队伍名称", comment: "")
            : NSLocalizedString("common_names_player", value: "选手名称", comment: "")
    }

    private var allFilteredSelected: Bool {
        !filteredNames.isEmpty && selectedNames.isSuperset(of: filteredNames)
    }

    private var showFloatingAdd: Bool {
        !isEditMode && !isSearchActive && !showAddSheet && !showEditSheet
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isEditMode {
                    VStack(spacing: Theme.sm) {
                        CommonDataSearchField(
                            text: $searchText,
                            placeholder: NSLocalizedString("common_names_search_placeholder", value: "搜索名称", comment: "")
                        )
                        categoryChips
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.top, Theme.sm)
                    .padding(.bottom, Theme.sm)
                }

                if filteredNames.isEmpty {
                    emptyState
                } else {
                    namesList
                }

                if isEditMode && !filteredNames.isEmpty && !isSearchActive {
                    CommonDataBatchEditBar(
                        allSelected: allFilteredSelected,
                        selectedCount: selectedNames.count,
                        onToggleSelectAll: toggleSelectAll,
                        onDelete: { showBatchDeleteConfirm = true }
                    )
                } else if showFloatingAdd {
                    CommonDataFloatingAddButton(
                        title: NSLocalizedString("common_names_add", value: "添加", comment: "")
                    ) {
                        openAddSheet()
                    }
                }
            }

            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .transition(.opacity)
                        .padding(.bottom, showFloatingAdd ? 96 : 28)
                }
            }
        }
        .navigationTitle(NSLocalizedString("common_names_manage", value: "常用名称管理", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear(perform: reload)
        .onChange(of: selectedType) { _, _ in
            selectedNames.removeAll()
        }
        .onChange(of: isEditMode) { _, editing in
            if !editing {
                selectedNames.removeAll()
            } else {
                searchText = ""
            }
        }
        .alert(
            NSLocalizedString("common_names_clear_current", value: "清空当前分类", comment: ""),
            isPresented: $showClearConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("clear", value: "清空", comment: ""), role: .destructive) {
                manager.clearNames(type: selectedType)
                reload()
                selectedNames.removeAll()
                isEditMode = false
            }
        } message: {
            Text(String(format: NSLocalizedString(
                "common_names_clear_current_message",
                value: "将清空%@的所有常用名称，此操作无法撤销。",
                comment: ""
            ), currentTypeTitle))
        }
        .alert(
            NSLocalizedString("delete", value: "删除", comment: ""),
            isPresented: $showBatchDeleteConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text(String(format: NSLocalizedString(
                "common_names_batch_delete_confirm",
                value: "确认删除选中的 %d 个名称？",
                comment: ""
            ), selectedNames.count))
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isEditMode {
                Button(NSLocalizedString("done", comment: "")) {
                    isEditMode = false
                }
                .foregroundColor(Theme.accentColor)
            } else if !currentNames.isEmpty {
                Menu {
                    Button {
                        isEditMode = true
                    } label: {
                        Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label(
                            NSLocalizedString("common_names_clear_current", value: "清空当前分类", comment: ""),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var categoryChips: some View {
        HStack(spacing: Theme.sm) {
            CommonDataCategoryChip(
                title: NSLocalizedString("common_names_player", value: "选手名称", comment: ""),
                selected: selectedType == .player
            ) {
                selectedType = .player
            }
            CommonDataCategoryChip(
                title: NSLocalizedString("common_names_team", value: "队伍名称", comment: ""),
                selected: selectedType == .team
            ) {
                selectedType = .team
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.md) {
            Spacer()
            EmptyStateCourtIcon(size: 44)
            Text(currentNames.isEmpty
                 ? NSLocalizedString("common_names_empty", value: "暂无常用名称", comment: "")
                 : NSLocalizedString("common_names_no_search_results", value: "无搜索结果", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
            if currentNames.isEmpty && !isEditMode {
                Text(NSLocalizedString(
                    "common_names_empty_hint",
                    value: "可在首页的「常用名称」中添加队伍或选手名称，下次即可快速选择。",
                    comment: ""
                ))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.lg)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var namesList: some View {
        ScrollView {
            LazyVStack(spacing: CommonDataManagementChrome.listSpacing) {
                ForEach(filteredNames, id: \.self) { name in
                    nameRow(name)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.sm)
            .padding(.bottom, showFloatingAdd ? 8 : Theme.md)
        }
    }

    private func nameRow(_ name: String) -> some View {
        HStack(spacing: 0) {
            if isEditMode {
                Button {
                    toggleSelection(name)
                } label: {
                    Image(systemName: selectedNames.contains(name) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedNames.contains(name) ? Theme.accentColor : Theme.textSecondary)
                        .frame(width: 44, height: 48)
                }
                .buttonStyle(.plain)
            }

            Button {
                if isEditMode {
                    toggleSelection(name)
                } else {
                    openEditSheet(name: name)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selectedType == .team ? "person.2" : "person")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 24)
                    Text(name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, isEditMode ? 8 : 16)
                .padding(.trailing, 8)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditMode {
                Button {
                    openEditSheet(name: name)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.accentColor)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        .commonDataListCardStyle()
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                VStack(spacing: 16) {
                    Picker("", selection: $addType) {
                        Text(NSLocalizedString("common_names_player", value: "选手名称", comment: ""))
                            .tag(NameType.player)
                        Text(NSLocalizedString("common_names_team", value: "队伍名称", comment: ""))
                            .tag(NameType.team)
                    }
                    .pickerStyle(.segmented)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $addInput)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.textPrimary)
                            .focused($isEditorFocused)
                            .padding(8)
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                            .background(Theme.homeCardDark)
                            .cornerRadius(10)

                        if addInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(NSLocalizedString(
                                "common_names_batch_hint",
                                value: "每行一个名称，或用逗号分隔",
                                comment: ""
                            ))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                        }
                    }

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(NSLocalizedString("common_names_add", value: "添加", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        closeAddSheet()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let canAdd = !addInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button(NSLocalizedString("common_names_add", value: "添加", comment: "")) {
                        submitAddAndContinue()
                    }
                    .disabled(!canAdd)
                    .foregroundStyle(canAdd ? Theme.primary : Theme.textSecondary)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isEditorFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var editSheet: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField(
                        selectedType == .team
                            ? NSLocalizedString("common_names_team_placeholder", value: "输入队伍名称", comment: "")
                            : NSLocalizedString("common_names_player_placeholder", value: "输入选手名称", comment: ""),
                        text: $editInput
                    )
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isEditorFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Theme.homeCardDark)
                    .cornerRadius(10)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(NSLocalizedString("common_names_edit_title", value: "编辑名称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        closeEditSheet()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("save", value: "保存", comment: "")) {
                        submitEdit()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isEditorFocused = true
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func reload() {
        teamNames = manager.getNames(type: .team)
        playerNames = manager.getNames(type: .player)
        selectedNames = selectedNames.intersection(Set(currentNames))
        if currentNames.isEmpty {
            isEditMode = false
        }
    }

    private func openAddSheet() {
        addType = selectedType
        addInput = ""
        showAddSheet = true
    }

    private func closeAddSheet() {
        isEditorFocused = false
        showAddSheet = false
        addInput = ""
    }

    private func submitAddAndContinue() {
        let names = CommonNamesBatchParser.parse(addInput)
        guard !names.isEmpty else {
            showMessage(NSLocalizedString("common_names_batch_empty", value: "请输入至少一个有效名称", comment: ""))
            return
        }
        let result = manager.addNamesBatch(names, type: addType)
        reload()
        addInput = ""
        if result.added == 1 && result.skipped == 0 {
            showMessage(NSLocalizedString("common_names_added", value: "已添加", comment: ""))
        } else {
            showMessage(String(format: NSLocalizedString(
                "common_names_batch_result",
                value: "已添加 %d 个，跳过 %d 个",
                comment: ""
            ), result.added, result.skipped))
        }
    }

    private func openEditSheet(name: String) {
        editingOriginalName = name
        editInput = name
        showEditSheet = true
    }

    private func closeEditSheet() {
        isEditorFocused = false
        showEditSheet = false
        editingOriginalName = nil
        editInput = ""
    }

    private func submitEdit() {
        guard let oldName = editingOriginalName else { return }
        do {
            try manager.updateName(oldName: oldName, newName: editInput, type: selectedType)
            reload()
            closeEditSheet()
            showMessage(NSLocalizedString("common_names_updated", value: "已更新", comment: ""))
        } catch {
            handleError(error, fallback: NSLocalizedString("common_names_update_failed", value: "更新失败", comment: ""))
        }
    }

    private func toggleSelection(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }

    private func toggleSelectAll() {
        if allFilteredSelected {
            selectedNames.subtract(filteredNames)
        } else {
            selectedNames.formUnion(filteredNames)
        }
    }

    private func deleteSelected() {
        let toDelete = selectedNames
        guard !toDelete.isEmpty else { return }
        let wasSelectAll = allFilteredSelected
        for name in toDelete {
            manager.removeName(name, type: selectedType)
        }
        selectedNames.removeAll()
        reload()
        if wasSelectAll {
            isEditMode = false
        }
        showMessage(NSLocalizedString("common_names_deleted", value: "已删除", comment: ""))
    }

    private func handleError(_ error: Error, fallback: String) {
        if let commonError = error as? CommonNamesError {
            switch commonError {
            case .emptyName:
                showMessage(NSLocalizedString("common_names_empty_name", value: "名称不能为空", comment: ""))
            case .duplicateName:
                showMessage(NSLocalizedString("common_names_already_exists", value: "该名称已存在", comment: ""))
            case .nameNotFound:
                showMessage(fallback)
            }
            return
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
