import SwiftUI

private enum BookingNamePickerTarget: Identifiable {
    case participant(Int)
    case team1
    case team2
    case redTop
    case redBottom
    case blueTop
    case blueBottom

    var id: String {
        switch self {
        case .participant(let index): return "participant-\(index)"
        case .team1: return "team1"
        case .team2: return "team2"
        case .redTop: return "redTop"
        case .redBottom: return "redBottom"
        case .blueTop: return "blueTop"
        case .blueBottom: return "blueBottom"
        }
    }
}

struct CreateBookingPage: View {
    @Environment(\.dismiss) private var dismiss

    var initialBooking: LocalBooking? = nil
    var copyingBooking: LocalBooking? = nil
    var onCreated: (() -> Void)? = nil

    @State private var sportType: BookingSportType = .badminton
    @State private var billiardsFormat: BookingBilliardsFormat = .standard
    @State private var dateTime: Date = defaultBookingDateTime()
    @State private var durationMinutes: Int = LocalBooking.defaultDurationMinutes
    @State private var location: String = ""
    @State private var participantRows: [String] = ["", ""]
    @State private var matchMode: BookingMatchMode = .singles
    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var redTopName: String = ""
    @State private var redBottomName: String = ""
    @State private var blueTopName: String = ""
    @State private var blueBottomName: String = ""
    @State private var maxSets: Int?
    @State private var pointsPerSet: Int?
    @State private var tieBreakPoints: Int?
    @State private var tennisDeuceMode: String?
    @State private var notes: String = ""
    @State private var reminders: Set<Int> = Set(LocalBooking.defaultReminderMinutes)
    @State private var didLoadInitial = false
    @State private var ignoresNextDateReconciliation = false
    @State private var showCommonPlaces = false
    @State private var namePickerTarget: BookingNamePickerTarget?
    @State private var saveErrorMessage: String?

    private var isEditing: Bool { initialBooking != nil }

    private var selectableSportTypes: [BookingSportType] {
        if isEditing, sportType == .other {
            return BookingSportType.creatableCases + [.other]
        }
        return BookingSportType.creatableCases
    }

    private var supportsNamePreset: Bool {
        sportType != .other
    }

    private var isDoubles: Bool {
        sportType.supportsSinglesAndDoubles && matchMode == .doubles
    }

    var body: some View {
        NavigationStack {
            Form {
                scheduleSection
                locationSection
                participantsSection

                if supportsNamePreset {
                    startPresetSection
                }

                if !ruleSetOptions.isEmpty || !pointOptions.isEmpty || sportType == .tennis {
                    rulePresetSection
                }

                reminderSection

                Section(NSLocalizedString("schedule_notes", value: "备注", comment: "")) {
                    TextEditor(text: Binding(
                        get: { notes },
                        set: { notes = String($0.prefix(200)) }
                    ))
                    .frame(minHeight: 80)
                }
            }
            .frame(maxWidth: Theme.focusedContentMaxWidth)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundColor)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) { saveBooking() }
                        .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: applyInitialBookingIfNeeded)
            .onChange(of: sportType) { oldValue, newValue in
                guard didLoadInitial, oldValue != newValue else { return }
                billiardsFormat = .standard
                matchMode = .singles
                team1Name = ""
                team2Name = ""
                redTopName = ""
                redBottomName = ""
                blueTopName = ""
                blueBottomName = ""
                maxSets = nil
                pointsPerSet = nil
                tieBreakPoints = nil
                tennisDeuceMode = nil
            }
            .onChange(of: dateTime) { oldValue, newValue in
                if ignoresNextDateReconciliation {
                    ignoresNextDateReconciliation = false
                    normalizeReminderSelection()
                    return
                }
                if !Calendar.current.isDate(oldValue, inSameDayAs: newValue) {
                    let reconciled = reconciledBookingDateTime(newValue)
                    if reconciled != newValue {
                        dateTime = reconciled
                        return
                    }
                }
                normalizeReminderSelection()
            }
            .analyticsScreen(.createBookingPage, source: isEditing ? .bookingDetailPage : .scheduleList)
            .alert(
                NSLocalizedString("schedule_save_failed", value: "无法保存预约", comment: ""),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button(NSLocalizedString("confirm", comment: ""), role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .sheet(isPresented: $showCommonPlaces) {
                CommonPlacePickerView { place in
                    location = String(place.name.prefix(48))
                    showCommonPlaces = false
                }
            }
            .sheet(item: $namePickerTarget) { target in
                CommonNameSelectorDialog(nameType: nameType(for: target)) { name in
                    applyCommonName(name, to: target)
                    namePickerTarget = nil
                }
            }
        }
    }

    private var navigationTitle: String {
        if isEditing {
            return NSLocalizedString("schedule_edit", value: "编辑", comment: "")
        }
        if copyingBooking != nil {
            return NSLocalizedString("schedule_copy_booking", value: "复制预约", comment: "")
        }
        return NSLocalizedString("schedule_create_title", value: "预约新球局", comment: "")
    }

    private var scheduleSection: some View {
        Section {
            Picker(NSLocalizedString("schedule_sport", value: "项目", comment: ""), selection: $sportType) {
                ForEach(selectableSportTypes) { type in
                    Text("\(type.icon) \(type.displayName)").tag(type)
                }
            }

            if sportType == .billiards {
                Picker(NSLocalizedString("schedule_billiards_mode", value: "台球玩法", comment: ""), selection: $billiardsFormat) {
                    ForEach(BookingBilliardsFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            DatePicker(
                NSLocalizedString("schedule_datetime", value: "时间", comment: ""),
                selection: $dateTime,
                displayedComponents: [.date, .hourAndMinute]
            )

            HStack {
                Text(NSLocalizedString("schedule_duration", value: "时长", comment: ""))
                Spacer()
                durationButton(systemName: "minus.circle", delta: -LocalBooking.durationStepMinutes)
                Text(String(format: NSLocalizedString("schedule_duration_short", value: "%d分钟", comment: ""), durationMinutes))
                    .font(.body)
                    .foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 72)
                    .multilineTextAlignment(.center)
                durationButton(systemName: "plus.circle", delta: LocalBooking.durationStepMinutes)
            }
        }
    }

    private var locationSection: some View {
        Section(NSLocalizedString("schedule_location", value: "地点", comment: "")) {
            HStack {
                TextField(
                    NSLocalizedString("schedule_location_placeholder", value: "输入地点", comment: ""),
                    text: Binding(get: { location }, set: { location = String($0.prefix(48)) })
                )
                Button { showCommonPlaces = true } label: {
                    Image(systemName: "location.circle")
                        .foregroundColor(Theme.primaryDark)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("schedule_pick_common_place", value: "选择常用地点", comment: ""))
            }
        }
    }

    private var participantsSection: some View {
        Section {
            ForEach(participantRows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(
                        String(format: NSLocalizedString("schedule_participant_placeholder", value: "参与者 %d", comment: ""), index + 1),
                        text: Binding(
                            get: { participantRows[index] },
                            set: { participantRows[index] = String($0.prefix(24)) }
                        )
                    )
                    Button { namePickerTarget = .participant(index) } label: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(.plain)

                    if index >= 2 {
                        Button(role: .destructive) { participantRows.remove(at: index) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if participantRows.count < LocalBooking.maximumParticipants {
                Button {
                    participantRows.append("")
                } label: {
                    Label(
                        NSLocalizedString("schedule_add_participant", value: "添加参与者", comment: ""),
                        systemImage: "plus.circle"
                    )
                }
            }
        } header: {
            Text(NSLocalizedString("schedule_participants", value: "参与者", comment: ""))
        } footer: {
            Text(String(format: NSLocalizedString("schedule_participants_limit", value: "最多 %d 人，重复姓名会自动合并", comment: ""), LocalBooking.maximumParticipants))
        }
    }

    private var startPresetSection: some View {
        Section(NSLocalizedString("schedule_start_preset", value: "开局预设", comment: "")) {
            if sportType.supportsSinglesAndDoubles {
                Picker(NSLocalizedString("schedule_match_mode", value: "比赛模式", comment: ""), selection: $matchMode) {
                    Text(NSLocalizedString("singles", value: "单打", comment: "")).tag(BookingMatchMode.singles)
                    Text(NSLocalizedString("doubles", value: "双打", comment: "")).tag(BookingMatchMode.doubles)
                }
                .pickerStyle(.segmented)
            }

            if isDoubles {
                presetNameField(
                    NSLocalizedString("schedule_red_top", value: "红方选手 1", comment: ""),
                    text: $redTopName,
                    target: .redTop
                )
                presetNameField(
                    NSLocalizedString("schedule_red_bottom", value: "红方选手 2", comment: ""),
                    text: $redBottomName,
                    target: .redBottom
                )
                presetNameField(
                    NSLocalizedString("schedule_blue_top", value: "蓝方选手 1", comment: ""),
                    text: $blueTopName,
                    target: .blueTop
                )
                presetNameField(
                    NSLocalizedString("schedule_blue_bottom", value: "蓝方选手 2", comment: ""),
                    text: $blueBottomName,
                    target: .blueBottom
                )
            } else {
                presetNameField(sideOneLabel, text: $team1Name, target: .team1)
                presetNameField(sideTwoLabel, text: $team2Name, target: .team2)
            }
        }
    }

    private var rulePresetSection: some View {
        Section(NSLocalizedString("schedule_rules_preset", value: "规则预设（可选）", comment: "")) {
            if !ruleSetOptions.isEmpty {
                optionalIntPicker(
                    title: sportType == .billiards
                        ? NSLocalizedString("schedule_target_rounds", value: "目标局数", comment: "")
                        : NSLocalizedString("schedule_max_sets", value: "局/盘数", comment: ""),
                    selection: $maxSets,
                    options: ruleSetOptions
                )
            }
            if !pointOptions.isEmpty {
                optionalIntPicker(
                    title: NSLocalizedString("schedule_points_per_set", value: "每局分数", comment: ""),
                    selection: $pointsPerSet,
                    options: pointOptions
                )
            }
            if sportType == .tennis {
                optionalIntPicker(
                    title: NSLocalizedString("schedule_tiebreak_points", value: "抢七分数", comment: ""),
                    selection: $tieBreakPoints,
                    options: [7, 10]
                )
                Picker(NSLocalizedString("schedule_deuce_mode", value: "平分规则", comment: ""), selection: $tennisDeuceMode) {
                    Text(NSLocalizedString("schedule_use_project_default", value: "项目默认", comment: "")).tag(String?.none)
                    Text(NSLocalizedString("tennis_deuce_option_advantage", value: "有占先", comment: "")).tag(String?.some("advantage"))
                    Text(NSLocalizedString("tennis_deuce_option_no_ad", value: "无占先", comment: "")).tag(String?.some("no_ad"))
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            HStack(spacing: 8) {
                Text(NSLocalizedString("schedule_reminders", value: "提醒", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                SystemHelpButton(
                    title: NSLocalizedString("schedule_reminder_help_title", value: "提醒说明", comment: ""),
                    message: NSLocalizedString(
                        "schedule_reminder_help_message",
                        value: "这些提醒为本地通知，由设备在预约时间前触发。\n- 需开启系统通知权限\n- 修改或取消预约时，相关提醒会同步更新或移除",
                        comment: ""
                    ),
                    iconFontSize: 16,
                    accessibilityIdentifier: "schedule_reminder_help"
                )
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(LocalBooking.reminderOptions, id: \.self) { minute in
                    reminderChip(minute: minute)
                }
            }
        }
    }

    private var sideOneLabel: String {
        sportType.usesTeamNames
            ? NSLocalizedString("schedule_team1_name", value: "队伍 1", comment: "")
            : NSLocalizedString("schedule_side1_name", value: "选手/一方名称", comment: "")
    }

    private var sideTwoLabel: String {
        sportType.usesTeamNames
            ? NSLocalizedString("schedule_team2_name", value: "队伍 2", comment: "")
            : NSLocalizedString("schedule_side2_name", value: "选手/另一方名称", comment: "")
    }

    private var ruleSetOptions: [Int] {
        switch sportType {
        case .badminton, .pingpong, .tennis, .pickleball:
            return [1, 3, 5, 7]
        case .billiards:
            switch billiardsFormat {
            case .eightBall: return [5, 7, 9, 11]
            case .snooker: return [1, 3, 5, 7, 9]
            default: return []
            }
        default:
            return []
        }
    }

    private var pointOptions: [Int] {
        switch sportType {
        case .badminton: return [11, 15, 21]
        case .pingpong: return [5, 7, 9, 11]
        case .pickleball: return [11, 15, 21]
        default: return []
        }
    }

    private func durationButton(systemName: String, delta: Int) -> some View {
        let next = durationMinutes + delta
        let enabled = (LocalBooking.minimumDurationMinutes...LocalBooking.maximumDurationMinutes).contains(next)
        return Button {
            guard enabled else { return }
            durationMinutes = next
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 26))
                .foregroundStyle(enabled ? Theme.primaryDark : Theme.textSecondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func optionalIntPicker(
        title: String,
        selection: Binding<Int?>,
        options: [Int]
    ) -> some View {
        Picker(title, selection: selection) {
            Text(NSLocalizedString("schedule_use_project_default", value: "项目默认", comment: "")).tag(Int?.none)
            ForEach(options, id: \.self) { value in
                Text("\(value)").tag(Int?.some(value))
            }
        }
    }

    private func presetNameField(
        _ placeholder: String,
        text: Binding<String>,
        target: BookingNamePickerTarget
    ) -> some View {
        HStack {
            TextField(
                placeholder,
                text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(24)) })
            )
            Button { namePickerTarget = target } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func reminderChip(minute: Int) -> some View {
        let enabled = enabledBookingReminderOptions(for: dateTime).contains(minute)
        let selected = reminders.contains(minute)
        return Button {
            guard enabled else { return }
            if selected { reminders.remove(minute) } else { reminders.insert(minute) }
        } label: {
            Text(reminderLabel(minute))
                .font(.system(size: Theme.fontBody2, weight: selected ? .medium : .regular))
                .foregroundColor(enabled ? (selected ? .white : Theme.textPrimary) : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(enabled ? (selected ? Theme.primaryDark : Theme.dialogControlBackground) : Theme.dialogControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(enabled ? (selected ? Theme.primaryDark : Theme.divider) : Theme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(reminderLabel(minute))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .opacity(enabled ? 1 : 0.85)
    }

    private func reminderLabel(_ minute: Int) -> String {
        if minute >= 60 {
            return String(format: NSLocalizedString("schedule_reminder_hours_before", value: "%d 小时前", comment: ""), minute / 60)
        }
        return String(format: NSLocalizedString("schedule_reminder_minutes_before", value: "%d 分钟前", comment: ""), minute)
    }

    private func normalizeReminderSelection(now: Date = Date()) {
        reminders.formIntersection(enabledBookingReminderOptions(for: dateTime, now: now))
    }

    private func saveBooking() {
        let now = Date()
        guard dateTime > now else {
            saveErrorMessage = NSLocalizedString("schedule_future_time_required", value: "请选择未来的预约时间。", comment: "")
            return
        }

        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            saveErrorMessage = NSLocalizedString("schedule_location_required", value: "请填写地点。", comment: "")
            return
        }

        normalizeReminderSelection(now: now)
        let original = initialBooking
        let source = original ?? copyingBooking
        let booking = LocalBooking(
            id: original?.id ?? UUID().uuidString,
            sportType: sportType,
            dateTime: dateTime,
            durationMinutes: durationMinutes,
            location: trimmedLocation,
            gameFormat: sportType == .billiards ? billiardsFormat.rawValue : "",
            locationLat: source?.locationLat,
            locationLng: source?.locationLng,
            matchMode: sportType.supportsSinglesAndDoubles ? matchMode : nil,
            team1Name: cleaned(team1Name),
            team2Name: cleaned(team2Name),
            redTopName: isDoubles ? cleaned(redTopName) : nil,
            redBottomName: isDoubles ? cleaned(redBottomName) : nil,
            blueTopName: isDoubles ? cleaned(blueTopName) : nil,
            blueBottomName: isDoubles ? cleaned(blueBottomName) : nil,
            maxSets: maxSets,
            pointsPerSet: pointsPerSet,
            tieBreakPoints: tieBreakPoints,
            tennisDeuceMode: sportType == .tennis ? tennisDeuceMode : nil,
            participantNames: participantRows,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            reminderMinutes: Array(reminders),
            status: original?.status ?? .pending,
            createdAt: original?.createdAt ?? now,
            updatedAt: now,
            completedAt: original?.completedAt,
            calendarEventId: original?.calendarEventId
        )

        let saved = LocalBookingManager.shared.upsertBooking(booking)
        AppAnalytics.track(.submitForm, parameters: [
            .contentType: .string(isEditing ? "booking_update" : "booking_create"),
            .gameType: .string(booking.resolvedGameType?.analyticsIdentifier ?? sportType.rawValue),
            .result: .string(saved ? AnalyticsResult.success.rawValue : AnalyticsResult.failed.rawValue)
        ])
        guard saved else {
            saveErrorMessage = NSLocalizedString("schedule_save_failed_message", value: "本地数据写入失败，请稍后重试。", comment: "")
            return
        }

        CommonPlacesManager.shared.savePlaceIfNeeded(trimmedLocation)
        saveCommonNames(from: booking)
        onCreated?()
        dismiss()
    }

    private func applyInitialBookingIfNeeded() {
        guard !didLoadInitial else { return }
        defer { didLoadInitial = true }

        guard let booking = initialBooking ?? copyingBooking else {
            normalizeReminderSelection()
            return
        }

        sportType = copyingBooking != nil && booking.sportType == .other ? .badminton : booking.sportType
        billiardsFormat = booking.billiardsFormat
        if copyingBooking != nil, booking.dateTime <= Date() {
            ignoresNextDateReconciliation = true
            dateTime = defaultBookingDateTime()
        } else {
            ignoresNextDateReconciliation = true
            dateTime = booking.dateTime
        }
        durationMinutes = LocalBooking.normalizedDuration(booking.durationMinutes)
        location = booking.location
        matchMode = booking.matchMode ?? .singles
        team1Name = booking.team1Name ?? ""
        team2Name = booking.team2Name ?? ""
        redTopName = booking.redTopName ?? ""
        redBottomName = booking.redBottomName ?? ""
        blueTopName = booking.blueTopName ?? ""
        blueBottomName = booking.blueBottomName ?? ""
        maxSets = booking.maxSets
        pointsPerSet = booking.pointsPerSet
        tieBreakPoints = booking.tieBreakPoints
        tennisDeuceMode = booking.tennisDeuceMode
        participantRows = booking.participantNames
        while participantRows.count < 2 { participantRows.append("") }
        participantRows = Array(participantRows.prefix(LocalBooking.maximumParticipants))
        notes = booking.notes
        reminders = Set(booking.reminderMinutes)
        if copyingBooking != nil, reminders.isEmpty {
            reminders = Set(LocalBooking.defaultReminderMinutes)
        }
        normalizeReminderSelection()
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nameType(for target: BookingNamePickerTarget) -> NameType {
        if sportType.usesTeamNames {
            switch target {
            case .team1, .team2:
                return .team
            default:
                break
            }
        }
        switch target {
        case .participant, .team1, .team2, .redTop, .redBottom, .blueTop, .blueBottom:
            return .player
        }
    }

    private func applyCommonName(_ name: String, to target: BookingNamePickerTarget) {
        switch target {
        case .participant(let index):
            guard participantRows.indices.contains(index) else { return }
            participantRows[index] = name
        case .team1: team1Name = name
        case .team2: team2Name = name
        case .redTop: redTopName = name
        case .redBottom: redBottomName = name
        case .blueTop: blueTopName = name
        case .blueBottom: blueBottomName = name
        }
    }

    private func saveCommonNames(from booking: LocalBooking) {
        let playerNames = booking.participantNames + [
            booking.redTopName,
            booking.redBottomName,
            booking.blueTopName,
            booking.blueBottomName
        ].compactMap { $0 }
        let sideNames = [booking.team1Name, booking.team2Name].compactMap { $0 }

        Task {
            for name in playerNames {
                await CommonNamesManager.shared.saveNameIfNeeded(name, .player)
            }
            for name in sideNames {
                await CommonNamesManager.shared.saveNameIfNeeded(name, booking.sportType.usesTeamNames ? .team : .player)
            }
        }
    }
}
