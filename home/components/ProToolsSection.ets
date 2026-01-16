import { Colors, Spacing, FontSizes, BorderRadius } from '../../../common/theme';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';

@Component
struct ToolItem {
  @Prop name: string;
  @Prop icon: string;
  @Prop iconColor: string; // Hex string for icon color
  @Prop isDarkTheme: boolean;
  onClickCallback?: () => void;

  build() {
    Column({ space: 8 }) {
      // Icon Container
      Column() {
        Text(this.icon)
          .fontSize(24)
          .fontColor(this.iconColor)
      }
      .width(56)
      .height(56)
      .borderRadius(BorderRadius.xl)
      .backgroundColor(this.isDarkTheme ? '#1C1C1E' : '#F5F5F5')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .shadow(this.isDarkTheme ? { radius: 0 } : { radius: 2, color: 'rgba(0,0,0,0.05)', offsetY: 1 })
      
      // Label
      Text(this.name)
        .fontSize(FontSizes.overline)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDarkTheme ? Colors.textTertiary : Colors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(72) // Fixed width for snap alignment
    .onClick(() => {
      if (this.onClickCallback) {
        this.onClickCallback();
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

interface ToolDef {
  id: string;
  name: string;
  icon: string;
  color: string;
}

@Component
export struct ProToolsSection {
  @Prop isWide: boolean = false;
  @Prop isDarkTheme: boolean = true; // Default to black UI
  onToolClick?: (toolId: string) => void;

  private tools: ToolDef[] = [
    { id: 'whistle', name: '', icon: '🔊', color: Colors.toolWhistleRed },
    { id: 'coin', name: '', icon: '🪙', color: Colors.toolGray },
    { id: 'dice', name: '', icon: '🎲', color: Colors.toolGray },
    { id: 'team', name: '', icon: '🛡️', color: Colors.toolGray },
    { id: 'rankings', name: '', icon: '📊', color: Colors.toolRankingsIndigo },
    { id: 'timer', name: '', icon: '⏱️', color: Colors.toolGray },
  ];

  aboutToAppear() {
    this.initToolNames();
  }

  private initToolNames() {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const rm = context.resourceManager;
      this.tools.forEach(tool => {
        switch (tool.id) {
          case 'whistle': tool.name = rm.getStringSync($r('app.string.home_tool_whistle').id); break;
          case 'rankings': tool.name = rm.getStringSync($r('app.string.home_tool_rankings').id); break;
          case 'timer': tool.name = rm.getStringSync($r('app.string.home_tool_timer').id); break;
          case 'coin': tool.name = rm.getStringSync($r('app.string.home_tool_coin').id); break;
          case 'dice': tool.name = rm.getStringSync($r('app.string.home_tool_dice').id); break;
          case 'team': tool.name = rm.getStringSync($r('app.string.home_tool_team').id); break;
        }
      });
    } catch (e) {
      console.error('[ProToolsSection] Failed to init tool names:', e);
    }
  }

  build() {
    Column() {
      // Header
      Row({ space: Spacing.sm }) {
        Text($r('app.string.home_tools'))
          .fontSize(FontSizes.h5)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.textPrimary)
        
        Blank()
        
        Image($r('app.media.chevron_forward'))
          .width(20)
          .height(20)
          .onClick(() => {
            router.pushUrl({ url: 'pages/tools/ToolsPage' });
          })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: Spacing.md })
      .width('100%')

      if (this.isWide) {
        // Desktop/Tablet: Grid - 6 columns in one row
        Grid() {
          ForEach(this.tools, (tool: ToolDef, index: number) => {
            GridItem() {
              ToolItem({
                name: tool.name,
                icon: tool.icon,
                iconColor: tool.color,
                isDarkTheme: this.isDarkTheme,
                onClickCallback: () => {
                  if (this.onToolClick) this.onToolClick(tool.id);
                }
              })
            }
            .margin({ left: index === 0 ? 0 : undefined })
          }, (tool: ToolDef) => tool.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr') // 6 columns
        .rowsGap(0)
        .columnsGap(0)
        .padding({ left: 0 })
      } else {
        // Mobile: Horizontal Scroll List
        List({ space: 0 }) {
          ForEach(this.tools, (tool: ToolDef, index: number) => {
            ListItem() {
              ToolItem({
                name: tool.name,
                icon: tool.icon,
                iconColor: tool.color,
                isDarkTheme: this.isDarkTheme,
                onClickCallback: () => {
                   if (this.onToolClick) this.onToolClick(tool.id);
                }
              })
            }
            .margin({ left: index === 0 ? 0 : undefined })
          }, (tool: ToolDef) => tool.id)
        }
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(80) // Reduced height
        .scrollBar(BarState.Off)
        .padding({ left: 0 })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
