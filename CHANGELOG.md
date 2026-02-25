# Changelog

## [Unreleased]

### Removed
- **Watch 隐私协议与退出流程**：移除 Watch 端独立隐私协议页与「退出」逻辑（原抄自鸿蒙，Apple 未强制要求）。删除 WatchPrivacyAgreementView、WatchAppExit 及 WatchPreferences.privacyAccepted；Watch 启动后直接进入 WatchTabView。
- **新比赛弹窗中移除秒表**：GameCatalog.newGameDialogGameTypes 过滤掉 .stopwatch，新比赛弹窗不再展示秒表；秒表仍在计时 Tab 与工具中使用。
- **新比赛对话框计分/计时双 Tab（对齐鸿蒙）**：NewGameDialogView 顶部增加分段选择「计分」「计时」；计分 Tab 展示全部计分项目（scoreboardGameTypes），计时 Tab 展示可选计时项目（不含秒表）；沿用 scoreboard_title、tab_timer 本地化。
- **新比赛与快速开始设置网格与样式统一**：HomeUtils 新增 GameTypeGridLayout（spacing Theme.md、minItemWidth 110、动态列数），新比赛与快速开始编辑两处共用 columns(containerWidth) 与 spacing；新比赛项改为使用 SportOptionView（与快速开始一致的正方形格、自适应图标/文字），两处内部处理与视觉统一。
- **新比赛用 dialog 呈现（对齐快速开始设置）**：新比赛不再使用可拖拽的 medium/large 多档位 bottom sheet，改为与快速开始设置一致的 .presentationDetents([.large]) + .presentationDragIndicator(.visible)，以整页 dialog 形式展示。
- **自定义主卡片对话框移除秒表**：QuickStartEditView 使用 editDialogSports（availableSports 过滤 .stopwatch），主卡片可选列表中不再出现秒表项。
- **设置弹窗最近记录**：SportsSetupDialogView 中移除「最近记录」区块（横向滚动的最近对局卡片及「点击快速使用」提示）；移除相关状态、loadRecentRecords/loadFromRecord/formatTime/formatSetsInfo/buildRecentGameCard 及 ScoreboardRecordManager 依赖；HomeModels 中移除仅用于该功能的 RecentGameDisplay 结构体。

### Added
- **所有计分项目均需先走 setup（至少输入名字）**：HomeTab 与 ScoreboardTab 的 sportsWithSetup 扩展为全部计分项目（乒/网/羽/足/篮/排 + 射箭/拳击/台球/匹克球/掼蛋/斗地主/简易计分/多人计分/计数器）。SportsSetupDialogView 的 getTitle 支持上述项目（无单独 key 时用 gameType.displayName +「设置」）。各计分板（Archery/Boxing/Billiards/Pickleball/Guandan/Doudizhu/SimpleScoreboard/MultiScoreboard）增加 initialSetup、onSetupConsumed，在 onAppear 中应用队名/选手名并调用 onSetupConsumed；HomeTab 与 ScoreboardTab 的 getScoreboardView 对上述项目统一传入 initialSetup 与 onSetupConsumed，从设置弹窗确认后进入计分板时名称生效。
- **计分板常用名称与设置弹窗（对齐鸿蒙）**：SportsSetupDialogView 支持「常用名称」选择：队伍名称输入框右侧 Chevron 打开 CommonNameSelectorDialog，从 CommonNamesManager 的常用队名列表中选择并填入。从「新比赛」或首页快速开始主卡/副卡点击乒乓球/网球/羽毛球/足球/篮球/排球时，先弹出 SportsSetupDialogView 设置队名与选项，确认后再进入计分板；新比赛弹窗关闭后延迟 0.35s 再弹出设置弹窗以避免 sheet 冲突。计分板六项支持 initialSetup/onSetupConsumed，在 onAppear 中应用队名与局数/抢七/换边等配置。新增 common_names_title、common_names_empty 本地化。
- **双人计时器设置弹窗**：围棋/象棋/国际象棋在计时 Tab（或从首页新比赛跳转）点击后先弹出 DualTimerSetupView 选择主时间（5/10/15/30/60 分钟），确认后进入 DualPlayerTimerView。新增 dual_timer_main_time 本地化。
- **Watch 工具：计数器**：工具 Tab 新增「计数器」（WatchCounterView）。点击屏幕 +1、底部「重置」按钮二次确认清零；移除底部「计数器」副标题，保留导航栏标题。Watch 本地化 game_counter、press_again_to_reset。

### Changed
- **秒表支持中途计时（分段）**：工具内秒表增加「分段」按钮，运行中或暂停时可记录当前时刻为一条分段；列表展示序号、本段时长、总时长，主显示精确到百分之一秒（00:00.00），刷新间隔 10ms。重置时清空分段记录。新增 stopwatch_total、stopwatch_lap、stopwatch_lap_list_title、stopwatch_lap_no、stopwatch_lap_segment、stopwatch_lap_total 本地化。
- **休息倒计时弹窗**：RestCountdownOverlay 标题改为由调用方传入（羽毛球局间显示「第N局结束」、局中显示「第N局 · 局中间隙」）；右上角小按钮改为「撤销」、底部主按钮改为「继续」。新增 rest_title_set_end、rest_title_mid_game 本地化。
- **计分项目图标统一**：GameType.icon 中简易计分、多人计分改为与计分 Tab（GameCatalog.scoreboardItems）一致：简易计分 🔢、多人计分 👥；新比赛、设置弹窗、最近记录、记录详情等使用 gameType.icon 处与计分 Tab 图标统一。
- **计分板数字等宽与外挂字体**：比分/局分/盘分加 .monospacedDigit()；FontRegistrar 注释说明 iOS 外挂字体（UIAppFonts + fontFamily 传 PostScript 名可对齐鸿蒙数字体）。
- **工具页横屏**：ToolSectionView 标题与网格、网格行/列间距由 12 改为 Theme.md（16pt），两行工具卡片不再挤在一起。
- **首页工具区横屏**：ProToolsSectionView 宽屏网格按可用宽度动态列数 6～8（columnCount：单格约 84pt+spacing），当前常见宽度多为 7 列，避免过疏；行/列间距 Theme.md。
- **首页横屏两栏对齐**：宽屏下「快速开始」与「最近记录」改为同一行绘制（高度 44pt + 下边距），两栏标题顶部对齐；QuickStartGridView 增加 showSectionTitle，宽屏时仅渲染网格，标题由 HomeTab 统一排布。
- **计分板名字**：TeamSection 名字区上边距与字号按设备区分：手机 nameTopPadding 28、nameFontSize 32；平板 36/44，双打名字平板 28。名字不再贴顶、平板上更大易读。
- **计分板大分/局分字号**：大分数在平板上 1.5×、上限 200pt；局分/盘分在平板 80pt、手机 48pt，更充分利用大屏空间。
- **魔方计时**：操作提示改为进入页面时一次性 dialog（双手准备 / 松开开始 + 确定），不再常驻盖住手掌图案；底部退出/拍照/重置按钮对齐计分板，使用 ScoreboardConstants、.ignoresSafeArea(edges: [.bottom, .leading, .trailing]) 贴边。
- **放弃未完成比赛弹窗**：确定按钮由「确认」改为「放弃」，避免语义模糊；新增 unfinished_discard_button 本地化（放弃 / Discard）。
- **比赛详情页内容限制宽度**：ScoreboardRecordDetailPage 内 ScrollView 内容区增加 maxWidth: 600 并居中，宽屏下内容不铺满整屏（参考鸿蒙/项目内 AACalculatorView）。
- **我的球局页面限制内容宽度**：SchedulePage 列表及顶部状态选择器、底部「预约新球局」按钮均限制最大宽度 600pt 并居中，宽屏下与比赛详情页一致。
- **预约新球局时长**：时长行改为左侧显示「时长」、右侧分钟数包裹在 [−] 与 [+] 按钮中（步长 15，30～360 分钟），替代原 Stepper；−/+ 与中间「90分钟」保留间距（HStack spacing: Theme.sm），按钮图标改为白色。
- **射箭计分板层级**：通过梳理 ZStack 层级实现「箭头只比左右半区高一层、按钮和菜单在最上层」。ScoreboardTemplate 使用 contentOverlayProvider: ((Bool) -> AnyView)?，传入 isEditMode，在编辑/底部按钮与 MenuDialog 之间渲染；射箭将发球箭头与左右半区点击层通过 provider 注入。
- **射箭编辑模式不触发加分面板**：射箭与羽毛球等共用同一模板，仅计分逻辑单独处理。TemplateConfig 的 contentOverlayProvider 传入 isEditMode；ArcheryMiddleLayer 在 isEditMode 为 true 时不显示箭头与左右半区点击层，编辑模式仅走模板的编辑能力，不再误触加分面板。
- **自定义主卡片项图标与文字自适应**：SportOptionView 用 GeometryReader 按单元格尺寸计算图标与文字大小（图标 24～56pt、文字 11～18pt 随格子缩放），大屏/平板下每项图标和文字自动变大。
- **常用名称过滤预制名称**：CommonNamesManager 增加预制名称集合（红队/蓝队、主队/客队、选手1/2、红方/蓝方、左队/右队及英文对应），recordUsage 不写入、addName/addNamesBatch 不接纳，与鸿蒙一致。
- **编辑模式下隐藏发球指示器**：TemplateConfig 增加 onEditModeChange 回调，模板在 isEditMode 变化时通知父视图；羽毛球/乒乓球/网球/排球计分板在编辑模式下不再显示 serve indicator（第 N 局发球方三角）。
- **射箭编辑模式局分 ± 生效**：ScoreViewModelProtocol 增加 adjustSets(isLeft:delta:)，默认空实现。模板 onSetsAdjust 内对 ArcheryViewModel 做显式 as? 转换后调用 adjustSets，避免协议默认实现被误派发导致局分不变；其余类型仍走 config.viewModel.adjustSets。
- **编辑模式局分 ± 统一派发**：模板新增 applySetsAdjust，对 Archery/PingPong/Badminton/Tennis/Pickleball/Boxing 等实现 adjustSets 的 ViewModel 均做显式 as? 后调用，修复乒乓球、羽毛球等编辑模式下局分改不动的问题（与射箭同因：协议默认实现被误派发）。
- **对话框标题行统一**：所有带标题 + X 关闭按钮的对话框改为「标题整体居中、X 在右侧」：使用 ZStack 居中标题，HStack { Spacer(); Button(X) } 叠在右侧。涉及 MenuDialog（操作）、射箭加分面板、棋类计时设置（DualTimerSetupView）、拳击回合结束弹窗（BoxingRoundDialog）。
- **首页宽屏两栏布局**：参考鸿蒙 HomeTab.ets，当屏幕宽度 ≥ 768pt 时采用两栏布局：左侧为快速开始、我的球局、工具区（约 2/3 宽），右侧为最近记录（约 1/3 宽，最小 240pt）；窄屏保持单列自上而下。
- **射箭计分板**：移除底部「记箭」按钮，改为点击左侧红方区域或右侧蓝方区域直接弹出对应侧的加分面板（记箭选分），点击哪侧即为该侧记一箭。
- **预约新球局提醒与鸿蒙对齐**：参考鸿蒙 CreateBookingPage.ets：默认提醒改为「2 小时 + 15 分钟」；预约时间早于某档位时该档位不可选并灰显；修改日期/时间时自动去掉已不可选的提醒；提醒区增加「?」按钮，弹窗展示 schedule_reminder_help_title / schedule_reminder_help_message 说明；新增中英文 schedule_reminder_help_title、schedule_reminder_help_message 本地化。提醒选项改为一行 chip 样式（2小时前/30分钟前/15分钟前 三枚可多选芯片），节省空间。
- **骰子/AA 计算器背景与工具统一**：DiceToolView、AACalculatorView 背景改为 Theme.backgroundColor（#1a1a1a），与秒表/口哨/抛硬币等工具一致；dice.html 的 body 背景由 #000000 改为 #1a1a1a，加载失败时的 fallback HTML 同步为 #1a1a1a。
- **设置里「删除全部记录」改为「清除数据」**：SettingsView 数据区入口及确认弹窗标题/按钮改用 clear_data 文案（中文「清除数据」、英文「Clear data」）；记录 Tab 仍使用「删除全部记录」/「Clear All Records」。
- **多人计分多出最后一格显示 🤡**：MultiScoreboardView 网格在玩家数不足整行时，多出的最后一格显示 🤡 emoji，其余多出格为浅色占位。
- **计分项目无论从首页还是计分 Tab 打开均先展示 setup**：首页「新比赛」选择计分后一律先弹出设置弹窗（移除按 sportsWithSetup 分支直接进入计分板的逻辑）；首页快速开始主卡/副卡点击计分项目时一律在首页弹出 setup，确认后再进入计分板（不再跳转计分 Tab 再进）。计分 Tab 内点击任意计分卡片或由首页带 selectedGame 跳转时，均先弹出 setup，确认后再进入对应计分板。
- **计分/计时 Tab 卡片背景**：计分 Tab 与计时 Tab 的网格项背景由 `Theme.homeCardDark` 改为 `.ultraThinMaterial`，与首页工具区一致，提升与页面背景的对比度。
- **计分/计时 Tab 项上下内边距**：计分 Tab 的 SportCardView、计时 Tab 的网格项内容使用 `.padding(.vertical, Theme.md)`（16pt），卡片内纵向留白加大，避免过紧。
- **工具页面网格**：工具列表（ToolsListPageView）内 ToolSectionView 的 LazyVGrid 由每行 2 列改为每行 3 列，至少 3 个 item 一行。
- **记录 Tab 条目纵向内边距**：记录页计分/计时条目的行内容（scoreboardRowContent、timerRowContent）由 `.padding(.vertical, Theme.sm)` 改为 `.padding(.vertical, Theme.md)`（16pt），纵向留白加大。
- **首页最近记录条目纵向内边距**：RecentRecordsSectionView 内计时/计分条目的行内容由 `.padding(.vertical, Theme.sm)` 改为 `.padding(.vertical, Theme.md)`（16pt），与记录 Tab 一致。
- **所有 Tab 隐藏滚动条**：首页、记录、计分、计时、工具五个 Tab 的主 ScrollView 增加 `showsIndicators: false`，不再显示滚动条。
- **记录 Tab 搜索栏与分类 Tab 对比度**：搜索栏背景改为 `.ultraThinMaterial` 并加 `Theme.homeOverlayBorder` 描边，图标改为更高对比度；全部/计分/计时芯片未选态背景改为 `Theme.surface`、文字改为 `Theme.textPrimary`，并加描边与略增纵向 padding，选中态保持 accent 色并加字重，整体更突出。
- **计分/计时 Tab 首 section 上边距**：计分 Tab 与计时 Tab 内容区 `.padding(.top)` 由 `Theme.sm` 改为 `Theme.md`（16pt），第一个 section 上方留白增加。
- **计分 Tab 分区标题**：第一分区「体育」改为「运动」（scoreboard_sports 中文文案与 fallback）。
- **比赛详情菜单按钮样式**：ScoreboardRecordDetailPage 右上角菜单按钮改为与记录 Tab 一致，仅使用 `Image(systemName: "ellipsis.circle")`，去掉圆形 material 背景与自定义字体/颜色。
- **删除记录流程**：比赛详情页删除记录时先显示 loading（「正在删除记录...」），删除成功后显示「已删除」toast，约 1 秒后自动退出当前页并刷新记录列表；新增 record_deleted 本地化。
- **暂停/超时页导航栏**：退出按钮由右上角改为左上角（.topBarLeading），文案由 watch_exit（主应用未定义故显示 key）改为使用 exit 本地化（退出/Exit）；右侧不再放置按钮；主应用新增 exit 本地化。
- **首页工具区 item 放大**：ProToolsSectionView 内 ToolItemView 图标 24→32、容器 56×56→64×64、文案 fontCaption→fontBody2、单格宽度 72→84、横向滚动区高度 80→100。
- **计时页退出按钮统一在左侧**：魔方、篮球 24/12 秒、双人计时（围棋/象棋/国际象棋）与暂停/超时一致，退出按钮改为左上角（.topBarLeading），文案统一为 exit 本地化（退出/Exit）；双人计时并交换左右：左侧退出、右侧开始/暂停/继续，游戏结束 overlay 内按钮文案改为 exit。
- **篮球/魔方/暂停/双人计时返回为图标**：BasketballCountdownView、CubeTimerView、TimeoutCountdownView、DualPlayerTimerView 左上角退出按钮由文字「退出」改为 chevron.left 图标，与计分子页一致。
- **骰子工具进入提示**：进入骰子页时底部显示 toast「点击屏幕摇骰子」/「Tap to roll dice」（tap_to_roll），约 2 秒后自动消失。
- **工具中「计时器」改为「秒表」**：首页工具区与工具页内该入口标题改为「秒表」/「Stopwatch」（tool_stopwatch）；StopwatchView 导航标题同步为秒表；布局调整：时间字号 64、Spacer 撑满、按钮 minWidth+padding 与 Theme.surface 背景，保存成功改为底部 ToastView 提示。
- **秒表不进入记录、无保存按钮**：StopwatchView 移除「保存」按钮及保存到记录的逻辑（不再写入 TimerRecordsViewModel）；记录 Tab 与「全部记录」页（RecentActivityPage）展示计时记录时过滤掉 gameType == .stopwatch，秒表不再出现在记录中。
- **时间工具改名为全屏时间**：tool_time、time_tool_title 中文改为「全屏时间」、英文改为「Fullscreen Time」，首页工具区、工具页与 DateTimeToolView 导航标题同步。
- **计时 Tab 分组**：计时页改为「棋类」（围棋、象棋、国际象棋）与「其他」（通用计时、篮球 24/12 秒、魔方、暂停/超时）两组展示；新增 timer_section_board_games、timer_section_other 本地化。
- **计时 Tab 里秒表改为正计时（对齐鸿蒙）**：计时 Tab「其他」中第一项由「秒表」改为「正计时」，使用新视图 CountUpTimerView（从 0 开始正计时，开始/暂停/重置，左上角 chevron 返回）；工具里的秒表仍为 StopwatchView，两者区分。新增 timer_count_up 本地化（正计时 / Count Up）。
- **Quick Start 可选项**：快速开始编辑页（主卡/副卡）中移除「计时器」「计数器」「跳棋」，availableSports 过滤掉 .stopwatch、.counter、.checkers。
- **简易计分修复（对齐鸿蒙）**：SimpleScoreboardView 在 init 中统一创建 SimpleScoreboardController 并以 BaseScoreViewModel(controller:) 注入，保证从首帧起 viewModel 与 controller 绑定，首次点击即可记录并支持撤销；移除依赖 onAppear 再赋 controller 的逻辑。
- **多人计分（对齐鸿蒙）**：MultiScoreboardView 左上角增加「退出」按钮（与计分/计时页一致），菜单内退出文案由 watch_exit 改为 exit 本地化；默认玩家名改为使用 multi_score_player_default 本地化（「玩家 1」～「玩家 4」）；保存记录时标题使用 game_multi_scoreboard 本地化；菜单按钮改为 ellipsis.circle 与 Theme.textPrimary 风格统一。
- **首页工具 section 箭头颜色**：工具区标题右侧「>」由 Theme.accentColor（绿色）改为 Theme.textSecondary，与设置等列表的 chevron 一致。
- **计分板设置改为底部 sheet、羽毛球支持单双打**：SportsSetupDialogView 改为以 bottom sheet 呈现（.presentationDetents([.medium, .large])、.presentationDragIndicator(.visible)），不再整屏占满。羽毛球设置增加「单双打」选项：单打时两栏为「选手1」「选手2」，双打时为「主队名称」「客队名称」；SportsSetupResult 新增 isSingles，确认时写入。新增本地化 player1_name、player2_name、singles、doubles、badminton_singles_doubles。
- **计分 Tab 六项运动统一走 setup bindsheet（对齐鸿蒙）**：乒乓球、网球、羽毛球、足球、篮球、排球在计分 Tab 点击时先弹出 SportsSetupDialogView 的 bottom sheet（.presentationDetents + .presentationDragIndicator），确认后再进入对应计分板并传入 setup 结果；计分 Tab 内用 getScoreboardView(for:setupResult:onSetupConsumed:onBack:) 统一构建六项视图并传入 initialSetup，与首页入口规则一致。
- **计分/计时 Setup 弹窗不再空白（对齐鸿蒙）**：计分板设置弹窗与棋类计时设置弹窗改为基于 item 的 sheet，保证有内容时再呈现。HomeTab 使用 ScoreboardSetupItem (Identifiable) 与 .sheet(item: $pendingScoreboardSetupItem)，Quick Start / 新比赛 选运动后直接设 item 即弹出设置；TimerTab 使用 .sheet(item: $pendingDualTimerDest) 呈现围棋/象棋/国际象棋主时间设置，移除 showDualTimerSetup。DualTimerSetupView 改为与 SportsSetupDialogView 一致的卡片样式（遮罩 + 340pt 宽卡片、标题行、主时间选项、取消/开始游戏按钮）。新增本地化 team_home、team_away、team1_name、team2_name。
- **计分 Tab 返回与内容对齐鸿蒙**：计分子页返回按钮统一为图标样式（chevron.left），与 ScoreboardTemplate 一致。MultiScoreboardView、ArcheryScoreboardView、GuandanScoreboardView、DoudizhuScoreboardView 左上角改为圆形半透明背景 + chevron.left 图标，右上角菜单改为 line.3.horizontal + 同款圆形按钮；射箭/掼蛋/斗地主菜单内退出文案 watch_exit 改为 exit，射箭菜单增加「退出」项。
- **Watch 退出按钮文案**：计分/射箭/篮球训练菜单中的「退出」由 key `watch_exit` 改为 `exit`，并加 NSLocalizedString value 回退 "Exit"，避免界面显示 string_key；Watch 本地化新增 `exit`。
- **移除工具 Tab，首页工具区入口**：底部/侧栏移除「工具」Tab；首页工具 section 标题右侧仅保留「>」箭头（去掉「进入工具页面」文字），点击通过 path 进入工具列表；工具列表改为 ToolsListPageView（无内层 NavigationStack），从首页 push 时在首页栈内用 navigationDestination(for: ToolItem.self) 再 push 具体工具，避免嵌套 NavigationStack 导致进入后自动退出。
- **记录 Tab 编辑模式**：进入编辑模式后，「完成」按钮改为显示在右侧（.topBarTrailing），编辑时右侧仅显示「完成」、隐藏菜单按钮，避免误触菜单。
- **新比赛弹窗支持全部项目**：NewGameDialogView 由 6 项改为 GameType.allCases，可选所有计分与计时类型；选择计时类型时调用 onTimerGameSelected 跳转计时 Tab，其余通过 path 进入计分。HomeTab getScoreboardView 补全 guandan、doudizhu、simpleScore、multiScoreboard、counter（计数器用 SimpleScoreboardView）。弹窗增加 .large 高度以便浏览全部项。
- **Quick Start 配置支持全部项目与计时**：快速开始编辑页（QuickStartEditView）可选范围由 6 项扩展为全部 GameType（availableSports = GameType.allCases），包含所有计分项目与计时类型（围棋/象棋/国际象棋/通用计时等）；主卡/副卡点击时，计时类型（stopwatch/go/xiangqi/chess）跳转计时 Tab 并自动打开对应计时页，其余跳转计分 Tab。MainTabView 新增 pendingTimerGameType，TimerTab 支持 Binding 入参并在 onChange 时打开对应目的地后清空。
- **首页与 Tab 顺序（对齐鸿蒙）**：记录 Tab 调整为第二位（首页 → 记录 → 计分 → 计时 → 工具），手机与 iPad 一致；首页「工具」section 扩展为抛硬币、骰子、哨子、红黄牌、积分表、计时器、时间、AA 计算器、十秒挑战等入口，点击仍通过 path 进入对应工具页，工具 Tab 保留完整列表。
- **Watch 使用说明**：「使用说明」从计分 Tab 移至设置 Tab；计分页不再显示使用说明入口与首次进入提示，设置内新增「使用说明」行，点击弹出说明弹窗。

### Fixed
- **BUGS_AND_OPTIMIZATION_REPORT 修复与优化**：FlipCoinView 在 onDisappear 中清理 flipTimer，避免页面消失后定时器仍触发。NewGameDialogView 选项目后先同步执行 onSelect/onTimerGameSelected 再 dismiss，避免 asyncAfter 在 presenter 释放后回调。计分详情/多人计分/计时器/秒表等处 force unwrap 改为 if let 或 guard。计分详情 getScoringActionText、拳击「第 N 回合」改为本地化（record_action_team_*、boxing_round_n）。QuickStartEditView、设置常用名称 sheet 增加 .presentationDragIndicator(.visible)。ScoreboardRecordsViewModel.refreshRecords/refreshRecordsImmediately 将加载与分组放到后台队列，仅主线程更新 @Published。CHANGELOG 将「新比赛对话框计分/计时双 Tab」与「新比赛用 dialog 呈现」拆为两条并补全空条目。
- **计时 Tab 文案显示 string_key**：为计时 Tab 及子页补充主应用本地化。zh-Hans / en 新增：tab_timer、timer_common、timer_go、timer_xiangqi、timer_chess、timer_basketball_24s、timer_basketball_12s、timer_cube、timer_timeout、timer_section_board_games、timer_section_other、exit、pause、resume、wins、dual_timer_player、dual_timer_main_time、cube_hold_to_start、cube_hold、seconds_short、minute、minutes。
- **Watch 右滑返回**：计分/射箭/篮球训练页因 `.navigationBarHidden(true)` 导致系统右滑返回失效。在各自拖拽手势中增加「从左向右滑」（dx > 50 且 |dy| < 50）触发 dismiss()，与系统返回手势一致；退出方式仍保留「上滑 → 菜单 → 退出」。
- **Watch 工具/记录/计时子页导航与返回**：工具子页（抛硬币、随机数字、十秒挑战、计数器）与记录详情、计时详情补全 `.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`，显示导航栏与系统返回；并统一增加右滑返回手势（同上），保证无导航栏或系统手势不可用时仍可返回。Watch 本地化增加 tab_timer。
- **PointsTableRecord**：增加 `Hashable` 一致性，满足 `NavigationLink(value:)`、`path.append`、`navigationDestination(for:destination:)` 对 Hashable 的要求。
- **MainTabView iPad 布局**：`List(selection: selectedTab)` 在 iOS 上不可用，改为 `List` + `ForEach` + `Button` 手动驱动选中并高亮当前项；iPad 详情不再在闭包内使用 `navigatingFromTab.wrappedValue` / `selectedGame.wrappedValue`，改为通过闭包 `onSetNavigatingFromTab`、`onSetSelectedGame` 由父视图设置，修复 “'init(selection:content:)' is unavailable in iOS” 与 “Value of type 'Int?'/‘GameType?’ has no member 'wrappedValue'”。
- **TimerTab navigationDestination**：闭包参数 `dest` 已是非可选 `TimerDestination`，去掉多余的 `if let dest = dest`，修复 “Initializer for conditional binding must have Optional type”。
- **斗地主/多人计分 history 类型**：`[(scores: [Int])]` 改为 `[[Int]]`，修复 “Cannot create a single-element tuple with an element label”（Swift 不允许单元素元组带标签）。
- **Multiple commands produce PointsTableView.stringsdata**：删除重复的 `jifen/Features/Tools/PointsTableView.swift`（简单玩家积分版），仅保留 `jifen/Features/Tools/PointsTable/PointsTableView.swift`（完整积分表工具）。项目使用 PBXFileSystemSynchronizedRootGroup 同步 jifen 目录，两个同名 struct 导致重复编译产物。
- **全项目本地化审查与修复**：见 LOCALIZATION_AUDIT.md。计分板模板（ScoreboardTemplate）所有 toast 与截图弹窗改用 NSLocalizedString（press_again_to_reset、has_been_reset、no_undo_available、screenshot_failed/saved、unknown_error、please_allow_photo_access、save_failed、screenshot_filename、cancel、save、save_screenshot_title）。羽毛球/乒乓球局结束与换边、局间/中场休息改用 set_ended_winner、change_sides、set_break、halftime_break。网球局/盘结束 toast、盘间休息、换边、抢七改用 tennis_game_end_toast、tennis_set_end_toast、set_break_tennis、change_sides、tennis_tiebreak。十秒挑战「误差」「秒」「开始」「停止」、AA 计算器「请输入有效金额」、抛硬币「Recent Flips」、首页「Game not supported」、时间工具星期（Locale.current）均已本地化或修复。新增 Localizable key：screenshot_filename、save_screenshot_title、tennis_*、ten_second_*、aa_enter_valid_amount、flip_coin_recent、game_not_supported、seconds。
- **羽毛球局结束 toast 本地化**：局结束文案改为 String(format: NSLocalizedString("set_ended_winner", ...), setNumber, winnerName, finalLeftScore, finalRightScore)。
- **足球/篮球/排球默认队名本地化**：FootballViewModel/VolleyballViewModel 默认队名改为 NSLocalizedString("red_team"/"blue_team")；BasketballViewModel 改为 NSLocalizedString("team_home"/"team_away")。新增 team_home、team_away 中英文。
- 所有撤销操作均显示 toast：主应用计分板（菜单撤销、左右滑撤销、休息弹窗撤销）成功时显示「已撤销」；Watch 计分板（羽毛球/网球/乒乓球等）、射箭、篮球训练撤销时显示「已撤销」toast。Watch 新增 watch_undo_toast 本地化。
- Watch App 羽毛球计分板：发球权规则修正为与鸿蒙一致。采用 rally 计分规则：谁得分谁获得下一分发球权；新一局由上局负方先发。新增状态 servingIsRed，并在 ScoreSnapshot/undo 中保存与恢复；乒乓球/网球仍使用原有「每 2 分换发 + 局次决定先发方」或网球按局换发逻辑。
- Watch App 匹克球计分板：暂不显示发球指示器。匹克球有球权/side-out、双打一二发等规则，与简单 rally 计分不同，完整支持较复杂；先隐藏 server indicator，计分与局数逻辑不变。
- 计分板（乒乓球/网球/排球）：在 addScore 中加分之前增加「局/盘/抢七已结束则不再加分」的防护，避免快速连点导致分数超出胜局条件（如乒乓球 12:2）。羽毛球此前已在加分前做局胜判断并 return，逻辑正确未改。
- Watch App: 修复所有界面显示字符串 key（如 tab_score、game_badminton、game_tennis）而非本地化文案的问题。为 Watch 应用添加独立 Resources（en.lproj / zh-Hans.lproj）下的 Localizable.strings，使 NSLocalizedString 从 Watch 自身 bundle 正确加载中英文文案。
- Watch App 抛硬币：修复动画结束时硬币不正对用户的问题。原因是旋转圈数包含小数导致最终角度不是 0°/180°；改用整数圈数（4-6圈随机），确保硬币落地时正面朝上（0°）或反面朝上（180°）。
- Watch App 抛硬币：重新设计硬币外观，与鸿蒙版本风格一致。
- Watch App 随机数字：为起始 👆 emoji 添加脉冲动画，提示用户点击。
- Watch App：将「记录」从计分页移出，改为独立 Tab，顺序为：工具 → 计分 → 记录 → 设置。
- Watch App 十秒挑战：未计时时显示 👆 并添加与随机数字相同的脉冲动画，提示点击开始。
- Watch App 计分 Tab：将网球排在乒乓球之前，顺序为羽毛球 → 网球 → 乒乓球。
- Watch App 记录：列表行显示相对时间戳（如 5分钟前、2小时前、3天前），与鸿蒙 SportsSetupDialog 一致；记录详情「比赛记录」中每条动作为相对比赛开始时间显示 MM:SS 或 HH:MM:SS，与鸿蒙 WatchRecordDetail 一致；盘结束/比赛结束动作用强调色。使用径向渐变模拟金属光泽，添加边缘高光描边增强立体感，文字添加微妙阴影呈现浮雕效果。尺寸比例调整为 120/110/104（与鸿蒙 144/132/124 比例一致）。
- Watch App 抛硬币：引入与主应用/鸿蒙一致的 flip_coin.mp3 音效；将 flip_coin.mp3 放入 Watch App Resources，抛硬币时使用 mp3 播放。
- Watch App 首页 Tabs：计分、工具、记录、设置四个 Tab 的页面标题使用内联样式（.navigationBarTitleDisplayMode(.inline)）。

### 三端一致（iOS 主应用 / Watch / 鸿蒙）
- **休息弹窗 + 撤销**：iOS 主应用局间/局中/盘间休息弹窗（RestCountdownOverlay）增加可选「撤销」按钮；羽毛球/乒乓球/网球计分页在显示休息时传入 onUndo，与 Watch、鸿蒙一致。鸿蒙 Watch 局中休息已在 ViewModel 中调用 showUndoButton。
- **日期同年不显示年份**：iOS 主应用 ScoreboardRecordSummary.date、ScoreboardRecordDetailPage.formatDate 改为同年 MM-dd、跨年 yyyy-MM-dd；鸿蒙多人计分记录详情页（MultiGroupRecordDetailPage）日期改用 formatDateWithConditionalYear。Watch 记录详情此前已改。

### Added
- **足球/篮球菜单「结束比赛」**：计分板菜单（MenuDialog）在足球、篮球下增加「结束比赛」项，点击后设置 gameFinished = true，比赛结束浮层正常显示。ScoreViewModelProtocol 新增 endGame()，BaseScoreViewModel 默认空实现，FootballViewModel/BasketballViewModel 重写并置 gameFinished = true。本地化 menu_end_game。
- **计分项目补全（拳击/台球/匹克球）**：计分 Tab 体育区新增拳击（BoxingScoreboardView）、台球（BilliardsScoreboardView）、匹克球（PickleballScoreboardView）。拳击：回合制，总分+胜回合数，通过「回合结束」弹窗输入本回合双方分数，支持撤销与编辑队名，保存记录含 team1SetScore/team2SetScore。台球：左右两队，单球分值 6/7/8/9/10 点击加分，BilliardsScoreboardController + BaseScoreViewModel + ScoreboardTemplate。匹克球：11 分制、三局两胜、每球得分，PickleballViewModel 与 ScoreboardTemplate，局结束 toast、比赛结束浮层。ScoreboardTemplate 支持 BoxingViewModel/PickleballViewModel（adjustSets/adjustScore）、拳击时左右区点击不触发加分。首页 getScoreboardView 与 ScoreboardTab.sportsItems 接入 .boxing / .billiards / .pickleball。本地化 boxing_end_round、boxing_round_scores、pickleball_set_end。
- **工具：积分表**：工具 Tab 其他区新增「积分表」（PointsTableView）。多张积分表，每张含名称与多队伍（赛/胜/平/负/积分，积分=3×胜+平），排名按积分排序。列表增删、详情编辑名称与队伍数据、添加/删除队伍，本地持久化 UserDefaults key points_table_records。PointsTableModels、PointsTableStorage、PointsTableDetailView、PointsTableTeamEditView。本地化 points_table_*。
- **射箭计分板**：计分 Tab 体育区新增射箭（ArcheryScoreboardView）。局分制先到 6 分胜，每局 3 箭/方、5:5 时 1 箭/方，点击半区弹出 0–10/M 选分，与 Watch 规则一致。GameType 新增 archery；本地化 project_archery、watch_team_red、watch_team_blue、watch_set_end_format、watch_match_finished。首页 getScoreboardView 支持 .archery。
- **计时 Tab 全部实现**：围棋/象棋/国际象棋（DualPlayerTimerView）：双人主时 60 分钟，点击切换行棋方，一方归零即结束并保存记录（GameType.go/xiangqi/chess）。篮球 24 秒/12 秒（BasketballCountdownView）：倒计时、开始/暂停/重置，退出可保存。暂停/超时（TimeoutCountdownView）：预设 15s～30min 倒计时。魔方（CubeTimerView）：长按 0.5 秒开始、点击停止，可保存。GameType 新增 go/xiangqi/chess；本地化 dual_timer_player、resume、seconds_short、minute、minutes、cube_hold_to_start、cube_hold。
- **鸿蒙对齐阶段 1（主框架）**：新增「计时」Tab（TimerTab）：入口为通用计时（StopwatchView）、围棋/象棋/国际象棋/篮球24秒/篮球12秒/魔方/暂停超时，顺序为首页 → 计分 → 记录 → 计时 → 工具。设置页：振动开关与 PreferencesManager 同步持久化；新增「数据」区与「清空全部记录」（计分+计时）。iPad 使用 NavigationSplitView 侧栏（首页/计分/记录/计时/工具）+ 详情，手机保持底部 TabView。本地化 tab_timer、timer_common、timer_go、timer_xiangqi、timer_chess、timer_basketball_24s/12s、timer_cube、timer_timeout、settings_data。
- **计时持久化接入**：工具中新增「计时器」（StopwatchView）：开始/暂停/重置/保存，保存时调用 `TimerRecordsViewModel.shared.addRecord(_:)` 写入 GameRecordSummary（gameType: .stopwatch），记录 Tab 计时子项展示并可点击进入详情。新增 GameType.stopwatch 与 game_stopwatch 本地化。记录 Tab「清空全部」同时清空计分与计时记录，「清空」在两项均为空时禁用。TimerRecordDetailPage 展示单条计时记录（项目、时长、记录时间）。本地化增加 pause / timer_record_saved / timer_record_time / tab_timer_record。
- 计分 Tab 棋牌与计分真实页：**斗地主**（DoudizhuScoreboardView）：3 人 3 列横屏布局，点击加分、菜单编辑名称/撤销/退出，退出时保存记录（extraData 含 players）；**掼蛋**（GuandanScoreboardView）：左右两队 + 中间等级（2~10/J/Q/K/A/王），点击加分、菜单编辑/升级/撤销/退出，保存记录含 level；棋牌两项不再使用占位页。多人计分：右上角菜单按钮唤起菜单；多人记录 extraData 使用 AnyCodable 正确编码保存。
- 计时记录持久化：新增 TimerRecordManager（UserDefaults），TimerRecordsViewModel 启动与增删时读写；记录 Tab 展示的计时数据重启后保留；计时功能侧需调用 `TimerRecordsViewModel.shared.addRecord(_:)` 写入记录。
- Watch 记录列表：与鸿蒙 WatchRecordTab 一致，圆角胶囊行（高 56、圆角 30、背景 #222）、行间距 8；展示所有 Watch 类型（含匹克球、射箭、篮球训练）；匹克球行显示🎾+匹/P 角标。新增 FEATURE_CHECKLIST.md 计分/记录/计时/Watch 收尾清单。
- 计分 / 记录 Tab 对齐鸿蒙（先手机端后手表端）：**手机计分 Tab**：改为分节（体育 / 棋牌 / 计分）+ 网格图标卡片，体育为足球/篮球/排球/乒/羽/网，棋牌为斗地主/掼蛋，计分为简易计分/多人计分；暂仅体育 6 项可进入计分页。**手机记录 Tab**：增加子 Tab「全部 / 计分 / 计时」、搜索框、按日期分组列表，支持编辑模式删除单条；计分数据来自 ScoreboardRecordsViewModel，计时来自 TimerRecordsViewModel。**Watch 计分首页**：最后选择的项目置顶（持久化 watchLastSelectedGame），与鸿蒙 WatchHomeTab 一致。
- Watch App：参考鸿蒙 Watch，新增匹克球、射箭、篮球训练。计分 Tab 增加入口：匹克球（可选 3 局 2 胜 / 5 局 3 胜）、射箭（局分制，先到 6 分胜，每局 3 箭/方，5:5 时 1 箭/方；点击半区弹出 0–10/M 选分）、篮球训练（左出手/右命中，上滑菜单结束训练，下滑撤销）。WatchGameType 与 WatchScoreboardRoute 增加 pickleball、archery、basketballTraining；记录列表与详情支持新类型，篮球训练详情显示命中率。
- Watch App 计分板：参考鸿蒙 Watch 计分页，菜单增加「重置」与「切换布局」。重置：清空本场分数/局/盘/休息/历史并回到 0-0。布局：竖屏（红上蓝下）与横屏（红左蓝右）切换，偏好持久化于 WatchPreferences.scoreboardLayout。中英文 Localizable 增加 menu_undo / menu_reset / watch_continue / watch_stop / watch_layout_vertical / watch_layout_horizontal / watch_reset_toast。
- Watch App 计分板菜单：改为图标 + 文字、2 列网格样式（LazyVGrid），缩短纵向高度。四项：撤销(arrow.uturn.backward)、暂停/继续(stop/play)、重置(arrow.counterclockwise)、切换布局(rectangle.split)。
- Watch App 设置：参考鸿蒙 Watch 设置页，增加「计分板布局」选项（watch_settings_layout_title），点击进入竖屏/横屏选择页，与 WatchPreferences.scoreboardLayout 同步。
- iOS 主应用：新增「记录」Tab（与 Watch 一致）。Tab 顺序为首页 → 计分 → 记录 → 工具；记录 Tab 展示计分记录列表（按日期分组）、空状态与加载态，点击进入记录详情。首页「最近记录」保留最近 3 条，底部「查看全部记录」改为跳转到记录 Tab（onViewAllTapped），不再进入活动页。

### Fixed / Improved
- 计分板：羽毛球、网球导航标题改为 NSLocalizedString（game_badminton / game_tennis），与其余运动一致。
- 计分板：篮球、足球、排球增加比赛结束浮层（GameFinishedOverlay），ViewModel 增加 getWinnerName()，与乒/羽/网一致。
- 计分板：排球局数已通过 TeamData.sets 与 TeamSection 展示，无需改动。
- 计分板：菜单（MenuDialog）标题与项（操作、哨子、截图、交换边、重置、撤销）、休息弹窗撤销按钮、比赛结束浮层「X 获胜」改为本地化文案（operations / menu_whistle / menu_screenshot / menu_swap_sides / menu_reset / menu_undo / game_winner_format）。
- 主应用抛硬币（FlipCoinView）：对齐 Watch 实现——整数圈数（4–6 圈）保证落地 0°/180° 无跳变；硬币外观改为径向渐变（外/中/内 180/165/156）、边缘描边、正反面文字阴影；动画用 ease-out cubic、perspective 0.6、scale 0.25；结束时使用精确 targetAngle 不做二次 snap。
- 快速开始设置：按钮文案由「完成并保存」改为「保存」（中英文 Localizable.strings）。
- 记录详情分享：从鸿蒙 jifen MultiGroupRecordDetailPage 移植分享功能。比赛详情页菜单增加「分享」项；将记录摘要（项目、比分、日期时间等）渲染为图片，通过系统分享面板（UIActivityViewController）分享；新增 RecordDetailShareCardView、ShareActivityView 及 share_match_record 本地化。
- 发布前清理：新增 RELEASE_CHECKLIST.md（除 App Icon、Launch Screen 外的发布检查项）。QuickStartConfigManager.saveConfig 中 fatalError 改为 do/try/throw；所有调试用 print() 包在 #if DEBUG；SportsSetupDialogView 中 CommonNameSelectorDialog 占位按钮移除 print。
- Watch 显示名：与主应用一致。新增 Watch App Resources 下 en.lproj/InfoPlist.strings、zh-Hans.lproj/InfoPlist.strings，CFBundleDisplayName 分别为「iScore」「全能计分器」；移除 project.pbxproj 中 Watch target 的 INFOPLIST_KEY_CFBundleDisplayName = jifenWatch。
