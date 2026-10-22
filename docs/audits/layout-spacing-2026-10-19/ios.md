# 全能计分器 iOS 全项目边距源码审计（2026-10-19）

只读工作区审计；本轮未修改代码、配置或业务文档，未构建、未启动模拟器、未抓取新截图、未测量运行态像素。所有数值为当前源码的 pt/逻辑尺寸。按当前含未提交改动的工作区读取，因此不能将旧截图或用户此前看到的版本认作当前实现。未发现适用于此目录的 AGENTS.md。

## 1. 覆盖口径

- 全量检索 `jifen/` 下 247 个 Swift 文件（不含测试、Packages、marketing、artifacts）。
- UI 声明或间距/容器规则命中 138 个文件、321 个声明、2629 行证据。声明含共享组件、ViewModifier、UIView 包装和 4 个带 Fixture/CaptureRoot 名称的声明，**不是 321 个独立页面**。
- 人工复核 43 个文件的关键页面/容器源码片段；其余为全量静态索引及命中项复核。**这不等于全项目逐屏视觉验收**。
- 随附 `/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/ios-inventory.json`：逐文件分类、声明及准确行号、padding/spacing/safeArea/maxWidth/listRowInsets 证据、人工复核标记、未命中 Swift 文件清单。
- 确定问题指源码可以确定的同角色间距叠加或对齐规则不一致；“视觉待确认”不作已复现缺陷；合理差异保留用途说明。

## 2. 现有尺寸体系

|角色|当前值/位置|解读|
|---|---|---|
|基础刻度|Theme.swift:187-194，4/8/16/24，通用 spacing12|已有刻度，允许用途明确的6/10/14/18等光学校正|
|主页面左右|Theme.swift:197，手机16、iPad24|设备 idiom 决定，窄 iPad 窗仍24|
|区块/标题内容/网格|Theme.swift:259-261，24/12/12|是最合适的跨页面参照|
|卡片内边距|Theme.swift:262-263，16/紧凑12|普通/紧凑两类已有语义|
|记录行/Tab尾部|Theme.swift:264-265，垂直12/尾部24|尾部24不含系统安全区|
|二级页/聚焦/登录|Theme.swift:199-206，iPad760 / 600 / 375|不要把所有角色统一一个宽度|
|首页平板|HomeTab.swift:15-31，最小边≥600时左右64；iPad宽≥768双列|有意对齐 Android 首页，不等同于普通二级页24|
|自定义弹窗|Theme.swift:223-243，setup340/480，菜单320/480，结束360/480，调分600|随可用宽收口；手机最少左右16，iPad宽≥600最少40|
|计分板边缘控制|ScoreboardConstants.swift:12-19，外缘20，按钮48，最小点击44|应独立于普通列表16/24，不能直接全局替换|

## 3. 建议优先评审的源码问题（未改代码）

### IOS-01 首页快速开始仍有标题间距叠加（确定，P2）

**证据**：`jifen/Features/Home/Components/QuickStartGridView.swift:29-47`，编辑按钮 `.frame(width:44,height:44)`（41），标题行随后 `.padding(.bottom,Theme.sectionContentSpacing)` 即12（47）。同页小组 `HomeTab.swift:1126-1129` 为44标题行+spacing0；我的球局 `HomeTab.swift:1283-1297` 为内容标题行+spacing12。

若可见标题布局高为 H，快速开始标题框到底下卡片为 `(44-H)/2+12`；小组为 `(44-H)/2`。源码能确定快速开始多叠了12；H以及文字实际墨迹边界需要新截图。建议统一“标题到卡片可见间距”目标12，保留44点击区域，不能只把所有 Section 的 spacing 都改0。风险：需要同时确认区块上方留白与标题基线。

### IOS-02 投屏与同步页顶部分段控件脱离正文限宽（确定，P2）

**证据**：`jifen/Features/Display/CastConnectionView.swift:25-34` 顶部 Picker 仅左右 `Theme.pageHorizontalInset`；`65-69` 正文左右 padding 后 `maxWidth:760`；CloudSyncEntryView.swift:51-55 同样限760。

iPad可用窗宽1024时，Picker宽976、左24；正文卡片宽712、左156（760总宽内含左右24）。左右相差132。若放在窄 form sheet 差异会缩小。建议 Picker 与两种 Tab 正文共用同一个限宽容器，使左右边界相同；目标宽保持现有760角色。风险低，需分别看完整 iPad 页和 form sheet。

### IOS-03 常用名称/地点编辑态批量操作条未跟随正文限宽（确定，P2）

**证据**：CommonNamesManagementView.swift:77-99、CommonPlacesManagementView.swift:61-83。列表与浮动添加在max760内，CommonDataBatchEditBar 位于该容器外、全窗 VStack 中；CommonDataManagementShared.swift:121-122 批量条只有横向16、高52，没有maxWidth。RecordsTab.swift:53-61 使用同一个条，但整个父容器已限920。

窗宽1024时，列表外壳760，批量条1024；条左右文本16，而列表普通行文本距窗至少 `(1024-760)/2+16+16=164`。建议背景仍可全窗，实际按钮/文字区跟随该页760正文容器，并用同一左右16。风险：编辑态、多选计数、长文字均要确认。

### IOS-04 “我的”→会员同名760宽度因修饰顺序产生48差异（确定，P2/设计决定）

**证据**：SettingsView.swift:93-96：`frame(maxWidth:760)→frame(infinity)→padding(horizontal:24)`；MembershipView.swift:71-75：`padding(horizontal:24)→frame(maxWidth:760)→frame(infinity)`。

iPad足够宽时，“我的”卡片宽760；会员正文卡片宽 `760-24*2=712`。相同 meTabContentMaxWidth 被分别当成“内容宽”与“含内边距容器宽”，导航后左右各缩24。建议先决定760含不含边距，随后同一页面族统一修饰顺序；若目标“卡片宽760”，会员栏应采用同一内容宽约定。风险：各下级页、底部栏需同步评估，不能仅更改全局token。

### IOS-05 我的球局列表的筛选/CTA与卡片边缘相差8（确定差异，P2/可选）

**证据**：SchedulePage.swift:55 行外边距左右16；126 底部CTA左右24；135 顶部状态Picker左右24；298-299卡片内部横14/纵13。手机从窗边到卡内文本是16+14=30，Picker/CTA为24。顶底互相对齐，但比卡片左右各缩8。

建议决定“卡片/顶筛/底CTA统一16”或明确保留CTA24作为独立操作角色；优先统一顶筛与卡片外缘16，CTA可单独保留24。风险：页面采用系统List，运行态还要确认系统默认边距/顶部safeAreaInset spacing，不能只加减8即认为最终像素已确定。

### IOS-06 会员手机正文16、购买栏24（确定差异，P2/可选）

**证据**：MembershipView.swift:71，手机正文横16；654购买栏横24。iPad这两者都是24。手机购买按钮比权益/套餐卡片左右各缩8。

建议统一手机购买按钮外缘16，或将24正式记录为CTA角色；不建议为消除差异去增大所有正文边距。风险：协议、未登录同步提示、恢复购买会影响底栏总高，须保留safeAreaInset和滚动可达性。

## 4. 待视觉或产品决策的差异

### IOS-07 记录详情宽度720、计时详情600（确定配置差异，非直接缺陷）

ScoreboardRecordDetailPage.swift:158-160：默认`.padding()`后max720；TimerRecordDetailPage.swift:28-32：内容max600后横16/顶8/底24。前者内容宽约688（系统默认padding通常16，仍需运行态确认），后者内容宽600。两个详情类型的可读宽度不一致，但比分趋势/多选手表格确实需要更宽。建议保留“普通详情600、图表详情720”两个明确角色，或由用户统一选一档；不要直接把图表强压600。

### IOS-08 小组容器左右20、其他普通页16/24（合理子系统差异，可评估）

GroupDetailView.swift:59 内容全向20；654 GroupSurface内16，即手机窗边到卡内文字20+16=36。Settings 普通行可为16+16=32；首页小组卡16+16=32；首页球局紧凑卡16+12=28。小组内部纵区块20、卡内spacing14也独立于全局24/12。

建议若追求跨模块一致，普通卡片可选外16内16、区块24/内容12；但小组密集信息不宜机械换成24。GroupDetail tabs、底操作条当前也左右20，内部是自洽的。不能把这些差异全部算 bug。

### IOS-09 iPad四列由设备决定，窄窗口仍四列（潜在拥挤，需新截图）

ScoreboardTab.swift:119-122、TimerTab.swift:133-138、ToolsTab.swift:90-95均iPad固定4列；Theme.swift:20-24明确不按窗口改变 idiom，页面左右24。窗口320时，单格可用宽约 `(320-48-36)/4=59`；计分/计时格再扣横向6*2，文字可用约47，艺术图56已接近格宽。源码能确定没有按窄窗口降列，不能仅据此声称文字截断或溢出。建议在320/375/600宽的 iPad 窗口确认后决定是否按最小卡宽切2/3/4列；桌面宽屏仍4。风险：现有跨端四列约定与截图布局可能变化。

### IOS-10 新比赛/设置居中弹窗的最低280高度可能挤占超短窗口（边界风险，未复现）

CenteredSetupDialogContainer.swift:153、190：`max(280,proxy.height-48)`；AdaptiveSetupDialogLayout:93-95最小滚动区80；同文件39/51固定末项余量12。容器高度不足280时，maxDialogHeight仍280，不能据源码保证始终在窗内。

建议最终允许高度≤实际可用高度，常规窗保留上下24；先复核最短横屏、键盘打开、iPad小窗、动态字体。风险：header/actions测量和滚动区最小80需一起预算，单减280可能挤掉操作。

### IOS-11 棋类计时设置未显式限宽（条件差异，需确认呈现容器）

DualTimerSetupView.swift:45-68：滚动内容横16/顶14/底28、区块14，但未设置maxWidth。一般由系统sheet限宽，故不必然过宽；若同一视图作为宽页使用，会比 sports setup340/480宽得多。建议由实际sheet呈现宽度决定，必要时归入600聚焦表单，不直接添加全局480。

### IOS-12 计分板/全屏工具安全区多种实现，应按场景确认而非统一边距（边界复核项）

ScoreboardConstants.swift:12/19 20边距/44点击；ScoreboardTemplate.swift:199-201仅iPad补topChromeInset，430-431右上20+safeTop；BasketballScoreboardView.swift:110-111取窗口/geometry左右安全区最大值；FullscreenBarrageView.swift:13-30主动映射旋转后安全区，额外6且横向最少16。

这些差异服务刘海、全屏背景、旋转后的逻辑边，而不是普通页面留白。建议保留独立规则，运行态确认四角、Home指示条、横竖和悬浮窗口。未观察到运行态遮挡，不将20 vs16直接列缺陷。

## 5. 已处理或应保留的现状

### IOS-13 用户提到的小组标题间距，在当前工作区已处理

HomeTab.swift:1125-1129明确注释和实现：44标题行、VStack spacing0；1173小组条目卡内16。当前不能再报告“小组44行+12间距仍未修复”。标题框H与卡片间距是 `(44-H)/2`，不是0像素。标题上方仍会有半行留白；与普通标题行的上方光学节奏要用新截图评估。

首页已有小组卡没有创建/加入双按钮；此审计不修改其他端。该行为只对首页section，不能据此删除GroupList管理页现有底部入口。

### IOS-14 首页未结束球局浮条已有尾部避让，不应把100尾距当成重复留白

HomeTab.swift:239-240 68高+8gap预留76；260滚动尾部24+76=100；594-595浮条横Theme.pageHorizontalInset、底8。无浮条时尾部24。建议保留状态性避让，后续只能在运行态确认浮条实际高后决定是否还可压缩；不能统一删掉76。

### IOS-15 网格与登录页当前有合理且成组一致的规则

计分/计时/工具列表顶部手机16/iPad24，左右16/24，区块24、标题内容12、网格12、底24，证据ScoreboardTab.swift:24-38、TimerTab.swift:39-57、ToolsTab.swift:34-56。卡图44占位、56画面、图文10、纵padding14是已有成组调整，应成组保留。工具卡无横6而计分/计时有横6（ToolsTab:114-126 vs ScoreboardTab:245-258、TimerTab:158-173），可能影响长标题留白，属于可选对齐项。

AccountViews.swift:154-158和302-305均padding24后max375，Apple登录/密码登录正文横向一致；苹果与密码页logo顶部12 vs32服务不同标题结构，不应仅因数值不同自动判断多余20。登录页375与普通页760是明确角色差异。

## 6. 功能覆盖矩阵（供跨端主报告合并）

|模块|全量静态覆盖功能|容器/间距主参照与结论|
|---|---|---|
|首页|头部/投屏入口、快速开始、常用名称地点、小组、球局、工具、最近记录、未结束浮条、编辑快速开始、新比赛|左右16/24/64；区块24；快速开始44+12叠加，组44+0当前已改|
|计分目录|所有GameCatalog分组及卡片|1080上限，区块24/内容12/格12；手机2/3列，iPad4列|
|记录与活动|全部/计分/计时、搜索筛选/批量、比分详情、复盘/时间轴/趋势/排名、图文语音笔记、计时详情、旧最近活动页|列表920；比分详情720、计时详情600有用途差异，需明确阅读档位|
|计时|计时目录，围棋/象棋/国际象棋双人计时、设置、暂停倒计时、魔方|目录统一；实际计时全屏单独预算，不套列表边距|
|工具|工具目录、秒表、硬币、骰子、哨子/蜂鸣、随机分组、AA、10秒挑战、红黄牌、日期时钟、全屏弹幕、积分表列表/详情|AA600、积分表600、秒表720、随机380/520；存在明确工具用途差异|
|我的/设置|我的、账号卡、偏好/声音、计分设置、FAQ、关于、常用名称/地点及新增编辑/搜索/批量|内容760；常用数据批量条脱离限宽是优先项|
|账号|Apple/密码登录、协议网页、资料/昵称/头像裁剪、注销、扫码/授权/相机包装|登录375；扫码主体无统一正文max，需确认现有呈现方式|
|会员|套餐/权益、已开通、购买/协议/恢复、兑换、活动sheet|和我的同token但容器含padding规则不同；手机CTA24 vs正文16|
|本地预约|列表空态/正常/批量、状态筛选、新建/编辑/复制、详情/开始/取消|600聚焦；卡片16、筛/CTA24；表单系统Form边距归系统|
|小组概览/列表|列表/归档/创建/加入/扫码/分享、详情概览/活动/成员/排名/结果、管理|列表/详情960；内容20、卡内16，内部自洽但独立体系|
|小组活动/赛程/录分|活动创建/详情、报名、成员/席位、赛程/阵容、规则、比赛编辑/录分、结果上传/修复/预览、成员成绩|多数系统Form/List，不能把系统默认section inset臆填16；JSON逐文件证据|
|小组训练/通知|训练tab/编辑、请假/报告、训练通知/取消、通知收件箱/详情/跳转、推送设置|静态覆盖；未逐屏截图；GroupSurface16和区块20为基线|
|云同步/投屏|投屏说明状态、同步角色/加入/共享、远端显示、外接显示待机/各项目surface|顶Picker无760限制、正文760，优先同轴；外显按画面缩放独立|
|所有计分板|通用/多人、篮球/3x3/投篮训练、足球、乒乓球/羽毛球/网球单双、排球/沙排/气排、匹克球、桌上足球、台球/八球/九球/斯诺克、拳击、射箭、斗地主/掼蛋/升级|共享Template、TwoSide和自有surface，按钮20/48/44；密度曲线与安全区分开审计|
|共享弹窗/样式|setup各项目/名称选择、菜单、结束、调分、显示设置、样式面板/调色/帮助、提示教学动画、确认/帮助/关闭、记录笔记|Theme各role宽340/320/360/600，iPad480；高度边界待确认，不强制一宽|
|网页/系统桥接|内嵌法律/协议/反馈链接网页、系统分享/扫描/照片/Apple按钮|系统UI边距不冒充自定义页面已量化|

## 7. 给排版决策的建议顺序

1. 优先统一同页明确对齐项：快速开始标题额外12、投屏页Picker宽度、常用数据批量栏。
2. 用户决定“正文宽含不含padding”、普通/紧凑卡片、底CTA是否采用独立24。建议保留手机外16、普通卡内16、紧凑12、区块24、标题视觉间距12、Tab尾24作为评审默认。
3. 宽屏按角色保留：首页64/双列、目录1080、列表760/920/960、聚焦600、图表720、登录375、弹窗480；统一角色含义，而非强制同一个数。
4. 视觉复核：手机窄/常规/横屏，iPad窄窗/全屏，中文/长文字/大字体，有/无小组、空/有球局、有/无未结束浮条；系统Form/List/安全区必须运行态确认。

以上建议供用户决定排版。

## 附录：全量命中文件与视图声明

下表为静态源码覆盖清单；“容器片段”仅指人工读取关键容器源码；“静态索引”不等于视觉验收。精确padding/spacing行号见JSON。

|文件|视图/包装声明|复核口径|
|---|---|---|
|jifen/ContentView.swift|ContentView:10|静态索引|
|jifen/Core/Analytics/AppAnalytics.swift|AnalyticsActivityView:607|静态索引|
|jifen/Core/AppReviewPrompt.swift|LaunchReviewPromptModifier:74|静态索引|
|jifen/Core/Components/AddValueLabel.swift|AddValueLabel:19|静态索引|
|jifen/Core/Components/AppLogoImage.swift|AppLogoImage:4|静态索引|
|jifen/Core/Components/CustomDialogs.swift|SystemHelpButton:15, OptionalAccessibilityIdentifier:118, CustomDialogCard:139, CustomDialogPillButton:165, CustomDialogScrim:185, CustomConfirmDialog:203|容器片段|
|jifen/Core/Components/EmptyStateCourtIcon.swift|EmptyStateCourtIcon:3|静态索引|
|jifen/Core/Components/FloatingBackButton.swift|FloatingBackButton:4|静态索引|
|jifen/Core/Components/GridCardTitleStyle.swift|GridCardTitleStyle:6|静态索引|
|jifen/Core/Components/ModalCloseButton.swift|ModalCloseButton:5, ScoreboardDialogCloseButton:24|静态索引|
|jifen/Core/Components/RemoteImage.swift|RemoteImage:64|静态索引|
|jifen/Core/Components/SectionTitleView.swift|SectionTitleView:7|容器片段|
|jifen/Core/Display/ScoreboardDisplayOutputs.swift|ScoreboardExternalDisplayModifier:159|静态索引|
|jifen/Core/Theme/Theme.swift|尺寸/布局规则|容器片段|
|jifen/Features/Account/AccountViews.swift|AccountCenterView:5, AccountLoginSheet:25, AccountLoginView:87, PasswordLoginView:217, LoginAgreementBar:357, LoginLegalWebPage:417, AccountProfileView:432, AccountDeletionView:715, ProfileHeaderCard:998, CameraImagePicker:1229, ProfileAvatarFallback:1268, ProfileInfoRow:1286, ProfileNicknameRow:1333, ProfileThinDivider:1370, NicknameEditDialog:1379|容器片段|
|jifen/Features/Account/AppleAuthProvider.swift|AppleIDButton:157|静态索引|
|jifen/Features/Account/AvatarCropView.swift|AvatarCropView:79|静态索引|
|jifen/Features/Account/QRLoginApprovalView.swift|QRLoginApprovalView:103, QRDataScannerView:374|静态索引|
|jifen/Features/Activity/RecentActivityPage.swift|RecentActivityPage:3|容器片段|
|jifen/Features/Activity/TimerRecordDetailPage.swift|TimerRecordDetailPage:10|容器片段|
|jifen/Features/Display/CastConnectionView.swift|CastConnectionView:4, CastRippleRing:337|容器片段|
|jifen/Features/Display/CloudSyncEntryView.swift|CloudSyncEntryPanel:6, ConnectedDisplayCard:449, CloudSyncIntroCard:479, CloudSyncIntroSection:561, CloudSyncRoleCard:593, CloudSyncScoreboardSharingEntry:655, RemoteSyncSharingDialog:746|容器片段|
|jifen/Features/Display/DisplaySnapshotFixture.swift|DisplaySnapshotFixtureView:217|静态索引；截图fixture|
|jifen/Features/Display/MarketingScreenshotFixture.swift|MarketingScreenshotFixtureView:97|静态索引；截图fixture|
|jifen/Features/Display/RemoteDisplayView.swift|RemoteDisplayView:8|静态索引|
|jifen/Features/Display/ScoreboardExternalDisplayView.swift|ScoreboardExternalDisplayRootView:121, ScoreboardExternalWaitingView:163, ScoreboardExternalLiveView:545, DisplayTwoSideSurface:1704, DisplayChaseStatsStrip:2227, ServingTriangle:2268, DisplayDoublesCourtSurface:2338, DisplayMultiGridSurface:2528, GridTile:2767, DisplayShotTrainingSurface:2862, ScoreboardExternalClockView:3031, ScoreboardExternalKeyPointBadgeLayer:3130, ScoreboardExternalTableTennisMarkerLayer:3196, ScoreboardExternalBadmintonMarkerLayer:3238, ScoreboardExternalRestOverlay:3278|静态索引|
|jifen/Features/Feedback/FeedbackViews.swift|FeedbackAuthorAvatarView:109, FeedbackTypeChipView:162, FeedbackPlatformChipView:176, FeedbackPostBadges:189, FeedbackModerationNotice:206, FeedbackLinkifiedText:231, FeedbackStatusStampView:264, FeedbackErrorStateView:279, FeedbackEmptyStateView:313, FeedbackListView:338, FeedbackListCard:554, FeedbackDetailView:614, FeedbackCommentRow:1081, FeedbackImagePreviewPage:1120, FeedbackReportDialog:1160, FeedbackReportReasonRow:1279, CreateFeedbackView:1309|静态索引|
|jifen/Features/Groups/GroupActivityViews.swift|GroupActivityCreateView:4, GroupActivityView:110, GroupRemoteResultView:290, GroupDirectScheduleView:305|静态索引|
|jifen/Features/Groups/GroupCaptureRoot.swift|GroupCaptureRoot:6|静态索引；截图fixture|
|jifen/Features/Groups/GroupDetailView.swift|GroupDetailView:3, GroupSurface:654, GroupSectionTitle:659, GroupActivityTagChip:668, GroupToast:678, GroupActivityStatusChip:698, GroupEmptyCard:717, GroupAvatar:725, GroupEditConflictActions:733|容器片段|
|jifen/Features/Groups/GroupForms.swift|GroupMatchEditor:5|静态索引|
|jifen/Features/Groups/GroupManagementView.swift|GroupManagementView:5, GroupCommonNameImportView:153|容器片段|
|jifen/Features/Groups/GroupPreviewReportView.swift|GroupPreviewReportView:3, GroupExistingUploadResultView:43|静态索引|
|jifen/Features/Groups/GroupPushViews.swift|GroupPushSettingsView:3, GroupPushDestinationView:51|静态索引|
|jifen/Features/Groups/GroupQRViews.swift|GroupJoinView:7, GroupScannerView:189, GroupShareView:203, GroupQRCode:270|静态索引|
|jifen/Features/Groups/GroupRankingTable.swift|GroupRankingTable:4|静态索引|
|jifen/Features/Groups/GroupRegistrationEditor.swift|GroupRegistrationEditor:33|静态索引|
|jifen/Features/Groups/GroupResultScoreControls.swift|GroupResultScoreControls:3, GroupResultNumericField:85, GroupRuleChoices:110|静态索引|
|jifen/Features/Groups/GroupScheduleEditor.swift|GroupActivityLineupEditor:3, GroupScheduleEditor:8|静态索引|
|jifen/Features/Groups/GroupSupportViews.swift|GroupMemberSelector:3, GroupSeatPicker:26, GroupRosterAddButton:49, GroupRulesEditor:68, GroupSetDetailsEditor:103, GroupNoticeInbox:122, GroupNoticeDestinationView:230, GroupReminderDestinationView:330, GroupUploadRepairView:357|静态索引|
|jifen/Features/Groups/GroupTrainingNoticesView.swift|GroupTrainingNoticesView:16, GroupTrainingNoticeInbox:46, GroupTrainingCancelView:67|静态索引|
|jifen/Features/Groups/GroupTrainingViews.swift|GroupTrainingTab:3, GroupTrainingEditor:246, GroupLeaveView:252, GroupReportView:274|静态索引|
|jifen/Features/Groups/GroupViews.swift|GroupListView:4, GroupArchivedListView:173, GroupBetaSportTags:198, GroupAccountBoundary:244, GroupAdaptiveOrientation:255, GroupNotice:281, GroupCreateView:286, GroupCreatedView:332, GroupResultLink:341, GroupResultSummary:352, GroupResultDetailView:414, GroupMemberResultsView:553|容器片段|
|jifen/Features/Home/Components/BentoCardView.swift|BentoCardView:3|静态索引|
|jifen/Features/Home/Components/CenteredSetupDialogContainer.swift|AdaptiveSetupDialogScrollView:30, AdaptiveSetupDialogLayout:72, CenteredSetupDialogContainer:146, CenteredSetupDialogPresenter:183|容器片段|
|jifen/Features/Home/Components/CommonDataManagementShared.swift|ConditionalSystemSearchModifier:10, CommonDataCategoryChip:41, CommonDataFloatingAddButton:64, CommonDataBatchEditBar:88, CommonDataListCardBackground:130|容器片段|
|jifen/Features/Home/Components/CommonDataSectionView.swift|CommonDataSectionView:3|静态索引|
|jifen/Features/Home/Components/HomeHeaderView.swift|HomeHeaderView:3, HomeSharingActiveHeaderView:96|容器片段|
|jifen/Features/Home/Components/MultiScoreSetupDialogView.swift|MultiScoreSetupDialogView:5|静态索引|
|jifen/Features/Home/Components/NewGameDialogView.swift|NewGameDialogView:19|静态索引|
|jifen/Features/Home/Components/NineBallSetupDialogView.swift|NineBallSetupDialogView:7|静态索引|
|jifen/Features/Home/Components/ProToolsSectionView.swift|ToolItemView:40, ProToolsSectionView:78|容器片段|
|jifen/Features/Home/Components/QuickStartEditView.swift|QuickStartEditView:5|静态索引|
|jifen/Features/Home/Components/QuickStartGridView.swift|QuickStartGridView:3|容器片段|
|jifen/Features/Home/Components/RecentRecordsSectionView.swift|RecentRowView:8, RecentRecordsSectionView:183|静态索引|
|jifen/Features/Home/Components/ShotTrainingSetupDialogView.swift|ShotTrainingSetupDialogView:31|静态索引|
|jifen/Features/Home/Components/SportOptionView.swift|SportOptionView:3|静态索引|
|jifen/Features/Home/Components/SportsSetupCommonNameViews.swift|CommonNameSelectorDialog:7, InlineCommonNameTextField:79|静态索引|
|jifen/Features/Home/Components/SportsSetupDialogView.swift|SportsSetupDialogView:7|静态索引|
|jifen/Features/Home/Components/SportsSetupMatchFeatures.swift|SportsSetupMatchFeaturesSection:63, SportsSetupFeatureCard:253|静态索引|
|jifen/Features/Home/Components/SportsSetupParticipantSection.swift|SportsSetupParticipantSection:4|静态索引|
|jifen/Features/Home/Components/SportsSetupSettingsSection.swift|SportsSetupSettingsSection:4|静态索引|
|jifen/Features/Home/Components/UnfinishedGameBarView.swift|UnfinishedGameBarView:173, UnfinishedGameDiscardToast:273|静态索引|
|jifen/Features/Home/HomeTab.swift|HomeTab:140, HomeFormSheet:1405|容器片段|
|jifen/Features/Home/HomeUtils.swift|尺寸/布局规则|静态索引|
|jifen/Features/MainTabView.swift|MainTabView:4|容器片段|
|jifen/Features/Me/CommonNamesManagementView.swift|CommonNamesManagementView:4|容器片段|
|jifen/Features/Me/CommonPlacesManagementView.swift|CommonPlacesManagementView:4, CommonPlacePickerView:535|容器片段|
|jifen/Features/Me/SettingsView.swift|SettingsView:60, SettingsFormSheet:472, MeTab:520, SettingsRowDivider:533, SettingsSection:541, SettingsNavigationRow:571, MeAccountEntryRow:610, ScoreboardSettingsView:697, ScoreboardToggleSettingRow:830, OfficialBreakHelpContent:865, MeSoundToggleRow:928, FAQView:966, AboutUsView:1028, ToggleRow:1173, InfoRow:1197|容器片段|
|jifen/Features/Membership/MembershipView.swift|MembershipView:34, MembershipOfferCodeRedemptionPresenter:855, MembershipAgreementWebPage:907|容器片段|
|jifen/Features/Membership/NationalDayMembershipSheet.swift|NationalDayMembershipSheet:19, LifetimeTicket:353, CampaignArtwork:465, CampaignArtworkCanvas:478, CampaignSparkles:570, CampaignScoreboard:666|静态索引|
|jifen/Features/Records/RecordNotesCard.swift|RecordNotesSectionView:35, RecordNoteSheet:221, TextNoteEntryView:658, VoiceNoteEntryView:699|静态索引|
|jifen/Features/Records/RecordsTab.swift|RecordsTab:13|容器片段|
|jifen/Features/Records/ScoreboardRecordDetailPage.swift|ScoreboardRecordDetailPage:6, ScoreTrendChart:1106, RecordDetailShareCardView:1159, MarketingTrendScreenshotFixtureView:1299|容器片段|
|jifen/Features/Records/ScoreboardRecordTrendBuilder.swift|尺寸/布局规则|静态索引|
|jifen/Features/Schedule/BookingDetailPage.swift|BookingDetailPage:3|容器片段|
|jifen/Features/Schedule/CreateBookingPage.swift|CreateBookingPage:26|容器片段|
|jifen/Features/Schedule/SchedulePage.swift|SchedulePage:3|容器片段|
|jifen/Features/Scoreboard/Cards/Doudizhu/DoudizhuScoreboardView.swift|DoudizhuScoreboardView:40|静态索引|
|jifen/Features/Scoreboard/Cards/Guandan/GuandanScoreboardView.swift|GuandanScoreboardView:358|静态索引|
|jifen/Features/Scoreboard/Cards/Shengji/ShengjiScoreboardView.swift|ShengjiScoreboardView:42|静态索引|
|jifen/Features/Scoreboard/MultiScore/MultiScoreboardView.swift|MultiScoreboardView:55|静态索引|
|jifen/Features/Scoreboard/ScoreboardTab.swift|ScoreboardTab:11, SportCardView:236|容器片段|
|jifen/Features/Scoreboard/Shared/GameOverDialog.swift|TwoSideScoreResultRow:13, GameOverDialog:144|容器片段|
|jifen/Features/Scoreboard/Shared/MenuDialog.swift|MenuDialog:238|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreCustomAdjustPanel.swift|ScoreCustomAdjustPanel:4|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreboardAppearance.swift|ScoreboardDisplaySettingsView:1662, OfficialBreakOverlay:1936, ImmersiveCornerRevealZones:2134|静态索引|
|jifen/Features/Scoreboard/Shared/ScoreboardConstants.swift|ScoreboardBackButtonAccessibility:44, ScoreboardMenuVoiceStatus:59|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreboardKeyPointBadge.swift|ScoreboardKeyPointBadge:25, ScoreboardKeyPointBadgeLayer:43|静态索引|
|jifen/Features/Scoreboard/Shared/ScoreboardLaunchView.swift|ScoreboardMatchTimeDisplay:125, IPadForcedLandscapeSurface:145, ScoreboardLaunchView:166|静态索引|
|jifen/Features/Scoreboard/Shared/ScoreboardLayoutMetrics.swift|尺寸/布局规则|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreboardStyleEditOverlay.swift|ScoreboardStyleElementSelectableModifier:80, ScoreboardStyleEditOverlayView:203, CircularColorPickerPage:1429, ColorPickerPanel:1534|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreboardStyleEditorEntry.swift|ScoreboardStyleEditorEntryModifier:65|静态索引|
|jifen/Features/Scoreboard/Shared/ScoreboardTemplate.swift|ScoreboardNameEditorField:15, ScoreboardTemplate:111, ScoreboardOrientationLockModifier:1076, TeamSection:1116, TwoFingerSwipeDownView:1519, ToastView:1582|容器片段|
|jifen/Features/Scoreboard/Shared/ScoreboardUsageHint.swift|ScoreboardUsageHintDialog:310|静态索引|
|jifen/Features/Scoreboard/Shared/ScreenshotSaveCoordinator.swift|ScreenshotSaveOverlay:422|静态索引|
|jifen/Features/Scoreboard/Shared/ServeTriangleIndicator.swift|ServeTriangleIndicator:78, CenterLineServeIndicator:91|静态索引|
|jifen/Features/Scoreboard/Shared/TwoSideScoreboardScaffold.swift|TwoSideScoreboardScaffold:12|容器片段|
|jifen/Features/Scoreboard/SimpleScore/SimpleScoreboardView.swift|SimpleScoreboardView:11|静态索引|
|jifen/Features/Scoreboard/Sports/Archery/ArcheryScoreboardView.swift|ArcheryScoreboardView:25, ArcheryMiddleLayer:1187|静态索引|
|jifen/Features/Scoreboard/Sports/Badminton/BadmintonScoreboardView.swift|BadmintonScoreboardView:4|静态索引|
|jifen/Features/Scoreboard/Sports/Basketball/BasketballScoreboardView.swift|BasketballScoreboardView:5, BasketballEditTeamPanel:747, BasketballTeamPanel:882, BasketballCenterPanel:1160|静态索引|
|jifen/Features/Scoreboard/Sports/Basketball/ShotTrainingScoreboardView.swift|ShotTrainingScoreboardView:89|静态索引|
|jifen/Features/Scoreboard/Sports/Billiards/BilliardsScoreboardView.swift|BilliardsScoreboardView:22|静态索引|
|jifen/Features/Scoreboard/Sports/Billiards/EightBallScoreboardView.swift|EightBallScoreboardView:8|静态索引|
|jifen/Features/Scoreboard/Sports/Billiards/NineBallChaseScoreboardView.swift|NineBallChaseScoreboardView:35|静态索引|
|jifen/Features/Scoreboard/Sports/Billiards/SnookerScoreboardView.swift|SnookerScoreboardView:17|静态索引|
|jifen/Features/Scoreboard/Sports/Boxing/BoxingScoreboardView.swift|BoxingScoreboardView:11, BoxingRoundDialog:317|静态索引|
|jifen/Features/Scoreboard/Sports/Foosball/FoosballScoreboardView.swift|FoosballScoreboardView:5|静态索引|
|jifen/Features/Scoreboard/Sports/Football/FootballScoreboardView.swift|FootballScoreboardView:13|静态索引|
|jifen/Features/Scoreboard/Sports/Pickleball/PickleballScoreboardView.swift|PickleballScoreboardView:4|静态索引|
|jifen/Features/Scoreboard/Sports/PingPong/PingPongScoreboardView.swift|PingPongScoreboardView:4|静态索引|
|jifen/Features/Scoreboard/Sports/Rally/RallyScoreboardView.swift|TableTennisAdministrativeCards:104, BadmintonMisconductCards:138, TeamCourtScoreboardPanel:182, TableTennisPauseDialog:253, RallyScoreboardView:345|静态索引|
|jifen/Features/Scoreboard/Sports/Rally/TableTennisCardsDialog.swift|TableTennisCardsDialog:4|静态索引|
|jifen/Features/Scoreboard/Sports/Tennis/TennisScoreboardView.swift|TennisTieBreakIndicator:28, TennisScoreboardView:46|静态索引|
|jifen/Features/Scoreboard/Sports/Volleyball/VolleyballScoreboardView.swift|VolleyballScoreboardView:4|静态索引|
|jifen/Features/Scoreboard/UsageHintAnimation/HintAnimationPlayerView.swift|RallyMiniScoreboard:6, HintAnimationPlayerView:82|静态索引|
|jifen/Features/Scoreboard/UsageHintAnimation/ScoreboardUsageHintAnimatedDialog.swift|ScoreboardUsageHintAnimatedDialog:9|静态索引|
|jifen/Features/Shared/AppCatalogIcon.swift|AppCatalogIcon:52|静态索引|
|jifen/Features/Shared/InAppWebLink.swift|InAppWebLinksHostModifier:76, InAppWebLinkDestinationModifier:86, WebLinkDestinationBinding:100, InAppWebLinkPage:126, AppWebView:144, WebContainer:233|静态索引|
|jifen/Features/Timer/CubeTimerView.swift|CubeTimerView:15|静态索引|
|jifen/Features/Timer/DualPlayerTimerView.swift|DualPlayerTimerView:31|静态索引|
|jifen/Features/Timer/DualTimerSetupView.swift|DualTimerSetupView:10|容器片段|
|jifen/Features/Timer/TimeoutCountdownView.swift|TimeoutCountdownView:36|静态索引|
|jifen/Features/Timer/TimerTab.swift|TimerTab:10|容器片段|
|jifen/Features/Tools/AACalculatorView.swift|AACalculatorView:33|容器片段|
|jifen/Features/Tools/CoinWebEngine.swift|CoinWebView:143|静态索引|
|jifen/Features/Tools/DateTimeToolView.swift|DateTimeToolView:10, FlipClockFace:128, FlipDigitView:212, FlipDigitHalf:394|静态索引|
|jifen/Features/Tools/DiceToolView.swift|DiceToolView:11, DiceWebView:182|静态索引|
|jifen/Features/Tools/FlipCoinView.swift|FlipCoinView:11|静态索引|
|jifen/Features/Tools/FullscreenBarrageView.swift|FullscreenBarrageView:35|容器片段|
|jifen/Features/Tools/PointsTable/PointsTableView.swift|PointsTableView:11, PointsTableDetailView:151|容器片段|
|jifen/Features/Tools/RandomTeamView.swift|RandomTeamView:38, RandomTeamMultiTouchLayer:385, MultiTouchCaptureUIView:407|容器片段|
|jifen/Features/Tools/RedYellowCardView.swift|RedYellowCardView:10|静态索引|
|jifen/Features/Tools/StopwatchView.swift|StopwatchView:17|静态索引|
|jifen/Features/Tools/TenSecondChallengeView.swift|TenSecondChallengeView:19|静态索引|
|jifen/Features/Tools/ToolsTab.swift|ToolsTab:3, ToolsListPageView:22, ToolSectionView:69, ToolCardView:100|容器片段|
|jifen/Features/Tools/WhistleToolView.swift|WhistleToolView:35|静态索引|
