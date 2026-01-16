import { RecentActivity, ActivityType, GameType, GameTypeIcons } from '../../../model/types';
import { getGameName } from './HomeUtils';
import { Colors } from '../../../common/theme';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

@Component
struct RecentRow {
  @Prop activity: RecentActivity;
  @Prop isLast: boolean;
  @Prop isDarkTheme: boolean;

  build() {
    Column() {
      if (this.activity.activityType === ActivityType.TIMER) {
        this.buildTimerItem()
      } else {
        this.buildScoreboardItem()
      }

      // Divider
      if (!this.isLast) {
        Divider()
          .color(this.isDarkTheme ? Colors.homeOverlayBorder : Colors.homeDividerLight)
      }
    }
    .width('100%')
  }

  @Builder
  private buildTimerItem() {
    Row() {
      // 左侧比赛图标
      this.buildGameIcon(this.activity.gameType)

      // 中间信息
      Row() {
        Text(this.formatTime(this.activity.timestamp))
          .fontSize(14)
          .fontColor(Colors.textPrimary)

        if (this.activity.description) {
          Text(this.activity.description)
            .fontSize(12)
            .fontColor(Colors.textSecondary)
            .margin({ left: 16 })
        }

        Blank()
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ left: 12 })

      // 右侧箭头
      Image($r('app.media.chevron_forward'))
        .width(16)
        .height(16)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 12, bottom: 12 })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/timer/TimerRecordDetailPage',
        params: { recordId: this.activity.id }
      }).catch((error: Error) => {
        console.error('[RecentRow] Failed to navigate to TimerRecordDetailPage:', error);
      });
    })
  }

  @Builder
  private buildScoreboardItem() {
    Row() {
      // 左侧比赛emoji图标
      Text(GameTypeIcons[this.activity.gameType] || '🎮')
        .fontSize(28)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)

      // 中间信息
      Row() {
        Column({ space: 4 }) {
          // 游戏名称
          Text(this.activity.title || getGameName(this.activity.gameType))
            .fontSize(14)
            .fontColor(Colors.textPrimary)
            .fontWeight(FontWeight.Medium)

          Row({ space: 8 }) {
            Text(this.formatTime(this.activity.timestamp))
              .fontSize(12)
              .fontColor(Colors.textSecondary)
          }
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 显示比分
        Column({ space: 4 }) {
          if (this.activity.description) {
            Text(this.activity.description)
              .fontSize(16)
              .fontColor(Colors.primary)
              .fontWeight(FontWeight.Bold)
          }
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ left: 12 })

      // 右侧箭头
      Image($r('app.media.chevron_forward'))
        .width(16)
        .height(16)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 12, bottom: 12 })
    .onClick(() => {
      // 多人计分板跳转到 MultiGroupRecordDetailPage，其他跳转到 ScoreboardRecordDetailPage
      const route = this.activity.gameType === GameType.MULTI_SCOREBOARD 
        ? 'pages/scoreboard/MultiGroupRecordDetailPage'
        : 'pages/scoreboard/ScoreboardRecordDetailPage';
      router.pushUrl({
        url: route,
        params: { recordId: this.activity.id }
      }).catch((error: Error) => {
        console.error('[RecentRow] Failed to navigate to ScoreboardRecordDetailPage:', error);
      });
    })
  }

  @Builder
  private buildGameIcon(gameType: GameType) {
    // 对于计时器类型（围棋、象棋、国际象棋），使用Stack显示两个图标
    if ([GameType.GO, GameType.XIANGQI, GameType.CHESS].includes(gameType)) {
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
    } else {
      // 其他类型使用emoji图标
      Text(GameTypeIcons[gameType] || '🎮')
        .fontSize(24)
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
    }
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

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    
    // 如果是今天，显示 HH:MM
    if (date.getDate() === now.getDate() && date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear()) {
      return `${hours}:${minutes}`;
    }
    
    // 否则显示"昨天"或日期
    const context = getContext(this) as common.UIAbilityContext;
    const resourceManager = context.resourceManager;
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (date.getDate() === yesterday.getDate() && date.getMonth() === yesterday.getMonth() && date.getFullYear() === yesterday.getFullYear()) {
      return resourceManager.getStringSync($r('app.string.home_yesterday').id);
    }
    
    // 其他日期显示 MM-DD
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${month}-${day}`;
  }
}

@Component
export struct RecentRecordsSection {
  @Prop records: RecentActivity[] = [];
  @Prop isDarkTheme: boolean = false;
  onSeeAllClick?: () => void;

  build() {
    Column() {
      // Container
      Column() {
        if (this.records.length === 0) {
          // Empty State
          Column() {
            Text('🧘')
              .fontSize(48)
            
            Text($r('app.string.home_no_records'))
              .fontSize(14)
              .fontColor(this.isDarkTheme ? Colors.homeTextDisabledDark : Colors.homeTextDisabledLight)
              .margin({ top: 16 })
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // List
          Column({ space: 0 }) {
            ForEach(this.records, (record: RecentActivity, index: number) => {
              RecentRow({
                activity: record,
                isLast: index === this.records.length - 1,
                isDarkTheme: this.isDarkTheme
              })
            }, (record: RecentActivity) => record.id)
          }
          
          // Footer Button - Plain Text Style
          if (this.records.length > 0) {
            Text($r('app.string.home_view_all_records'))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.primary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 20 })
              .padding({ top: 12, bottom: 12 })
              .onClick(() => {
                if (this.onSeeAllClick) this.onSeeAllClick();
              })
          }
        }
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
      .borderRadius(24)
      .border({ width: 1, color: this.isDarkTheme ? Colors.homeOverlayBorder : Colors.homeOverlayBorderLight })
      .shadow(this.isDarkTheme ? { radius: 0 } : { radius: 2, color: Colors.homeShadowLight, offsetY: 1 })
    }
  }
}
