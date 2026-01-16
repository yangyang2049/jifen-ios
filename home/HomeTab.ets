import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { Colors, FontSizes, Spacing, BorderRadius } from '../../common/theme';
import { 
  ActivityType, 
  RecentActivity, 
  GameType, 
  GameTypeIcons, 
  SourcePage, 
  RouterParams, 
  PlayerScore,
  UserPreferences 
} from '../../model/types';
import { NewGameDialog } from '../../components/NewGameDialog';
import { SportsSetupDialog, SportsSetupResult } from '../../components/SportsSetupDialog';
import { CardGameSetupDialog, CardGameSetupResult } from '../../components/CardGameSetupDialog';
import { RecordsViewModel } from '../../viewmodel/recordsViewModel';
import { GameRecordSummary, formatDuration } from '../../model/timerRecord';
import { scoreboardRecordsViewModel } from '../../viewmodel/scoreboardRecordsViewModel';
import { ScoreboardRecordSummary } from '../../model/scoreboardRecord';
import { timerRecordManager } from '../../managers/timerRecordManager';
import { scoreboardRecordManager } from '../../managers/scoreboardRecordManager';
import { deviceCapabilities, DeviceCapabilities } from '../../helpers/deviceDetection';
import { preferencesManager } from '../../managers/prefs';
import { quickStartConfigManager } from '../../managers/quickStartConfigManager';
import { QuickStartConfig, DEFAULT_QUICK_START_CONFIG_PHONE } from '../../model/QuickStartConfig';
import { GoSettingsView, GoTimerSettings } from '../../components/GoSettingsView';
import { XiangqiSettingsView, XiangqiTimerSettings } from '../../components/XiangqiSettingsView';
import { ChessSettingsView, ChessTimerSettings } from '../../components/ChessSettingsView';

// New Design D Components
import { QuickStartGrid } from './components/QuickStartGrid';
import { ProToolsSection } from './components/ProToolsSection';
import { RecentRecordsSection } from './components/RecentRecordsSection';
import { LiveActivityBanner, LiveGameInfo } from './components/LiveActivityBanner';
import { QuickStartEditDialog } from './components/QuickStartEditDialog';
import { getGameName } from './components/HomeUtils';

interface ActivityWithRecord {
  activity: RecentActivity;
  timerRecord?: GameRecordSummary;
  scoreboardRecord?: ScoreboardRecordSummary;
}

@Component
export struct HomeTab {
  // Navigation & Data Callbacks
  onNavigateToTab?: (index: number) => void;
  onViewAllActivities?: () => void;
  onActivitySelected?: (activity: RecentActivity) => void;

  // Device & Layout State
  @State private deviceInfo: DeviceCapabilities = deviceCapabilities.getCapabilities();
  @State private isWide: boolean = false;
  @State private isDarkTheme: boolean = true; // Use black UI theme

  // Data State
  @State recentActivities: Array<RecentActivity> = [];
  @State private timerRecords: GameRecordSummary[] = [];
  @State private scoreboardRecords: ScoreboardRecordSummary[] = [];
  
  // Configuration
  @State private quickStartConfig: QuickStartConfig = DEFAULT_QUICK_START_CONFIG_PHONE;
  @StorageLink('quickStartConfigUpdated') @Watch('onQuickStartConfigUpdated') quickStartConfigUpdatedTimestamp: number = 0;

  // Dialog Controllers
  private newGameDialogController?: CustomDialogController;
  private activeDialogController: CustomDialogController | null = null;

  // Quick Start Edit Dialog Controller
  private quickStartEditDialogController: CustomDialogController | null = null;

  // Timer Settings State
  @State private isTimerSettingsSheetOpen: boolean = false;
  @State private selectedTimerGameType: 'Go' | 'Xiangqi' | 'Chess' | null = null;
  @State private goSettings: GoTimerSettings | null = null;
  @State private xiangqiSettings: XiangqiTimerSettings | null = null;
  @State private chessSettings: ChessTimerSettings | null = null;
  
  // Date State
  @State private headerDate: string = '';

  // ViewModels
  private recordsViewModel: RecordsViewModel = RecordsViewModel.getInstance();
  private updateListener: () => void = () => {
    this.updateTimerRecords();
  };
  private updateScoreboardListener: () => void = () => {
    this.updateScoreboardRecords();
  };

  // Debounce
  private lastRefreshTime: number = 0;
  private readonly REFRESH_DEBOUNCE_TIME: number = 1000;

  aboutToAppear(): void {
    // Initialize Layout
    this.updateLayoutState();
    this.updateHeaderDate();
    
    // Initialize Managers & Data
    this.initializeDialogControllers();
    this.loadQuickStartConfig();
    this.initializeDataManagers();
  }

  aboutToDisappear(): void {
    this.recordsViewModel.removeListener(this.updateListener);
    scoreboardRecordsViewModel.removeListener(this.updateScoreboardListener);
  }

  private updateHeaderDate(): void {
    const now = new Date();
    this.headerDate = `${now.toLocaleDateString('zh-CN', { month: 'long', day: 'numeric' })}  ${now.toLocaleDateString('zh-CN', { weekday: 'long' })}`;
  }

  private updateLayoutState() {
    this.isWide = this.deviceInfo.isTablet || this.deviceInfo.is2in1 || this.deviceInfo.screenWidth >= 768;
    // Check system theme if possible, defaulting to light for now or dark if preferred
    // For now we pass isDarkTheme as false (light) or check if we can get it from context
    try {
       // const context = getContext(this);
       // const config = context.config;
       // Simply checking colorMode if available, otherwise default false
       // this.isDarkTheme = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {}
  }

  // --- Initialization & Data Loading ---

  private initializeDataManagers() {
    try {
      const uiContext = getContext(this) as common.UIAbilityContext;

      timerRecordManager.init(uiContext).then(() => {
        this.recordsViewModel.refreshRecords();
      }).catch((error: Error) => console.error('[HomeTab] Timer Manager Init Failed:', error));

      scoreboardRecordManager.init(uiContext).then(async () => {
        await scoreboardRecordsViewModel.init(uiContext);
        scoreboardRecordsViewModel.refreshRecords();
      }).catch((error: Error) => console.error('[HomeTab] Scoreboard Manager Init Failed:', error));

      this.recordsViewModel.addListener(this.updateListener);
      scoreboardRecordsViewModel.addListener(this.updateScoreboardListener);
      this.recordsViewModel.loadRecordsInBackground();
      
      this.updateTimerRecords();
      this.updateScoreboardRecords();
    } catch (error) {
      console.error('[HomeTab] Init Error:', error);
    }
  }

  private async loadQuickStartConfig(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await quickStartConfigManager.init(context);
      const config = await quickStartConfigManager.loadConfig(this.deviceInfo.isLargeScreen, this.deviceInfo.is2in1);
      if (config) {
        this.quickStartConfig = config;
      }
    } catch (error) {
      console.error('[HomeTab] Failed to load config:', error);
      // Fallback
      this.quickStartConfig = DEFAULT_QUICK_START_CONFIG_PHONE;
    }
  }

  private onQuickStartConfigUpdated(): void {
    this.loadQuickStartConfig();
  }

  private updateTimerRecords(): void {
    this.timerRecords = this.recordsViewModel.getRecords();
    this.updateRecentActivities();
  }

  private updateScoreboardRecords(): void {
    this.scoreboardRecords = scoreboardRecordsViewModel.getRecords();
    this.updateRecentActivities();
  }

  private updateRecentActivities(): void {
    // Combine and sort records for display
    const activities: RecentActivity[] = [];
    const context = getContext(this);
    const resourceManager = context.resourceManager;
    const gameEndedText = resourceManager.getStringSync($r('app.string.home_game_ended').id);
    
    this.timerRecords.forEach(r => {
      activities.push({
        id: r.id,
        activityType: ActivityType.TIMER,
        gameType: r.gameType,
        timestamp: r.timestamp,
        title: getGameName(r.gameType),
        description: r.duration ? formatDuration(r.duration) : gameEndedText
      });
    });

    this.scoreboardRecords.forEach(r => {
       activities.push({
         id: r.id,
         activityType: ActivityType.SCOREBOARD,
         gameType: r.gameType,
         timestamp: r.timestamp,
         title: `${r.team1Name} vs ${r.team2Name}`,
         description: `${r.team1FinalScore} : ${r.team2FinalScore}`
       });
    });

    // Sort by timestamp desc, take top 5
    this.recentActivities = activities.sort((a, b) => b.timestamp - a.timestamp).slice(0, 5);
  }

  private refreshDataOnVisible(): void {
    const now = Date.now();
    if (now - this.lastRefreshTime < this.REFRESH_DEBOUNCE_TIME) return;
    this.lastRefreshTime = now;
    
    this.recordsViewModel.refreshRecords();
    scoreboardRecordsViewModel.refreshRecords();
  }

  // --- Dialogs & Controllers ---

  private initializeDialogControllers() {
    // New Game Dialog
    this.newGameDialogController = new CustomDialogController({
      builder: NewGameDialog({
        sourcePage: SourcePage.HOME,
        onSelect: (type: ActivityType, sourcePage: SourcePage) => {
          // 关闭对话框
          this.newGameDialogController?.close();
          this.handleNewGameSelection(type, sourcePage);
        },
        onCancel: () => {
          // 确保对话框关闭
          this.newGameDialogController?.close();
        },
        onTimerGameSelected: (gameType: 'Go' | 'Xiangqi' | 'Chess') => {
          // 对话框已经在 NewGameDialog 内部关闭，这里只需要设置状态
          // 确保快速开始配置对话框关闭
          this.quickStartEditDialogController?.close();
          // 先设置游戏类型，再打开 sheet，确保状态正确
          this.selectedTimerGameType = gameType;
          // 使用 setTimeout 确保状态更新顺序
          setTimeout(() => {
            this.isTimerSettingsSheetOpen = true;
          }, 0);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
  }

  // --- Actions ---

  private async saveQuickStartConfig(primary: GameType, secondary: GameType) {
    try {
      await quickStartConfigManager.setPrimarySport(primary);
      await quickStartConfigManager.setSecondarySport(secondary);
      this.loadQuickStartConfig(); // Reload to update UI
    } catch (error) {
      console.error('[HomeTab] Failed to save quick start config:', error);
    }
  }

  private handleNewGameSelection(type: ActivityType, sourcePage: SourcePage): void {
    if (type === ActivityType.SCOREBOARD) this.onNavigateToTab?.(1);
    else if (type === ActivityType.TIMER) this.onNavigateToTab?.(2);
  }

  private openNewGameDialog(): void {
    this.newGameDialogController?.open();
  }

  private openEditDialog = (): void => {
    console.info('[HomeTab] openEditDialog called');
    // 确保计时器设置 sheet 关闭
    if (this.isTimerSettingsSheetOpen) {
      this.isTimerSettingsSheetOpen = false;
      this.selectedTimerGameType = null;
    }
    
    // Clean up old controller
    if (this.quickStartEditDialogController) {
      this.quickStartEditDialogController.close();
      this.quickStartEditDialogController = null;
    }
    
    // 创建并打开对话框
    this.quickStartEditDialogController = new CustomDialogController({
      builder: QuickStartEditDialog({
        isDarkTheme: this.isDarkTheme,
        currentPrimary: this.quickStartConfig?.primarySport || GameType.BASKETBALL,
        currentSecondary: this.quickStartConfig?.secondarySport || GameType.BADMINTON,
        onSave: (primary: GameType, secondary: GameType) => {
          this.saveQuickStartConfig(primary, secondary);
          this.quickStartEditDialogController?.close();
        },
        onCancel: () => {
          this.quickStartEditDialogController?.close();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.quickStartEditDialogController.open();
  }

  // --- Navigation Logic (Preserved from Original) ---
  
  private navigateToGame(gameType: GameType): void {
     // 1. Sports Games
     const sports = [
       GameType.FOOTBALL, GameType.BASKETBALL, GameType.VOLLEYBALL, GameType.PINGPONG, 
       GameType.BADMINTON, GameType.TENNIS, GameType.BILLIARDS, GameType.BOXING, GameType.PICKLEBALL
     ];
     
     if (sports.includes(gameType)) {
       try {
         const context = getContext(this);
         const resourceManager = context.resourceManager;
         const team1 = resourceManager.getStringSync($r('app.string.red_team').id);
         const team2 = resourceManager.getStringSync($r('app.string.blue_team').id);
         
         // Clean up old controller
         if (this.activeDialogController) {
           this.activeDialogController.close();
           this.activeDialogController = null;
         }
         
         this.activeDialogController = new CustomDialogController({
           builder: SportsSetupDialog({
             gameType: gameType,
             defaultTeam1Name: team1,
             defaultTeam2Name: team2,
             onConfirm: (config) => {
               this.navigateToSportsWithConfig(gameType, config);
               this.activeDialogController?.close();
             },
             onCancel: () => {
               this.activeDialogController?.close();
             }
           }),
           autoCancel: true,
           alignment: DialogAlignment.Center,
           customStyle: true
         });
         this.activeDialogController.open();
       } catch (e) {
         console.error(`[HomeTab] Failed to open sports setup for ${gameType}:`, e);
       }
       return;
     }

     // 2. Card Games
     const cards = [GameType.DOUDIZHU, GameType.GUANDAN, GameType.SIMPLE_SCORE, GameType.MULTI_SCOREBOARD];
     if (cards.includes(gameType)) {
       try {
         const context = getContext(this);
         const resourceManager = context.resourceManager;
         const defaultTeam1 = resourceManager.getStringSync($r('app.string.red_team').id);
         const defaultTeam2 = resourceManager.getStringSync($r('app.string.blue_team').id);
         
         let names: string[] = [];
         if (gameType === GameType.DOUDIZHU) names = ['A', 'B', 'C'];
         else if (gameType === GameType.MULTI_SCOREBOARD) names = ['P1', 'P2', 'P3', 'P4'];
         else names = [defaultTeam1, defaultTeam2];

         // Clean up old controller
         if (this.activeDialogController) {
           this.activeDialogController.close();
           this.activeDialogController = null;
         }

         this.activeDialogController = new CustomDialogController({
           builder: CardGameSetupDialog({
             gameType: gameType,
             defaultPlayerNames: names,
             onConfirm: (config) => {
               this.navigateToCardGame(gameType, config);
               this.activeDialogController?.close();
             },
             onCancel: () => {
               this.activeDialogController?.close();
             }
           }),
           autoCancel: true,
           alignment: DialogAlignment.Center,
           customStyle: true
         });
         this.activeDialogController.open();
       } catch (e) {
         console.error(`[HomeTab] Failed to open card setup for ${gameType}:`, e);
       }
       return;
     }

     // 3. Timer Games
     if ([GameType.GO, GameType.XIANGQI, GameType.CHESS].includes(gameType)) {
       this.selectedTimerGameType = gameType === GameType.GO ? 'Go' : (gameType === GameType.XIANGQI ? 'Xiangqi' : 'Chess');
       this.isTimerSettingsSheetOpen = true;
       return;
     }

     // 4. Direct Navigation Fallback
     try {
       const route = this.getGameRoute(gameType);
       router.pushUrl({ url: route, params: { sourcePage: SourcePage.HOME } });
     } catch (e) {
       console.error(`[HomeTab] Navigation failed for ${gameType}:`, e);
     }
  }

  private navigateToSportsWithConfig(gameType: GameType, config: SportsSetupResult): void {
    const route = this.getGameRoute(gameType);
    const params: RouterParams = {
        sourcePage: SourcePage.HOME as Object,
        team1Name: config.team1Name as Object,
        team2Name: config.team2Name as Object,
        // ... Copy other optional params if needed
    };
    // Basic param copying for MVP
    if (config.maxSets) params.maxSets = config.maxSets as Object;
    if (config.pointsPerSet) params.pointsPerSet = config.pointsPerSet as Object;
    
    router.pushUrl({ url: route, params: params });
  }

  private navigateToCardGame(gameType: GameType, config: CardGameSetupResult): void {
    const route = this.getGameRoute(gameType);
    router.pushUrl({
        url: route,
        params: {
            sourcePage: SourcePage.HOME as Object,
            playerNames: config.playerNames as Object,
            players: config.playerNames as Object // For multi-score
        }
    });
  }

  private startTimerGame(): void {
    const context = getContext(this);
    const resourceManager = context.resourceManager;
    // Common default values
    const fastChess = resourceManager.getStringSync($r('app.string.fast_chess').id);
    // Assuming '横版' corresponds to 'landscape' or similar. 
    // If '横版' is not in strings, we can keep it or use a safe default if available.
    // Looking at string.json, we don't see 'landscape' translation explicitly as '横版'.
    // However, GoTimer seems to expect '横版'.
    // If I cannot find a resource for '横版', I will leave it hardcoded or use a constant if I created one.
    // For now, I will leave '横版' as is to avoid breaking logic, but replace '快棋'.
    
    if (this.selectedTimerGameType === 'Go') {
      const goSettings = this.goSettings || {
        timeMode: fastChess,
        mainTimeMinutes: 60,
        mainTimeSeconds: 0,
        byoyomiSeconds: 30,
        byoyomiTimes: 3,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      router.pushUrl({
        url: 'pages/timer/GoTimer',
        params: {
          gameType: this.selectedTimerGameType,
          timeMode: goSettings.timeMode,
          mainTimeMinutes: goSettings.mainTimeMinutes,
          mainTimeSeconds: goSettings.mainTimeSeconds,
          incrementSeconds: 0,
          byoyomiSeconds: goSettings.byoyomiSeconds,
          byoyomiTimes: goSettings.byoyomiTimes,
          soundEnabled: goSettings.soundEnabled,
          vibrationEnabled: goSettings.vibrationEnabled,
          redFlashEnabled: goSettings.redFlashEnabled,
          selectedLayout: goSettings.selectedLayout,
          sourcePage: SourcePage.HOME
        }
      }).catch((error: Error) => {
        console.error(`[HomeTab] Failed to navigate to GoTimer:`, error);
      });
    } else if (this.selectedTimerGameType === 'Xiangqi') {
      const xiangqiSettings = this.xiangqiSettings || {
        timeMode: fastChess,
        mainTimeMinutes: 10,
        mainTimeSeconds: 0,
        incrementSeconds: 10,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      router.pushUrl({
        url: 'pages/timer/XiangqiTimer',
        params: {
          gameType: this.selectedTimerGameType,
          timeMode: xiangqiSettings.timeMode,
          mainTimeMinutes: xiangqiSettings.mainTimeMinutes,
          mainTimeSeconds: xiangqiSettings.mainTimeSeconds,
          incrementSeconds: xiangqiSettings.incrementSeconds,
          byoyomiSeconds: 0,
          byoyomiTimes: 0,
          soundEnabled: xiangqiSettings.soundEnabled,
          vibrationEnabled: xiangqiSettings.vibrationEnabled,
          redFlashEnabled: xiangqiSettings.redFlashEnabled,
          selectedLayout: xiangqiSettings.selectedLayout,
          sourcePage: SourcePage.HOME
        }
      }).catch((error: Error) => {
        console.error(`[HomeTab] Failed to navigate to XiangqiTimer:`, error);
      });
    } else if (this.selectedTimerGameType === 'Chess') {
      const chessSettings = this.chessSettings || {
        timeMode: fastChess,
        mainTimeMinutes: 15,
        mainTimeSeconds: 0,
        incrementSeconds: 10,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      router.pushUrl({
        url: 'pages/timer/ChessTimer',
        params: {
          gameType: this.selectedTimerGameType,
          timeMode: chessSettings.timeMode,
          mainTimeMinutes: chessSettings.mainTimeMinutes,
          mainTimeSeconds: chessSettings.mainTimeSeconds,
          incrementSeconds: chessSettings.incrementSeconds,
          byoyomiSeconds: 0,
          byoyomiTimes: 0,
          soundEnabled: chessSettings.soundEnabled,
          vibrationEnabled: chessSettings.vibrationEnabled,
          redFlashEnabled: chessSettings.redFlashEnabled,
          selectedLayout: chessSettings.selectedLayout,
          sourcePage: SourcePage.HOME
        }
      }).catch((error: Error) => {
        console.error(`[HomeTab] Failed to navigate to ChessTimer:`, error);
      });
    }
  }

  private getGameRoute(gameType: GameType): string {
    // ... (Map gameType to route string, copied from original)
    // Simplified mapping:
    switch (gameType) {
        case GameType.FOOTBALL: return 'pages/scoreboard/sports/FootballScoreboard';
        case GameType.BASKETBALL: return 'pages/scoreboard/sports/BasketballScoreboard';
        case GameType.BADMINTON: return 'pages/scoreboard/sports/BadmintonScoreboard';
        case GameType.PINGPONG: return 'pages/scoreboard/sports/PingPongScoreboard';
        case GameType.TENNIS: return 'pages/scoreboard/sports/TennisScoreboard';
        case GameType.VOLLEYBALL: return 'pages/scoreboard/sports/VolleyballScoreboard';
        case GameType.BILLIARDS: return 'pages/scoreboard/sports/BilliardsScoreboard';
        case GameType.BOXING: return 'pages/scoreboard/sports/BoxingScoreboard';
        case GameType.PICKLEBALL: return 'pages/scoreboard/sports/PickleballScoreboard';
        case GameType.DOUDIZHU: return 'pages/scoreboard/cards/DoudizhuScore';
        case GameType.GUANDAN: return 'pages/scoreboard/cards/GuandanScore';
        case GameType.SIMPLE_SCORE: return 'pages/scoreboard/cards/SimpleScorePage';
        case GameType.MULTI_SCOREBOARD: return 'pages/scoreboard/cards/MultiGroupScore';
        case GameType.GO: return 'pages/timer/GoTimer';
        case GameType.XIANGQI: return 'pages/timer/XiangqiTimer';
        case GameType.CHESS: return 'pages/timer/ChessTimer';
        default: return 'pages/scoreboard/sports/FootballScoreboard';
    }
  }

  private handleToolClick(toolId: string) {
    let route = '';
    switch (toolId) {
      case 'whistle': route = 'pages/tools/WhistleTool'; break;
      case 'rankings': route = 'pages/tools/PointsTable'; break;
      case 'coin': route = 'pages/tools/FlipCoin'; break;
      case 'dice': route = 'pages/tools/DiceTool'; break;
      case 'team': route = 'pages/tools/RandomTeam'; break;
      case 'timer': route = 'pages/tools/TenSecondChallenge'; break;
      default: 
        console.info('[HomeTab] Tool not implemented or no route:', toolId);
        return;
    }
    
    router.pushUrl({ url: route }).catch((e: Error) => {
      console.error(`[HomeTab] Failed to navigate to tool ${toolId}:`, e);
    });
  }

  // --- UI Building ---

  build() {
    Column() {
      // Main Content (Scrollable)
      Scroll() {
        Column() {
          // 1. Header (Now scrollable)
          this.buildHeader()

          if (this.isWide) {
             this.buildDesktopLayout();
          } else {
             this.buildMobileLayout();
             
             Column({ space: Spacing.md }) {
               Row({ space: Spacing.sm }) {
                 Text($r('app.string.recent_records'))
                   .fontSize(FontSizes.h5)
                   .fontWeight(FontWeight.Medium)
                   .fontColor(Colors.textPrimary)
               }
               .width('100%')
               .padding({ left: Spacing.lg, right: Spacing.lg })
               
               Row() {
                 RecentRecordsSection({
                   records: this.recentActivities,
                   isDarkTheme: this.isDarkTheme,
                   onSeeAllClick: () => router.pushUrl({ url: 'pages/activity/RecentActivityPage' })
                 })
               }
               .width('100%')
               .padding({ left: Spacing.lg, right: Spacing.lg, bottom: 0 })
             }
             .width('100%')
             .margin({ top: Spacing.lg })
          }
        }
        .width('100%')
        .padding({ bottom: 0 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkTheme ? Colors.background : Colors.homeBackgroundLight)
    .onAreaChange((o, n) => {
        const w = Number(n.width);
        const h = Number(n.height);
        deviceCapabilities.updateScreenSize(w, h);
        this.deviceInfo = deviceCapabilities.getCapabilities();
        this.updateLayoutState();
    })
    .onVisibleAreaChange([0.0, 1.0], (isVisible, ratio) => {
        if (isVisible && ratio > 0.5) this.refreshDataOnVisible();
    })
    .bindSheet($$this.isTimerSettingsSheetOpen, this.buildTimerSettingsSheet, {
        height: this.deviceInfo.isWideScreen ? 560 : SheetSize.MEDIUM,
        width: this.deviceInfo.isWideScreen ? 480 : undefined,
        dragBar: !this.deviceInfo.isWideScreen,
        blurStyle: BlurStyle.Thick,
        showClose: true,
        preferType: this.deviceInfo.isWideScreen ? SheetType.CENTER : SheetType.BOTTOM,
        title: { title: this.getGameTitle(this.selectedTimerGameType) },
        onWillDismiss: () => {
          this.isTimerSettingsSheetOpen = false;
          this.selectedTimerGameType = null;
        }
    })
  }

  @Builder
  buildHeader() {
    Column() {
      Row() {
        Column() {
          Text($r('app.string.app_name'))
            .fontSize(FontSizes.h4)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.textPrimary)
          
          Text(this.headerDate)
            .fontSize(FontSizes.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.textSecondary)
            .margin({ top: Spacing.xs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Row({ space: Spacing.xs }) {
          Image($r('app.media.ic_display'))
            .width(16)
            .height(16)
          Text($r('app.string.home_share'))
            .fontSize(FontSizes.body2)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.textOnPrimary)
        }
        .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
        .borderRadius(BorderRadius.round)
        .backgroundColor(Colors.primary)
        .onClick(() => {
           router.pushUrl({ url: 'pages/display/JoinMatchPage' });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: 0 })
  }

  @Builder
  buildMobileLayout() {
    Column({ space: 32 }) {
       QuickStartGrid({
         primarySport: this.quickStartConfig?.primarySport || GameType.BASKETBALL,
         secondarySport: this.quickStartConfig?.secondarySport || GameType.BADMINTON,
         isDarkTheme: this.isDarkTheme,
         onPrimaryClick: () => this.navigateToGame(this.quickStartConfig?.primarySport || GameType.BASKETBALL),
         onSecondaryClick: () => this.navigateToGame(this.quickStartConfig?.secondarySport || GameType.BADMINTON),
         onNewGameClick: () => this.openNewGameDialog(),
         onEditClick: () => this.openEditDialog()
       })

       ProToolsSection({
         isWide: false,
         isDarkTheme: this.isDarkTheme,
         onToolClick: (id: string): void => {
           this.handleToolClick(id);
         }
       })

    }
    .padding({ left: 24, right: 24 })
  }

  @Builder
  buildDesktopLayout() {
    Grid() {
      GridItem() {
        Column({ space: 32 }) {
          QuickStartGrid({
            primarySport: this.quickStartConfig?.primarySport || GameType.BASKETBALL,
            secondarySport: this.quickStartConfig?.secondarySport || GameType.BADMINTON,
            isDarkTheme: this.isDarkTheme,
            onPrimaryClick: () => this.navigateToGame(this.quickStartConfig?.primarySport || GameType.BASKETBALL),
            onSecondaryClick: () => this.navigateToGame(this.quickStartConfig?.secondarySport || GameType.BADMINTON),
            onNewGameClick: () => this.openNewGameDialog(),
            onEditClick: () => this.openEditDialog()
          })

          ProToolsSection({
            isWide: true,
            isDarkTheme: this.isDarkTheme,
            onToolClick: (id: string): void => {
           this.handleToolClick(id);
         }
          })
        }
      }
      .columnStart(0)
      .columnEnd(7)

      GridItem() {
        Column() {
           Row({ space: Spacing.sm }) {
             Text($r('app.string.recent_records'))
               .fontSize(FontSizes.h5)
               .fontWeight(FontWeight.Medium)
               .fontColor(Colors.textPrimary)
           }
           .width('100%')
           .margin({ bottom: 16 })
           
           RecentRecordsSection({
             records: this.recentActivities,
             isDarkTheme: this.isDarkTheme,
             onSeeAllClick: () => router.pushUrl({ url: 'pages/activity/RecentActivityPage' })
           })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: Spacing.lg }) // Match QuickStartGrid's top margin
      }
      .columnStart(8)
      .columnEnd(11)
      .margin({ left: 32 }) // Add gutter
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr') // 12 cols
    .padding({ left: 24, right: 24 })
  }

  private getGameTitle(selectedGameType: 'Go' | 'Xiangqi' | 'Chess' | null): ResourceStr {
    switch (selectedGameType) {
      case 'Go': return $r('app.string.timer_go_settings');
      case 'Xiangqi': return $r('app.string.timer_xiangqi_settings');
      case 'Chess': return $r('app.string.timer_chess_settings');
      default: return $r('app.string.timer_game_settings');
    }
  }

  @Builder
  private buildTimerSettingsSheet() {
    Column({ space: 16 }) {
      if (this.selectedTimerGameType === 'Go') {
        GoSettingsView({
          onDismiss: () => {
            this.isTimerSettingsSheetOpen = false;
            this.selectedTimerGameType = null;
          },
          onSettingsChange: (s) => {
            this.goSettings = s;
          }
        })
      } else if (this.selectedTimerGameType === 'Xiangqi') {
        XiangqiSettingsView({
          onDismiss: () => {
            this.isTimerSettingsSheetOpen = false;
            this.selectedTimerGameType = null;
          },
          onSettingsChange: (s) => {
            this.xiangqiSettings = s;
          }
        })
      } else if (this.selectedTimerGameType === 'Chess') {
        ChessSettingsView({
          onDismiss: () => {
            this.isTimerSettingsSheetOpen = false;
            this.selectedTimerGameType = null;
          },
          onSettingsChange: (s) => {
            this.chessSettings = s;
          }
        })
      } else {
        Column() {
          Text($r('app.string.timer_select_mode'))
            .fontSize(16)
            .fontColor(Colors.textSecondary)
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      if (this.selectedTimerGameType) {
        Button($r('app.string.timer_start_game'))
          .type(ButtonType.Capsule)
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Colors.primary)
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.startTimerGame();
            this.isTimerSettingsSheetOpen = false;
            this.selectedTimerGameType = null;
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.isDarkTheme ? Colors.background : Colors.homeBackgroundLight)
  }
}