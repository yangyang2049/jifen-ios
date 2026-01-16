/**
 * 计分板记录详情页面 - 显示单个比赛记录的详细信息
 */

import { router } from '@kit.ArkUI';
import { getThemeColors, Colors } from '../../common/theme';
import { scoreboardRecordsViewModel } from '../../viewmodel/scoreboardRecordsViewModel';
import { ScoreboardRecord, ScoreAction, ScoreActionType, TeamType, formatTimestamp, formatDate, formatDateWithConditionalYear } from '../../model/scoreboardRecord';
import { GameType, GameTypeNames, GameTypeIcons } from '../../model/types';
import { scoreboardRecordManager } from '../../managers/scoreboardRecordManager';
import { CustomConfirmDialog } from '../../components/CustomConfirmDialog';
import deviceInfo from '@ohos.deviceInfo';
import common from '@ohos.app.ability.common';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { wantConstant, Want } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';

@Entry
@Component
    struct ScoreboardRecordDetailPage {
    @State record: ScoreboardRecord | null = null;
    @State isDeleting: boolean = false;
    @State showMoreMenu: boolean = false;
    private recordId: string = '';
    private contentId: string = 'scoreboard_content_area';

    // 删除确认对话框控制器
    private deleteDialogController: CustomDialogController = new CustomDialogController({
        builder: CustomConfirmDialog({
            title: $r('app.string.confirm_delete'),
            message: $r('app.string.confirm_delete_record_message'),
            confirmText: $r('app.string.delete'),
            cancelText: $r('app.string.cancel'),
            confirmColor: '#FF3B30',
            cancelColor: Colors.primary,
            onConfirm: () => {
                this.handleDeleteConfirm();
            }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true
    })

    aboutToAppear() {
        // 初始化计分板记录管理器
        try {
            const uiContext = getContext(this) as common.UIAbilityContext;
            scoreboardRecordManager.init(uiContext).catch((error: Error) => {
                console.error('[ScoreboardRecordDetailPage] Failed to initialize scoreboardRecordManager:', error);
            });
        } catch (error) {
            console.error('[ScoreboardRecordDetailPage] Initialization error:', error);
        }

        // 获取路由参数
        try {
            const uiContext = this.getUIContext();
            const routerInstance = uiContext.getRouter();
            const params = routerInstance.getParams();

            if (params && typeof params === 'object') {
                const paramsObj = params as Record<string, Object>;
                if (paramsObj.recordId) {
                    this.recordId = paramsObj.recordId as string;
                    this.loadRecord();
                }
            }
        } catch (error) {
            console.error('Failed to get router params:', error);
        }
    }

    async loadRecord(): Promise<void> {
        try {
            const record: ScoreboardRecord | null = await scoreboardRecordsViewModel.getRecordById(this.recordId);
            this.record = record;

            if (record) {
                console.info(`[ScoreboardRecordDetailPage] Loaded record:`, JSON.stringify({
                    id: record.id,
                    gameType: record.gameType
                }));
            }
        } catch (error) {
            console.error('Failed to load record:', error);
        }
    }

    // 获取本地化的游戏类型名称
    private getGameTypeName(gameType: GameType): Resource {
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

    private showDeleteDialog(): void {
        this.deleteDialogController.open();
    }

    private async handleDeleteConfirm(): Promise<void> {
        this.isDeleting = true;

        try {
            const success = await scoreboardRecordsViewModel.deleteRecord(this.recordId);

            if (success) {
                console.info('[ScoreboardRecordDetailPage] Record deleted successfully');

                setTimeout(() => {
                    router.back();
                }, 500);
            } else {
                console.error('[ScoreboardRecordDetailPage] Failed to delete record');
                this.isDeleting = false;
            }
        } catch (error) {
            console.error('[ScoreboardRecordDetailPage] Error deleting record:', error);
            this.isDeleting = false;
        }
    }

    private isTablet(): boolean {
        try {
            const deviceType = deviceInfo.deviceType;
            return deviceType === 'tablet' || deviceType === '2in1';
        } catch (error) {
            return false;
        }
    }

    // 处理分享功能
    private async handleShare(): Promise<void> {
        try {
            console.info('[ScoreboardRecordDetailPage] Starting share process...');

            const pixelMap = await this.captureContent();
            if (!pixelMap) {
                console.error('[ScoreboardRecordDetailPage] Failed to capture content');
                return;
            }

            const imageUri = await this.packImage(pixelMap);
            if (imageUri) {
                await this.shareImage(imageUri);
            }

            this.showMoreMenu = false;
        } catch (error) {
            console.error('[ScoreboardRecordDetailPage] Share failed:', error);
            this.showMoreMenu = false;
        }
    }

    private async captureContent(): Promise<image.PixelMap | null> {
        try {
            const pixelMap = await componentSnapshot.get(this.contentId);
            console.info('[ScoreboardRecordDetailPage] Content captured successfully');
            return pixelMap;
        } catch (error) {
            console.error('[ScoreboardRecordDetailPage] Failed to capture content:', error);
            return null;
        }
    }

    private async packImage(pixelMap: image.PixelMap): Promise<string> {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            const imagePackerApi = image.createImagePacker();
            const packOpts: image.PackingOption = {
                format: 'image/jpeg',
                quality: 90
            };

            const data = await imagePackerApi.packing(pixelMap, packOpts);

            const filePath = context.cacheDir + '/scoreboard_share_' + Date.now() + '.jpg';
            const fileHandle = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
            fs.writeSync(fileHandle.fd, data);
            fs.closeSync(fileHandle);

            console.info('[ScoreboardRecordDetailPage] Image saved to:', filePath);
            return filePath;  // 返回文件路径而不是 URI
        } catch (error) {
            console.error('[ScoreboardRecordDetailPage] Failed to pack image:', error);
            return '';
        }
    }

    // 分享图片 - 使用 HarmonyOS 标准分享框架
    private async shareImage(filePath: string): Promise<void> {
        try {
            const context = getContext(this) as common.UIAbilityContext;

            // 获取文件的 UTD 类型
            const utdTypeId = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.jpg', uniformTypeDescriptor.UniformDataType.IMAGE);

            // 获取本地化标题
            const title = context.resourceManager.getStringSync($r('app.string.scoreboard_record_title').id);
            const description = context.resourceManager.getStringSync($r('app.string.share_match_record').id);

            // 创建分享数据
            const shareData: systemShare.SharedData = new systemShare.SharedData({
                utd: utdTypeId,
                uri: fileUri.getUriFromPath(filePath),
                title: title,
                description: description
            });

            // 创建分享控制器
            const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

            // 显示分享面板
            await controller.show(context, {
                selectionMode: systemShare.SelectionMode.SINGLE,
                previewMode: systemShare.SharePreviewMode.DETAIL
            });

            console.info('[ScoreboardRecordDetailPage] Share panel opened successfully');
        } catch (error) {
            const err = error as BusinessError;
            console.error(`[ScoreboardRecordDetailPage] Failed to open share panel. code: ${err?.code}, message: ${err?.message}`);
        }
    }

    build() {
        Column() {
            // 顶部导航栏
            Row() {
                Button({ type: ButtonType.Normal }) {
                    Image($r('app.media.back'))
                        .width(24)
                        .height(24)
                }
        .width(40)
                    .height(40)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                        router.back();
                    })

                Blank()

                Text($r('app.string.match_detail'))
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(getThemeColors().textPrimary)

                Blank()

                Button({ type: ButtonType.Normal }) {
                    Text('⋮')
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(getThemeColors().textPrimary)
                }
        .width(40)
                    .height(40)
                    .backgroundColor(Color.Transparent)
                    .bindMenu([
                        {
                            value: $r('app.string.share'),
                            action: () => {
                                this.handleShare();
                            }
                        },
                        {
                            value: $r('app.string.delete'),
                            action: () => {
                                this.showDeleteDialog();
                            }
                        }
                    ])
            }
      .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .backgroundColor('#000000')

            // 主要内容区域
            if (this.isDeleting) {
                Column({ space: 16 }) {
                    Text('🗑️')
                        .fontSize(48)

                    Text($r('app.string.deleting_record'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(getThemeColors().textPrimary)

                    Text($r('app.string.please_wait_return_to_list'))
                        .fontSize(14)
                        .fontColor(getThemeColors().textSecondary)
                }
        .width('100%')
                    .layoutWeight(1)
                    .padding({ top: 120 })
                    .alignItems(HorizontalAlign.Center)
                    .backgroundColor(getThemeColors().background)
            } else if (!this.record) {
                Column({ space: 16 }) {
                    Text('❌')
                        .fontSize(48)

                    Text($r('app.string.record_not_found'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(getThemeColors().textPrimary)

                    Text($r('app.string.record_may_deleted'))
                        .fontSize(14)
                        .fontColor(getThemeColors().textSecondary)
                }
        .width('100%')
                    .layoutWeight(1)
                    .padding({ top: 120 })
                    .alignItems(HorizontalAlign.Center)
                    .backgroundColor(getThemeColors().background)
            } else {
                Scroll() {
                    Column() {
                        this.buildGameInfo()
                        this.buildActionsList()
                    }
          .width('100%')
                        .constraintSize({ maxWidth: 600 })
                        .alignSelf(ItemAlign.Center)
                        .justifyContent(FlexAlign.Start)
                        .padding({ left: 12, right: 12, top: 16, bottom: 96 })
                        .id(this.contentId)
                }
        .width('100%')
                    .layoutWeight(1)
                    .scrollBar(BarState.Off)
                    .edgeEffect(EdgeEffect.Spring)
                    .backgroundColor(getThemeColors().background)
            }
        }
    .width('100%')
            .height('100%')
            .backgroundColor(getThemeColors().background)
    }

    @Builder
    buildGameInfo() {
        if (this.record) {
            Column({ space: 16 }) {
                // 比赛图标和类型
                Row({ space: 12 }) {
                    Text(GameTypeIcons[this.record.gameType] || '🎮')
                        .fontSize(36)

                    Text(this.getGameTypeName(this.record.gameType))
                        .fontSize(24)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(getThemeColors().textPrimary)
                }
      .justifyContent(FlexAlign.Center)

                // 比分 - 判断是否为斗地主（3个玩家）
                if (this.record.team3Name && this.record.team3FinalScore !== undefined) {
                    // 斗地主：显示3个玩家
                    Row({ space: 4 }) {
                        Column({ space: 4 }) {
                            Text(this.record.team1Name)
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                                .textAlign(TextAlign.Center)

                            Text(this.record.team1FinalScore.toString())
                                .fontSize(36)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.record.winner === TeamType.TEAM1 ? '#34C759' : getThemeColors().textPrimary)
                        }
        .layoutWeight(1)

                        Text('-')
                            .fontSize(24)
                            .fontColor(getThemeColors().textSecondary)

                        Column({ space: 4 }) {
                            Text(this.record.team2Name)
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                                .textAlign(TextAlign.Center)

                            Text(this.record.team2FinalScore.toString())
                                .fontSize(36)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.record.winner === TeamType.TEAM2 ? '#34C759' : getThemeColors().textPrimary)
                        }
        .layoutWeight(1)

                        Text('-')
                            .fontSize(24)
                            .fontColor(getThemeColors().textSecondary)

                        Column({ space: 4 }) {
                            Text(this.record.team3Name)
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                                .textAlign(TextAlign.Center)

                            Text(this.record.team3FinalScore.toString())
                                .fontSize(36)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.record.winner === TeamType.TEAM3 ? '#34C759' : getThemeColors().textPrimary)
                        }
        .layoutWeight(1)
                    }
      .width('100%')
                        .padding({ top: 8, bottom: 8 })
                } else {
                    // 普通2队模式
                    Row({ space: 8 }) {
                        Column({ space: 4 }) {
                            Text(this.record.team1Name)
                                .fontSize(16)
                                .fontColor(getThemeColors().textPrimary)
                                .textAlign(TextAlign.Center)

                            Text(this.record.team1FinalScore.toString())
                                .fontSize(48)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.record.winner === TeamType.TEAM1 ? '#34C759' : getThemeColors().textPrimary)
                        }
        .layoutWeight(1)

                        Text('-')
                            .fontSize(32)
                            .fontColor(getThemeColors().textSecondary)
                            .margin({ left: 8, right: 8 })

                        Column({ space: 4 }) {
                            Text(this.record.team2Name)
                                .fontSize(16)
                                .fontColor(getThemeColors().textPrimary)
                                .textAlign(TextAlign.Center)

                            Text(this.record.team2FinalScore.toString())
                                .fontSize(48)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.record.winner === TeamType.TEAM2 ? '#34C759' : getThemeColors().textPrimary)
                        }
        .layoutWeight(1)
                    }
      .width('100%')
                        .padding({ top: 8, bottom: 8 })
                }

                // 获胜者
                if (this.record.winner) {
                    Text(`${this.getTeamName(this.record.winner)} ${this.getWinsText()}`)
                        .fontSize(18)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#34C759')
                        .textAlign(TextAlign.Center)
                }

                // 比赛信息
                Column({ space: 8 }) {
                    Row() {
                        Text($r('app.string.date'))
                            .fontSize(14)
                            .fontColor(getThemeColors().textSecondary)
                            .layoutWeight(1)

                        Text(formatDateWithConditionalYear(this.record.startTime))
                            .fontSize(14)
                            .fontColor(getThemeColors().textPrimary)
                    }
        .width('100%')

                    Row() {
                        Text($r('app.string.record_start_time'))
                            .fontSize(14)
                            .fontColor(getThemeColors().textSecondary)
                            .layoutWeight(1)

                        Text(formatTimestamp(this.record.startTime))
                            .fontSize(14)
                            .fontColor(getThemeColors().textPrimary)
                    }
        .width('100%')

                    if (this.record.endTime) {
                        Row() {
                            Text($r('app.string.record_end_time'))
                                .fontSize(14)
                                .fontColor(getThemeColors().textSecondary)
                                .layoutWeight(1)

                            Text(formatTimestamp(this.record.endTime))
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                        }
          .width('100%')
                    }

                    if (this.record.duration) {
                        Row() {
                            Text($r('app.string.record_duration'))
                                .fontSize(14)
                                .fontColor(getThemeColors().textSecondary)
                                .layoutWeight(1)

                            Text(this.formatDuration(this.record.duration))
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                        }
          .width('100%')
                    }

                    if (this.record.totalRounds !== undefined && this.record.totalRounds > 0) {
                        Row() {
                            Text(this.record.gameType === GameType.DOUDIZHU ?
                                $r('app.string.total_rounds_doudizhu') : $r('app.string.total_rounds'))
                                .fontSize(14)
                                .fontColor(getThemeColors().textSecondary)
                                .layoutWeight(1)

                            Text(this.record.totalRounds.toString())
                                .fontSize(14)
                                .fontColor(getThemeColors().textPrimary)
                        }
          .width('100%')
                    }
                }
      .width('100%')
                    .padding(16)
                    .backgroundColor(getThemeColors().surface)
                    .borderRadius(12)
            }
      .width('100%')
                .padding(16)
                .backgroundColor(getThemeColors().surface)
                .borderRadius(12)
                .margin({ bottom: 16 })
        }
    }

    @Builder
    buildActionsList() {
        if (this.record && this.record.actions && this.record.actions.length > 0) {
            Column({ space: 8 }) {
                Text($r('app.string.match_record'))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(getThemeColors().textPrimary)
                    .margin({ bottom: 8 })

                ForEach(this.record.actions, (action: ScoreAction, index: number) => {
                    this.buildActionItem(action, index, this.calculateRoundNumber(action, index));
                }, (action: ScoreAction, index: number) => `${action.timestamp}_${index}`)
            }
      .width('100%')
                .padding(16)
                .backgroundColor(getThemeColors().surface)
                .borderRadius(12)
        }
    }

    @Builder
    buildActionItem(action: ScoreAction, index: number, roundNumber: number) {
        Column({ space: 4 }) {
            Row({ space: 12 }) {
                // 局数（如果有）
                if (roundNumber > 0) {
                    Text(this.getRoundText(roundNumber))
                        .fontSize(13)
                        .fontColor(getThemeColors().textPrimary)
                        .fontWeight(FontWeight.Medium)
                        .width(this.getRoundTextWidth())
                }

                // 时间（使用相对时间，从 00:00 开始）
                Text(this.formatRelativeTimestamp(action.timestamp))
                    .fontSize(12)
                    .fontColor(getThemeColors().textSecondary)
                    .width(60)

                // 动作描述
                Text(this.getActionDisplayDescription(action))
                    .fontSize(14)
                    .fontColor(this.isSpecialAction(action) ? Colors.primary : getThemeColors().textPrimary)
                    .layoutWeight(1)

                // 比分/局分
                if (this.getActionScoreText(action)) {
                    Text(this.getActionScoreText(action))
                        .fontSize(14)
                        .fontColor(getThemeColors().textSecondary)
                        .fontWeight(FontWeight.Medium)
                }
            }
      .width('100%')

            // 如果有获胜者和失败者信息，显示详细信息（每个玩家一行）
            if (action.winners && action.winners.length > 0 && action.losers && action.losers.length > 0 && this.record) {
                Column({ space: 4 }) {
                    // 获胜者
                    ForEach(action.winners, (winner: TeamType) => {
                        this.buildPlayerScoreRow(winner, action, true)
                    }, (winner: TeamType) => winner)

                    // 失败者
                    ForEach(action.losers, (loser: TeamType) => {
                        this.buildPlayerScoreRow(loser, action, false)
                    }, (loser: TeamType) => loser)
                }
                .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: roundNumber > 0 ? this.getDetailLeftPadding() : 72, top: 6 })
            }
        }
        .width('100%')
            .padding(12)
            .backgroundColor(index % 2 === 0 ? getThemeColors().background : Color.Transparent)
            .borderRadius(8)
    }

    @Builder
    buildPlayerScoreRow(team: TeamType, action: ScoreAction, isWinner: boolean) {
        Row({ space: 8 }) {
            Text(`${this.getTeamName(team)}(${this.getPlayerRole(team, action)})`)
                .fontSize(13)
                .fontColor(isWinner ? '#34C759' : '#FF3B30')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(isWinner ? 'rgba(52, 199, 89, 0.15)' : 'rgba(255, 59, 48, 0.15)')
                .borderRadius(4)

            if (action.scoreChange) {
                Text(this.getPlayerScoreChange(action, isWinner))
                    .fontSize(13)
                    .fontColor(isWinner ? '#34C759' : '#FF3B30')
                    .fontWeight(FontWeight.Medium)
            }
        }
    }

    private calculateRoundNumber(action: ScoreAction, currentIndex: number): number {
        if (!this.record || !action.winners || action.winners.length === 0) {
            return 0;
        }

        let roundNumber = 0;
        for (let i = 0; i <= currentIndex; i++) {
            if (this.record.actions[i].winners && this.record.actions[i].winners!.length > 0) {
                roundNumber++;
            }
        }
        return roundNumber;
    }

    private getTeamName(team: TeamType): string {
        if (!this.record) return '';

        if (team === TeamType.TEAM1) {
            return this.record.team1Name;
        } else if (team === TeamType.TEAM2) {
            return this.record.team2Name;
        } else if (team === TeamType.TEAM3 && this.record.team3Name) {
            return this.record.team3Name;
        }
        return '';
    }

    private getPlayerRole(team: TeamType, action: ScoreAction): string {
        if (!action.landlord) return '';
        try {
            const context = getContext(this) as common.UIAbilityContext;
            if (action.landlord === team) {
                return context.resourceManager.getStringSync($r('app.string.landlord').id);
            } else {
                return context.resourceManager.getStringSync($r('app.string.farmer').id);
            }
        } catch (error) {
            return action.landlord === team ? 'Landlord' : 'Farmer';
        }
    }

    private getActionDisplayDescription(action: ScoreAction): string {
        const isSetEnd = action.actionType === ScoreActionType.SET_END;
        const isGameEnd = action.actionType === ScoreActionType.GAME_END;

        // 对于"局结束"，保留完整的描述（包括"分数 X-Y"）
        // 描述格式：第N局结束，分数 X-Y 或 XXX 局结束，分数 X-Y（网球）
        // 支持 SET_END 类型（其他运动项目）和 SCORE_CHANGE 类型（网球局结束）
        if ((isSetEnd || action.description.includes('局结束')) && action.description.includes('局结束')) {
            // 保留完整描述，不移除分数信息
            return action.description;
        }

        if (isGameEnd && action.description.includes('比赛结束')) {
            // 移除描述中的分数信息，只保留"比赛结束"
            // 匹配格式：比赛结束，分数 X-Y 或 比赛结束，分数X-Y
            return action.description.replace(/，分数\s*\d+\s*-\s*\d+$/, '');
        }

        return action.description;
    }

    private getActionScoreText(action: ScoreAction): string {
        // 比赛开始不显示分数
        if (action.actionType === ScoreActionType.GAME_START) {
            return '';
        }

        const isSetEnd = action.actionType === ScoreActionType.SET_END;
        const isGameEnd = action.actionType === ScoreActionType.GAME_END;
        // 检查是否是网球的局结束（描述包含"局结束"）
        const isTennisGameEnd = this.record?.gameType === GameType.TENNIS && 
                                action.description.includes('局结束');

        // 判断是否为斗地主（3个玩家）
        if (action.team3Score !== undefined) {
            if (isSetEnd || isGameEnd) {
                // 显示局分（如果有）
                if (action.team1SetScore !== undefined && action.team2SetScore !== undefined) {
                    return `${action.team1SetScore} - ${action.team2SetScore}`;
                }
            }
            return `${action.team1Score} - ${action.team2Score} - ${action.team3Score}`;
        } else {
            if (isSetEnd || isGameEnd) {
                // 显示局分
                if (action.team1SetScore !== undefined && action.team2SetScore !== undefined) {
                    return `${action.team1SetScore} - ${action.team2SetScore}`;
                } else {
                    return `${action.team1Score} - ${action.team2Score}`;
                }
            } else if (isTennisGameEnd) {
                // 网球的局结束：显示局分（数字格式，不转换）
                return `${action.team1Score} - ${action.team2Score}`;
            } else {
                // 显示当前局分数
                return `${action.team1Score} - ${action.team2Score}`;
            }
        }
    }

    private isSpecialAction(action: ScoreAction): boolean {
        // 识别特殊动作：盘结束、比赛结束，以及网球的局结束
        return action.actionType === ScoreActionType.SET_END || 
               action.actionType === ScoreActionType.GAME_END ||
               (action.description.includes('局结束') && this.record?.gameType === GameType.TENNIS);
    }

    private getPlayerScoreChange(action: ScoreAction, isWinner: boolean): string {
        if (!action.scoreChange || !action.winners || !action.losers) return '';

        if (isWinner) {
            const winScore = action.winners.length === 1 ? action.scoreChange :
                (action.winners.length === 2 ? action.scoreChange : 0);
            return `+${winScore}`;
        } else {
            const loseScore = action.losers.length === 1 ?
                -action.scoreChange * action.winners.length : -action.scoreChange;
            return `${loseScore}`;
        }
    }

    private getWinsText(): string {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            return context.resourceManager.getStringSync($r('app.string.wins').id);
        } catch (error) {
            return 'wins';
        }
    }

    private getRoundText(roundNumber: number): string {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            const prefix = context.resourceManager.getStringSync($r('app.string.round_prefix').id);
            const suffix = context.resourceManager.getStringSync($r('app.string.round_suffix').id);
            return `${prefix}${roundNumber}${suffix}`;
        } catch (error) {
            return `Round ${roundNumber}`;
        }
    }

    private getRoundTextWidth(): number {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            const config = context.resourceManager.getConfigurationSync();
            const currentLang = config.locale;
            // 中文需要更多空间
            return currentLang?.startsWith('zh') ? 50 : 70;
        } catch (error) {
            return 70;
        }
    }

    private getDetailLeftPadding(): number {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            const config = context.resourceManager.getConfigurationSync();
            const currentLang = config.locale;
            // 英文Round文本更长，需要更多左侧padding
            return currentLang?.startsWith('zh') ? 122 : 142;
        } catch (error) {
            return 142;
        }
    }

    /**
     * 格式化相对时间戳
     * 将绝对时间转换为相对于比赛开始时间的相对时间，以 00:00:00 格式显示
     * 如果超过1小时，显示为 HH:MM:SS 格式
     * 参考围棋记录详情页面的实现
     */
    private formatRelativeTimestamp(timestamp: number): string {
        if (!this.record) {
            return '--:--';
        }

        const startTime = this.record.startTime;
        const relativeTime = timestamp - startTime;

        // 转换为小时、分钟和秒
        const totalSeconds = Math.floor(relativeTime / 1000);
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;

        // 如果超过1小时，显示为 HH:MM:SS 格式
        if (hours > 0) {
            return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
        } else {
            // 不到1小时，显示为 MM:SS 格式
            return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
        }
    }

    private formatDuration(milliseconds: number): string {
        const totalSeconds = Math.floor(milliseconds / 1000);
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const seconds = totalSeconds % 60;

        try {
            const context = getContext(this) as common.UIAbilityContext;
            const hourUnit = context.resourceManager.getStringSync($r('app.string.hour_unit').id);
            const minuteUnit = context.resourceManager.getStringSync($r('app.string.minute_unit').id);
            const secondUnit = context.resourceManager.getStringSync($r('app.string.second_unit').id);

            if (hours > 0) {
                return `${hours}${hourUnit}${minutes}${minuteUnit}${seconds}${secondUnit}`;
            } else if (minutes > 0) {
                return `${minutes}${minuteUnit}${seconds}${secondUnit}`;
            } else {
                return `${seconds}${secondUnit}`;
            }
        } catch (error) {
            // Fallback
            if (hours > 0) {
                return `${hours}h${minutes}min${seconds}s`;
            } else if (minutes > 0) {
                return `${minutes}min${seconds}s`;
            } else {
                return `${seconds}s`;
            }
        }
    }
}

