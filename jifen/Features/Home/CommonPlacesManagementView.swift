import SwiftUI

struct CommonPlacesManagementView: View {
    @FocusState private var isEditorFocused: Bool

    @State private var places: [CommonPlace] = []
    @State private var searchText = ""
    @State private var isEditMode = false
    @State private var selectedIds: Set<UUID> = []

    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var showClearConfirm = false
    @State private var showBatchDeleteConfirm = false

    @State private var addInput = ""
    @State private var editingPlace: CommonPlace?
    @State private var editInput = ""

    @State private var toastMessage = ""
    @State private var showToast = false

    private let manager = CommonPlacesManager.shared

    private var filteredPlaces: [CommonPlace] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return places }
        return places.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var allFilteredSelected: Bool {
        let ids = Set(filteredPlaces.map(\.id))
        return !ids.isEmpty && selectedIds.isSuperset(of: ids)
    }

    private var showFloatingAdd: Bool {
        !isEditMode && !isSearchActive && !showAddSheet && !showEditSheet
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isEditMode {
                    CommonDataSearchField(
                        text: $searchText,
                        placeholder: NSLocalizedString("common_places_search_placeholder", value: "搜索地点", comment: "")
                    )
                    .padding(.horizontal, Theme.md)
                    .padding(.top, Theme.sm)
                    .padding(.bottom, Theme.sm)
                }

                if filteredPlaces.isEmpty {
                    emptyState
                } else {
                    placesList
                }

                if isEditMode && !filteredPlaces.isEmpty && !isSearchActive {
                    CommonDataBatchEditBar(
                        allSelected: allFilteredSelected,
                        selectedCount: selectedIds.count,
                        onToggleSelectAll: toggleSelectAll,
                        onDelete: { showBatchDeleteConfirm = true }
                    )
                } else if showFloatingAdd {
                    CommonDataFloatingAddButton(
                        title: NSLocalizedString("common_places_add", value: "添加地点", comment: "")
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
        .navigationTitle(NSLocalizedString("common_places_title", value: "常用地点", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear(perform: reload)
        .onChange(of: isEditMode) { _, editing in
            if !editing {
                selectedIds.removeAll()
            } else {
                searchText = ""
            }
        }
        .alert(
            NSLocalizedString("common_places_clear", value: "清空地点", comment: ""),
            isPresented: $showClearConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("clear", value: "清空", comment: ""), role: .destructive) {
                manager.clearAll()
                reload()
                selectedIds.removeAll()
                isEditMode = false
            }
        } message: {
            Text(NSLocalizedString("common_places_clear_message", value: "将清空所有常用地点，此操作无法撤销。", comment: ""))
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
                "common_places_batch_delete_confirm",
                value: "确认删除选中的 %d 个地点？",
                comment: ""
            ), selectedIds.count))
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
            } else if !places.isEmpty {
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
                            NSLocalizedString("common_places_clear", value: "清空地点", comment: ""),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.md) {
            Spacer()
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 44))
                .foregroundColor(Theme.primaryDark)
            Text(places.isEmpty
                 ? NSLocalizedString("common_places_no_records", value: "暂无常用地点", comment: "")
                 : NSLocalizedString("common_places_no_search_results", value: "无搜索结果", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
            if places.isEmpty && !isEditMode {
                Text(NSLocalizedString(
                    "common_places_usage_desc",
                    value: "预约球局中输入的地点会自动保存在这里，下次可以快速选择。",
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
        .padding(Theme.lg)
    }

    private var placesList: some View {
        ScrollView {
            LazyVStack(spacing: CommonDataManagementChrome.listSpacing) {
                ForEach(filteredPlaces) { place in
                    placeRow(place)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.top, Theme.sm)
            .padding(.bottom, showFloatingAdd ? 8 : Theme.md)
        }
    }

    private func placeRow(_ place: CommonPlace) -> some View {
        HStack(spacing: 0) {
            if isEditMode {
                Button {
                    toggleSelection(place.id)
                } label: {
                    Image(systemName: selectedIds.contains(place.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedIds.contains(place.id) ? Theme.accentColor : Theme.textSecondary)
                        .frame(width: 44, height: 48)
                }
                .buttonStyle(.plain)
            }

            Button {
                if isEditMode {
                    toggleSelection(place.id)
                } else {
                    openEditSheet(place)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(place.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !isEditMode, place.useCount > 0 {
                            Text("×\(place.useCount)")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    if !isEditMode, place.useCount > 0 {
                        Text(String(format: NSLocalizedString("common_places_use_count", value: "使用 %d 次", comment: ""), place.useCount))
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .padding(.leading, isEditMode ? 8 : 16)
                .padding(.trailing, 8)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditMode {
                Button {
                    openEditSheet(place)
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
                                "common_places_batch_hint",
                                value: "每行一个地点，或用逗号分隔",
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
            .navigationTitle(NSLocalizedString("common_places_add", value: "添加地点", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        closeAddSheet()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common_places_add", value: "添加地点", comment: "")) {
                        submitAddAndContinue()
                    }
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
                        NSLocalizedString("common_places_placeholder", value: "输入地点", comment: ""),
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
            .navigationTitle(NSLocalizedString("common_places_edit_title", value: "编辑地点", comment: ""))
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
        places = manager.getAllPlaces()
        selectedIds = selectedIds.intersection(Set(places.map(\.id)))
        if places.isEmpty {
            isEditMode = false
        }
    }

    private func openAddSheet() {
        addInput = ""
        showAddSheet = true
    }

    private func closeAddSheet() {
        isEditorFocused = false
        showAddSheet = false
        addInput = ""
    }

    private func submitAddAndContinue() {
        let values = CommonNamesBatchParser.parse(addInput)
        guard !values.isEmpty else {
            showMessage(NSLocalizedString("common_places_batch_empty", value: "请输入至少一个有效地点", comment: ""))
            return
        }
        let result = manager.addPlacesBatch(values)
        reload()
        addInput = ""
        if result.added == 1 && result.skipped == 0 {
            showMessage(NSLocalizedString("common_places_added", value: "已添加", comment: ""))
        } else {
            showMessage(String(format: NSLocalizedString(
                "common_places_batch_result",
                value: "已添加 %d 个，跳过 %d 个",
                comment: ""
            ), result.added, result.skipped))
        }
    }

    private func openEditSheet(_ place: CommonPlace) {
        editingPlace = place
        editInput = place.name
        showEditSheet = true
    }

    private func closeEditSheet() {
        isEditorFocused = false
        showEditSheet = false
        editingPlace = nil
        editInput = ""
    }

    private func submitEdit() {
        guard let editingPlace else { return }
        do {
            try manager.updatePlace(id: editingPlace.id, name: editInput)
            reload()
            closeEditSheet()
            showMessage(NSLocalizedString("common_places_updated", value: "已更新", comment: ""))
        } catch CommonPlacesError.emptyName {
            showMessage(NSLocalizedString("common_places_empty_name", value: "地点不能为空", comment: ""))
        } catch CommonPlacesError.duplicateName {
            showMessage(NSLocalizedString("common_places_already_exists", value: "该地点已存在", comment: ""))
        } catch {
            showMessage(NSLocalizedString("common_places_save_failed", value: "保存失败", comment: ""))
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func toggleSelectAll() {
        let ids = Set(filteredPlaces.map(\.id))
        if allFilteredSelected {
            selectedIds.subtract(ids)
        } else {
            selectedIds.formUnion(ids)
        }
    }

    private func deleteSelected() {
        let toDelete = selectedIds
        guard !toDelete.isEmpty else { return }
        let wasSelectAll = allFilteredSelected
        for id in toDelete {
            manager.deletePlace(id: id)
        }
        selectedIds.removeAll()
        reload()
        if wasSelectAll {
            isEditMode = false
        }
        showMessage(NSLocalizedString("common_places_deleted", value: "已删除", comment: ""))
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

struct CommonPlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (CommonPlace) -> Void

    private var places: [CommonPlace] { CommonPlacesManager.shared.getAllPlaces() }

    var body: some View {
        NavigationStack {
            Group {
                if places.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("common_places_no_records", value: "暂无常用地点", comment: ""),
                        systemImage: "mappin.and.ellipse",
                        description: Text(NSLocalizedString("common_places_empty_hint", value: "可在首页的“常用地点”中添加", comment: ""))
                    )
                } else {
                    List(places) { place in
                        Button {
                            CommonPlacesManager.shared.recordUsage(place.name)
                            onSelect(place)
                        } label: {
                            Label(place.name, systemImage: "mappin.circle")
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("common_places_select", value: "选择地点", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
