import { GameType } from '../../../model/types';
import { getGameIcon } from './HomeUtils';

export interface LiveGameInfo {
  gameType: GameType;
  score1: number;
  score2: number;
  time: string;
  quarter?: string;
  matchName: string;
  matchId: string;
}

@Component
export struct LiveActivityBanner {
  @Prop isVisible: boolean = false;
  @Prop gameInfo: LiveGameInfo | null = null;
  @Prop isFloating: boolean = false;
  @Prop isDarkTheme: boolean = false;

  @State pulseScale: number = 1;

  aboutToAppear() {
    this.startPulse();
  }

  startPulse() {
    animateTo({
      duration: 1000,
      iterations: -1,
      playMode: PlayMode.Alternate,
      curve: Curve.EaseInOut
    }, () => {
      this.pulseScale = 1.2;
    })
  }

  build() {
    if (this.isVisible && this.gameInfo) {
      Row() {
        // Left: Game Icon & Live Indicator
        Stack({ alignContent: Alignment.TopEnd }) {
          // Game Icon
          Row() {
             Text(getGameIcon(this.gameInfo.gameType))
               .fontSize(20)
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .linearGradient({
             angle: 135,
             colors: [['#F97316', 0.0], ['#C2410C', 1.0]] // Orange default for live
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .shadow({ radius: 8, color: 'rgba(194, 65, 12, 0.4)', offsetY: 4 })

          // Live Dot (Pulsing)
          Row() {
            Circle({ width: 8, height: 8 })
              .fill('#EF4444')
              .scale({ x: this.pulseScale, y: this.pulseScale })
          }
          .width(14)
          .height(14)
          .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#FFFFFF')
          .borderRadius(7)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ top: -2, right: -2 })
        }
        .margin({ right: 12 })

        // Center: Score & Info
        Column() {
          Row({ space: 8 }) {
            Text(`${this.gameInfo.score1} : ${this.gameInfo.score2}`)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isDarkTheme ? Color.White : Color.Black)
            
            if (this.gameInfo.quarter) {
              Text(this.gameInfo.quarter)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F97316')
                .backgroundColor(this.isDarkTheme ? 'rgba(255,255,255,0.1)' : '#FFF7ED')
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(4)
            }
          }

          Row({ space: 8 }) {
            // Time Icon (Text for now)
            Text('🕒')
              .fontSize(10)
              .fontColor('#9CA3AF')
            
            Text(this.gameInfo.time)
              .fontSize(12)
              .fontColor('#9CA3AF')
              .fontFamily('Monospace')
            
            Text('|')
              .fontSize(10)
              .fontColor(this.isDarkTheme ? 'rgba(255,255,255,0.1)' : '#E5E7EB')
            
            Text(this.gameInfo.matchName)
              .fontSize(10)
              .fontColor('#6B7280')
          }
          .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // Right: Controls
        Row({ space: 8 }) {
          // Pause Button
          Button() {
             Text('⏸') // Replace with proper icon
               .fontSize(16)
               .fontColor(this.isDarkTheme ? Color.White : '#1F2937')
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor(this.isDarkTheme ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.05)')

          // Fullscreen Button
          Button() {
             Text('⛶') // Replace with proper icon
               .fontSize(16)
               .fontColor(Color.Black)
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor('#30D158')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.isDarkTheme ? 'rgba(28, 28, 30, 0.95)' : 'rgba(255, 255, 255, 0.9)')
      .backdropBlur(20)
      .borderRadius(32)
      .shadow(this.isFloating ? { radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 10 } : { radius: 0 })
      .border({ 
        width: 1, 
        color: this.isDarkTheme ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.05)' 
      })
    }
  }
}
