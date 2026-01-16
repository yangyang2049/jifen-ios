import { GameType } from '../../../model/types';
import { Colors, Spacing, FontSizes, BorderRadius } from '../../../common/theme';

@Component
export struct BentoCard {
  @Prop title: string;
  @Prop subtitle: string = '';
  @Prop icon: string;
  @Prop gradientColors: [ResourceColor, ResourceColor] = [Colors.surface, Colors.surface];
  @Prop isDarkText: boolean = false;
  onClickCard?: () => void;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Content
      Column() {
        Row() {
          Column() {
            Text(this.title)
              .fontSize(FontSizes.h5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isDarkText ? Colors.black : Colors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            if (this.subtitle) {
              Text(this.subtitle)
                .fontSize(FontSizes.overline)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDarkText ? Colors.textTertiary : Colors.textSecondary)
                .margin({ top: Spacing.xs })
                .textCase(TextCase.UpperCase)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.icon)
            .fontSize(FontSizes.h3)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.SpaceBetween)

        // Decorative Bars (only if subtitle exists and not simple background)
        if (this.subtitle && this.gradientColors[0] !== Colors.surface && this.gradientColors[0] !== Colors.white) {
          Blank()
          Row({ space: 2 }) {
            this.DecorativeBar(16)
            this.DecorativeBar(28)
            this.DecorativeBar(20)
            this.DecorativeBar(40)
            this.DecorativeBar(24)
          }
          .height(48)
          .opacity(0.3)
          .alignSelf(ItemAlign.Start)
        }
      }
      .width('100%')
      .height('100%')
      .padding(Spacing.md)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height('100%')
    .borderRadius(BorderRadius.xxl)
    .linearGradient({
      angle: 135,
      colors: [[this.gradientColors[0], 0.0], [this.gradientColors[1], 1.0]]
    })
    .shadow({ radius: 10, color: Colors.homeButtonShadow, offsetY: 5 })
    .onClick(() => {
      if (this.onClickCard) {
        this.onClickCard();
      }
    })
    // Add touch effect
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

  @Builder
  DecorativeBar(height: number) {
    Column()
      .width(4)
      .height(height)
      .backgroundColor(Colors.textOnPrimary)
      .borderRadius(2)
  }
}
