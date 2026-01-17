import { GameType } from '../../../model/types';
import { BentoCard } from './BentoCard';
import { getGameGradient, getGameIcon, getGameName, GAME_GRADIENTS } from './HomeUtils';
import { Colors, Spacing, FontSizes, BorderRadius } from '../../../common/theme';
import common from '@ohos.app.ability.common';

@Component
export struct QuickStartGrid {
  @Prop primarySport: GameType = GameType.BASKETBALL;
  @Prop secondarySport: GameType = GameType.BADMINTON;
  @Prop isDarkTheme: boolean = true; // Default to black UI
  
  onPrimaryClick?: () => void;
  onSecondaryClick?: () => void;
  onNewGameClick?: () => void;
  onEditClick?: () => void;

  @State private startGameText: string = '';
  @State private newGameText: string = '';
  @State private allItemsText: string = '';

  aboutToAppear() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.startGameText = context.resourceManager.getStringSync($r('app.string.home_start_game').id);
      this.newGameText = context.resourceManager.getStringSync($r('app.string.home_new_game_short').id);
      this.allItemsText = context.resourceManager.getStringSync($r('app.string.home_all_items').id);
    } catch (e) {
      this.startGameText = 'Start Game';
      this.newGameText = 'New Game';
      this.allItemsText = 'All Items';
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Row({ space: Spacing.sm }) {
          Text($r('app.string.home_quick_start'))
            .fontSize(FontSizes.h5)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.textPrimary)
        }

        Button() {
          Image($r('app.media.ic_edit'))
            .width(20)
            .height(20)
        }
        .type(ButtonType.Normal)
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          const callback = this.onEditClick;
          if (callback) {
            callback();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 16 })

      // Grid
      Grid() {
        // Primary Card (Left, Spans 2 Rows) - Always use orange (basketball) background
        GridItem() {
          BentoCard({
            title: getGameName(this.primarySport),
            subtitle: this.startGameText,
            icon: getGameIcon(this.primarySport),
            gradientColors: GAME_GRADIENTS[GameType.BASKETBALL], // Always orange
            onClickCard: () => {
              if (this.onPrimaryClick) {
                this.onPrimaryClick();
              }
            }
          })
        }
        .rowStart(0)
        .rowEnd(1)
        .columnStart(0)
        .columnEnd(0)

        // Secondary Card (Right Top)
        GridItem() {
          BentoCard({
            title: getGameName(this.secondarySport),
            icon: getGameIcon(this.secondarySport),
            gradientColors: [Colors.primary, Colors.primary],
            isDarkText: false,
            onClickCard: () => {
              if (this.onSecondaryClick) {
                this.onSecondaryClick();
              }
            }
          })
        }
        .rowStart(0)
        .rowEnd(0)
        .columnStart(1)
        .columnEnd(1)

        // New Game Button (Right Bottom)
        GridItem() {
          BentoCard({
            title: this.newGameText,
            subtitle: this.allItemsText,
            icon: '➕',
            gradientColors: [Colors.homeSecondaryCardGreen, Colors.homeSecondaryCardGreen],
            isDarkText: false,
            onClickCard: () => {
              if (this.onNewGameClick) this.onNewGameClick();
            }
          })
        }
        .rowStart(1)
        .rowEnd(1)
        .columnStart(1)
        .columnEnd(1)
      }
      .columnsTemplate('1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(Spacing.md)
      .rowsGap(Spacing.md)
      .height(240) // Reduced height for quick start items
    }
    .width('100%')
    .margin({ top: Spacing.lg })
  }
}
