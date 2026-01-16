import { GameType } from '../../../model/types';
import { getGameIcon, getGameName } from './HomeUtils';
import { FontSizes, Colors } from '../../../common/theme';
import common from '@ohos.app.ability.common';

@Component
struct SportOption {
  @Prop sport: GameType;
  @Prop isSelected: boolean;
  @Prop isDarkTheme: boolean;
  onClickOption?: () => void;

  build() {
    Column({ space: 8 }) {
      Text(getGameIcon(this.sport))
        .fontSize(24)
      
      Text(getGameName(this.sport))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .aspectRatio(1)
    .backgroundColor(this.isDarkTheme ? Colors.homeOverlayBorder : Colors.homeOverlayLight)
    .borderRadius(16)
    .border({ 
      width: 2, 
      color: this.isSelected ? Colors.homeEditButtonGreen : Colors.transparent 
    })
    .onClick(() => {
      if (this.onClickOption) {
        this.onClickOption();
      }
    })
    .stateStyles({
      pressed: {
        .scale({ x: 0.95, y: 0.95 })
        .opacity(0.8)
      },
      normal: {
        .scale({ x: 1, y: 1 })
        .opacity(1)
      }
    })
    .animation({ duration: 150, curve: Curve.EaseInOut })
  }
}

// Available sports to choose from
const availableSports: GameType[] = [
  GameType.BASKETBALL, GameType.FOOTBALL, GameType.BADMINTON, 
  GameType.PINGPONG, GameType.TENNIS, GameType.VOLLEYBALL,
  GameType.BILLIARDS, GameType.BOXING,
  GameType.GO, GameType.XIANGQI, GameType.CHESS,
  GameType.GUANDAN, GameType.DOUDIZHU
];

// Component version with proper state binding
@Component
export struct QuickStartEditSheetComponent {
  @Prop isDarkTheme: boolean = true;
  @Prop currentPrimary: GameType = GameType.BASKETBALL;
  @Prop currentSecondary: GameType = GameType.BADMINTON;
  @Prop initialPrimary: GameType = GameType.BASKETBALL;
  @Prop initialSecondary: GameType = GameType.BADMINTON;
  
  // Internal state
  @State private selectedPrimary: GameType = GameType.BASKETBALL;
  @State private selectedSecondary: GameType = GameType.BADMINTON;
  @State private isPrimaryExpanded: boolean = true;
  @State private isSecondaryExpanded: boolean = true;
  
  onSave?: (primary: GameType, secondary: GameType) => void;

  aboutToAppear(): void {
    this.selectedPrimary = this.initialPrimary;
    this.selectedSecondary = this.initialSecondary;
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // Primary Selection
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('1')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Colors.textOnPrimary)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(Colors.homePrimaryCardOrange)
                .textAlign(TextAlign.Center)
              
              Text($r('app.string.home_edit_primary_card'))
                .fontSize(FontSizes.body1)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: this.selectedPrimary === sport,
                    isDarkTheme: this.isDarkTheme,
                    onClickOption: () => {
                      this.selectedPrimary = sport;
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
          }
          .alignItems(HorizontalAlign.Start)

          // Secondary Selection
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('2')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Colors.textOnPrimary)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(Colors.homeSecondaryCardGreen)
                .textAlign(TextAlign.Center)
              
              Text($r('app.string.home_edit_secondary_card'))
                .fontSize(FontSizes.body1)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: this.selectedSecondary === sport,
                    isDarkTheme: this.isDarkTheme,
                    onClickOption: () => {
                      this.selectedSecondary = sport;
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      // Footer Button
      Column() {
        Button($r('app.string.home_complete_and_save'))
          .type(ButtonType.Capsule)
          .width('100%')
          .height(56)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.black)
          .backgroundColor(Colors.homeEditButtonGreen)
          .onClick(() => {
            if (this.onSave) {
              this.onSave(this.selectedPrimary, this.selectedSecondary);
            }
          })
      }
      .padding(24)
      .backgroundColor(this.isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
      .border({ width: { top: 1 }, color: this.isDarkTheme ? Colors.homeOverlayBorder : Colors.homeDividerLight })
    }
    .width('100%')
    .backgroundColor(this.isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
  }
}

// Keep backward compatible @Builder function
@Builder
export function QuickStartEditSheet(
  isDarkTheme: boolean,
  currentPrimary: GameType,
  currentSecondary: GameType,
  selectedPrimary: GameType,
  selectedSecondary: GameType,
  isPrimaryExpanded: boolean,
  isSecondaryExpanded: boolean,
  onPrimaryToggle: () => void,
  onSecondaryToggle: () => void,
  onPrimarySelect: (sport: GameType) => void,
  onSecondarySelect: (sport: GameType) => void,
  onSave: () => void
) {
  Column() {
    Scroll() {
      Column({ space: 24 }) {
        // Primary Selection
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('1')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor('#F97316') // Orange
              .textAlign(TextAlign.Center)
            
            Text($r('app.string.home_edit_primary_card'))
              .fontSize(FontSizes.body1)
              .fontWeight(FontWeight.Medium)
              .fontColor(isDarkTheme ? Color.White : Color.Black)
              .layoutWeight(1)
          }
          .width('100%')
          .onClick(() => {
            onPrimaryToggle();
          })

          if (isPrimaryExpanded) {
            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: selectedPrimary === sport,
                    isDarkTheme: isDarkTheme,
                    onClickOption: () => {
                      onPrimarySelect(sport);
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
            .height(200)
          }
        }
        .alignItems(HorizontalAlign.Start)

        // Secondary Selection
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('2')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.textOnPrimary)
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor(Colors.homeSecondaryCardGreen)
              .textAlign(TextAlign.Center)
            
            Text($r('app.string.home_edit_secondary_card'))
              .fontSize(FontSizes.body1)
              .fontWeight(FontWeight.Medium)
              .fontColor(isDarkTheme ? Colors.textPrimary : Colors.black)
              .layoutWeight(1)
          }
          .width('100%')
          .onClick(() => {
            onSecondaryToggle();
          })

          if (isSecondaryExpanded) {
            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: selectedSecondary === sport,
                    isDarkTheme: isDarkTheme,
                    onClickOption: () => {
                      onSecondarySelect(sport);
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
            .height(200)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    }
    .layoutWeight(1)

    // Footer Button
    Column() {
      Button($r('app.string.home_complete_and_save'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(56)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.black)
        .backgroundColor(Colors.homeEditButtonGreen)
        .onClick(() => {
          onSave();
        })
    }
    .padding(24)
    .backgroundColor(isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
    .border({ width: { top: 1 }, color: isDarkTheme ? Colors.homeOverlayBorder : Colors.homeDividerLight })
  }
  .width('100%')
  .backgroundColor(isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
}

// Center Dialog version for CustomDialogController
@CustomDialog
export struct QuickStartEditDialog {
  controller: CustomDialogController;
  @Prop isDarkTheme: boolean = true;
  @Prop currentPrimary: GameType = GameType.BASKETBALL;
  @Prop currentSecondary: GameType = GameType.BADMINTON;
  
  // Internal state
  @State private selectedPrimary: GameType = GameType.BASKETBALL;
  @State private selectedSecondary: GameType = GameType.BADMINTON;
  
  onSave?: (primary: GameType, secondary: GameType) => void;
  onCancel?: () => void;

  aboutToAppear(): void {
    this.selectedPrimary = this.currentPrimary;
    this.selectedSecondary = this.currentSecondary;
  }

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.home_customize_quick_start'))
          .fontSize(FontSizes.h5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
          .layoutWeight(1)
        
        Button() {
          Text('✕')
            .fontSize(20)
            .fontColor(Colors.textSecondary)
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.onCancel) {
            this.onCancel();
          }
        })
      }
      .width('100%')
      .padding({ bottom: 16 })

      Scroll() {
        Column() {
          // Primary Selection
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('1')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Colors.textOnPrimary)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(Colors.homePrimaryCardOrange)
                .textAlign(TextAlign.Center)
              
              Text($r('app.string.home_edit_primary_card'))
                .fontSize(FontSizes.body1)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
                .layoutWeight(1)
            }
            .width('100%')

            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: this.selectedPrimary === sport,
                    isDarkTheme: this.isDarkTheme,
                    onClickOption: () => {
                      this.selectedPrimary = sport;
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // Secondary Selection
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('2')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Colors.textOnPrimary)
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(Colors.homeSecondaryCardGreen)
                .textAlign(TextAlign.Center)
              
              Text($r('app.string.home_edit_secondary_card'))
                .fontSize(FontSizes.body1)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkTheme ? Colors.textPrimary : Colors.black)
                .layoutWeight(1)
            }
            .width('100%')

            Grid() {
              ForEach(availableSports, (sport: GameType) => {
                GridItem() {
                  SportOption({
                    sport: sport,
                    isSelected: this.selectedSecondary === sport,
                    isDarkTheme: this.isDarkTheme,
                    onClickOption: () => {
                      this.selectedSecondary = sport;
                    }
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(8)
            .columnsGap(8)
          }
          .alignItems(HorizontalAlign.Start)
        }
      }
      .constraintSize({ maxHeight: 400 })
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)

      // Save Button
      Button($r('app.string.home_complete_and_save'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.black)
        .backgroundColor(Colors.homeEditButtonGreen)
        .margin({ top: 24 })
        .onClick(() => {
          if (this.onSave) {
            this.onSave(this.selectedPrimary, this.selectedSecondary);
          }
        })
    }
    .width('90%')
    .constraintSize({ maxWidth: 400, maxHeight: '80%' })
    .padding(24)
    .backgroundColor(this.isDarkTheme ? Colors.homeCardDark : Colors.homeCardLight)
    .borderRadius(24)
  }
}
