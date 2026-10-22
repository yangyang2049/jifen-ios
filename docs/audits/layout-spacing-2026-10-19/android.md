# Android 全项目边距审计（2026-10-19，只读）

审计仓库：`/Users/yangyang/Desktop/jifenqi/jifen-android`。基线 HEAD `385fcb757ebc16f683428a6696bbe46e0026e3c0`，当前工作区 139 条未提交记录；按工作区现状审计，未覆盖、撤销或修改它们。已阅读仓库 `AGENTS.md`。本次只读源代码与生成审计材料，没有运行 Gradle、安装、截图或设备操作，也没有改业务代码、配置、现有业务文档。

这份报告证明的是源码中的尺寸规则、父子叠加和容器归属。不能把静态检索当作每屏视觉验收，不能由 12 和 16 不同直接判定错误。以下“确定”是确定存在几何差异；其是否要改、目标取值，仍由排版决策决定。圆角、图标尺寸只在影响可见间距或触控外壳时讨论。

## 覆盖与限制

- 对五个模块 `app`、`wear-oppo`、`shared-core`、`shared-model`、`score-engine` 的 1,390 个 Kotlin/XML/运行时 HTML 文件做全量 UI/布局特征检索。
- 共枚举 UI 相关源码 326 个：生产 270 个（手机 app 228、OPPO 腕端 42），辅助测试/debug 56。生产清单含路由、主题与布局辅助文件，不等于 270 个独立页面。shared-core/shared-model/score-engine 无独立页面 UI，数据/引擎文件不作为屏幕。
- 生产部分 1,083 个 Composable 函数声明、2,847 处布局/间距调用命中；计数包括组件、容器、弹层，不是页面数，也不是问题数。静态提取不替代 Compose 运行时测量。
- 人工重点复核 63 个源文件的主容器/父子调用及关键片段（57 个手机/共享文件、6 个腕端文件），详见 JSON `manualReviewedFiles`。其余生产 UI 文件全部在清单内分类并提取 spacing/inset 位置，未声称逐函数人工审读。
- 首页、记录列表/详情、计分目录、计时目录与页面、工具目录及 14 个工具、我的/登录资料/会员/常用数据、预约、小组全部业务分支、反馈、首启合规、扫码、计分设置/样式、远程同步/投屏/观众显示、通用弹窗与宽屏容器均纳入范围。
- `docs/` 原型和历史截图不作为当前运行 UI；未引用历史截图。XML 主体是资源和清单，手机 UI 主要为 Compose；运行时骰子/硬币 HTML 也已登记。

完整可机读清单：`/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/android-inventory.json`。每项含绝对/相对路径、类别、source set、人工/静态复核级别、Composable 名、行号与完整多行间距片段。它覆盖上下左右 padding、组件间距、最大宽度、高度约束和系统/键盘 inset。

生产 UI 相关文件分类：计分 67、小组 35、公共 UI 31、我的 20、工具 15、首页 7、记录 7、投屏显示 7、导航 7、计时 6、反馈 5、预约 4、远程同步 3、纯布局辅助 3、运行时网页工具 2、首启 1、扫码 1、app shell/其他 7、腕端 42。

## 可供三端对照的现有基准

以下路径若未注明模块，均相对 `app/src/main/java/com/douhua/jifen/`。

| 角色 | 当前 Android 值与源码 | 意义/建议 |
|---|---|---|
| 常规留白阶梯 | `ui/theme/DesignSystem.kt:14–39`：2/4/8/12/16/24/32；另外6/10用于紧凑控件 | 可以统一语义，不宜机械把所有6/10/14改为8/12 |
| 普通页左右 | `DesignSystem.kt:23–25`，`helpers/DeviceLayout.kt:73–109`：手机16，平板64；主Tab顶16，L2顶12，底16 | 在**最终内容柱**内生效；64不是窗口边缘最终总留白 |
| Section/卡片 | `DesignSystem.kt:30–39`：section24，title-content12，component16，card12 | 同一语义优先复用；标题行的隐含高度须一并计算 |
| 首页表面 | `DesignSystem.kt:118–124`：内边距水平16、垂直12，内容gap12 | 首页小组卡片与预约卡片都已有相同级别表面规范 |
| 内容最大宽度 | `DeviceLayout.kt:120–142`：首页/记录680，计分计时804，预约560，常用/工具/我的设置/同步600，小组840，小组表单560 | 角色差异合理；比较时区分外容器宽度与扣padding后实际内容宽 |
| 控件/标题栏 | `DesignSystem.kt:63–99`：图标操作触控48，普通按钮48，紧凑40，强调56；页顶栏64/弹窗56 | 可见图形和触控外壳不能混为一谈 |
| 普通弹窗 | `DesignSystem.kt:150–159`：内24，紧凑16，标题gap16，正文/动作gap24/16；`ui/dialog/DialogWidth.kt:21–39` 外侧至少24 | 窗外留白与窗内padding都是必要层级，不是一律重复 |
| 表单/Setup/确认宽度 | `DeviceLayout.kt:241–258`：Form手机384/平板480，Setup340/480且窄窗两侧16，Confirm280/400 | 三类弹窗宽度应按任务分工保留 |
| 系统底栏责任 | `MainActivity.kt:596–662` Scaffold `.padding(innerPadding)`；宽屏rail `:508–578` 自己windowInsetsPadding | 页面附加 navigationBarsPadding 时必须追踪是否消费父级inset，不能把系统安全区算入设计16 |
| 宽屏页面弹窗 | `ui/components/WideScreenPageDialog.kt:52–65,140–165,193–197`：外24/max560、高最多约520、头部水平16；主动消费navigationBars | 代码注释写90%宽，实际是W−48后max560；报告以实现为准 |

## 重要证据与建议（按排版价值排序）

### A01 已有组首页当前已同步，标题重复间距也已去掉

**当前已处理项，不应重复报旧问题。** `screen/group/home/HomeGroupSection.kt:239–273` 标题行有两个可见44dp操作容器，标题后不再额外 Spacer12；`:275–304` 仅未登录/空组使用 `HomeGroupEmptyState`，`:310–331` 只有空态内绘制创建/加入。已有组分支只有 `HomeGroupCard`。卡片水平16/垂直12（`:341–348`），卡片之间12（`:272`）。

标题采用24sp行高（`ui/theme/Type.kt:27–28`，`screen/home/HomeCommonDataComponents.kt:40–46`）。按默认字体缩放、24dp文本行高和44dp可见标题行估计，文本行底到卡片约 `(44−24)/2 = 10dp`；“我的球局”标题行由24dp文字/22dp箭头决定高24，另加12（`screen/home/HomeTabContent.kt:163–178`，手机同类`:263–280`）。因此目前两者约10对12，已经接近，不能沿用“还多12”的结论。Material最小触控区和字体缩放可能改变实际测量，应同屏截图确认；不建议为追求2dp让通知按钮失去触控外壳。

### A02 常用名/地点批量操作条：平板内容64，条内仍16

**确定存在同页水平轴差异，建议优先决策。** 常用名正文在max600中（`screen/me/CommonNamesScreen.kt:147–151`），卡片左右 `hPad`=16/64（`:274–283`）。批量条在同一max600容器内（`:303–316`），但没有传 `horizontalPadding`，共享条默认16（`ui/components/SharedComponents.kt:134–155`）。地点对应 `screen/me/CommonPlacesScreen.kt:136–140,223–236,255–264`。

在600dp内容柱、平板hPad64时：卡片左边=64；批量条按钮所在外部行左边=16，相差48dp（按钮还有自身内容padding，不能据此声称文案精确差48）。手机16对16相同。普通新增底栏已与正文共同max600+hPad（名称`:328–337`；地点`:279–286`）。

建议目标：批量条在该页面接收同一个hPad（手机16、平板64），仍可让背景铺满600；是否把操作文案贴齐卡片内容（再加内16）应另定，不应混在同次修复。风险：长“取消全选”文案在紧凑弹窗更易挤压，三等分布局应保留。

### A03 会员中心正文与购买栏在手机/平板的收窄方向反转

**确定差异；是否需要同轴由用户排版决定。** `screen/me/membership/AccountMembershipScreens.kt:529–546` 内容柱max600，正文左右hPad=16/64；购买栏在同一600柱的底部`:583–608`，内部固定左右24（`:1204–1210`）。

- 手机：正文边16，购买按钮边24，按钮比正文每侧内缩8。
- 平板：正文边64，购买按钮边24，按钮反而每侧向外40。
- 在600柱：正文可用472，购买按钮可用552，相差80。该差异不由居中误差造成。

建议两种需选择的目标：正文与按钮共同16/64；或购买栏比正文固定内缩8，即24/72。后一方案保留手机强调按钮节奏，但平板实际按钮只456dp。不要全局改responsiveHorizontalPadding；只统一会员容器口径。风险：购买条有协议、未登录/退款说明，会改变换行及覆盖高度。

正文为非VIP预留154+navigationBarBottomPadding（`:542–545`），末尾另有Spacer24（`:579`）；购买栏自己也消费navigationBars（`:1209`）。这个154是覆盖栏预算，不应直接当多余margin删除，应分别验证已登录/未登录/退款、Guest绑定和长文案。

### A04 计时记录详情有112–128dp显式尾部空白

**确定存在大留白；建议列为统一候选。** `screen/records/TimerDetailScreen.kt:152–165` 纵向滚动容器使用L2 bottom16，尾部无条件Spacer96，故有actions时最后一张卡片到滚动内容尾=96+16=112dp；无actions时前面的Spacer16依旧保留，总计128dp。该screen `:105–145` 无底部覆盖CTA；分享是注册ComposeView而非这里的悬浮栏。

同类计分记录详情 `screen/records/ScoreboardDetailScreen.kt:255–322` 滚动内容bottom16，CTA另置Column底部，不靠96dp占位。建议计时详情目标最后卡片后16或24，先确认是否有外部历史分享/截图设计依赖尾部。风险：导出截图构图可能变化；应以屏幕底部和导出图片两种输出分别验收。

### A05 普通页面可能重复处理系统底部inset，先做责任归一再调视觉值

**代码路径可确认，实际多出多少依系统/导航模式待验证。** 普通导航页面由MainActivity Scaffold `.padding(innerPadding)`（`MainActivity.kt:656–662`）包裹，没有同处`consumeWindowInsets(innerPadding)`；常用名`:145`、地点`:134`、全屏登录`screen/me/login/AccountLoginScreens.kt:282–305`再次 `windowInsetsPadding(navigationBars)`。计分记录CTA `screen/records/ScoreboardDetailScreen.kt:318–322`也加navigationBarsPadding。小组活动底栏 `screen/group/detail/GroupDetailActivitiesTab.kt:205–213`同样处理。

若系统导航栏底部inset为N且未被导航宿主其他层消费，路径变为父级N+子级N+设计底16/10；这应标为**待运行验证的重复风险**，不能仅凭此报告断言已多N。宽屏弹窗已有显式consume（`WideScreenPageDialog.kt:163–165`），不能照搬“删除全部页面safe area”。建议目标：普通页系统底部仅由一个宿主负责，设计底距另记16；全屏计分/工具与Dialog自己负责。风险：手势、三键、横屏侧导航、软键盘弹出收起四类都要验证。

### A06 预约当前上下/底部同轴；筛选到卡片有28dp叠加

**水平合理参考；纵向待排版选择。** `screen/schedule/ScheduleScreen.kt:148–160` 筛选max560+hPad；`:188–190,224–232`列表同max560+hPad；`:266–282`新增CTA同max560+hPad（上8/下16）。手机全部16；平板全部64；不像“卡片16、筛选/按钮24”的混合水平轴。

筛选行自身bottom12（`:160`）+列表contentPadding.top16（`:229`）=筛选外形底到首卡片28dp。对照记录列表：chips bottom12+列表top4=16（`RecordsTabScreen.kt:430–435,508–511`）；常用名：chips bottom12+列表top12=24（`CommonNamesScreen.kt:200–205,278–281`）。三者同类带筛选列表分别28/16/24，不等于全是bug，但应在报告中让用户定一个层级；建议列表起点统一到筛选外形底后16或24，修改一层即可，避免上下都留。

### A07 网格Section标题使用“item padding + grid gap”，实际不是单一12

**确定的组合规则；需要三端看齐语义。** 计分 `screen/score/ScoreTabScreen.kt:163–180`、计时 `screen/timer/TimerTabScreen.kt:244–259`、工具 `screen/tools/ToolsScreen.kt:69–85`都共用：grid top16，标题自身top8/bottom2，grid gap手机8/平板12（`DeviceLayout.kt:261–292`）。

首标题文本顶部=16+8=24；标题文本底到下方网格项=2+8=10（手机）/2+12=14（平板）；上一排卡片到底下Section标题文本顶=8+8=16（手机）/12+8=20（平板）。这是三端比较时应使用的数值，不能只拿`titleContentGap12`说已统一。

建议目标：若要所有Section标题到卡片固定12，使用独立标题/网格组而不是依赖grid全局gap，或显式补2/减2；Section之间可24。风险：网格虚拟化、span与滚动定位会变化，谨慎独立处理，不能修改全局cardGap来连带改变列表。

### A08 平板计分/计时固定4列，不按实际内容宽自适应

**待视觉确认的密度差异，非裁切证据。** `DeviceLayout.kt:261–283`平板固定4列；容器max804（`:128`）但仍扣左右64。宽度达到804时单格 `(804−128−3×12)/4=160dp`；600dp窗口为109dp。`ui/component/SquareItemCard.kt:91–129`<118进入compact且按图标预算缩小，因此有防溢出适配。

工具目录max600，按min128动态列数（`DeviceLayout.kt:295–312`），在600宽可3列，每格149.33。计分/计时和工具目录会有109对149的密度差。另`:124–126`注释以184dp最小格和16dp侧距解释804，与实际平板64和固定4列不一致；这是文档解释与实现的确定分歧，不是已证视觉bug。

建议选项：保持固定4列但接受109小格；或按最小128决定3/4列。若目标真是184，4列max内容容器至少需要`4×184+3×12+2×64=900dp`。需用户先决定目录密度，风险是入口数量与首屏可见数量变化。

### A09 宽屏页面弹窗头部16，页面正文继承平板64

**确定层级差异；建议将Dialog内容gutter单列。** `ui/components/WideScreenPageDialog.kt:193–197`头部水平16、max560；常用名/地点、设置、About/Faq等内部仍 `responsiveHorizontalPadding()` 或 `l2ContentPadding()`。例如名称正文64（`CommonNamesScreen.kt:130,160–163`）；设置用L2（`ScoreboardSettingsScreen.kt:132–139`）。在560窗，正文边比头部外行边内缩48，正文宽432。手机普通页仅16；弹窗却因设备是平板保持64。

对照登录弹窗 `screen/me/AccountLayoutSupport.kt:29–35` 已显式去掉水平方向双重inset，属于可参考的容器区分。建议页级Dialog正文独立16或24，保持普通平板页面64；不建议把全局平板64改小。风险：长字段变宽后页内高度、键盘与可滚区域有连带变化。

### A10 远程同步/投屏页已经整块同轴，可作为iOS对照参考

**合理实现，不建议因端间数值不同直接改。** `display/connection/DisplayConnectionScreen.kt:110–127`整块max600+L2 padding，`:171–180`顶部tabs与投屏/远程正文在同一个Column中，tabs自身内4（`:192–197`），外轴相同；tabs到正文16。手机两侧16，平板64。

首页入口弹窗 `cloudsync/ui/RemoteSyncSharedUi.kt:369–421`外24，maxSetup480（平板），头部水平16，正文也16。这里明确使用Dialog正文16，和A09页面弹窗正文64形成跨容器差异；可以统一“弹窗正文16或24”的角色，而不必改变独立页max600。

观众显示 `display/ui/DisplaySurfaceHost.kt` / `DisplayScoreboardView.kt`采用投影尺寸/scale和surface模型内边距，外部显示必须与手机表单留白分开。勿用16常量覆盖动态20×scale、名字预算与画面安全边。

### A11 首页内容轴总体一致；首页组标题要按行框高度比较

**合理基准，保留已完成的局部修正。** 手机首页在max680后给item统一hPad（`HomeTabContent.kt:220–235`及后续items）；Section之间24；宽屏双栏body先左右hPad、列间24（`:82–100`），顶栏独立全宽。未完成条覆盖时bottom单独预算：无覆盖16、手机80、宽屏16+80+24（`:50–59`，`HomeTabModels.kt:16`）。80是覆盖预算，不能一律改16。

小组title的44/48触控外壳与普通标题24行高不同，外显间距应从可见标题文字/卡片表面量，不应从Row边界量后忽略文本居中。A01给出了当前近似10对12，待同屏确认。

### A12 “我的”Tab和设置/会员使用不同内容柱

**确定宽度差异但用途可合理。** `screen/me/MeTabScreen.kt:307–314`使用MainTab680+mainTabContentPadding；`helpers/DeviceLayout.kt:135–138`虽有MeTab600，实际设置/会员使用它（`ScoreboardSettingsScreen.kt:132–138`，会员`:529–546`）。大窗口下，平板64后：我的首页卡片宽552，设置/会员472，相差80。

建议将Token命名角色说明清楚：若需要“我的系列页”同轴，可选共同600；若首页保留680而深页600，标记为有意层级，不列缺陷。不要仅因名叫MeTab却没用就改页面。

### A13 空态混用固定120与垂直居中，需要实际高度对照

**待视觉确认。** 记录列表空态 `screen/records/RecordsTabScreen.kt:493–500`传`weight(1f).padding(top=120)`，共享`EmptyStateContent`自身又`verticalArrangement=Center`（`ui/components/SharedComponents.kt:64–80`）。可用高度H时其中心约从H/2偏到H/2+60（不是偏120），图标与文字gap14。`TimerDetailScreen.kt:371,395,415`同样使用120。

积分表空态在可用内容Column内Center（`screen/tools/PointsTableScreen.kt:156–171`）；小组使用自身图标/说明/动作的空态组件。建议无数据、无搜索结果、错误态各确定统一锚点：可视区域中心或距内容顶固定值，二者选其一，不能用“top120”误当纯顶部布局。风险：有无筛选、底部CTA、长错误提示都会影响可用高度。

### A14 全屏工具和计分板使用独立边缘角色，不能与普通L2机械统一

**合理差异与设备确认项。** `screen/tools/ToolUi.kt:81–89,128–147`工具顶部保护`max(statusIgnoringVisibility,cutout,44)`，各屏再放48触控返回键/64标题栏：骰子`DiceToolScreen.kt:261–273`在保护区后加top16；倒计时`CountdownToolScreen.kt:468–477`标题栏64并水平16/64；秒表`StopwatchToolScreen.kt:412–422`直接加同保护区与64栏。

因此工具返回按钮可能从至少44+16=60开始，普通页则由系统TopBar处理。建议定义“全屏工具顶安全区”和“标题栏后内容距”两个角色，不将44认作多余margin。计分板四角按钮大量使用边20+48触控（`ScoreboardTemplate.kt:1298–1378`、`cards/DoudizhuScoreScreen.kt:728–785`）；应比较短边/侧cutout/隐藏系统栏重新显露时的可用边界，不直接改成普通16。横屏/折叠屏需当前设备截图与实机确认。

### A15 自定义弹层内边距保留任务差异；重点补窄窗外侧保护

**大多合理；少数待窄窗确认。** 通用确认是外24/内24、title gap16/body后24（`ui/dialog/CustomConfirmDialog.kt:72–117`）；比赛设置主体通常外16、内20×18（`screen/score/SportsSetupScreen.kt:806–814`）；改比分弹窗内18/下22（`screen/score/ScoreCustomAdjustDialog.kt:138–144`）；姓名/地点选择窗内16×20（`screen/score/setup/CommonNamePickerDialog.kt:100–108`，`screen/schedule/CommonPlacePickerDialog.kt:96–104`）。20/24/18对应不同密度，不能直接批量改24。

样式文本颜色传播提示 `screen/score/style/ScoreboardStyleEditOverlay.kt:519–552`在全屏遮罩内max340/400、fillMaxWidth，未加外侧水平padding；若可用窗≤340，面板可能贴两边。建议所有非全屏弹层外侧至少16或24，内部按任务角色保留16/20/24。是否会触发于当前支持方向须运行确认；风险是面板进一步收窄后长文案/双按钮换行。

### A16 小组整块关闭后，首页外层Section留白仍然存在

**宽屏48dp叠加是确定的；窄屏为待运行确认风险。** `screen/home/HomeTabContent.kt:153`常用数据后无条件Spacer24，`:155–161`调用HomeGroupSection，`:162`再无条件Spacer24；而`screen/group/home/HomeGroupSection.kt:233`在groupsEnabled=false时立即return，故宽屏“常用数据→我的球局”中间无组内容但残留24+24=48，比正常Section24多24。不是HomeGroupSection内部标题距导致。

窄屏`HomeTabContent.kt:228–232`LazyColumn的item间gap24；`:253`之后的小组item在外层仍存在，其内Box仍会构建但小组Composable可为空。是否最终出现两个gap或空item高度需Compose布局实测，不能直接声称窄屏已48。

建议目标：当服务端关闭小组时，外层同时移除整个小组Section及对应单份间距，前后正常Section之间保留24。需把可见性条件提升到安排item/Spacer的层级；风险是开关与账号/缓存状态不同步，不能把“未登录/未加载/无组”误判为整块关闭，因为它们仍应显示空态入口。

## 模块对照矩阵（给三端总报告合并）

| 模块 | Android现状 | 建议/状态 |
|---|---|---|
| 首页 | 主Tab边16/64，Section24；表面内16×12；小组已有组按钮隐藏，标题后0额外gap | 已修项登记；同屏核对文字行底而非Row底 |
| 记录列表/详情 | 列表边16/64，分组卡片gap12，卡片内16×12；详情max680、内16；计时详情尾112/128 | 优先决定计时尾留白与空态锚点 |
| 计分/计时目录 | top16+标题top8=24，标题卡片10/14；平板固定4列 | 先决定目录密度和标题统一角色 |
| 预约 | 筛选、列表、CTA同max560+16/64；筛选到首卡28；卡片内12 | 水平同轴可参考；纵向候选16/24 |
| 常用名/地点 | 正文/新增max600+16/64；批量条同柱但默认16 | 平板批量条差48值得优先统一 |
| 我的/设置 | 首页max680，深页max600；Section24；设置L2 top12/bottom32 | 角色宽度差异可保留，命名/目标需明确 |
| 登录/资料 | 账号max500；普通L2 padding，Dialog单独去水平层；资料另16/20/22局部角色 | 账号Dialog去重复层做参考；系统bottom责任待验证 |
| 会员 | 正文16/64，购买条固定24，同max600；覆盖预留154+system | 手机内缩8/平板外扩40，需用户选方案 |
| 小组 | 列表/detail max840，表单560，常用页面内16、card内12，组内gap12/16；顶栏全宽 | 与普通平板64不同是子系统规则，不能孤立改64；保持底部同柱 |
| 工具 | 目录max600；AA/积分表L2；全屏工具44安全顶+本地title/overlay；抛硬币/骰子HTML零页面默认margin | 层级合理；返回区安全与页面内容距分开 |
| 投屏/远程同步 | 独立页整个max600+16/64；tabs与正文同轴；入口Dialog正文16 | 可作为iOS顶部picker/body同轴参考 |
| 观众显示 | 按displayScale、surface模型、top/name budgets动态布局 | 不与手机表单统一固定16/24 |
| 反馈 | FeedbackContainer外max600+16/64，表单顶12/底16，Section24；图片/提示弹层另20 | 当前公共内容轴可复用；Keyboard/长错误需要运行验证 |
| 首启/扫码 | 首启max680+16/64、内16×14摘要；扫码相机按视口，底说明16/行gap12 | 专用场景保留 |
| 设置/样式弹层 | 确认24、表单20、紧凑16；不同弹层宽度角色 | 保留内部密度差异，统一最小窗外保护 |

## 腕端附录（单独尺寸体系）

`wear-oppo` 42个生产UI相关文件全部静态登记，6个重点人工复核。`wear-oppo/src/main/java/com/douhua/jifen/oppowatch/ui/WearChrome.kt:45–66`全局pagePadding16/pageTop8、标题栏32、<210dp紧凑屏、列表行52/56；`:101–107`紧凑标题28/top2、常规32/top4。腕端标题/圆屏边缘与手机系统栏不同，不应强制手机48/64。

记录与设置列表共top8/bottom32/gap6（`WearRecordsPage.kt:125–127,184–186`，`WearSettingsPage.kt:75–77`）；常用名列表bottom70用于底部动作（`WearCommonNamesScreen.kt:85–87,203`）；详情底24和水平12（`WearRecordDetailScreen.kt:120–128`）。建议只在腕端内部比较同类页，重点实测圆屏边缘裁切、长名、旋钮滚动后最后一行；没有腕端当前截图，不判定这些尾部值是错误。

## 建议排版决策顺序

1. 同页横向轴与隐藏Section：常用数据批量栏、会员购买栏；选择与正文同轴还是有固定强调内缩；小组关闭时无内容却残留48dp应收敛回24。
2. 明显尾部留白与系统责任：计时记录尾112/128、普通页面bottom inset消费；先确认责任再定16/24，防止盲删安全区。
3. 相同列表的筛选至首卡：当前16/24/28；选统一16或24并指定由一层负责。
4. 目录标题与密度：标题卡片10/14、首标题24；平板固定4列是否保留。
5. 弹窗内容gutter：页面Dialog64与任务Dialog16/20/24分开定义；普通宽页64保持独立。
6. 最后再核对全屏计分/工具与腕端，保留动态尺寸和已通过的专项布局。

建议的待拍矩阵：手机窄/常规、600–767平板单栏、≥768首页双栏、≥1024 rail；每类有内容/空态/编辑/长文案/放大字体；普通页有无键盘、手势/三键/横屏侧导航；折叠前后；计分设置/样式编辑覆盖层；腕端圆/方两形态。此矩阵是后续验证建议，本轮没有进行这些视觉验收。

## 验证

只运行文件检索、带行号源码读取、静态枚举与JSON格式检查。遵守用户“先报告，不动代码”和仓库AGENTS：没有运行构建，因为没有代码修改且本轮是静态布局审计。结束时 `git status --porcelain=v1` 仍为139条，SHA-1 `97107be031447e4ca8704978c84c499c6004428f`。审计底稿先生成于临时目录；最终报告与JSON副本统一保存在总报告目录。
