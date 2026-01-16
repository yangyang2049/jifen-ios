import { ScoreboardRecordSummary, ScoreboardRecord } from '../model/scoreboardRecord';
import { GameType, GameTypeIcons } from '../model/types';
import { scoreboardRecordManager } from '../managers/scoreboardRecordManager';
import { CommonNameSelectorDialog } from './CommonNameSelectorDialog';
import { NameType } from '../model/CommonNames';
import { commonNamesManager } from '../managers/commonNamesManager';
import { Colors } from '../common/theme';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';

export interface SportsSetupResult {
  team1Name: string;
  team2Name: string;
  maxSets?: number;
  pointsPerSet?: number;
  tieBreakPoints?: number;
  autoChangeSides?: boolean; // 自动换边（仅乒乓球）
  // 匹克球特定字段
  gameMode?: 'singles' | 'doubles';
  targetScore?: 11 | 15 | 21;
  winByTwo?: boolean;
  scoreCap?: number | null;
  useRallyScoring?: boolean;
}

interface RecentGameDisplay {
  team1Name: string;
  team2Name: string;
  score: string;
  time: string;
  recordId: string;
  setsInfo?: string; // 局数信息，如 "2/3", "3/5", "4/7" 或 "7", "10" (抢七/抢10)
}

@CustomDialog
export struct SportsSetupDialog {
  controller?: CustomDialogController;
  gameType: GameType = GameType.BASKETBALL;
  defaultTeam1Name: string = '';
  defaultTeam2Name: string = '';
  initialMaxSets?: number;
  initialPointsPerSet?: number;
  initialTieBreakPoints?: number;
  onConfirm?: (config: SportsSetupResult) => void;
  onCancel?: () => void;

  @State private team1Name: string = '';
  @State private team2Name: string = '';
  @State private recentGames: RecentGameDisplay[] = [];
  @State private selectedMaxSets: number = 0;
  @State private selectedPointsPerSet: number = 0;
  @State private selectedTieBreakPoints: number = 0;
  @State private autoChangeSides: boolean = true; // 默认开启自动换边
  // 匹克球特定状态
  @State private selectedGameMode: 'singles' | 'doubles' = 'singles';
  @State private selectedTargetScore: 11 | 15 | 21 = 11;
  @State private selectedWinByTwo: boolean = true;
  @State private selectedScoreCap: number | null = null;
  @State private selectedUseRallyScoring: boolean = false;

  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    console.info(`[SportsSetupDialog] aboutToAppear START for gameType: ${this.gameType}`);
    try {
      console.info('[SportsSetupDialog] Setting team names...');
      this.team1Name = this.defaultTeam1Name;
      this.team2Name = this.defaultTeam2Name;
      console.info(`[SportsSetupDialog] Team names set: ${this.team1Name}, ${this.team2Name}`);

      console.info('[SportsSetupDialog] Setting game parameters...');
      console.info(`[SportsSetupDialog] initialMaxSets: ${this.initialMaxSets}, getDefaultMaxSets: ${this.getDefaultMaxSets()}`);

      const defaultMaxSets = this.getDefaultMaxSets();
      if (this.initialMaxSets !== undefined && this.initialMaxSets !== null) {
        this.selectedMaxSets = this.initialMaxSets;
      } else if (defaultMaxSets !== undefined && defaultMaxSets !== null) {
        this.selectedMaxSets = defaultMaxSets;
      } else {
        // 根据游戏类型设置默认值
        if (this.gameType === GameType.PICKLEBALL) {
          this.selectedMaxSets = 3;  // 匹克球默认3局（11分制）
        } else {
          this.selectedMaxSets = 0;
        }
      }
      console.info(`[SportsSetupDialog] FINAL selectedMaxSets: ${this.selectedMaxSets}`);

      const defaultPointsPerSet = this.getDefaultPointsPerSet();
      if (this.initialPointsPerSet !== undefined && this.initialPointsPerSet !== null) {
        this.selectedPointsPerSet = this.initialPointsPerSet;
      } else if (defaultPointsPerSet !== undefined && defaultPointsPerSet !== null) {
        this.selectedPointsPerSet = defaultPointsPerSet;
      } else {
        this.selectedPointsPerSet = 0;
      }
      console.info(`[SportsSetupDialog] FINAL selectedPointsPerSet: ${this.selectedPointsPerSet}`);

      const defaultTieBreakPoints = this.getDefaultTieBreakPoints();
      if (this.initialTieBreakPoints !== undefined && this.initialTieBreakPoints !== null) {
        this.selectedTieBreakPoints = this.initialTieBreakPoints;
      } else if (defaultTieBreakPoints !== undefined && defaultTieBreakPoints !== null) {
        this.selectedTieBreakPoints = defaultTieBreakPoints;
      } else {
        this.selectedTieBreakPoints = 0;
      }
      console.info(`[SportsSetupDialog] FINAL selectedTieBreakPoints: ${this.selectedTieBreakPoints}`);

      console.info('[SportsSetupDialog] Initializing scoreboardRecordManager...');
      this.initializeAsync();

      console.info('[SportsSetupDialog] aboutToAppear COMPLETED');
    } catch (error) {
      console.error('[SportsSetupDialog] Error in aboutToAppear:', error);
    }
  }

  private async initializeAsync() {
    try {
      const uiContext = getContext(this) as common.UIAbilityContext;
      await scoreboardRecordManager.init(uiContext);
      console.info('[SportsSetupDialog] scoreboardRecordManager initialized');

      console.info('[SportsSetupDialog] Loading recent records...');
      await this.loadRecentRecords();
      console.info('[SportsSetupDialog] Recent records loaded');
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to initialize:', error);
    }
  }

  private getDefaultMaxSets(): number | undefined {
    switch (this.gameType) {
      case GameType.PINGPONG:
        return 5;
      case GameType.TENNIS:
        return 3;
      default:
        return undefined;
    }
  }

  private getDefaultPointsPerSet(): number | undefined {
    switch (this.gameType) {
      case GameType.PINGPONG:
        return 11;
      default:
        return undefined;
    }
  }

  private getDefaultTieBreakPoints(): number | undefined {
    return this.gameType === GameType.TENNIS ? 7 : undefined;
  }

  private getDialogBackgroundColor(): string {
    return '#1E1E1E';
  }

  private getDialogTextColor(): string {
    return '#FFFFFF';
  }

  private getDialogSecondaryTextColor(): string {
    return '#CCCCCC';
  }

  private getInputBackgroundColor(): string {
    return 'rgba(255, 255, 255, 0.1)';
  }

  private getInputTextColor(): string {
    return '#FFFFFF';
  }

  private getPrimaryButtonColor(): string {
    return Colors.primary;
  }

  private getRecordCardBackgroundColor(): string {
    return 'rgba(255, 255, 255, 0.08)';
  }

  private getSetsInfoBackgroundColor(): string {
    return 'rgba(255, 255, 255, 0.15)';
  }

  private getChipBackgroundColor(selected: boolean): string {
    if (selected) {
      return Colors.primary;
    }
    return 'rgba(255, 255, 255, 0.12)';
  }

  private getChipTextColor(selected: boolean): string {
    if (selected) {
      return '#FFFFFF';
    }
    return this.getDialogTextColor();
  }

  private formatTime(timestamp: number): string {
    try {
      const context = getContext(this);
      const resourceManager = context.resourceManager;
      const now = Date.now();
      const diff = now - timestamp;
      const minutes = Math.floor(diff / 60000);
      const hours = Math.floor(diff / 3600000);
      const days = Math.floor(diff / 86400000);

      if (minutes < 60) {
        const template = resourceManager.getStringSync($r('app.string.minutes_ago').id);
        return `${minutes}${template}`;
      } else if (hours < 24) {
        const template = resourceManager.getStringSync($r('app.string.hours_ago').id);
        return `${hours}${template}`;
      } else if (days < 7) {
        const template = resourceManager.getStringSync($r('app.string.days_ago').id);
        return `${days}${template}`;
      }

      const date = new Date(timestamp);
      return `${date.getMonth() + 1}/${date.getDate()}`;
    } catch (error) {
      console.error('[SportsSetupDialog] Error in formatTime:', error);
      // Fallback to hardcoded Chinese
      const now = Date.now();
      const diff = now - timestamp;
      const minutes = Math.floor(diff / 60000);
      const hours = Math.floor(diff / 3600000);
      const days = Math.floor(diff / 86400000);

      if (minutes < 60) {
        return `${minutes}分钟前`;
      } else if (hours < 24) {
        return `${hours}小时前`;
      } else if (days < 7) {
        return `${days}天前`;
      }

      const date = new Date(timestamp);
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
  }

  private async loadRecentRecords(): Promise<void> {
    try {
      const allRecords: ScoreboardRecordSummary[] = await scoreboardRecordManager.getAllRecordSummaries();
      this.recentGames = allRecords
        .filter((record: ScoreboardRecordSummary) => record.gameType === this.gameType)
        .sort((a: ScoreboardRecordSummary, b: ScoreboardRecordSummary) => b.timestamp - a.timestamp)
        .slice(0, 3)
        .map((record: ScoreboardRecordSummary) => {
          const setsInfo = this.formatSetsInfo(record);
          return {
            team1Name: record.team1Name,
            team2Name: record.team2Name,
            score: `${record.team1FinalScore}-${record.team2FinalScore}`,
            time: this.formatTime(record.timestamp),
            recordId: record.id,
            setsInfo: setsInfo,
          } as RecentGameDisplay;
        });
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to load recent records:', error);
      this.recentGames = [];
    }
  }

  private formatSetsInfo(record: ScoreboardRecordSummary): string | undefined {
    if (this.gameType === GameType.PINGPONG) {
      // 乒乓球：只显示总局数，如 3 (3局2胜), 5 (5局3胜), 7 (7局4胜)
      let maxSets: number | undefined = undefined;
      if (record.extraData && typeof record.extraData.maxSets === 'number') {
        maxSets = record.extraData.maxSets;
      }

      // 如果无法获取 maxSets，根据已完成局数推断
      if (maxSets === undefined) {
        const team1Sets = record.team1SetScore || 0;
        const team2Sets = record.team2SetScore || 0;
        const completedSets = team1Sets + team2Sets;

        if (completedSets >= 5) {
          maxSets = completedSets <= 5 ? 5 : 7;
        } else if (completedSets >= 3) {
          maxSets = completedSets <= 3 ? 3 : 5;
        } else if (completedSets >= 2) {
          maxSets = 3; // 可能是3局2胜
        } else {
          maxSets = 5; // 默认5局
        }
      }

      if (maxSets > 0) {
        return maxSets.toString();
      }
    } else if (this.gameType === GameType.TENNIS) {
      // 网球：显示盘数和抢七/抢10，格式如 "3 7" 或 "5 10"
      let maxSets: number | undefined = undefined;
      let tieBreakPoints: number | undefined = undefined;

      if (record.extraData) {
        if (typeof record.extraData.maxSets === 'number') {
          maxSets = record.extraData.maxSets;
        }
        if (typeof record.extraData.tieBreakPoints === 'number') {
          tieBreakPoints = record.extraData.tieBreakPoints;
        }
      }

      // 如果无法获取，使用默认值
      if (maxSets === undefined) {
        maxSets = 3; // 默认3盘
      }
      if (tieBreakPoints === undefined) {
        tieBreakPoints = 7; // 默认抢7
      }

      // 只显示有效的抢七/抢10值
      if (tieBreakPoints === 7 || tieBreakPoints === 10) {
        return `${maxSets} | ${tieBreakPoints}`;
      } else {
        return maxSets.toString();
      }
    }
    // 羽毛球固定3局2胜，不需要显示

    return undefined;
  }

  private async loadFromRecord(game: RecentGameDisplay): Promise<void> {
    try {
      // 加载队名
      this.team1Name = game.team1Name;
      this.team2Name = game.team2Name;

      // 如果是乒乓球或网球，尝试同步局数和抢七设置
      if (this.gameType === GameType.PINGPONG || this.gameType === GameType.TENNIS) {
        const record: ScoreboardRecord | null = await scoreboardRecordManager.getRecordById(game.recordId);
        if (record && record.extraData) {
          // 同步局数设置
          if (this.gameType === GameType.PINGPONG) {
            if (typeof record.extraData.maxSets === 'number' && record.extraData.maxSets > 0) {
              this.selectedMaxSets = record.extraData.maxSets;
            }
          } else if (this.gameType === GameType.TENNIS) {
            if (typeof record.extraData.maxSets === 'number' && record.extraData.maxSets > 0) {
              this.selectedMaxSets = record.extraData.maxSets;
            }
            if (typeof record.extraData.tieBreakPoints === 'number' && record.extraData.tieBreakPoints > 0) {
              this.selectedTieBreakPoints = record.extraData.tieBreakPoints;
            }
          }
        }
      }

      // 显示 toast 提示
      promptAction.showToast({
        message: $r('app.string.load_recent_game'),
        duration: 2000
      });
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to load from record:', error);
      // 即使出错也显示 toast
      promptAction.showToast({
        message: $r('app.string.load_recent_game'),
        duration: 2000
      });
    }
  }

  private openTeam1NameSelector(): void {
    try {
      let team1NameSelectorController: CustomDialogController | null = null;
      team1NameSelectorController = new CustomDialogController({
        builder: CommonNameSelectorDialog({
          nameType: NameType.TEAM,
          onSelect: (name: string) => {
            this.team1Name = name;
            team1NameSelectorController?.close();
          }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true,
        autoCancel: true
      });
      team1NameSelectorController.open();
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to open team1 name selector:', error);
    }
  }

  private openTeam2NameSelector(): void {
    try {
      let team2NameSelectorController: CustomDialogController | null = null;
      team2NameSelectorController = new CustomDialogController({
        builder: CommonNameSelectorDialog({
          nameType: NameType.TEAM,
          onSelect: (name: string) => {
            this.team2Name = name;
            team2NameSelectorController?.close();
          }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true,
        autoCancel: true
      });
      team2NameSelectorController.open();
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to open team2 name selector:', error);
    }
  }

  private async confirmSetup(): Promise<void> {
    console.info('[SportsSetupDialog] ========================================');
    console.info('[SportsSetupDialog] *** CONFIRM SETUP BUTTON CLICKED ***');
    console.info('[SportsSetupDialog] ========================================');
    console.info(`[SportsSetupDialog] GameType: ${this.gameType}`);
    console.info(`[SportsSetupDialog] team1Name: ${this.team1Name}, team2Name: ${this.team2Name}`);
    console.info(`[SportsSetupDialog] Current state - selectedMaxSets: ${this.selectedMaxSets}, selectedPointsPerSet: ${this.selectedPointsPerSet}, selectedTieBreakPoints: ${this.selectedTieBreakPoints}`);

    const config: SportsSetupResult = {
      team1Name: this.team1Name.trim() || this.defaultTeam1Name,
      team2Name: this.team2Name.trim() || this.defaultTeam2Name,
    };

    // 检查名称是否重复
    if (config.team1Name === config.team2Name) {
      console.warn('[SportsSetupDialog] Duplicate names detected');
      promptAction.showToast({
        message: $r('app.string.duplicate_names_warning'),
        duration: 2000
      });
      return;
    }

    if (this.gameType === GameType.PINGPONG) {
      // 乒乓球：确保传递有效的局数
      if (this.selectedMaxSets > 0) {
        config.maxSets = this.selectedMaxSets;
      } else {
        config.maxSets = 5; // 默认5局
      }
      config.pointsPerSet = 11; // 乒乓球固定为11分制
      config.autoChangeSides = this.autoChangeSides; // 传递自动换边设置
      console.info(`[SportsSetupDialog] PINGPONG config - selectedMaxSets: ${this.selectedMaxSets}, final maxSets: ${config.maxSets}, pointsPerSet: ${config.pointsPerSet}, autoChangeSides: ${config.autoChangeSides}`);
    } else if (this.gameType === GameType.TENNIS) {
      // 网球：确保传递有效的局数和抢七分数
      if (this.selectedMaxSets > 0) {
        config.maxSets = this.selectedMaxSets;
      } else {
        config.maxSets = 3; // 默认3局
      }
      if (this.selectedTieBreakPoints > 0) {
        config.tieBreakPoints = this.selectedTieBreakPoints;
      } else {
        config.tieBreakPoints = 7; // 默认7分
      }
      config.autoChangeSides = this.autoChangeSides; // 传递自动换边设置
      console.info(`[SportsSetupDialog] TENNIS config - selectedMaxSets: ${this.selectedMaxSets}, final maxSets: ${config.maxSets}, selectedTieBreakPoints: ${this.selectedTieBreakPoints}, final tieBreakPoints: ${config.tieBreakPoints}, autoChangeSides: ${config.autoChangeSides}`);
    } else if (this.gameType === GameType.BADMINTON) {
      // 羽毛球：传递自动换边设置
      config.autoChangeSides = this.autoChangeSides;
      console.info(`[SportsSetupDialog] BADMINTON config - autoChangeSides: ${config.autoChangeSides}`);
    } else if (this.gameType === GameType.VOLLEYBALL) {
      // 排球：传递自动换边设置
      config.autoChangeSides = this.autoChangeSides;
      console.info(`[SportsSetupDialog] VOLLEYBALL config - autoChangeSides: ${config.autoChangeSides}`);
    } else if (this.gameType === GameType.PICKLEBALL) {
      // 匹克球：传递所有配置
      config.gameMode = this.selectedGameMode;
      config.targetScore = this.selectedTargetScore;
      config.winByTwo = this.selectedWinByTwo;
      config.scoreCap = this.selectedScoreCap;
      config.useRallyScoring = this.selectedUseRallyScoring;
      config.maxSets = this.selectedMaxSets;
      console.info(`[SportsSetupDialog] PICKLEBALL config - gameMode: ${config.gameMode}, targetScore: ${config.targetScore}, winByTwo: ${config.winByTwo}, scoreCap: ${config.scoreCap}, useRallyScoring: ${config.useRallyScoring}, maxSets: ${config.maxSets}`);
    }

    // 自动保存输入的队名到常用名称
    try {
      if (config.team1Name && config.team1Name !== this.defaultTeam1Name) {
        await commonNamesManager.recordUsage(config.team1Name, NameType.TEAM);
        console.info(`[SportsSetupDialog] Saved team1Name: ${config.team1Name}`);
      }
      if (config.team2Name && config.team2Name !== this.defaultTeam2Name) {
        await commonNamesManager.recordUsage(config.team2Name, NameType.TEAM);
        console.info(`[SportsSetupDialog] Saved team2Name: ${config.team2Name}`);
      }
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to save team names:', error);
    }

    console.info('[SportsSetupDialog] Calling onConfirm...');
    console.info(`[SportsSetupDialog] Final Config: ${JSON.stringify(config)}`);

    if (this.onConfirm) {
      console.info('[SportsSetupDialog] onConfirm exists, calling it...');
      this.onConfirm(config);
      console.info('[SportsSetupDialog] onConfirm called successfully');
    } else {
      console.error('[SportsSetupDialog] onConfirm is undefined!');
    }

    // 关闭对话框
    this.closeDialog();
  }

  private closeDialog(): void {
    console.info('[SportsSetupDialog] closeDialog called');
    if (this.onCancel) {
      console.info('[SportsSetupDialog] Calling onCancel callback...');
      this.onCancel();
    } else {
      console.warn('[SportsSetupDialog] onCancel is undefined, trying controller.close()...');
      if (this.controller) {
        this.controller.close();
      } else {
        console.error('[SportsSetupDialog] controller is also undefined!');
      }
    }
  }

  private shouldShowSettings(): boolean {
    return this.gameType === GameType.PINGPONG || 
           this.gameType === GameType.TENNIS || 
           this.gameType === GameType.BADMINTON || 
           this.gameType === GameType.VOLLEYBALL ||
           this.gameType === GameType.PICKLEBALL;
  }

  private getTeamNameLabel(isTeam1: boolean): string {
    try {
      const context = getContext(this);
      const resourceManager = context.resourceManager;

      // 足球、排球、篮球使用"主队名称"/"客队名称"
      if (this.gameType === GameType.FOOTBALL ||
        this.gameType === GameType.VOLLEYBALL ||
        this.gameType === GameType.BASKETBALL) {
        return isTeam1
          ? resourceManager.getStringSync($r('app.string.team1_name').id)
          : resourceManager.getStringSync($r('app.string.team2_name').id);
      }

      // 其他运动项目统一使用"队伍/运动员名称"
      return resourceManager.getStringSync($r('app.string.team_or_player_name').id);
    } catch (error) {
      console.error('[SportsSetupDialog] Error in getTeamNameLabel:', error);
      try {
        const context = getContext(this);
        const resourceManager = context.resourceManager;
        return isTeam1
          ? resourceManager.getStringSync($r('app.string.team1_name').id)
          : resourceManager.getStringSync($r('app.string.team2_name').id);
      } catch (e) {
        return isTeam1 ? '主队名称' : '客队名称';
      }
    }
  }

  private getTitle(): string {
    console.info(`[SportsSetupDialog] getTitle() called for gameType: ${this.gameType}`);
    try {
      console.info('[SportsSetupDialog] Getting context...');
      const context = getContext(this);
      console.info('[SportsSetupDialog] Context obtained, getting resourceManager...');
      const resourceManager = context.resourceManager;
      console.info('[SportsSetupDialog] ResourceManager obtained');

      let title: string;
      switch (this.gameType) {
        case GameType.FOOTBALL:
          console.info('[SportsSetupDialog] Getting FOOTBALL title...');
          title = resourceManager.getStringSync($r('app.string.football_setup_title').id);
          break;
        case GameType.BASKETBALL:
          console.info('[SportsSetupDialog] Getting BASKETBALL title...');
          title = resourceManager.getStringSync($r('app.string.basketball_setup_title').id);
          break;
        case GameType.VOLLEYBALL:
          console.info('[SportsSetupDialog] Getting VOLLEYBALL title...');
          title = resourceManager.getStringSync($r('app.string.volleyball_setup_title').id);
          break;
        case GameType.PINGPONG:
          console.info('[SportsSetupDialog] Getting PINGPONG title...');
          title = resourceManager.getStringSync($r('app.string.pingpong_setup_title').id);
          break;
        case GameType.BADMINTON:
          console.info('[SportsSetupDialog] Getting BADMINTON title...');
          title = resourceManager.getStringSync($r('app.string.badminton_setup_title').id);
          break;
        case GameType.TENNIS:
          console.info('[SportsSetupDialog] Getting TENNIS title...');
          title = resourceManager.getStringSync($r('app.string.tennis_setup_title').id);
          break;
        case GameType.BILLIARDS:
          console.info('[SportsSetupDialog] Getting BILLIARDS title...');
          title = resourceManager.getStringSync($r('app.string.billiards_setup_title').id);
          break;
        case GameType.BOXING:
          console.info('[SportsSetupDialog] Getting BOXING title...');
          title = resourceManager.getStringSync($r('app.string.boxing_setup_title').id);
          break;
        case GameType.PICKLEBALL:
          console.info('[SportsSetupDialog] Getting PICKLEBALL title...');
          title = resourceManager.getStringSync($r('app.string.project_pickleball').id);
          break;
        default:
          console.info('[SportsSetupDialog] Getting default title...');
          title = resourceManager.getStringSync($r('app.string.sports_setup_section_settings').id);
          break;
      }
      console.info(`[SportsSetupDialog] Title obtained: ${title}`);
      return title;
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to get title:', error);
      try {
        const context = getContext(this);
        const resourceManager = context.resourceManager;
        return resourceManager.getStringSync($r('app.string.setup').id);
      } catch (e) {
        return 'Setup';
      }
    }
  }

  private getEmoji(): string {
    console.info(`[SportsSetupDialog] getEmoji() called for gameType: ${this.gameType}`);
    try {
      const emoji: string = GameTypeIcons[this.gameType];
      console.info(`[SportsSetupDialog] Emoji obtained: ${emoji}`);
      return emoji ?? '⚽';
    } catch (error) {
      console.error('[SportsSetupDialog] Failed to get emoji:', error);
      return '⚽';
    }
  }


  @Builder
  private buildSettingsSection() {
    if (this.shouldShowSettings()) {
      Column({ space: 12 }) {
        if (this.gameType === GameType.PINGPONG) {
          Column({ space: 12 }) {
            Text($r('app.string.pingpong_set_count_label'))
              .fontSize(14)
              .fontColor(this.getDialogSecondaryTextColor())
              .width('100%');

            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.pingpong_set_option_best_of_3'))
                  .fontSize(14)
                  .fontWeight(this.selectedMaxSets === 3 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedMaxSets === 3))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 3))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] BEFORE set selectedMaxSets = 3, current value:', this.selectedMaxSets);
                  this.selectedMaxSets = 3;
                  console.info('[SportsSetupDialog] AFTER set selectedMaxSets = 3, new value:', this.selectedMaxSets);
                })

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.pingpong_set_option_best_of_5'))
                  .fontSize(14)
                  .fontWeight(this.selectedMaxSets === 5 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedMaxSets === 5))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 5))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] BEFORE set selectedMaxSets = 5, current value:', this.selectedMaxSets);
                  this.selectedMaxSets = 5;
                  console.info('[SportsSetupDialog] AFTER set selectedMaxSets = 5, new value:', this.selectedMaxSets);
                })

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.pingpong_set_option_best_of_7'))
                  .fontSize(14)
                  .fontWeight(this.selectedMaxSets === 7 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedMaxSets === 7))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 7))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] BEFORE set selectedMaxSets = 7, current value:', this.selectedMaxSets);
                  this.selectedMaxSets = 7;
                  console.info('[SportsSetupDialog] AFTER set selectedMaxSets = 7, new value:', this.selectedMaxSets);
                })
            }
            .justifyContent(FlexAlign.Start)
              .width('100%');

            // 自动换边开关
            Row() {
              Text($r('app.string.pingpong_auto_change_sides'))
                .fontSize(14)
                .fontColor(this.getDialogTextColor())
                .layoutWeight(1);

              Toggle({ type: ToggleType.Switch, isOn: this.autoChangeSides })
                .selectedColor(this.getPrimaryButtonColor())
                .onChange((isOn: boolean) => {
                  this.autoChangeSides = isOn;
                });
            }
            .width('100%')
              .padding({ top: 8 });
          }
          .width('100%');
        } else if (this.gameType === GameType.TENNIS) {
          Column({ space: 12 }) {
            Text($r('app.string.tennis_set_count_label'))
              .fontSize(14)
              .fontColor(this.getDialogSecondaryTextColor())
              .width('100%');

            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.tennis_set_option_best_of_3'))
                  .fontSize(14)
                  .fontWeight(this.selectedMaxSets === 3 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedMaxSets === 3))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 3))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] TENNIS: BEFORE set selectedMaxSets = 3, current value:', this.selectedMaxSets);
                  this.selectedMaxSets = 3;
                  console.info('[SportsSetupDialog] TENNIS: AFTER set selectedMaxSets = 3, new value:', this.selectedMaxSets);
                })

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.tennis_set_option_best_of_5'))
                  .fontSize(14)
                  .fontWeight(this.selectedMaxSets === 5 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedMaxSets === 5))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 5))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] TENNIS: BEFORE set selectedMaxSets = 5, current value:', this.selectedMaxSets);
                  this.selectedMaxSets = 5;
                  console.info('[SportsSetupDialog] TENNIS: AFTER set selectedMaxSets = 5, new value:', this.selectedMaxSets);
                })
            }
            .justifyContent(FlexAlign.Start)
              .width('100%');

            Text($r('app.string.tennis_tiebreak_label'))
              .fontSize(14)
              .fontColor(this.getDialogSecondaryTextColor())
              .width('100%');

            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.tennis_tiebreak_option_7'))
                  .fontSize(14)
                  .fontWeight(this.selectedTieBreakPoints === 7 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedTieBreakPoints === 7))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedTieBreakPoints === 7))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] TENNIS: BEFORE set selectedTieBreakPoints = 7, current value:', this.selectedTieBreakPoints);
                  this.selectedTieBreakPoints = 7;
                  console.info('[SportsSetupDialog] TENNIS: AFTER set selectedTieBreakPoints = 7, new value:', this.selectedTieBreakPoints);
                })

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.tennis_tiebreak_option_10'))
                  .fontSize(14)
                  .fontWeight(this.selectedTieBreakPoints === 10 ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.getChipTextColor(this.selectedTieBreakPoints === 10))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(this.getChipBackgroundColor(this.selectedTieBreakPoints === 10))
                .borderRadius(16)
                .onClick(() => {
                  console.info('[SportsSetupDialog] TENNIS: BEFORE set selectedTieBreakPoints = 10, current value:', this.selectedTieBreakPoints);
                  this.selectedTieBreakPoints = 10;
                  console.info('[SportsSetupDialog] TENNIS: AFTER set selectedTieBreakPoints = 10, new value:', this.selectedTieBreakPoints);
                })
            }
            .justifyContent(FlexAlign.Start)
              .width('100%');

            // 自动换边开关
            Row() {
              Text($r('app.string.tennis_auto_change_sides'))
                .fontSize(14)
                .fontColor(this.getDialogTextColor())
                .layoutWeight(1);

              Toggle({ type: ToggleType.Switch, isOn: this.autoChangeSides })
                .selectedColor(this.getPrimaryButtonColor())
                .onChange((isOn: boolean) => {
                  this.autoChangeSides = isOn;
                });
            }
            .width('100%')
              .padding({ top: 8 });
          }
          .width('100%');
        } else if (this.gameType === GameType.BADMINTON) {
          // 羽毛球：只显示自动换边开关
          Row() {
            Text($r('app.string.badminton_auto_change_sides'))
              .fontSize(14)
              .fontColor(this.getDialogTextColor())
              .layoutWeight(1);

            Toggle({ type: ToggleType.Switch, isOn: this.autoChangeSides })
              .selectedColor(this.getPrimaryButtonColor())
              .onChange((isOn: boolean) => {
                this.autoChangeSides = isOn;
              });
          }
          .width('100%');
        } else if (this.gameType === GameType.VOLLEYBALL) {
          // 排球：只显示自动换边开关
          Row() {
            Text($r('app.string.volleyball_auto_change_sides'))
              .fontSize(14)
              .fontColor(this.getDialogTextColor())
              .layoutWeight(1);

            Toggle({ type: ToggleType.Switch, isOn: this.autoChangeSides })
              .selectedColor(this.getPrimaryButtonColor())
              .onChange((isOn: boolean) => {
                this.autoChangeSides = isOn;
              });
          }
          .width('100%');
        } else if (this.gameType === GameType.PICKLEBALL) {
          // 匹克球：显示所有配置选项
          Column({ space: 12 }) {
            // 游戏模式
            Column({ space: 8 }) {
              Text($r('app.string.pickleball_doubles'))
                .fontSize(14)
                .fontColor(this.getDialogSecondaryTextColor())
                .width('100%');

              Row({ space: 8 }) {
                Button({ type: ButtonType.Normal }) {
                  Text($r('app.string.pickleball_singles'))
                    .fontSize(14)
                    .fontWeight(this.selectedGameMode === 'singles' ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedGameMode === 'singles'))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedGameMode === 'singles'))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedGameMode = 'singles';
                  })

                Button({ type: ButtonType.Normal }) {
                  Text($r('app.string.pickleball_doubles'))
                    .fontSize(14)
                    .fontWeight(this.selectedGameMode === 'doubles' ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedGameMode === 'doubles'))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedGameMode === 'doubles'))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedGameMode = 'doubles';
                  })
              }
              .justifyContent(FlexAlign.Start)
                .width('100%');
            }

            // 目标分数
            Column({ space: 8 }) {
              Text($r('app.string.pickleball_target_score'))
                .fontSize(14)
                .fontColor(this.getDialogSecondaryTextColor())
                .width('100%');

              Row({ space: 8 }) {
                Button({ type: ButtonType.Normal }) {
                  Text('11')
                    .fontSize(14)
                    .fontWeight(this.selectedTargetScore === 11 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedTargetScore === 11))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedTargetScore === 11))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedTargetScore = 11;
                    // 11分制默认3局
                    this.selectedMaxSets = 3;
                  })

                Button({ type: ButtonType.Normal }) {
                  Text('15')
                    .fontSize(14)
                    .fontWeight(this.selectedTargetScore === 15 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedTargetScore === 15))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedTargetScore === 15))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedTargetScore = 15;
                    // 15分制默认1局
                    this.selectedMaxSets = 1;
                  })

                Button({ type: ButtonType.Normal }) {
                  Text('21')
                    .fontSize(14)
                    .fontWeight(this.selectedTargetScore === 21 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedTargetScore === 21))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedTargetScore === 21))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedTargetScore = 21;
                    // 21分制默认1局
                    this.selectedMaxSets = 1;
                  })
              }
              .justifyContent(FlexAlign.Start)
                .width('100%');
            }

            // 必须净胜2分
            Row() {
              Text($r('app.string.pickleball_win_by_two'))
                .fontSize(14)
                .fontColor(this.getDialogTextColor())
                .layoutWeight(1);

              Toggle({ type: ToggleType.Switch, isOn: this.selectedWinByTwo })
                .selectedColor(this.getPrimaryButtonColor())
                .onChange((isOn: boolean) => {
                  this.selectedWinByTwo = isOn;
                });
            }
            .width('100%');

            // 分数封顶
            Column({ space: 8 }) {
              Text($r('app.string.pickleball_score_cap'))
                .fontSize(14)
                .fontColor(this.getDialogSecondaryTextColor())
                .width('100%');

              Row({ space: 8 }) {
                Button({ type: ButtonType.Normal }) {
                  Text($r('app.string.pickleball_no_cap'))
                    .fontSize(14)
                    .fontWeight(this.selectedScoreCap === null ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedScoreCap === null))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedScoreCap === null))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedScoreCap = null;
                  })

                Button({ type: ButtonType.Normal }) {
                  Text('13')
                    .fontSize(14)
                    .fontWeight(this.selectedScoreCap === 13 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedScoreCap === 13))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedScoreCap === 13))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedScoreCap = 13;
                  })

                Button({ type: ButtonType.Normal }) {
                  Text('15')
                    .fontSize(14)
                    .fontWeight(this.selectedScoreCap === 15 ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.getChipTextColor(this.selectedScoreCap === 15))
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.getChipBackgroundColor(this.selectedScoreCap === 15))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedScoreCap = 15;
                  })
              }
              .justifyContent(FlexAlign.Start)
                .width('100%');
            }

            // 每球得分制
            Row() {
              Text($r('app.string.pickleball_rally_scoring'))
                .fontSize(14)
                .fontColor(this.getDialogTextColor())
                .layoutWeight(1);

              Toggle({ type: ToggleType.Switch, isOn: this.selectedUseRallyScoring })
                .selectedColor(this.getPrimaryButtonColor())
                .onChange((isOn: boolean) => {
                  this.selectedUseRallyScoring = isOn;
                });
            }
            .width('100%');

            // 局数选择（仅在11分制时显示，15/21分制固定1局）
            if (this.selectedTargetScore === 11) {
              Column({ space: 8 }) {
                Text($r('app.string.total_sets'))
                  .fontSize(14)
                  .fontColor(this.getDialogSecondaryTextColor())
                  .width('100%');

                Row({ space: 8 }) {
                  Button({ type: ButtonType.Normal }) {
                    Text('1')
                      .fontSize(14)
                      .fontWeight(this.selectedMaxSets === 1 ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.getChipTextColor(this.selectedMaxSets === 1))
                  }
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 1))
                    .borderRadius(16)
                    .onClick(() => {
                      this.selectedMaxSets = 1;
                    })

                  Button({ type: ButtonType.Normal }) {
                    Text('3')
                      .fontSize(14)
                      .fontWeight(this.selectedMaxSets === 3 ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.getChipTextColor(this.selectedMaxSets === 3))
                  }
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 3))
                    .borderRadius(16)
                    .onClick(() => {
                      this.selectedMaxSets = 3;
                    })

                  Button({ type: ButtonType.Normal }) {
                    Text('5')
                      .fontSize(14)
                      .fontWeight(this.selectedMaxSets === 5 ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.getChipTextColor(this.selectedMaxSets === 5))
                  }
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.getChipBackgroundColor(this.selectedMaxSets === 5))
                    .borderRadius(16)
                    .onClick(() => {
                      this.selectedMaxSets = 5;
                    })
                }
                .justifyContent(FlexAlign.Start)
                  .width('100%');
              }
            }
          }
          .width('100%');
        }
      }
      .width('100%')
        .padding({ top: 4 });
    }
  }

  build() {
    Column() {
      Column({ space: 0 }) {
        // 标题栏
        Row() {
          Row({ space: 4 }) {
            Text(this.getEmoji())
              .fontSize(20);
            Text(this.getTitle())
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getDialogTextColor());
          }
          .layoutWeight(1)
            .justifyContent(FlexAlign.Center);
        }
        .width('100%')
          .height(56)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 16, right: 16 });

        // 内容区域
        Column({ space: 16 }) {
          // 队伍1名称输入
          Column({ space: 8 }) {
            Text(this.getTeamNameLabel(true))
              .fontSize(14)
              .fontColor(this.getDialogSecondaryTextColor())
              .width('100%');

            Stack({ alignContent: Alignment.End }) {
              TextInput({ placeholder: this.defaultTeam1Name, text: this.team1Name })
                .width('100%')
                .height(44)
                .fontSize(16)
                .fontColor(this.getInputTextColor())
                .backgroundColor(this.getInputBackgroundColor())
                .borderRadius(8)
                .padding({ left: 12, right: 44 })
                .placeholderColor(this.getDialogSecondaryTextColor())
                .onChange((value: string) => {
                  this.team1Name = value;
                });

              Button({ type: ButtonType.Normal }) {
                Image($r('app.media.chevron_forward'))
                  .width(20)
                  .height(20);
              }
              .width(40)
                .height(40)
                .margin({ right: 2 })
                .backgroundColor('transparent')
                .borderRadius(8)
                .stateStyles({
                  pressed: {
                    .backgroundColor(this.getInputBackgroundColor())
                  },
                  normal: {
                    .backgroundColor('transparent')
                  }
                })
                .onClick(() => {
                  this.openTeam1NameSelector();
                });
            }
            .width('100%');
          }
          .width('100%')
            .alignItems(HorizontalAlign.Start);

          // 队伍2名称输入
          Column({ space: 8 }) {
            Text(this.getTeamNameLabel(false))
              .fontSize(14)
              .fontColor(this.getDialogSecondaryTextColor())
              .width('100%');

            Stack({ alignContent: Alignment.End }) {
              TextInput({ placeholder: this.defaultTeam2Name, text: this.team2Name })
                .width('100%')
                .height(44)
                .fontSize(16)
                .fontColor(this.getInputTextColor())
                .backgroundColor(this.getInputBackgroundColor())
                .borderRadius(8)
                .padding({ left: 12, right: 44 })
                .placeholderColor(this.getDialogSecondaryTextColor())
                .onChange((value: string) => {
                  this.team2Name = value;
                });

              Button({ type: ButtonType.Normal }) {
                Image($r('app.media.chevron_forward'))
                  .width(20)
                  .height(20);
              }
              .width(40)
                .height(40)
                .margin({ right: 2 })
                .backgroundColor('transparent')
                .borderRadius(8)
                .stateStyles({
                  pressed: {
                    .backgroundColor(this.getInputBackgroundColor())
                  },
                  normal: {
                    .backgroundColor('transparent')
                  }
                })
                .onClick(() => {
                  this.openTeam2NameSelector();
                });
            }
            .width('100%');
          }
          .width('100%')
            .alignItems(HorizontalAlign.Start);

          // 设置区域（如果有）
          this.buildSettingsSection();
        }
        .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 });

        // 最近比赛记录（横向滚动）
        if (this.recentGames.length > 0) {
          Column({ space: 8 }) {
            Row() {
              Text($r('app.string.recent_records'))
                .fontSize(14)
                .fontColor(this.getDialogSecondaryTextColor());

              Blank();

              Text($r('app.string.tap_to_quick_use'))
                .fontSize(11)
                .fontColor(this.getDialogSecondaryTextColor())
                .opacity(0.6);
            }
            .width('100%');

            Scroll(this.scroller) {
              Row({ space: 8 }) {
                ForEach(this.recentGames, (game: RecentGameDisplay, index: number) => {
                  Row({ space: 6 }) {
                    Text(game.team1Name)
                      .fontSize(13)
                      .fontColor(this.getDialogTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .maxFontSize(13);

                    Text(game.score)
                      .fontSize(12)
                      .fontColor(this.getDialogSecondaryTextColor());

                    Text(game.team2Name)
                      .fontSize(13)
                      .fontColor(this.getDialogTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .maxFontSize(13);

                    // 在右侧显示局数配置
                    if (game.setsInfo) {
                      Text(game.setsInfo)
                        .fontSize(11)
                        .fontColor(this.getPrimaryButtonColor())
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.getSetsInfoBackgroundColor())
                        .borderRadius(4);
                    }
                  }
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                    .backgroundColor(this.getRecordCardBackgroundColor())
                    .borderRadius(6)
                    .onClick(async () => {
                      await this.loadFromRecord(game);
                    })
                    .stateStyles({
                      pressed: {
                        .opacity(0.6)
                          .scale({ x: 0.95, y: 0.95 })
                      },
                      normal: {
                        .opacity(1)
                          .scale({ x: 1, y: 1 })
                      }
                    })
                    .animation({ duration: 150, curve: Curve.Sharp });
                }, (game: RecentGameDisplay, index: number) => `${game.recordId}_${index}`);
              }
            }
            .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%');
          }
          .width('100%')
            .padding({ left: 20, right: 20, bottom: 12 });
        }

        // 按钮区域
        Row({ space: 12 }) {
          // 取消按钮
          Button($r('app.string.cancel'))
            .type(ButtonType.Capsule)
            .width(100)
            .height(44)
            .fontSize(16)
            .fontColor(this.getDialogSecondaryTextColor())
            .backgroundColor(this.getInputBackgroundColor())
            .onClick(() => {
              console.info('[SportsSetupDialog] Cancel button clicked');
              this.closeDialog();
            });

          // 开始比赛按钮（主按钮）
          Button($r('app.string.start_game'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor(this.getPrimaryButtonColor())
            .onClick(async () => {
              console.info('[SportsSetupDialog] Start button clicked');
              await this.confirmSetup();
            });
        }
        .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 20 });
      }
      .width(340)
        .backgroundColor(this.getDialogBackgroundColor())
        .borderRadius(20)
        .clip(true)
        .shadow({
          radius: 32,
          color: 'rgba(0, 0, 0, 0.15)',
          offsetX: 0,
          offsetY: 12,
        });
    }
    .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(0, 0, 0, 0.6)');
  }
}
