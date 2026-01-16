import { ActivityType, GameType, GameTypeIcons, SourcePage, RouterParams } from '../model/types';
import { Colors } from '../common/theme';
import router from '@ohos.router';
import { SportsSetupDialog, SportsSetupResult } from './SportsSetupDialog';
import { CardGameSetupDialog, CardGameSetupResult } from './CardGameSetupDialog';
import { GoSettingsView, GoTimerSettings } from './GoSettingsView';
import { XiangqiSettingsView, XiangqiTimerSettings } from './XiangqiSettingsView';
import { ChessSettingsView, ChessTimerSettings } from './ChessSettingsView';
import common from '@ohos.app.ability.common';

interface GameItem {
  type: GameType;
  nameRes: Resource;
  emoji: string;
  route: string;
}


@CustomDialog
export struct NewGameDialog {
  controller?: CustomDialogController
  onSelect?: (type: ActivityType, sourcePage: SourcePage) => void;
  onCancel?: () => void;
  onTimerGameSelected?: (gameType: 'Go' | 'Xiangqi' | 'Chess') => void;
  sourcePage: SourcePage = SourcePage.HOME; // 默认来源页面

  @State private currentTabIndex: number = 0;
  @State private showTimerSettings: boolean = false;
  @State private selectedTimerGameType: 'Go' | 'Xiangqi' | 'Chess' | null = null;
  @State private goSettings: GoTimerSettings | null = null;
  @State private xiangqiSettings: XiangqiTimerSettings | null = null;
  @State private chessSettings: ChessTimerSettings | null = null;
  
  private sportsSetupDialogController?: CustomDialogController;
  private cardGameSetupDialogController?: CustomDialogController;


  @Builder
  private buildTabBarItem(text: ResourceStr, index: number) {
    Column() {
      Text(text)
        .fontSize(16)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTabIndex === index ? Colors.primary : Colors.textSecondary)
      
      // Indicator
      Divider()
        .strokeWidth(2)
        .color(this.currentTabIndex === index ? Colors.primary : Color.Transparent)
        .width(24)
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  private getScoreboardItems(): GameItem[] {
    return [
      // 非快速开始比赛 - 放在顶部，更常用
      { type: GameType.VOLLEYBALL, nameRes: $r('app.string.tab_volleyball'), emoji: GameTypeIcons[GameType.VOLLEYBALL], route: 'pages/scoreboard/sports/VolleyballScoreboard' },
      { type: GameType.PINGPONG, nameRes: $r('app.string.tab_pingpong'), emoji: GameTypeIcons[GameType.PINGPONG], route: 'pages/scoreboard/sports/PingPongScoreboard' },
      { type: GameType.TENNIS, nameRes: $r('app.string.tab_tennis'), emoji: GameTypeIcons[GameType.TENNIS], route: 'pages/scoreboard/sports/TennisScoreboard' },
      // { type: GameType.PICKLEBALL, nameRes: $r('app.string.project_pickleball'), emoji: GameTypeIcons[GameType.PICKLEBALL], route: 'pages/scoreboard/sports/PickleballScoreboard' }, // Hidden
      { type: GameType.BOXING, nameRes: $r('app.string.tab_boxing'), emoji: GameTypeIcons[GameType.BOXING], route: 'pages/scoreboard/sports/BoxingScoreboard' },
      { type: GameType.GUANDAN, nameRes: $r('app.string.tab_guandan'), emoji: GameTypeIcons[GameType.GUANDAN], route: 'pages/scoreboard/cards/GuandanScore' },
      { type: GameType.DOUDIZHU, nameRes: $r('app.string.tab_doudizhu'), emoji: GameTypeIcons[GameType.DOUDIZHU], route: 'pages/scoreboard/cards/DoudizhuScore' },
      { type: GameType.MULTI_SCOREBOARD, nameRes: $r('app.string.tab_multi_score'), emoji: GameTypeIcons[GameType.MULTI_SCOREBOARD], route: 'pages/scoreboard/cards/MultiGroupScore' },

      // 快速开始比赛 - 放在底部，用户可以直接从首页快速访问
      { type: GameType.FOOTBALL, nameRes: $r('app.string.tab_football'), emoji: GameTypeIcons[GameType.FOOTBALL], route: 'pages/scoreboard/sports/FootballScoreboard' },
      { type: GameType.BASKETBALL, nameRes: $r('app.string.tab_basketball'), emoji: GameTypeIcons[GameType.BASKETBALL], route: 'pages/scoreboard/sports/BasketballScoreboard' },
      { type: GameType.BADMINTON, nameRes: $r('app.string.tab_badminton'), emoji: GameTypeIcons[GameType.BADMINTON], route: 'pages/scoreboard/sports/BadmintonScoreboard' },
    ];
  }

  private getTimerItems(): GameItem[] {
    return [
      { type: GameType.XIANGQI, nameRes: $r('app.string.timer_xiangqi'), emoji: GameTypeIcons[GameType.XIANGQI], route: 'pages/timer/XiangqiTimer' },
      { type: GameType.GO, nameRes: $r('app.string.timer_go'), emoji: GameTypeIcons[GameType.GO], route: 'pages/timer/GoTimer' },
      { type: GameType.CHESS, nameRes: $r('app.string.timer_chess'), emoji: GameTypeIcons[GameType.CHESS], route: 'pages/timer/ChessTimer' },
    ];
  }

  build() {
    Column() {
      // 顶部空白区域，点击时关闭对话框
      Column()
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.controller) {
            this.controller.close();
          }
          this.onCancel?.();
        })
      
      // 对话框内容
      Row() {
        // 左侧空白区域，点击时关闭对话框
        Column()
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
            this.onCancel?.();
          })
        
        if (this.showTimerSettings && this.selectedTimerGameType) {
          // 显示计时器设置视图
          Column() {
            this.buildTimerSettingsView()
          }
          .onClick(() => {
            // 阻止事件冒泡，防止点击内容区域时关闭对话框
          })
        } else {
          // 显示游戏列表
          Column({ space: 0 }) {
          // 标题和关闭按钮
          Row() {
            Text($r('app.string.dialog_new_game_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.textPrimary)
              .layoutWeight(1)

            Button({ type: ButtonType.Normal }) {
              Image($r('app.media.close'))
                .width(24)
                .height(24)
            }
            .width(48)
            .height(48)
            .backgroundColor(Color.Transparent)
            .borderRadius(24)
            .onClick(() => {
              if (this.controller) {
                this.controller.close();
              }
              this.onCancel?.();
            })
          }
          .width('100%')
            .padding({ left: 20, right: 20, top: 20, bottom: 16 })
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)

          // 分隔线
          Divider()
            .color(Colors.divider)
            .strokeWidth(0.5)

          // Tabs
          Tabs({ index: this.currentTabIndex }) {
            TabContent() {
              this.buildGameList(this.getScoreboardItems())
            }
            .tabBar(this.buildTabBarItem($r('app.string.tab_score'), 0))

            TabContent() {
              this.buildGameList(this.getTimerItems())
            }
            .tabBar(this.buildTabBarItem($r('app.string.tab_timer'), 1))
          }
          .barMode(BarMode.Fixed)
            .barHeight(48)
            .barBackgroundColor(Colors.homeDialogBackground)
            .clip(true)
            .borderRadius({
              bottomLeft: 16,
              bottomRight: 16
            })
            .onChange((index: number) => {
              this.currentTabIndex = index;
            })
            .layoutWeight(1)
        }
        .width('90%')
          .height('70%')
          .backgroundColor(Colors.homeDialogBackground)
          .clip(true)
          .borderRadius({
            topLeft: 16,
            topRight: 16,
            bottomLeft: 16,
            bottomRight: 16
          })
          .constraintSize({
            maxWidth: 400,
            minWidth: 280
          })
          .onClick(() => {
            // 阻止事件冒泡，防止点击内容区域时关闭对话框
          })
        }
        
        // 右侧空白区域，点击时关闭对话框
        Column()
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
            this.onCancel?.();
          })
      }
      .width('100%')
      
      // 底部空白区域，点击时关闭对话框
      Column()
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.controller) {
            this.controller.close();
          }
          this.onCancel?.();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private buildGameList(items: GameItem[]) {
    List({ space: 0 }) {
      ForEach(items, (item: GameItem, index: number) => {
        ListItem() {
          this.buildGameItem(item, index === items.length - 1);
        }
      }, (item: GameItem) => item.type)
    }
    .width('100%')
      .scrollBar(BarState.Off)
      .divider({
        strokeWidth: 0.5,
        color: Colors.divider,
        startMargin: 52,
        endMargin: 20
      })
  }

  @Builder
  private buildGameItem(item: GameItem, isLast: boolean) {
    Row({ space: 16 }) {
      // Emoji 图标
      Text(item.emoji)
        .fontSize(28)

      // 名称
      Text(item.nameRes)
        .fontSize(16)
        .fontWeight(FontWeight.Regular)
        .fontColor(Colors.textPrimary)
        .layoutWeight(1)

      // 箭头
      Image($r('app.media.chevron_forward'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
      .height(64)
      .padding({ left: 20, right: 20 })
      .backgroundColor(Colors.homeDialogBackground)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.handleGameItemClick(item);
      })
  }

  private handleGameItemClick(item: GameItem): void {
    const gameType = item.type;
    
    // 1. Sports Games - 显示设置对话框
    const sports = [
      GameType.FOOTBALL, GameType.BASKETBALL, GameType.VOLLEYBALL, GameType.PINGPONG, 
      GameType.BADMINTON, GameType.TENNIS, GameType.BILLIARDS, GameType.BOXING, GameType.PICKLEBALL
    ];
    
    if (sports.includes(gameType)) {
      // 立即关闭当前对话框
      if (this.controller) {
        this.controller.close();
      }
      this.onCancel?.();
      
      try {
        // 先获取 context
        const context = getContext(this) as common.UIAbilityContext;
        const resourceManager = context.resourceManager;
        const team1 = resourceManager.getStringSync($r('app.string.red_team').id);
        const team2 = resourceManager.getStringSync($r('app.string.blue_team').id);
        
        // 延迟打开新对话框，确保当前对话框已关闭
        setTimeout(() => {
          // 创建新的对话框控制器
          const dialogController = new CustomDialogController({
            builder: SportsSetupDialog({
              gameType: gameType,
              defaultTeam1Name: team1,
              defaultTeam2Name: team2,
              onConfirm: (config) => {
                this.navigateToSportsWithConfig(gameType, config);
                dialogController?.close();
              },
              onCancel: () => {
                dialogController?.close();
              }
            }),
            autoCancel: true,
            alignment: DialogAlignment.Center,
            customStyle: true
          });
          this.sportsSetupDialogController = dialogController;
          dialogController?.open();
        }, 200);
      } catch (e) {
        console.error(`[NewGameDialog] Failed to setup sports dialog for ${gameType}:`, e);
      }
      return;
    }

    // 2. Card Games - 显示设置对话框
    const cards = [GameType.DOUDIZHU, GameType.GUANDAN, GameType.SIMPLE_SCORE, GameType.MULTI_SCOREBOARD];
    if (cards.includes(gameType)) {
      // 立即关闭当前对话框
      if (this.controller) {
        this.controller.close();
      }
      this.onCancel?.();
      
      try {
        // 先获取 context
        const context = getContext(this) as common.UIAbilityContext;
        const resourceManager = context.resourceManager;
        const defaultTeam1 = resourceManager.getStringSync($r('app.string.red_team').id);
        const defaultTeam2 = resourceManager.getStringSync($r('app.string.blue_team').id);
        
        let names: string[] = [];
        if (gameType === GameType.DOUDIZHU) names = ['A', 'B', 'C'];
        else if (gameType === GameType.MULTI_SCOREBOARD) names = ['P1', 'P2', 'P3', 'P4'];
        else names = [defaultTeam1, defaultTeam2];

        // 延迟打开新对话框，确保当前对话框已关闭
        setTimeout(() => {
          // 创建新的对话框控制器
          const dialogController = new CustomDialogController({
            builder: CardGameSetupDialog({
              gameType: gameType,
              defaultPlayerNames: names,
              onConfirm: (config) => {
                this.navigateToCardGame(gameType, config);
                dialogController?.close();
              },
              onCancel: () => {
                dialogController?.close();
              }
            }),
            autoCancel: true,
            alignment: DialogAlignment.Center,
            customStyle: true
          });
          this.cardGameSetupDialogController = dialogController;
          dialogController?.open();
        }, 200);
      } catch (e) {
        console.error(`[NewGameDialog] Failed to setup card game dialog for ${gameType}:`, e);
      }
      return;
    }

    // 3. Timer Games - 关闭对话框，通过回调通知父组件显示 bindSheet
    if ([GameType.GO, GameType.XIANGQI, GameType.CHESS].includes(gameType)) {
      const timerType: 'Go' | 'Xiangqi' | 'Chess' = gameType === GameType.GO ? 'Go' : (gameType === GameType.XIANGQI ? 'Xiangqi' : 'Chess');
      
      // 先关闭对话框
      if (this.controller) {
        this.controller.close();
      }
      this.onCancel?.();
      
      // 延迟调用回调，让父组件显示 bindSheet
      setTimeout(() => {
        this.onTimerGameSelected?.(timerType);
      }, 200);
      return;
    }

    // 4. Direct Navigation Fallback
    this.controller?.close();
    setTimeout(() => {
      router.pushUrl({
        url: item.route,
        params: { sourcePage: this.sourcePage }
      }).catch((error: Error) => {
        console.error(`[NewGameDialog] Failed to navigate to ${item.route}:`, error);
      });
    }, 100);
    this.onCancel?.();
  }

  private navigateToSportsWithConfig(gameType: GameType, config: SportsSetupResult): void {
    const route = this.getGameRoute(gameType);
    const params: RouterParams = {
      sourcePage: this.sourcePage as Object,
      team1Name: config.team1Name as Object,
      team2Name: config.team2Name as Object
    };
    if (config.maxSets) {
      params.maxSets = config.maxSets as Object;
    }
    if (config.pointsPerSet) {
      params.pointsPerSet = config.pointsPerSet as Object;
    }
    
    router.pushUrl({ url: route, params: params });
  }

  private navigateToCardGame(gameType: GameType, config: CardGameSetupResult): void {
    const route = this.getGameRoute(gameType);
    router.pushUrl({
      url: route,
      params: {
        sourcePage: this.sourcePage as Object,
        playerNames: config.playerNames as Object,
        players: config.playerNames as Object
      }
    });
  }

  private startTimerGame(): void {
    if (!this.selectedTimerGameType) return;
    
    if (this.selectedTimerGameType === 'Go') {
      const goSettings = this.goSettings || {
        timeMode: '快棋',
        mainTimeMinutes: 60,
        mainTimeSeconds: 0,
        byoyomiSeconds: 30,
        byoyomiTimes: 3,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      this.controller?.close();
      this.onCancel?.();
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
          sourcePage: this.sourcePage
        }
      }).catch((error: Error) => {
        console.error(`[NewGameDialog] Failed to navigate to GoTimer:`, error);
      });
    } else if (this.selectedTimerGameType === 'Xiangqi') {
      const xiangqiSettings = this.xiangqiSettings || {
        timeMode: '快棋',
        mainTimeMinutes: 10,
        mainTimeSeconds: 0,
        incrementSeconds: 10,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      this.controller?.close();
      this.onCancel?.();
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
          sourcePage: this.sourcePage
        }
      }).catch((error: Error) => {
        console.error(`[NewGameDialog] Failed to navigate to XiangqiTimer:`, error);
      });
    } else if (this.selectedTimerGameType === 'Chess') {
      const chessSettings = this.chessSettings || {
        timeMode: '快棋',
        mainTimeMinutes: 15,
        mainTimeSeconds: 0,
        incrementSeconds: 10,
        soundEnabled: true,
        vibrationEnabled: true,
        redFlashEnabled: true,
        selectedLayout: '横版'
      };
      this.controller?.close();
      this.onCancel?.();
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
          sourcePage: this.sourcePage
        }
      }).catch((error: Error) => {
        console.error(`[NewGameDialog] Failed to navigate to ChessTimer:`, error);
      });
    }
  }

  private getGameRoute(gameType: GameType): string {
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

  @Builder
  private buildTimerSettingsView() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.back'))
            .width(20)
            .height(20)
        }
        .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showTimerSettings = false;
            this.selectedTimerGameType = null;
          })

        Text(this.selectedTimerGameType === 'Go' ? $r('app.string.timer_go') :
             this.selectedTimerGameType === 'Xiangqi' ? $r('app.string.timer_xiangqi') :
             $r('app.string.timer_chess'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(40)
      }
      .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

      Divider()
        .color(Colors.divider)
        .strokeWidth(0.5)

      // 设置内容
      Scroll() {
        Column() {
          if (this.selectedTimerGameType === 'Go') {
            GoSettingsView({
              onDismiss: () => {
                this.showTimerSettings = false;
                this.selectedTimerGameType = null;
              },
              onSettingsChange: (s) => {
                this.goSettings = s;
              }
            })
          } else if (this.selectedTimerGameType === 'Xiangqi') {
            XiangqiSettingsView({
              onDismiss: () => {
                this.showTimerSettings = false;
                this.selectedTimerGameType = null;
              },
              onSettingsChange: (s) => {
                this.xiangqiSettings = s;
              }
            })
          } else if (this.selectedTimerGameType === 'Chess') {
            ChessSettingsView({
              onDismiss: () => {
                this.showTimerSettings = false;
                this.selectedTimerGameType = null;
              },
              onSettingsChange: (s) => {
                this.chessSettings = s;
              }
            })
          }

          Button($r('app.string.home_start_match'))
            .type(ButtonType.Capsule)
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor(Colors.primary)
            .margin({ top: 16, bottom: 16 })
            .onClick(() => {
              this.startTimerGame();
            })
        }
        .width('100%')
          .padding(16)
      }
      .layoutWeight(1)
    }
    .width('90%')
      .height('70%')
      .backgroundColor(Colors.homeDialogBackground)
      .clip(true)
      .borderRadius({
        topLeft: 16,
        topRight: 16,
        bottomLeft: 16,
        bottomRight: 16
      })
      .constraintSize({
        maxWidth: 400,
        minWidth: 280
      })
      .margin({
        left: 20,
        right: 20
      })
  }
}
