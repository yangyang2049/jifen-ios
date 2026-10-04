import { promptAction } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import router from '@ohos.router';
import deviceInfo from '@ohos.deviceInfo';
import { display } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { preferencesManager } from '../../managers/prefs';
import { vibrationManager } from '../../media/vibration';
import { analyticsPageTracker } from '../../analytics/analyticsPageTracker';
import { AnalyticsScreenName } from '../../analytics/analyticsSchema';

import {
  APP_APPEARANCE_IS_LIGHT_STORAGE_KEY,
  applyNormalPageWindowChrome
} from '../../helpers/appAppearanceMode';
import { withPhoneBottomBarInset, withPhoneStatusBarInset } from '../../helpers/phoneSafeArea';
import { colorByName } from '../../ui/themeUtil';

@Entry
@Component
export struct WhistleTool {
  @State private isPlayingShort: boolean = false
  @State private isPlayingLong: boolean = false
  @State private vibrationEnabled: boolean = true
  @State private screenWidth: number = 0
  @State private screenHeight: number = 0
  @StorageLink(APP_APPEARANCE_IS_LIGHT_STORAGE_KEY) private appAppearanceIsLight: boolean = false

  private soundPool: media.SoundPool | null = null
  private whistleSoundId: number = -1
  private buzzerSoundId: number = -1

private applyToolSystemBars(): void {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext | undefined
    void applyNormalPageWindowChrome(context, this.appAppearanceIsLight, {
      statusBarColor: colorByName('app_background'),
      navigationBarColor: colorByName('app_background')
    })
  }

  async aboutToAppear() {
    analyticsPageTracker.trackScreen(AnalyticsScreenName.WHISTLE_TOOL, 'WhistleTool');
    this.applyToolSystemBars();
    await this.loadVibrationPreference();
    this.initSoundPool();
    this.detectScreenSize();
  }

  onPageShow(): void {
    this.applyToolSystemBars();
  }

  private detectScreenSize(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      this.screenWidth = px2vp(displayInfo.width);
      this.screenHeight = px2vp(displayInfo.height);
    } catch (error) {
      console.error('[WhistleTool] Failed to detect screen size:', error);
      this.screenWidth = 360;
      this.screenHeight = 780;
    }
  }

  /**
   * 计算卡片尺寸
   * 基于屏幕高度计算可用空间，然后与屏幕宽度比较，取较小值
   */
  private calculateCardSize(): number {
    if (this.isTabletOr2in1()) {
      // 平板/2in1：固定尺寸
      return 300;
    }

    if (this.screenHeight === 0 || this.screenWidth === 0) {
      // 默认值
      return 200;
    }

    // 手机：纵向排列，两个卡片
    // 计算可用高度：总高度 - 顶部padding - 底部padding - 两个卡片之间的间距
    const topPadding = 16;
    const bottomPadding = 16;
    const cardSpacing = 16;
    const availableHeight = this.screenHeight - topPadding - bottomPadding - cardSpacing;

    // 每个卡片的高度 = 可用高度 / 2
    const cardHeightFromHeight = availableHeight / 2;

    // 计算可用宽度：总宽度 - 左右padding
    const horizontalPadding = 48 * 2; // 左右各48
    const availableWidth = this.screenWidth - horizontalPadding;

    // 使用较小的值作为卡片尺寸（保持正方形）
    const cardSize = Math.min(cardHeightFromHeight, availableWidth);

    // 确保最小尺寸
    return Math.max(cardSize, 150);
  }

  /**
   * 根据卡片尺寸计算图标大小
   */
  private getIconSizeForCard(cardSize: number): number {
    if (this.isTabletOr2in1()) {
      return 100;
    }
    // 图标大小约为卡片尺寸的 40%
    return Math.floor(cardSize * 0.4);
  }

  /**
   * 根据卡片尺寸计算内边距
   */
  private getPaddingForCard(cardSize: number): number {
    if (this.isTabletOr2in1()) {
      return 24;
    }
    // 内边距约为卡片尺寸的 10%
    return Math.max(12, Math.floor(cardSize * 0.1));
  }

  /**
   * 根据卡片尺寸计算文字大小
   */
  private getTextSizeForCard(cardSize: number): number {
    if (this.isTabletOr2in1()) {
      return 20;
    }
    // 文字大小根据卡片尺寸调整
    if (cardSize < 200) {
      return 14;
    } else if (cardSize < 250) {
      return 16;
    }
    return 20;
  }

  /**
   * 根据卡片尺寸计算元素间距
   */
  private getSpaceBetweenForCard(cardSize: number): number {
    if (this.isTabletOr2in1()) {
      return 12;
    }
    // 间距根据卡片尺寸调整
    if (cardSize < 200) {
      return 6;
    } else if (cardSize < 250) {
      return 8;
    }
    return 12;
  }

  private getShortWhistleIconSize(): number {
    const cardSize = this.calculateCardSize();
    return this.getIconSizeForCard(cardSize);
  }

  private getShortWhistleCardPadding(): number {
    const cardSize = this.calculateCardSize();
    return this.getPaddingForCard(cardSize);
  }

  private getShortWhistleTextSize(): number {
    const cardSize = this.calculateCardSize();
    return this.getTextSizeForCard(cardSize);
  }

  private getShortWhistleSpaceBetween(): number {
    const cardSize = this.calculateCardSize();
    return this.getSpaceBetweenForCard(cardSize);
  }

  private getShortWhistleEmojiSize(): number {
    const cardSize = this.calculateCardSize();
    // Emoji 稍小一些
    return Math.floor(this.getIconSizeForCard(cardSize) * 0.7);
  }

  private getLongWhistleEmojiSize(): number {
    const cardSize = this.calculateCardSize();
    // Emoji 稍小一些
    return Math.floor(this.getIconSizeForCard(cardSize) * 0.75);
  }

  private getLongWhistleCardPadding(): number {
    const cardSize = this.calculateCardSize();
    return this.getPaddingForCard(cardSize);
  }

  private getLongWhistleTextSize(): number {
    const cardSize = this.calculateCardSize();
    return this.getTextSizeForCard(cardSize);
  }

  private getLongWhistleSpaceBetween(): number {
    return this.getSpaceBetweenForCard(this.calculateCardSize());
  }

  private getCardSize(): number {
    return this.calculateCardSize();
  }

  aboutToDisappear() {
    if (this.soundPool) {
      this.soundPool.release()
      this.soundPool = null
    }
  }

  private async loadVibrationPreference(): Promise<void> {
    try {
      const context = this.getUIContext()?.getHostContext();
      if (!context) {
        console.warn('[WhistleTool] Host context unavailable, vibration on by default');
        this.vibrationEnabled = true;
        vibrationManager.setVibrationEnabled(true);
        return;
      }

      await preferencesManager.init(context as common.UIAbilityContext);
      const prefs = await preferencesManager.getUserPreferences();
      this.vibrationEnabled = prefs.vibrationEnabled !== false;
      vibrationManager.setVibrationEnabled(this.vibrationEnabled);
      console.info(`[WhistleTool] Vibration preference loaded: ${this.vibrationEnabled}`);
    } catch (error) {
      console.warn('[WhistleTool] Failed to load vibration preference, defaulting to on:', JSON.stringify(error));
      this.vibrationEnabled = true;
      vibrationManager.setVibrationEnabled(true);
    }
  }

  private triggerHaptic(type: 'short' | 'long'): void {
    if (!this.vibrationEnabled || !vibrationManager.isVibrationEnabledState()) {
      return;
    }

    const task = type === 'short'
      ? vibrationManager.vibrateLight()
      : vibrationManager.vibrateGameFinish();

    task.catch((error: Error) => {
      console.debug(`[WhistleTool] Vibration skipped (${type}):`, error.message);
    });
  }

  private async initSoundPool(): Promise<void> {
    try {
      const audioRendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 1
      }

      media.createSoundPool(
        5,
        audioRendererInfo,
        (error: BusinessError, soundPool_: media.SoundPool) => {
          if (error) {
            console.error(`[WhistleTool] Failed to create SoundPool: ${error.message}`)
          } else {
            this.soundPool = soundPool_
            console.log('[WhistleTool] SoundPool created successfully')
            this.loadSounds()
          }
        }
      )
    } catch (error) {
      console.error('[WhistleTool] Error creating SoundPool:', error)
    }
  }

  private loadSounds(): void {
    if (!this.soundPool) {
      return
    }

    try {
      // 加载 whistle.mp3
      const whistleFd = getContext().resourceManager.getRawFdSync('whistle.mp3')
      this.soundPool.load(
        whistleFd.fd,
        whistleFd.offset,
        whistleFd.length,
        (error: BusinessError, soundId: number) => {
          if (error) {
            console.error('[WhistleTool] Failed to load whistle.mp3:', error.message)
          } else {
            this.whistleSoundId = soundId
            console.log('[WhistleTool] whistle.mp3 loaded, soundId:', soundId)
          }
        }
      )

      // 加载 buzzer.mp3
      const buzzerFd = getContext().resourceManager.getRawFdSync('buzzer.mp3')
      this.soundPool.load(
        buzzerFd.fd,
        buzzerFd.offset,
        buzzerFd.length,
        (error: BusinessError, soundId: number) => {
          if (error) {
            console.error('[WhistleTool] Failed to load buzzer.mp3:', error.message)
          } else {
            this.buzzerSoundId = soundId
            console.log('[WhistleTool] buzzer.mp3 loaded, soundId:', soundId)
          }
        }
      )
    } catch (error) {
      console.error('[WhistleTool] Error loading sounds:', error)
    }
  }

  private playWhistleSound(): void {
    if (!this.soundPool || this.whistleSoundId === -1) {
      console.warn('[WhistleTool] Whistle sound not ready')
      return
    }

    const playParameters: media.PlayParameters = {
      loop: 0,
      rate: audio.AudioRendererRate.RENDER_RATE_NORMAL,
      leftVolume: 1.0,
      rightVolume: 1.0,
      priority: 1
    }

    this.soundPool.play(
      this.whistleSoundId,
      playParameters,
      (error: BusinessError, streamId: number) => {
        if (error) {
          console.error('[WhistleTool] Failed to play whistle:', error.message)
        } else {
          console.log('[WhistleTool] Whistle playing, streamId:', streamId)
        }
      }
    )
  }

  private playBuzzerSound(): void {
    if (!this.soundPool || this.buzzerSoundId === -1) {
      console.warn('[WhistleTool] Buzzer sound not ready')
      return
    }

    const playParameters: media.PlayParameters = {
      loop: 0,
      rate: audio.AudioRendererRate.RENDER_RATE_NORMAL,
      leftVolume: 1.0,
      rightVolume: 1.0,
      priority: 1
    }

    this.soundPool.play(
      this.buzzerSoundId,
      playParameters,
      (error: BusinessError, streamId: number) => {
        if (error) {
          console.error('[WhistleTool] Failed to play buzzer:', error.message)
        } else {
          console.log('[WhistleTool] Buzzer playing, streamId:', streamId)
        }
      }
    )
  }

  private async playShortWhistle(): Promise<void> {
    if (this.isPlayingShort || this.isPlayingLong) return

    this.isPlayingShort = true

    // 播放哨声音效（异步回调，不会阻塞）
    this.playWhistleSound()

    // 短震动 - 比赛暂停
    this.triggerHaptic('short')

    setTimeout(() => {
      this.isPlayingShort = false
    }, 200)
  }

  private async playLongWhistle(): Promise<void> {
    if (this.isPlayingShort || this.isPlayingLong) return

    this.isPlayingLong = true

    // 播放蜂鸣器音效（异步回调，不会阻塞）
    this.playBuzzerSound()

    // 长震动 - 比赛结束
    this.triggerHaptic('long')

    setTimeout(() => {
      this.isPlayingLong = false
    }, 1000)
  }


  private isTabletOr2in1(): boolean {
    try {
      const deviceType = deviceInfo.deviceType
      return deviceType === 'tablet' || deviceType === '2in1'
    } catch (error) {
      return false
    }
  }

  build() {
    Stack() {
      // 主要内容区域
      this.buildContent()

      // 透明返回按钮（左上角）
      Row() {
        Image($r('app.media.ic_back'))
          .width(28)
          .height(28)
          .onClick(() => {
            try {
              router.back()
            } catch (error) {
              console.error('[WhistleTool] Failed to navigate back:', error)
            }
          })
      }
      .width('100%')
        .padding({ left: 24, top: withPhoneStatusBarInset(16) })
        .position({ x: 0, y: 0 })
    }
    .width('100%')
      .height('100%')
      .backgroundColor(colorByName('app_background'))
  }

  @Builder
  private buildContent(): void {
    if (this.isTabletOr2in1()) {
      // 平板或2in1：横向排列，两个正方形卡片
      Row({ space: 24 }) {
        this.buildShortWhistleCard()
        this.buildLongWhistleCard()
      }
      .width('100%')
        .height('100%')
        .padding(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
    } else {
      // 手机：纵向排列
      Column({ space: 16 }) {
        this.buildShortWhistleCard()
        this.buildLongWhistleCard()
      }
      .width('100%')
        .height('100%')
        .padding({ left: 48, right: 48, top: withPhoneStatusBarInset(16), bottom: withPhoneBottomBarInset(16) })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private buildShortWhistleCard(): void {
    Column({ space: this.getShortWhistleSpaceBetween() }) {
      Text('🔊')
        .fontSize(this.getShortWhistleEmojiSize())
        .opacity(this.isPlayingShort ? 0.6 : 1.0)
        .animation({
          duration: this.isPlayingShort ? 200 : 300,
          curve: Curve.EaseInOut,
          iterations: 1,
          playMode: PlayMode.Normal
        })
        .scale({
          x: this.isPlayingShort ? 1.2 : 1.0,
          y: this.isPlayingShort ? 1.2 : 1.0
        })

      Text($r('app.string.whistle_short'))
        .fontSize(this.getShortWhistleTextSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.appAppearanceIsLight ? colorByName('app_text_primary') : $r('app.color.app_text_on_primary') as Object as string)
    }
    .width(this.isTabletOr2in1() ? 300 : this.getCardSize())
      .height(this.isTabletOr2in1() ? 300 : this.getCardSize())
      .padding(this.getShortWhistleCardPadding())
      .backgroundColor(this.isPlayingShort ? 'rgba(76, 175, 80, 0.42)' : 'rgba(76, 175, 80, 0.24)')
      .borderRadius(16)
      .border({
        width: this.isPlayingShort ? 3 : 1,
        color: this.isPlayingShort ? $r('app.color.app_success') as Object as string : 'rgba(76, 175, 80, 0.52)'
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.playShortWhistle())
      .enabled(!this.isPlayingShort && !this.isPlayingLong)
  }

  @Builder
  private buildLongWhistleCard(): void {
    Column({ space: this.getLongWhistleSpaceBetween() }) {
      Text('📯')
        .fontSize(this.getLongWhistleEmojiSize())
        .opacity(this.isPlayingLong ? 0.6 : 1.0)
        .animation({
          duration: this.isPlayingLong ? 1000 : 300,
          curve: Curve.EaseInOut,
          iterations: 1,
          playMode: PlayMode.Normal
        })
        .scale({
          x: this.isPlayingLong ? 1.2 : 1.0,
          y: this.isPlayingLong ? 1.2 : 1.0
        })

      Text($r('app.string.whistle_long'))
        .fontSize(this.getLongWhistleTextSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.appAppearanceIsLight ? colorByName('app_text_primary') : $r('app.color.app_text_on_primary') as Object as string)
    }
    .width(this.isTabletOr2in1() ? 300 : this.getCardSize())
      .height(this.isTabletOr2in1() ? 300 : this.getCardSize())
      .padding(this.getLongWhistleCardPadding())
      .backgroundColor(this.isPlayingLong ? 'rgba(244, 67, 54, 0.42)' : 'rgba(244, 67, 54, 0.24)')
      .borderRadius(16)
      .border({
        width: this.isPlayingLong ? 3 : 1,
        color: this.isPlayingLong ? $r('app.color.app_error') as Object as string : 'rgba(244, 67, 54, 0.52)'
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.playLongWhistle())
      .enabled(!this.isPlayingShort && !this.isPlayingLong)
  }
}
