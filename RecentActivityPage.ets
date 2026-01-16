import { Colors, Spacing } from '../../common/theme';
import { ActivityType, RecentActivity, GameType, GameTypeIcons, GameTypeNames, PlayerScore } from '../../model/types';
import { RecentActivityCard } from '../../components/RecentActivityCard';
import { RecordsViewModel, RecordGroup } from '../../viewmodel/recordsViewModel';
import { GameRecordSummary, GameTypeNames as RecordGameTypeNames, PlayerTypeNames, formatDuration, formatDate } from '../../model/timerRecord';
import { timerRecordManager } from '../../managers/timerRecordManager';
import { scoreboardRecordsViewModel, ScoreboardRecordsViewModel, ScoreboardRecordGroup } from '../../viewmodel/scoreboardRecordsViewModel';
import { ScoreboardRecordSummary, TeamType, formatDuration as formatScoreboardDuration } from '../../model/scoreboardRecord';
import { scoreboardRecordManager } from '../../managers/scoreboardRecordManager';
import { CustomConfirmDialog } from '../../components/CustomConfirmDialog';
import router from '@ohos.router';
import deviceInfo from '@ohos.deviceInfo';
import common from '@ohos.app.ability.common';
import { promptAction } from '@kit.ArkUI';

// 混合日期分组接口
interface MixedDateGroup {
    date: string;
    displayDate: string;
    timerRecords: GameRecordSummary[];
    scoreboardRecords: ScoreboardRecordSummary[];
}

// 混合记录项接口
interface MixedRecordItem {
    type: string;
    record: GameRecordSummary | ScoreboardRecordSummary;
}

// 日期记录映射接口
interface DateRecordMap {
    timerRecords: GameRecordSummary[];
    scoreboardRecords: ScoreboardRecordSummary[];
}

@Entry
@Component
export struct RecentActivityPage {
    @Prop recentActivities: Array<RecentActivity> = [];
    onActivitySelected?: (activity: RecentActivity) => void;

    @State private isTablet: boolean = false;
    @State private screenWidth: number = 0;
    @State private currentTab: number = 0; // 0: 全部, 1: 计分, 2: 计时

    // 计时记录相关状态
    @State private records: GameRecordSummary[] = [];
    @State private groupedRecords: RecordGroup[] = [];
    @State private isLoadingRecords: boolean = false;

    // 计分板记录相关状态
    @State private scoreboardRecords: ScoreboardRecordSummary[] = [];
    @State private groupedScoreboardRecords: ScoreboardRecordGroup[] = [];
    @State private isLoadingScoreboardRecords: boolean = false;

    // 搜索和筛选状态
    @State private searchText: string = '';
    @State private selectedTimeFilter: string = 'all'; // 'today', 'week', 'month', 'all'
    @State private selectedGameType: GameType | 'all' = 'all';
    @State private showFilterDialog: boolean = false;
    @State private isEditMode: boolean = false;
    @State private isDeleting: boolean = false; // 删除加载状态
    @State private isFiltering: boolean = false; // 筛选加载状态

    private recordsViewModel: RecordsViewModel = RecordsViewModel.getInstance();
    private scoreboardViewModel: ScoreboardRecordsViewModel = scoreboardRecordsViewModel;
    private deleteDialogController?: CustomDialogController;

    private updateListener: () => void = () => {
        this.updateRecordsUI();
    };

    private updateScoreboardListener: () => void = () => {
        this.updateScoreboardRecordsUI();
    };

    private searchDebounceTimer: number = -1;

    aboutToAppear(): void {
        this.detectDeviceType();

        // 初始化比赛记录管理器
        try {
            const uiContext = getContext(this) as common.UIAbilityContext;
            timerRecordManager.init(uiContext).catch((error: Error) => {
                console.error('[RecentActivityPage] Failed to initialize timerRecordManager:', error);
            });
            scoreboardRecordManager.init(uiContext).catch((error: Error) => {
                console.error('[RecentActivityPage] Failed to initialize scoreboardRecordManager:', error);
            });
        } catch (error) {
            console.error('[RecentActivityPage] Initialization error:', error);
        }

        // 添加记录监听器
        this.recordsViewModel.addListener(this.updateListener);
        this.scoreboardViewModel.addListener(this.updateScoreboardListener);

        // 加载计时记录和计分板记录
        this.recordsViewModel.loadRecordsInBackground();
        this.scoreboardViewModel.loadRecordsInBackground();
    }

    aboutToDisappear(): void {
        // 移除监听器
        this.recordsViewModel.removeListener(this.updateListener);
        this.scoreboardViewModel.removeListener(this.updateScoreboardListener);

        // 清理搜索防抖定时器
        if (this.searchDebounceTimer !== -1) {
            clearTimeout(this.searchDebounceTimer);
            this.searchDebounceTimer = -1;
        }
    }

    onPageShow(): void {
        // 刷新计时记录和计分板记录
        this.recordsViewModel.refreshRecords();
        this.scoreboardViewModel.refreshRecords();
    }

    private updateRecordsUI(): void {
        this.records = this.recordsViewModel.getRecords();
        this.groupedRecords = this.recordsViewModel.getGroupedRecords();
        this.isLoadingRecords = this.recordsViewModel.getIsLoading();
    }

    private updateScoreboardRecordsUI(): void {
        this.scoreboardRecords = this.scoreboardViewModel.getRecords();
        this.groupedScoreboardRecords = this.scoreboardViewModel.getGroupedRecords();
        this.isLoadingScoreboardRecords = this.scoreboardViewModel.getIsLoading();
    }

    private detectDeviceType(): void {
        try {
            const type = deviceInfo.deviceType;
            this.isTablet = type === 'tablet' || type === '2in1';
        } catch (error) {
            console.error('[RecentActivityPage] Failed to detect device type:', error);
            this.isTablet = false;
        }
    }

    private getFilteredActivities(): Array<RecentActivity> {
        if (!this.recentActivities) {
            return [];
        }
        return [...this.recentActivities].sort((a, b) => b.timestamp - a.timestamp);
    }

    private getScoreboardActivities(): Array<RecentActivity> {
        return this.getFilteredActivities().filter(activity => activity.activityType === ActivityType.SCOREBOARD);
    }

    // 检查搜索结果并显示 toast
    private checkSearchResults(): void {
        // 清除之前的定时器
        if (this.searchDebounceTimer !== -1) {
            clearTimeout(this.searchDebounceTimer);
        }

        // 如果搜索文本为空，不检查
        if (this.searchText.trim().length === 0) {
            return;
        }

        // 使用防抖，500ms 后检查结果
        this.searchDebounceTimer = setTimeout(() => {
            const filteredTimerRecords = this.applyFilters(this.records);
            const filteredScoreboardRecords = this.applyFiltersToScoreboard(this.scoreboardRecords);

            const hasResults = (this.currentTab === 0 && (filteredTimerRecords.length > 0 || filteredScoreboardRecords.length > 0)) ||
                (this.currentTab === 1 && filteredScoreboardRecords.length > 0) ||
                (this.currentTab === 2 && filteredTimerRecords.length > 0);

            if (!hasResults && this.searchText.trim().length > 0) {
                promptAction.showToast({
                    message: $r('app.string.no_search_results'),
                    duration: 2000
                });
            }
        }, 500);
    }

    // 应用搜索和筛选
    private applyFilters(records: GameRecordSummary[]): GameRecordSummary[] {
        let filtered = [...records];

        // 时间筛选
        if (this.selectedTimeFilter !== 'all') {
            const startOfToday = new Date().setHours(0, 0, 0, 0);
            const startOfWeek = startOfToday - 7 * 24 * 60 * 60 * 1000;
            const startOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime();

            filtered = filtered.filter(record => {
                if (this.selectedTimeFilter === 'today') {
                    return record.timestamp >= startOfToday;
                } else if (this.selectedTimeFilter === 'week') {
                    return record.timestamp >= startOfWeek;
                } else if (this.selectedTimeFilter === 'month') {
                    return record.timestamp >= startOfMonth;
                }
                return true;
            });
        }

        // 比赛类型筛选
        if (this.selectedGameType !== 'all') {
            filtered = filtered.filter(record => record.gameType === this.selectedGameType);
        }

        // 搜索文本（玩家名称）
        if (this.searchText.trim().length > 0) {
            const searchLower = this.searchText.toLowerCase().trim();
            filtered = filtered.filter(record => {
                // 搜索比赛类型名称
                const gameTypeName = RecordGameTypeNames[record.gameType] || '';
                if (gameTypeName.toLowerCase().includes(searchLower)) {
                    return true;
                }
                return false;
            });
        }

        return filtered;
    }

    // 应用搜索和筛选（计分板记录）
    private applyFiltersToScoreboard(records: ScoreboardRecordSummary[]): ScoreboardRecordSummary[] {
        let filtered = [...records];

        // 时间筛选
        if (this.selectedTimeFilter !== 'all') {
            const startOfToday = new Date().setHours(0, 0, 0, 0);
            const startOfWeek = startOfToday - 7 * 24 * 60 * 60 * 1000;
            const startOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime();

            filtered = filtered.filter(record => {
                if (this.selectedTimeFilter === 'today') {
                    return record.timestamp >= startOfToday;
                } else if (this.selectedTimeFilter === 'week') {
                    return record.timestamp >= startOfWeek;
                } else if (this.selectedTimeFilter === 'month') {
                    return record.timestamp >= startOfMonth;
                }
                return true;
            });
        }

        // 比赛类型筛选
        if (this.selectedGameType !== 'all') {
            filtered = filtered.filter(record => record.gameType === this.selectedGameType);
        }

        // 搜索文本（队伍名称）
        if (this.searchText.trim().length > 0) {
            const searchLower = this.searchText.toLowerCase().trim();
            filtered = filtered.filter(record => {
                // 搜索队伍名称
                const team1Name = (record.team1Name || '').toLowerCase();
                const team2Name = (record.team2Name || '').toLowerCase();
                if (team1Name.includes(searchLower) || team2Name.includes(searchLower)) {
                    return true;
                }
                // 搜索比赛类型名称
                const gameTypeName = GameTypeNames[record.gameType] || '';
                if (gameTypeName.toLowerCase().includes(searchLower)) {
                    return true;
                }
                if (record.extraData?.players) {
                    const matched = record.extraData.players.some(player => player.name.toLowerCase().includes(searchLower));
                    if (matched) {
                        return true;
                    }
                }
                return false;
            });
        }

        return filtered;
    }

    private getMultiScoreboardPlayers(record: ScoreboardRecordSummary): PlayerScore[] {
        if (record.extraData?.players && record.extraData.players.length > 0) {
            return [...record.extraData.players]
                .map((player): PlayerScore => ({ name: player.name, score: player.finalScore }))
                .sort((a, b) => b.score - a.score);
        }

        const players: PlayerScore[] = [];
        if (record.team1Name) {
            players.push({ name: record.team1Name, score: record.team1FinalScore });
        }
        if (record.team2Name) {
            players.push({ name: record.team2Name, score: record.team2FinalScore });
        }
        return players;
    }

    private getMultiScoreboardPlayerCount(record: ScoreboardRecordSummary): number {
        if (record.extraData?.playerCount) {
            return record.extraData.playerCount;
        }
        return this.getMultiScoreboardPlayers(record).length;
    }

    // 获取本地化的游戏类型名称
    private getGameNameResource(gameType: GameType): Resource {
        switch (gameType) {
            case GameType.FOOTBALL:
                return $r('app.string.tab_football');
            case GameType.BASKETBALL:
                return $r('app.string.tab_basketball');
            case GameType.VOLLEYBALL:
                return $r('app.string.tab_volleyball');
            case GameType.BADMINTON:
                return $r('app.string.tab_badminton');
            case GameType.PINGPONG:
                return $r('app.string.tab_pingpong');
            case GameType.TENNIS:
                return $r('app.string.tab_tennis');
            case GameType.BOXING:
                return $r('app.string.tab_boxing');
            case GameType.BILLIARDS:
                return $r('app.string.tab_billiards');
            case GameType.DOUDIZHU:
                return $r('app.string.tab_doudizhu');
            case GameType.GUANDAN:
                return $r('app.string.tab_guandan');
            case GameType.SIMPLE_SCORE:
                return $r('app.string.tab_simple_score');
            case GameType.MULTI_SCOREBOARD:
                return $r('app.string.tab_multi_score');
            case GameType.GO:
                return $r('app.string.timer_go');
            case GameType.XIANGQI:
                return $r('app.string.timer_xiangqi');
            case GameType.CHESS:
                return $r('app.string.timer_chess');
            default:
                return $r('app.string.tab_football');
        }
    }


    private handleActivityClick(activity: RecentActivity): void {
        if (this.onActivitySelected) {
            this.onActivitySelected(activity);
            return;
        }

        // 导航到对应的页面
        if (activity.targetRoute) {
            router.pushUrl({
                url: activity.targetRoute
            }).catch((error: Error) => {
                console.error(`[RecentActivityPage] Failed to navigate to ${activity.targetRoute}:`, error);
            });
        } else {
            // 根据活动类型导航到对应标签页
            if (activity.activityType === ActivityType.SCOREBOARD) {
                router.back();
                // 这里可以触发回到首页并切换到计分页
            } else if (activity.activityType === ActivityType.TIMER) {
                router.back();
                // 这里可以触发回到首页并切换到计时页
            }
        }
    }

    // 获取所有记录并按日期分组
    private getAllRecordsByDate(): MixedDateGroup[] {
        // 应用筛选
        const filteredTimerRecords = this.applyFilters(this.records);
        const filteredScoreboardRecords = this.applyFiltersToScoreboard(this.scoreboardRecords);

        // 创建日期到记录的映射
        const dateMap = new Map<string, DateRecordMap>();

        // 添加计时记录
        filteredTimerRecords.forEach(record => {
            if (!dateMap.has(record.date)) {
                const mapItem: DateRecordMap = { timerRecords: [], scoreboardRecords: [] };
                dateMap.set(record.date, mapItem);
            }
            dateMap.get(record.date)!.timerRecords.push(record);
        });

        // 添加计分板记录
        filteredScoreboardRecords.forEach(record => {
            if (!dateMap.has(record.date)) {
                const mapItem: DateRecordMap = { timerRecords: [], scoreboardRecords: [] };
                dateMap.set(record.date, mapItem);
            }
            dateMap.get(record.date)!.scoreboardRecords.push(record);
        });

        // 转换为数组并排序
        const result: MixedDateGroup[] = [];
        const today = new Date();
        const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, '0')}-${String(yesterday.getDate()).padStart(2, '0')}`;

        const todayText = getContext().resourceManager.getStringSync($r('app.string.today').id);
        const yesterdayText = getContext().resourceManager.getStringSync($r('app.string.yesterday').id);

        dateMap.forEach((records, date) => {
            let displayDate = date;
            if (date === todayStr) {
                displayDate = todayText;
            } else if (date === yesterdayStr) {
                displayDate = yesterdayText;
            } else {
                const parts = date.split('-');
                if (parts.length === 3) {
                    displayDate = `${parts[1]}-${parts[2]}`;
                }
            }

            const group: MixedDateGroup = {
                date: date,
                displayDate: displayDate,
                timerRecords: records.timerRecords,
                scoreboardRecords: records.scoreboardRecords
            };
            result.push(group);
        });

        // 按日期降序排序
        result.sort((a, b) => b.date.localeCompare(a.date));

        return result;
    }


    // 删除计时记录
    private async deleteTimerRecord(recordId: string): Promise<void> {
        this.deleteDialogController = new CustomDialogController({
            builder: CustomConfirmDialog({
                title: $r('app.string.delete_record_confirm'),
                message: $r('app.string.delete_record_message'),
                confirmText: $r('app.string.delete'),
                cancelText: $r('app.string.cancel'),
                confirmColor: '#FF3B30',
                cancelColor: Colors.primary,
                onConfirm: async () => {
                    try {
                        // 显示删除加载状态
                        this.isDeleting = true;

                        await timerRecordManager.deleteRecord(recordId);

                        // 立即刷新记录并等待完成
                        await this.recordsViewModel.loadRecordsInBackground();

                        // 关闭删除状态
                        this.isDeleting = false;

                        this.updateRecordsUI();

                        promptAction.showToast({
                            message: getContext().resourceManager.getStringSync($r('app.string.record_deleted').id),
                            duration: 1500
                        });
                    } catch (error) {
                        console.error('[RecentActivityPage] Failed to delete timer record:', error);
                        this.isDeleting = false;
                        promptAction.showToast({
                            message: getContext().resourceManager.getStringSync($r('app.string.delete_failed').id),
                            duration: 1500
                        });
                    }
                }
            }),
            alignment: DialogAlignment.Center,
            customStyle: true
        });
        this.deleteDialogController.open();
    }

    // 删除计分板记录
    private async deleteScoreboardRecord(recordId: string): Promise<void> {
        this.deleteDialogController = new CustomDialogController({
            builder: CustomConfirmDialog({
                title: $r('app.string.delete_record_confirm'),
                message: $r('app.string.delete_record_message'),
                confirmText: $r('app.string.delete'),
                cancelText: $r('app.string.cancel'),
                confirmColor: '#FF3B30',
                cancelColor: Colors.primary,
                onConfirm: async () => {
                    try {
                        // 显示删除加载状态
                        this.isDeleting = true;

                        await scoreboardRecordManager.deleteRecord(recordId);

                        // 立即刷新记录并等待完成
                        await this.scoreboardViewModel.loadRecordsInBackground();

                        // 关闭删除状态
                        this.isDeleting = false;

                        this.updateScoreboardRecordsUI();

                        promptAction.showToast({
                            message: getContext().resourceManager.getStringSync($r('app.string.record_deleted').id),
                            duration: 1500
                        });
                    } catch (error) {
                        console.error('[RecentActivityPage] Failed to delete scoreboard record:', error);
                        this.isDeleting = false;
                        promptAction.showToast({
                            message: getContext().resourceManager.getStringSync($r('app.string.delete_failed').id),
                            duration: 1500
                        });
                    }
                }
            }),
            alignment: DialogAlignment.Center,
            customStyle: true
        });
        this.deleteDialogController.open();
    }

    build() {
        Stack() {
            Column() {
                // 顶部标题栏
                this.buildHeader()

                // 主内容区域
                Column() {
                    this.buildContent()
                }
                .layoutWeight(1)
                    .width('100%')
            }
            .width('100%')
                .height('100%')
                .backgroundColor(Colors.homeBackground)
                .onAreaChange((oldValue: Area, newValue: Area) => {
                    this.screenWidth = Number(newValue.width);
                })

            // 筛选对话框（覆盖层）
            this.buildFilterDialog()
        }
        .width('100%')
            .height('100%')
    }

    @Builder
    private buildHeader() {
        Column({ space: 0 }) {
            // 顶部返回和标题
            Row() {
                // 返回按钮
                Button({ type: ButtonType.Circle }) {
                    Image($r('app.media.back'))
                        .width(24)
                        .height(24)
                }
          .width(44)
                    .height(44)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                        router.back();
                    })

                Blank().layoutWeight(1)

                // 标题 - 固定显示"最近记录"
                Text($r('app.string.recent_records'))
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Colors.textPrimary)

                Blank().layoutWeight(1)

                // 编辑模式：显示完成按钮；正常模式：显示更多菜单按钮
                if (this.isEditMode) {
                    // 完成按钮
                    Button({ type: ButtonType.Normal }) {
                        Text($r('app.string.done'))
                            .fontSize(16)
                            .fontColor(Colors.primary)
                    }
                    .width(60)
                        .height(36)
                        .backgroundColor(Color.Transparent)
                        .onClick(() => {
                            this.isEditMode = false;
                        })
                } else {
                    // 更多菜单按钮
                    Button({ type: ButtonType.Circle }) {
                        Text('⋮')
                            .fontSize(24)
                            .fontColor(Colors.textPrimary)
                    }
                    .width(44)
                        .height(44)
                        .backgroundColor(Color.Transparent)
                        .bindMenu([
                            {
                                value: getContext().resourceManager.getStringSync($r('app.string.advanced_filter').id),
                                action: () => {
                                    this.showFilterDialog = true;
                                }
                            },
                            {
                                value: getContext().resourceManager.getStringSync($r('app.string.edit').id),
                                action: () => {
                                    this.isEditMode = true;
                                }
                            }
                        ])
                }
            }
            .width('100%')
                .height(56)
                .padding({ left: Spacing.pageHorizontal, right: Spacing.pageHorizontal })
                .backgroundColor('#000000')

            // 搜索框（编辑模式下隐藏）
            if (!this.isEditMode) {
                Search({ value: this.searchText, placeholder: $r('app.string.search_team_or_game') })
                    .height(40)
                    .backgroundColor(Colors.homeCardBackground)
                    .placeholderColor(Colors.textSecondary)
                    .placeholderFont({ size: 14 })
                    .textFont({ size: 14 })
                    .onChange((value: string) => {
                        this.searchText = value;
                        this.checkSearchResults();
                    })
                    .onSubmit((value: string) => {
                        this.searchText = value;
                    })
                    .margin({ left: Spacing.pageHorizontal, right: Spacing.pageHorizontal, top: 12, bottom: 12 })
                    .constraintSize({
                        maxWidth: this.isTablet ? 600 : undefined
                    })
                    .alignSelf(ItemAlign.Center)
            }

            // Chip样式的Tab切换栏（编辑模式下隐藏）
            if (!this.isEditMode) {
                Row({ space: 8 }) {
                    // 全部 tab
                    Text($r('app.string.all'))
                        .fontSize(14)
                        .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.currentTab === 0 ? '#FFFFFF' : Colors.textSecondary)
                        .backgroundColor(this.currentTab === 0 ? Colors.primary : Colors.homeCardBackground)
                        .borderRadius(16)
                        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                        .onClick(() => {
                            this.currentTab = 0;
                        })

                    // 计分 tab
                    Text($r('app.string.scoreboard'))
                        .fontSize(14)
                        .fontWeight(this.currentTab === 1 ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.currentTab === 1 ? '#FFFFFF' : Colors.textSecondary)
                        .backgroundColor(this.currentTab === 1 ? Colors.primary : Colors.homeCardBackground)
                        .borderRadius(16)
                        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                        .onClick(() => {
                            this.currentTab = 1;
                        })

                    // 计时 tab
                    Text($r('app.string.timer'))
                        .fontSize(14)
                        .fontWeight(this.currentTab === 2 ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.currentTab === 2 ? '#FFFFFF' : Colors.textSecondary)
                        .backgroundColor(this.currentTab === 2 ? Colors.primary : Colors.homeCardBackground)
                        .borderRadius(16)
                        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                        .onClick(() => {
                            this.currentTab = 2;
                        })
                }
                .width('100%')
                    .padding({ left: Spacing.pageHorizontal, right: Spacing.pageHorizontal, bottom: 12 })
                    .constraintSize({
                        maxWidth: this.isTablet ? 600 : undefined
                    })
                    .alignSelf(ItemAlign.Center)
            }
        }
    }

    @Builder
    private buildContent() {
        if (this.currentTab === 0) {
            // 全部 - 显示最近活动和计时记录
            this.buildAllContent()
        } else if (this.currentTab === 1) {
            // 计分 - 只显示计分活动
            this.buildScoreboardContent()
        } else {
            // 计时 - 只显示计时记录
            this.buildTimerRecordsContent()
        }
    }

    @Builder
    private buildAllContent() {
        if (this.isDeleting) {
            // 删除加载中状态
            Column() {
                LoadingProgress()
                    .width(40)
                    .height(40)
                    .color(Colors.primary)
            }
            .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
        } else {
            Scroll() {
                Column({ space: Spacing.componentGap }) {
                    // 合并计时记录和计分板记录，按日期分组显示

                    // 合并所有记录并按日期分组
                    if (this.records.length > 0 || this.scoreboardRecords.length > 0) {
                        ForEach(this.getAllRecordsByDate(), (group: MixedDateGroup, groupIndex: number) => {
                            this.buildMixedDateGroup(group, groupIndex)
                        }, (group: MixedDateGroup) => group.date)
                    } else {
                        this.buildEmptyState()
                    }
                }
                .width('100%')
                    .padding({
                        left: Spacing.pageHorizontal,
                        right: Spacing.pageHorizontal,
                        top: Spacing.componentGap,
                        bottom: 96
                    })
                    .constraintSize({
                        maxWidth: this.isTablet ? 600 : undefined
                    })
                    .alignSelf(ItemAlign.Center)
            }
            .width('100%')
                .height('100%')
                .edgeEffect(EdgeEffect.Spring)
                .scrollBar(BarState.Off)
                .align(Alignment.Top)
        }
    }

    @Builder
    private buildScoreboardContent() {
        if (this.isDeleting || this.isFiltering) {
            // 加载中状态
            Column() {
                LoadingProgress()
                    .width(40)
                    .height(40)
                    .color(Colors.primary)
            }
            .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
        } else if (this.isLoadingScoreboardRecords) {
            // 加载中
            Column({ space: 16 }) {
                Text('⏳')
                    .fontSize(48)

                Text($r('app.string.loading_records'))
                    .fontSize(16)
                    .fontColor(Colors.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 120 })
                .backgroundColor(Colors.homeBackground)
        } else if (this.getScoreboardActivities().length === 0 && this.scoreboardRecords.length === 0) {
            // 空状态
            this.buildEmptyState()
        } else {
            // 显示计分活动和计分板记录
            Scroll() {
                Column({ space: Spacing.componentGap }) {
                    // 显示计分活动
                    if (this.getScoreboardActivities().length > 0) {
                        ForEach(this.getScoreboardActivities(), (activity: RecentActivity, index: number) => {
                            RecentActivityCard({
                                activity,
                                onSelect: (selected: RecentActivity) => {
                                    this.handleActivityClick(selected);
                                }
                            })
                        }, (activity: RecentActivity) => activity.id)
                    }

                    // 显示计分板记录
                    if (this.scoreboardRecords.length > 0) {
                        ForEach(this.groupedScoreboardRecords, (group: ScoreboardRecordGroup, groupIndex: number) => {
                            this.buildScoreboardDateGroup(group, groupIndex)
                        }, (group: ScoreboardRecordGroup) => group.date)
                    }
                }
                .width('100%')
                    .padding({
                        left: Spacing.pageHorizontal,
                        right: Spacing.pageHorizontal,
                        top: Spacing.componentGap,
                        bottom: 96
                    })
                    .constraintSize({
                        maxWidth: this.isTablet ? 600 : undefined
                    })
                    .alignSelf(ItemAlign.Center)
            }
            .width('100%')
                .height('100%')
                .edgeEffect(EdgeEffect.Spring)
                .scrollBar(BarState.Off)
                .align(Alignment.Top)
        }
    }

    @Builder
    private buildTimerRecordsContent() {
        // 计时记录
        this.buildRecordsContent()
    }

    // 获取筛选后的分组记录
    private getFilteredGroupedRecords(): RecordGroup[] {
        const filteredRecords = this.applyFilters(this.records);
        return this.groupTimerRecordsByDate(filteredRecords);
    }

    @Builder
    private buildFilteredRecordsList() {
        if (this.getFilteredGroupedRecords().length === 0) {
            // 筛选后没有记录
            this.buildEmptyState()
        } else {
            Scroll() {
                Column({ space: Spacing.componentGap }) {
                    ForEach(this.getFilteredGroupedRecords(), (group: RecordGroup, groupIndex: number) => {
                        this.buildDateGroup(group, groupIndex)
                    }, (group: RecordGroup) => group.date)
                }
                    .width('100%')
                    .constraintSize({ maxWidth: this.isTablet ? 600 : undefined })
                    .alignSelf(ItemAlign.Center)
                    .padding({ left: Spacing.pageHorizontal, right: Spacing.pageHorizontal, top: Spacing.componentGap, bottom: 96 })
            }
                .width('100%')
                .height('100%')
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .align(Alignment.Top)
                .backgroundColor(Colors.homeBackground)
        }
    }

    @Builder
    private buildRecordsContent() {
        if (this.isDeleting || this.isFiltering) {
            // 加载中状态
            Column() {
                LoadingProgress()
                    .width(40)
                    .height(40)
                    .color(Colors.primary)
            }
            .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
        } else if (this.isLoadingRecords) {
            // 加载中
            Column({ space: 16 }) {
                Text('⏳')
                    .fontSize(48)

                Text($r('app.string.loading_records'))
                    .fontSize(16)
                    .fontColor(Colors.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 120 })
                .backgroundColor(Colors.homeBackground)
        } else if (this.records.length === 0) {
            // 无记录时的占位内容
            Column({ space: 24 }) {
                Text('🧘‍♂️')
                    .fontSize(72)

                Text($r('app.string.no_recent_records'))
                    .fontSize(18)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Colors.textPrimary)
                    .textAlign(TextAlign.Center)
            }
            .alignItems(HorizontalAlign.Center)
                .width('100%')
                .padding({ top: 120, left: 24, right: 24 })
                .backgroundColor(Colors.homeBackground)
        } else {
            // 有记录时显示分组列表
            this.buildFilteredRecordsList()
        }
    }

    // 按日期分组计时记录（用于"计时"标签页，应用筛选后）
    private groupTimerRecordsByDate(records: GameRecordSummary[]): RecordGroup[] {
        const groups = new Map<string, GameRecordSummary[]>();

        // 按日期分组
        records.forEach((record) => {
            const date = record.date;
            if (!groups.has(date)) {
                groups.set(date, []);
            }
            groups.get(date)!.push(record);
        });

        // 转换为数组并排序
        const today = formatDate(Date.now());
        const yesterday = formatDate(Date.now() - 24 * 60 * 60 * 1000);

        const result: RecordGroup[] = [];
        groups.forEach((records, date) => {
            let displayDate = date;
            try {
                if (date === today) {
                    displayDate = getContext().resourceManager.getStringSync($r('app.string.today').id);
                } else if (date === yesterday) {
                    displayDate = getContext().resourceManager.getStringSync($r('app.string.yesterday').id);
                } else {
                    // 只显示月-日
                    const parts = date.split("-");
                    if (parts.length === 3) {
                        displayDate = `${parts[1]}-${parts[2]}`;
                    }
                }
            } catch (error) {
                // 如果获取资源失败，使用默认格式
                const parts = date.split("-");
                if (parts.length === 3) {
                    displayDate = `${parts[1]}-${parts[2]}`;
                }
            }

            result.push({
                date,
                displayDate,
                records,
            });
        });

        // 按日期降序排序
        result.sort((a, b) => b.date.localeCompare(a.date));

        return result;
    }

    @Builder
    private buildEmptyState() {
        Column({ space: 24 }) {
            // 空状态图标
            Text('🧘‍♂️')
                .fontSize(72)

            // 空状态文本
            Text($r('app.string.no_recent_records'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(Colors.textPrimary)
                .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding({ top: 120 })
    }

    // ========== 混合记录相关Builder ==========

    @Builder
    buildMixedDateGroup(group: MixedDateGroup, groupIndex: number) {
        Column() {
            // 日期标题
            Row() {
                Text(group.displayDate)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Colors.textSecondary)

                Blank()

                Text(`${group.timerRecords.length + group.scoreboardRecords.length} ${getContext().resourceManager.getStringSync($r('app.string.match_count').id)}`)
                    .fontSize(12)
                    .fontColor(Colors.textSecondary)
            }
            .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })

            // 合并并按时间排序显示记录
            ForEach(this.getMixedRecordsSorted(group.timerRecords, group.scoreboardRecords), (item: MixedRecordItem, itemIndex: number) => {
                if (item.type === 'timer') {
                    this.buildRecordItem(item.record as GameRecordSummary, itemIndex)
                } else {
                    this.buildScoreboardRecordItem(item.record as ScoreboardRecordSummary, itemIndex)
                }
            }, (item: MixedRecordItem) => item.record.id)
        }
        .width('100%')
            .margin({ bottom: 16 })
    }

    // 合并并排序记录
    private getMixedRecordsSorted(timerRecords: GameRecordSummary[], scoreboardRecords: ScoreboardRecordSummary[]): MixedRecordItem[] {
        const mixed: MixedRecordItem[] = [];

        timerRecords.forEach(record => {
            const item: MixedRecordItem = { type: 'timer', record: record };
            mixed.push(item);
        });

        scoreboardRecords.forEach(record => {
            const item: MixedRecordItem = { type: 'scoreboard', record: record };
            mixed.push(item);
        });

        // 按时间戳降序排序
        mixed.sort((a, b) => b.record.timestamp - a.record.timestamp);

        return mixed;
    }

    // ========== 计时记录相关Builder ==========

    @Builder
    buildDateGroup(group: RecordGroup, groupIndex: number) {
        Column() {
            // 日期标题
            Row() {
                Text(group.displayDate)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Colors.textSecondary)

                Blank()

                Text(`${group.records.length} ${getContext().resourceManager.getStringSync($r('app.string.game_count').id)}`)
                    .fontSize(12)
                    .fontColor(Colors.textSecondary)
            }
        .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })

            // 该日期下的记录列表
            ForEach(group.records, (record: GameRecordSummary, recordIndex: number) => {
                this.buildRecordItem(record, recordIndex)
            }, (record: GameRecordSummary) => record.id)
        }
    .width('100%')
            .margin({ bottom: groupIndex < this.groupedRecords.length - 1 ? 16 : 0 })
    }

    private getPlayerIconResource(gameType: GameType, playerId: number): Resource {
        switch (gameType) {
            case GameType.GO:
                return playerId === 1 ? $r('app.media.go_black') : $r('app.media.go_white');
            case GameType.XIANGQI:
                return playerId === 1 ? $r('app.media.xiangqi_red') : $r('app.media.xiangqi_black');
            case GameType.CHESS:
                return playerId === 1 ? $r('app.media.chess_white') : $r('app.media.chess_black');
            default:
                return $r('app.media.go_white');
        }
    }

    @Builder
    buildGameIcon(gameType: GameType) {
        Stack() {
            // 玩家2的图标（后面，稍微偏移）
            Image(this.getPlayerIconResource(gameType, 2))
                .width(24)
                .height(24)
                .translate({ x: 3, y: 3 })
                .opacity(0.8)

            // 玩家1的图标（前面）
            Image(this.getPlayerIconResource(gameType, 1))
                .width(24)
                .height(24)
                .translate({ x: -3, y: -3 })
        }
    .width(32)
            .height(32)
            .alignContent(Alignment.Center)
    }

    @Builder
    buildRecordItem(record: GameRecordSummary, index: number) {
        Row({ space: 0 }) {
            Column() {
                Row() {
                    // 左侧比赛图标
                    this.buildGameIcon(record.gameType)

                    // 中间信息
                    Row() {
                        Text(`${record.time}`)
                            .fontSize(14)
                            .fontColor(Colors.textPrimary)

                        if (record.duration) {
                            Text(formatDuration(record.duration))
                                .fontSize(12)
                                .fontColor(Colors.textSecondary)
                                .margin({ left: 16 })
                        }

                        Blank()

                        // 显示获胜者
                        if (record.winner) {
                            Text(`${PlayerTypeNames[record.winner]} 获胜`)
                                .fontSize(12)
                                .fontColor(Colors.primary)
                                .fontWeight(FontWeight.Medium)
                        }
                    }
                    .width('100%')
                        .layoutWeight(1)
                        .margin({ left: 12 })

                    // 右侧箭头或删除按钮
                    if (this.isEditMode) {
                        Row() {
                            Image($r('app.media.delete'))
                                .width(20)
                                .height(20)
                        }
                        .width(44)
                            .height(44)
                            .justifyContent(FlexAlign.Center)
                            .onClick(() => {
                                this.deleteTimerRecord(record.id);
                            })
                    } else {
                        Image($r('app.media.chevron_forward'))
                            .width(16)
                            .height(16)
                            .margin({ left: 12 })
                    }
                }
                .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .onClick(() => {
                        if (!this.isEditMode) {
                            // 跳转到记录详情页面
                            router.pushUrl({
                                url: 'pages/timer/TimerRecordDetailPage',
                                params: { recordId: record.id }
                            }).catch((error: Error) => {
                                console.error('[RecentActivityPage] Failed to navigate to TimerRecordDetailPage:', error);
                            });
                        }
                    })
            }
            .layoutWeight(1)
                .backgroundColor(Colors.homeCardBackground)
                .borderRadius(8)
        }
        .width('100%')
            .margin({ bottom: 4 })
    }

    // ========== 计分板记录相关Builder ==========

    @Builder
    buildScoreboardDateGroup(group: ScoreboardRecordGroup, groupIndex: number) {
        Column() {
            // 日期标题
            Row() {
                Text(group.displayDate)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Colors.textSecondary)

                Blank()

                Text(`${group.records.length} 场`)
                    .fontSize(12)
                    .fontColor(Colors.textSecondary)
            }
            .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })

            // 该日期下的记录列表
            ForEach(group.records, (record: ScoreboardRecordSummary, recordIndex: number) => {
                this.buildScoreboardRecordItem(record, recordIndex)
            }, (record: ScoreboardRecordSummary) => record.id)
        }
        .width('100%')
            .margin({ bottom: groupIndex < this.groupedScoreboardRecords.length - 1 ? 16 : 0 })
    }

    @Builder
    buildScoreboardRecordItem(record: ScoreboardRecordSummary, index: number) {
        if (record.gameType === GameType.MULTI_SCOREBOARD) {
            this.buildMultiScoreboardRecordItem(record, index);
        } else {

            Row({ space: 0 }) {
                Column() {
                    Row() {
                        // 左侧比赛emoji图标
                        Text(GameTypeIcons[record.gameType] || '🎮')
                            .fontSize(28)
                            .width(40)
                            .height(40)
                            .textAlign(TextAlign.Center)

                        // 中间信息
                        Row() {
                            Column({ space: 4 }) {
                                // 队伍名称和比分
                                Text(`${record.team1Name} vs ${record.team2Name}`)
                                    .fontSize(14)
                                    .fontColor(Colors.textPrimary)
                                    .fontWeight(FontWeight.Medium)

                                Row({ space: 8 }) {
                                    Text(`${record.time}`)
                                        .fontSize(12)
                                        .fontColor(Colors.textSecondary)

                                    if (record.duration) {
                                        Text(formatScoreboardDuration(record.duration))
                                            .fontSize(12)
                                            .fontColor(Colors.textSecondary)
                                    }
                                }
                            }
                        .alignItems(HorizontalAlign.Start)

                            Blank()

                            // 显示比分和获胜者
                            Column({ space: 4 }) {
                                Text(`${record.team1FinalScore} - ${record.team2FinalScore}`)
                                    .fontSize(16)
                                    .fontColor(Colors.primary)
                                    .fontWeight(FontWeight.Bold)

                                if (record.winner) {
                                    Text(`${record.winner === TeamType.TEAM1 ? record.team1Name : record.team2Name} 获胜`)
                                        .fontSize(11)
                                        .fontColor(Colors.textSecondary)
                                }
                            }
                        .alignItems(HorizontalAlign.End)
                        }
                    .width('100%')
                            .layoutWeight(1)
                            .margin({ left: 12 })

                        // 右侧箭头或删除按钮
                        if (this.isEditMode) {
                            Row() {
                                Image($r('app.media.delete'))
                                    .width(20)
                                    .height(20)
                            }
                            .width(44)
                                .height(44)
                                .justifyContent(FlexAlign.Center)
                                .onClick(() => {
                                    this.deleteScoreboardRecord(record.id);
                                })
                        } else {
                            Image($r('app.media.chevron_forward'))
                                .width(16)
                                .height(16)
                                .margin({ left: 12 })
                        }
                    }
                .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        .onClick(() => {
                            if (!this.isEditMode) {
                                // 跳转到计分板记录详情页面
                                router.pushUrl({
                                    url: 'pages/scoreboard/ScoreboardRecordDetailPage',
                                    params: { recordId: record.id }
                                }).catch((error: Error) => {
                                    console.error('[RecentActivityPage] Failed to navigate to ScoreboardRecordDetailPage:', error);
                                });
                            }
                        })
                }
            .layoutWeight(1)
                    .backgroundColor(Colors.homeCardBackground)
                    .borderRadius(8)
            }
        .width('100%')
                .margin({ bottom: 4 })
        }
    }

    @Builder
    private buildMultiScoreboardRecordItem(record: ScoreboardRecordSummary, index: number) {
        Row({ space: 0 }) {
            Column() {
                Row() {
                    Text(GameTypeIcons[record.gameType] || '🎮')
                        .fontSize(28)
                        .width(40)
                        .height(40)
                        .textAlign(TextAlign.Center)

                    Row() {
                        Column({ space: 4 }) {
                            Text(`${this.getMultiScoreboardPlayerCount(record)}人计分`)
                                .fontSize(14)
                                .fontColor(Colors.textPrimary)
                                .fontWeight(FontWeight.Medium)
                                .textAlign(TextAlign.Start);

                            Row({ space: 8 }) {
                                Text(`${record.time}`)
                                    .fontSize(12)
                                    .fontColor(Colors.textSecondary);

                                if (record.duration) {
                                    Text(formatScoreboardDuration(record.duration))
                                        .fontSize(12)
                                        .fontColor(Colors.textSecondary);
                                }
                            }
                        }
                        .alignItems(HorizontalAlign.Start);

                        Blank();

                        Column({ space: 4 }) {
                            if (this.getMultiScoreboardPlayers(record).length > 0) {
                                Text(this.getMultiScoreboardPlayers(record)[0].name)
                                    .fontSize(14)
                                    .fontColor(Colors.textPrimary)
                                    .textAlign(TextAlign.End);

                                Text(`${this.getMultiScoreboardPlayers(record)[0].score}`)
                                    .fontSize(18)
                                    .fontColor(Colors.primary)
                                    .fontWeight(FontWeight.Bold)
                                    .textAlign(TextAlign.End);
                            } else {
                                Text('--')
                                    .fontSize(16)
                                    .fontColor(Colors.textSecondary);
                            }
                        }
                        .alignItems(HorizontalAlign.End);
                    }
                    .width('100%')
                        .layoutWeight(1)
                        .margin({ left: 12 });

                    // 右侧箭头或删除按钮
                    if (this.isEditMode) {
                        Row() {
                            Image($r('app.media.delete'))
                                .width(20)
                                .height(20)
                        }
                        .width(44)
                            .height(44)
                            .justifyContent(FlexAlign.Center)
                            .onClick(() => {
                                this.deleteScoreboardRecord(record.id);
                            })
                    } else {
                        Image($r('app.media.chevron_forward'))
                            .width(16)
                            .height(16)
                            .margin({ left: 12 });
                    }
                }
                .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .onClick(() => {
                        if (!this.isEditMode) {
                            router.pushUrl({
                                url: 'pages/scoreboard/MultiGroupRecordDetailPage',
                                params: { recordId: record.id }
                            }).catch((error: Error) => {
                                console.error('[RecentActivityPage] Failed to navigate to MultiGroupRecordDetailPage:', error);
                            });
                        }
                    });
            }
            .layoutWeight(1)
                .backgroundColor(Colors.homeCardBackground)
                .borderRadius(8);
        }
        .width('100%')
            .margin({ bottom: 4 });
    }

    // 筛选对话框
    @Builder
    buildFilterDialog() {
        if (this.showFilterDialog) {
            Column() {
                // 遮罩层
                Column()
                    .width('100%')
                    .height('100%')
                    .backgroundColor('rgba(0, 0, 0, 0.5)')
                    .onClick(() => {
                        this.showFilterDialog = false;
                    })

                // 筛选面板
                Column({ space: 20 }) {
                    // 标题
                    Row() {
                        Text($r('app.string.filter'))
                            .fontSize(18)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(Colors.textPrimary)
                            .layoutWeight(1)

                        Button({ type: ButtonType.Circle }) {
                            Text('×')
                                .fontSize(24)
                                .fontColor(Colors.textSecondary)
                        }
                        .width(32)
                            .height(32)
                            .backgroundColor(Color.Transparent)
                            .onClick(() => {
                                this.showFilterDialog = false;
                            })
                    }
                    .width('100%')

                    // 时间筛选
                    Column({ space: 12 }) {
                        Text($r('app.string.time_filter'))
                            .fontSize(14)
                            .fontColor(Colors.textSecondary)
                            .width('100%')

                        Row({ space: 8 }) {
                            Text($r('app.string.today'))
                                .fontSize(14)
                                .fontWeight(this.selectedTimeFilter === 'today' ? FontWeight.Medium : FontWeight.Normal)
                                .fontColor(this.selectedTimeFilter === 'today' ? '#FFFFFF' : Colors.textSecondary)
                                .backgroundColor(this.selectedTimeFilter === 'today' ? Colors.primary : Colors.homeCardBackground)
                                .borderRadius(16)
                                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                .onClick(() => {
                                    this.selectedTimeFilter = 'today';
                                })

                            Text($r('app.string.this_week'))
                                .fontSize(14)
                                .fontWeight(this.selectedTimeFilter === 'week' ? FontWeight.Medium : FontWeight.Normal)
                                .fontColor(this.selectedTimeFilter === 'week' ? '#FFFFFF' : Colors.textSecondary)
                                .backgroundColor(this.selectedTimeFilter === 'week' ? Colors.primary : Colors.homeCardBackground)
                                .borderRadius(16)
                                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                .onClick(() => {
                                    this.selectedTimeFilter = 'week';
                                })

                            Text($r('app.string.this_month'))
                                .fontSize(14)
                                .fontWeight(this.selectedTimeFilter === 'month' ? FontWeight.Medium : FontWeight.Normal)
                                .fontColor(this.selectedTimeFilter === 'month' ? '#FFFFFF' : Colors.textSecondary)
                                .backgroundColor(this.selectedTimeFilter === 'month' ? Colors.primary : Colors.homeCardBackground)
                                .borderRadius(16)
                                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                .onClick(() => {
                                    this.selectedTimeFilter = 'month';
                                })

                            Text($r('app.string.all'))
                                .fontSize(14)
                                .fontWeight(this.selectedTimeFilter === 'all' ? FontWeight.Medium : FontWeight.Normal)
                                .fontColor(this.selectedTimeFilter === 'all' ? '#FFFFFF' : Colors.textSecondary)
                                .backgroundColor(this.selectedTimeFilter === 'all' ? Colors.primary : Colors.homeCardBackground)
                                .borderRadius(16)
                                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                .onClick(() => {
                                    this.selectedTimeFilter = 'all';
                                })
                        }
                        .width('100%')
                    }

                    // 比赛类型筛选
                    Column({ space: 12 }) {
                        Text($r('app.string.game_type_filter'))
                            .fontSize(14)
                            .fontColor(Colors.textSecondary)
                            .width('100%')

                        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                            // 全部
                            Text($r('app.string.all'))
                                .fontSize(14)
                                .fontWeight(this.selectedGameType === 'all' ? FontWeight.Medium : FontWeight.Normal)
                                .fontColor(this.selectedGameType === 'all' ? '#FFFFFF' : Colors.textSecondary)
                                .backgroundColor(this.selectedGameType === 'all' ? Colors.primary : Colors.homeCardBackground)
                                .borderRadius(16)
                                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                .margin({ right: 8, bottom: 8 })
                                .onClick(() => {
                                    this.selectedGameType = 'all';
                                })

                            // 各个比赛类型
                            ForEach([
                                GameType.FOOTBALL, GameType.BASKETBALL, GameType.VOLLEYBALL,
                                GameType.BADMINTON, GameType.PINGPONG, GameType.TENNIS,
                                GameType.BOXING, GameType.BILLIARDS,
                                GameType.XIANGQI, GameType.GO, GameType.CHESS,
                                GameType.GUANDAN, GameType.DOUDIZHU
                            ], (gameType: GameType) => {
                                Text(this.getGameNameResource(gameType))
                                    .fontSize(14)
                                    .fontWeight(this.selectedGameType === gameType ? FontWeight.Medium : FontWeight.Normal)
                                    .fontColor(this.selectedGameType === gameType ? '#FFFFFF' : Colors.textSecondary)
                                    .backgroundColor(this.selectedGameType === gameType ? Colors.primary : Colors.homeCardBackground)
                                    .borderRadius(16)
                                    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                                    .margin({ right: 8, bottom: 8 })
                                    .onClick(() => {
                                        this.selectedGameType = gameType;
                                    })
                            }, (gameType: GameType) => gameType)
                        }
                        .width('100%')
                    }

                    // 重置和应用按钮
                    Row({ space: 12 }) {
                        Button($r('app.string.reset'))
                            .fontSize(16)
                            .fontColor(Colors.textPrimary)
                            .backgroundColor(Colors.homeCardBackground)
                            .layoutWeight(1)
                            .onClick(() => {
                                this.selectedTimeFilter = 'all';
                                this.selectedGameType = 'all';
                                this.searchText = '';
                            })

                        Button($r('app.string.apply'))
                            .fontSize(16)
                            .fontColor('#FFFFFF')
                            .backgroundColor(Colors.primary)
                            .layoutWeight(1)
                            .onClick(() => {
                                this.showFilterDialog = false;
                                console.log(`[RecentActivityPage] Filter applied - Time: ${this.selectedTimeFilter}, GameType: ${this.selectedGameType}`);
                            })
                    }
                    .width('100%')
                }
                .width('100%')
                    .padding(20)
                    .backgroundColor('#1A1A1A')
                    .borderRadius({ topLeft: 20, topRight: 20 })
                    .border({ width: { top: 1 }, color: 'rgba(255, 255, 255, 0.1)' })
                    .position({ x: 0, y: '100%' })
                    .translate({ y: '-100%' })
            }
            .width('100%')
                .height('100%')
                .position({ x: 0, y: 0 })
        }
    }
}
