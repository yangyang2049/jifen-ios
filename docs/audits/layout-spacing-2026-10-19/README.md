# 全能计分器三端全项目边距检查报告

日期：2026-10-19。范围：iOS、Android、HarmonyOS 当前工作区中的产品界面，包括手机、平板、横屏和主仓内的手表模块。

**建议先统一同一页的内容轴线，再调整同类页面的上下节奏。** 三端已有手机左右16、标题内容12、区块24的共同基础，主要差异出在父子容器重复留白、正文与底部操作区采用不同限宽方式，以及普通页和弹窗混用了边距规则。没有必要先改一遍全局尺寸。

本轮仅生成报告与索引，未修改应用代码、配置或资源，未构建、安装或操作设备。全量静态检索与关键容器人工复核已完成；没有进行本轮逐屏截图及运行态像素测量。下面区分了源码可以确定的差异、合理用途差异和待视觉确认的风险。报告中的pt、dp、vp均为各端逻辑单位，不是截图物理像素。

## 阅读入口与覆盖范围

|材料|内容|
|---|---|
|本总报告|跨端结论、12组排版建议、逐模块覆盖和待决定参数|
|[iOS明细](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/ios.md)|15项证据、16类功能矩阵、138个命中文件清单|
|[Android明细](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/android.md)|16项证据、模块矩阵、手机及OPPO腕端附录|
|[HarmonyOS明细](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/hos.md)|15项证据、entry与wearable分类、宽窗与安全区分析|
|[可筛选的源码索引](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/source-index.html)|按平台、文件和表达式搜索padding、margin、间距、限宽与安全区；不代表逐屏视觉通过|

|端|工作区基线|全量检索与深度复核|
|---|---|---|
|iOS|jifen-ios，3.3，HEAD 66c2cc55|应用247个Swift全量检索；138个UI/布局命中文件；43个关键容器文件人工复核。Packages另检索，无直接产品页面UI。|
|Android|jifen-android主仓，3.3，HEAD 385fcb75|5模块1390个Kotlin/XML/运行时HTML文件检索；270个生产UI相关文件，其中手机228、腕端42；63个关键文件人工复核。另列56个测试/debug辅助文件。|
|HarmonyOS|jifen-hos，3.3，HEAD 9a744e4e|entry与wearable共379个ETS全量检索；326个产品UI源和1个测试harness；42个关键容器文件、7个TS布局支撑源人工复核。|

三个仓库都有本轮之前的未提交修改，本报告以保存的工作区源码为准，不能等同于已发布版本。组件声明数、表达式条数均不当作页面数量或问题数量。具体复核级别见各端JSON清单。

范围包含首页、计分与计时、记录、工具、我的、账号会员、常用数据、预约、小组所有页面族、反馈、法务、扫码、设置与样式、同步投屏、观众显示、通用弹窗及内嵌骰子/硬币网页。独立的小程序、网站、后端，以及另外仓库里的手表产品，不纳入三端手机边距统一。

## 一 原始小组问题的当前状态

|检查项|iOS|Android|HarmonyOS|结论|
|---|---|---|---|---|
|已有组时的创建/加入按钮|首页只显示条目卡片|有组分支只显示卡片；双按钮在空态内|有组分支只显示卡片；双按钮在空态内|当前源码已经同步，不作为待改项；小组管理列表的创建/加入入口另有用途。|
|标题行与卡片间距|44高操作区，显式下间距0|44高操作区，显式下间距0|窄屏44高操作区，下间距0；宽屏与球局均36高、下间距12|当前已去掉旧的重复留白。不能把显式0理解为文字贴卡片，也不能再按旧实现报错。|
|对照“我的球局”|普通文字标题行，下间距12|约24文字行，下间距12|普通文字标题行，下间距12|应比较文字底部与卡片上缘，而不是比较Row边界。|

标题文字行高若为H，44高且居中布局后，文字行到底部卡片的留白约为`(44−H)/2 + 显式下间距`。例如H为22时是11，已经接近普通标题后的12；这只是布局框计算示例，字形墨迹仍需截图确认。建议保留现有点击区域，先确认同屏视觉，不再盲加12。

证据：[iOS小组区块](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/HomeTab.swift:1123)、[Android小组区块](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/group/home/HomeGroupSection.kt:239)、[鸿蒙小组区块](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/home/components/HomeGroupSection.ets:183)。

## 二 建议采用的排版参照

这是供排版选择的建议值，尚未实施。优先按角色对齐，跨端不能照搬同名的md、lg：iOS和鸿蒙的md为16，Android的md为12。

|角色|现有基础|建议|
|---|---|---|
|手机普通页面外边距|三端通常左右16|保留16；筛选、列表、底部操作的内容外缘共享这一轴线。|
|普通卡片内边距|多处16，首页和密集行有12|保留普通16、紧凑12两档；不把所有卡片强制同一密度。|
|区块之间|三端已有24|以24为同级区块参照；隐藏区块后仍只保留一份24。|
|标题到内容|语义token为12，但标题行内部留白不同|视觉目标约12；有44/48操作区时把行内留白一起计算。|
|同组卡片/控件|卡片12、控件组16较常见|列表卡片12、独立控件组16作为默认，内部说明文字4/6/8允许保留。|
|筛选栏到首卡|Android同类页面存在16/24/28|建议普通筛选列表16；较独立的内容分区可24，由一层负责。|
|普通页尾呼吸量|iOS常24，Android常16，鸿蒙部分80/96|先清理没有覆盖物依据的大额占位；若要三端统一，普通滚动页尾可选24，系统安全区另算。|
|固定/悬浮操作区|有真实高度和动态状态|正文避让量按实际操作栏高度加间隙，不能把所有80/100/154都当成多余边距。|
|宽屏正文|iOS常600/760/920，Android常560/600/680/840，鸿蒙常560/600/680/700|保留用途档位，先统一同一页的正文、筛选和操作区；不要全项目都改成一个maxWidth。|
|导航栏和背景|系统/平台各有实现|导航栏维持全窗口；仅内部内容、底部操作内容居中限宽。|

参照：[iOS Theme](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Core/Theme/Theme.swift:187)、[Android DesignSystem](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/theme/DesignSystem.kt:14)、[HarmonyOS DesignTokens](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/common/DesignTokens.ts:213)。

## 三 优先排版项目

### R01 iOS快速开始仍比同页小组多叠一份12

**源码确定，建议优先调整。** 编辑按钮将标题行撑到44，标题行下又加12；小组当前是44加0。同样的标题文字框高H时，两者分别为`(44−H)/2+12`与`(44−H)/2`。

建议把快速开始纳入同一套标题视觉间距规则，保留44点击区域；同时确认标题上方的留白，避免只压缩底部后基线失衡。[证据](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/QuickStartGridView.swift:29)；iOS明细IOS-01。

### R02 三端会员正文和购买区的内容轴不一致

**源码确定，建议三端成组决定。**

|端|当前差异|影响|
|---|---|---|
|iOS|手机正文左右16、购买区24；iPad“我的”与会员虽共用760 token，padding位于限宽的不同层|手机购买按钮每侧内缩8；足够宽时我的卡片760、会员卡片712，导航后每侧再缩24。|
|Android|同一600柱内，正文左右16/64，购买区固定24|手机每侧内缩8；平板反而向外40。600柱中正文472、按钮552。|
|HarmonyOS|宽窗正文700限宽在内部，响应式padding在外；购买区700含左右padding|假定响应式边距64、窗口可用宽至少828、无额外父限制时，正文700、按钮572，每侧内缩64。手机不应照此推断。|

建议采用“正文和购买内容共用一个居中容器、同一外边距”。如果希望购买按钮额外内缩8，应明确为各端共同的CTA角色，而不能手机内缩、平板外扩。还应先定清楚maxWidth包含的是内容还是含padding的外框。滚动正文为底部购买栏预留的空间保留，协议换行与未登录提示一起验收。

证据：[iOS正文](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Membership/MembershipView.swift:71)、[iOS购买区](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Membership/MembershipView.swift:654)、[Android正文](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/me/membership/AccountMembershipScreens.kt:529)、[Android购买区](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/me/membership/AccountMembershipScreens.kt:1204)、[鸿蒙正文](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/me/VipPage.ets:1488)、[鸿蒙购买区](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/me/VipPage.ets:1584)。明细IOS-04/06、A03、H05。

### R03 常用名称和地点的编辑批量条需要跟随正文

**源码确定，优先处理宽屏。** iOS正文限760，批量条位于其外、全窗展开；鸿蒙正文及添加栏限600，批量条也在其外、全窗展开；Android批量条已经在600柱内，但正文平板边距64，条内默认16，操作外缘相差48。

建议背景可铺满原有区域，实际按钮和文字区跟随该页正文的最大宽度与外边距。普通添加栏和编辑批量栏切换时，不应改变操作内容轴。按钮文案还要不要贴齐卡内文字，是下一层选择，不能混成同一个“左边距”。

证据：[iOS名称页](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Me/CommonNamesManagementView.swift:77)、[iOS地点页](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Me/CommonPlacesManagementView.swift:61)、[Android名称页](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/me/CommonNamesScreen.kt:303)、[Android共享条](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/components/SharedComponents.kt:134)、[鸿蒙名称页](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/me/SavedNamesPage.ets:742)、[鸿蒙地点页](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/me/SavedPlacesPage.ets:459)。明细IOS-03、A02、H02/03。

### R04 预约页同时存在水平轴与筛选下方距离的差异

**源码确定，普通态与编辑态要分开。**

|端|水平|垂直/编辑状态|
|---|---|---|
|iOS|列表行左右16，顶部筛选与底CTA左右24，外缘差8|List系统默认行为仍需运行态确认；不能把卡片内14也算作外边距。|
|Android|筛选、列表、CTA共同max560及左右16/64，同轴|筛选bottom12加列表top16，首卡前共28；记录同类16、常用名称24。|
|HarmonyOS|普通筛选、列表、新建CTA共同max680，左右16，同轴|编辑工具栏脱离680容器，变为全宽加左右16。|

建议iOS先统一筛选和卡片外缘到16，CTA是否保留独立24由用户选择；鸿蒙只收拢编辑工具栏的内部内容；Android筛选至首卡建议在16和24中选一档。三端都应同时检查普通态、编辑态和空态。

证据：[iOS列表](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Schedule/SchedulePage.swift:55)、[iOS底栏](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Schedule/SchedulePage.swift:126)、[Android筛选](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/schedule/ScheduleScreen.kt:148)、[Android列表](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/schedule/ScheduleScreen.kt:224)、[鸿蒙编辑栏](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/schedule/SchedulePage.ets:628)。明细IOS-05、A06、H04。

### R05 iOS投屏页顶部切换栏没有跟随正文限宽

**源码确定，主要影响完整宽屏页面。** iOS顶部Picker仅左右16/24，正文则限760且含内部padding。以iPad可用宽1024、左右24为例，Picker宽976，正文卡片宽712，两侧外缘相差132。窄form sheet里差异可能不明显。Android整个切换与正文共同限600，鸿蒙共同限560，已经同轴。

建议iOS让切换栏和两种正文共用现有760内容容器；保留三端各自的内容宽度档位。[iOS证据](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Display/CastConnectionView.swift:25)、[Android对照](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/display/connection/DisplayConnectionScreen.kt:110)、[鸿蒙对照](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/display/DisplayConnectionPage.ets:190)。明细IOS-02、A10、H06。

### R06 Android关闭小组功能后仍留出两份区块间距

**宽屏源码确定；窄屏待确认。** 首页外层在小组前后无条件放置24，小组内部在服务关闭时直接返回，因此宽屏的常用数据到球局之间变成24加24等于48。窄屏保留的空Lazy item也有类似风险，但本轮没有测量其最终布局。

建议隐藏整个外层小组item及其对应间距，前后正常区块只保留24。无组、未登录或加载失败仍有空态内容，不能一并隐藏。[外层证据](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/home/HomeTabContent.kt:153)、[内部返回](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/group/home/HomeGroupSection.kt:233)。明细A16。

### R07 普通页尾需要区分呼吸留白与覆盖物避让

**大额预算确定，是否压缩按页面决定。** Android计时记录详情无该页底部覆盖CTA，却无条件尾Spacer96再加L2底16，合计112；没有actions时前一份16仍在，总计128。鸿蒙主Tab壳已避让系统栏，计分/计时内部底80、记录底96，与首页24、我的20并不属于同一呼吸量。

建议Android计时详情先以16或24作为页尾候选；鸿蒙普通Tab先看最后一行滚到底的截图，再判断80/96中哪些有状态依据。计时记录的导出图构图也需核对。

应保留的例子：iOS首页有未结束浮条时尾部24加76等于100；Android首页有浮条时80预算、会员未开通时154加系统inset；鸿蒙首页有浮层另加80。这些已有覆盖区原因，不应一律削减为24。

证据：[Android计时详情](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/records/TimerDetailScreen.kt:152)、[鸿蒙计分Tab](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/scoreboard/ScoreTab.ets:629)、[鸿蒙记录Tab](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/records/RecordsTab.ets:1326)、[iOS浮条预算](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/HomeTab.swift:238)。明细A04/11、H07、IOS-14。

### R08 Android宽屏页面弹窗继承了普通平板的64边距

**源码确定，属于容器角色选择。** 最大宽560的页面Dialog，标题行左右16；内部常用数据、设置等仍按平板取正文左右64，比标题外行每侧再缩48。与登录Dialog主动去掉重复水平层、任务Dialog正文16的做法不同。

建议将页面Dialog正文单独定为16或24，不改变独立平板页面64。正文变宽后，输入、错误提示和键盘状态的高度也会变化。[弹窗外壳](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/components/WideScreenPageDialog.kt:193)、[登录对照](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/me/AccountLayoutSupport.kt:29)。明细A09/10。

### R09 目录页标题间距和宽屏列数需要统一设计口径

**源码规则确定，密度优劣需视觉选择。** iOS计分/计时/工具标题内容12、区块24、网格12，规则成组一致。Android标题在网格中，标题bottom2再加grid gap8/12，实际标题到卡片为手机10、平板14；首标题上方16加8等于24。不能只比较token12。

密度上，iOS iPad固定4列，320宽小窗按左右24和格间12估算单格约59，尚未据此判定裁切；Android平板计分/计时也固定4列，600宽按左右64和格间12估算单格109，卡片已有紧凑适配。鸿蒙计分/计时限680且最多4列，工具可达8列并没有同一总限宽。

建议先定“目录标题视觉间距12”，再单独决定平板是否根据实际可用内容宽度切换2/3/4列，以及鸿蒙工具是否保留密集面板。不要为了4列或8列去全局改左右边距。明细IOS-09/15、A07/08、H13；证据：[iOS目录](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Scoreboard/ScoreboardTab.swift:119)、[Android布局规则](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/helpers/DeviceLayout.kt:261)、[鸿蒙工具目录](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/pages/tools/ToolsPage.ets:131)。

### R10 空态上下锚点有混合规则

**布局组合确定，视觉需要同条件截图。** Android记录空态在剩余区域上加120，再将内容居中，中心约由H/2变为H/2加60；不是单纯距顶120。积分表等空态直接在可用区域居中。

建议先区分“主列表空态”“筛选无结果”“操作失败”三类，再为同类选择可用区居中或距内容顶固定值。不能既用固定上边距又把它解释成自然居中。需要包含有无筛选与底部CTA两种状态。[记录空态](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/records/RecordsTabScreen.kt:493)、[共享空态](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/ui/components/SharedComponents.kt:64)。明细A13。

### R11 安全区责任不同，不能靠统一底部数值解决

**源码存在不同责任路径，尚未复现遮挡或重复像素。** Android普通导航宿主加Scaffold innerPadding，部分子页再加navigationBarsPadding，实际是否重复取决于中间层消费；鸿蒙预约详情、全家桶扩展到底部却只留固定24，新推送页也有底部责任和长文滚动需确认。iOS部分Form/List为系统内边距，全屏板又有独立刘海与旋转映射。

建议后续将每条路由的系统避让交给明确的一层；设计留白与系统inset分别计账。普通页面、Dialog和沉浸计分板分别检查，不能删除所有安全区处理。本项属于后续设备验证清单，不列为已经实测的遮挡问题。明细A05、H08/09/10、IOS-12。

### R12 短窗口弹窗的最小高度与外侧保护需要验证

**约束关系确定，实际裁切待验证。** iOS开赛弹窗可用高度仍至少280；鸿蒙多个宽屏页面Dialog最小高500/520，同时最大高86%/88%，短窗可能出现最小值大于最大值。Android样式传播提示限宽340/400但没有明确外侧水平保护，窄窗口可能贴边。

建议按实际窗口可用高度限定上限，短窗允许降低最小高度、正文滚动，固定标题和操作区可达；非全屏弹层保留至少16或24的窗外留白。不要把弹窗内部16/18/20/24的不同用途一并抹平。明细IOS-10、H11/12、A15；证据：[iOS居中弹窗](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/CenteredSetupDialogContainer.swift:146)、[鸿蒙页面Dialog](/Users/yangyang/Desktop/jifenqi/jifen-hos/entry/src/main/ets/components/WideScreenPageDialogs.ets:14)、[Android样式提示](/Users/yangyang/Desktop/jifenqi/jifen-android/app/src/main/java/com/douhua/jifen/screen/score/style/ScoreboardStyleEditOverlay.kt:519)。

## 四 全功能对照结论

“已索引”表示该功能族的源文件已纳入静态清单；并不表示每个状态都完成截图验收。每个具体源文件的行号和人工复核标记见三端附录及JSON。

|功能族|三端对照结果与建议|
|---|---|
|首页全部区块|手机主内容轴16、区块24是共同基础；有组按钮已同步。重点R01/R06，浮条避让保留。|
|计分目录|基础节奏成组，Android标题实际10/14与iOS12有差异；列数按可用内容宽决定，见R09。|
|全部运动/棋牌计分板|涵盖双边、双打、多人、篮球/3x3/投篮训练、足球、球拍及排球族、台球、射箭、拳击、斗地主/掼蛋/升级/UNO等。共享模板与各专用surface已索引；按同项目、同方向比较姓名/比分/计时轴，保留全屏独立边缘规则。|
|开赛设置/样式编辑/结束/调分|已索引各项目设置、姓名选择、操作菜单、显示设置、配色、帮助与结束弹窗；内部密度有用途区分，短窗和外侧保护见R12。|
|记录列表/筛选/批量|已索引全部/计分/计时、搜索和筛选、批量状态；筛选到首卡和空态锚点参照R04/R10，鸿蒙页尾参照R07。|
|记录详情/复盘/笔记/导出|iOS比分详情720与计时600、Android详情680、鸿蒙各记录模板按用途限宽；图表与普通详情可分档。优先检查Android计时尾留白，保留导出构图差异。|
|计时器|计时目录、棋类双人时钟、倒计时、暂停、魔方等已索引；全屏控制和普通目录分开。棋类设置由系统sheet限宽的情况不直接判成无maxWidth缺陷。|
|全部工具及内嵌网页|目录、AA、随机分组、积分表、秒表、骰子、硬币、口哨、10秒、红黄牌、时间显示、弹幕等已索引；全屏工具与阅读工具分档。骰子百分比margin是点位绘图，不能当成页面边距批量替换。|
|我的/偏好/设置/FAQ/关于|“我的”到深层页现有不同宽度档位：iOS760语义层级不同，Android680到600；由用户决定是否同轴，避免修改全局token连带其它页面。|
|账号/资料/登录/注销/扫码|登录宽度与普通阅读页不同属合理用途；iOS375、Android账号及Dialog、鸿蒙登录档位分别保留。二维码相机按视口布局，系统授权/相册/网页不冒充已量化自定义边距。|
|会员/购买/恢复/兑换/活动|三端同页轴线优先按R02处理；长协议、未登录、已开通和购买反馈影响底部栏高度。|
|常用名称/地点|列表、分类搜索、新增编辑、导入、多选已索引；批量条与正文共同限宽是R03的主要建议。|
|本地预约|列表、筛选、空态、编辑、创建/修改/复制、详情/开始/取消已索引；普通与编辑操作栏分别对照R04/R11。|
|小组全部页面族|列表/归档/创建/加入/扫码/分享、概览/活动/成员/排名/记录、管理、报名排阵、训练、请假、录分/审核/修复、通知/推送及弹窗已索引。iOS详情外20内16、Android常外16内12、鸿蒙常外16内16属于子系统密度选择，尚不能直接判错；可在统一普通16之后单独决定。|
|投屏/同步/观众/外接显示|连接页看R05，显示舞台按缩放和有效画幅布局；不能用普通页16覆盖投影surface的动态尺寸。|
|反馈/法务/首启/公共弹层|反馈列表/详情/创建/回复/举报、协议、首启及共享确认/提示已索引；保持系统与自定义边界，弹层窗外留白和正文留白分别比较。|
|主仓手表模块|Android wear-oppo 42个生产UI源，鸿蒙wearable 57个UI源单列。圆屏/方屏、滚动首尾与表冠操作单独验收，不套用手机16/24/64体系。|

## 五 供你决定的排版顺序

|顺序|可直接讨论的决定|建议选择|
|---|---|---|
|1|同一页正文、筛选、底部购买/批量操作是否共轴|共轴；背景可全宽，内部内容共用同一容器。先处理R02/03/04/05。|
|2|标题视觉间距|约12；包含44/48行内空白，先处理R01，保留当前小组补偿方式。|
|3|筛选到首张卡片|普通列表16；需要明确分区时24；每页只让一层负责。|
|4|普通滚动页尾|24作为三端统一候选；现有16也可作为平台档保留，先处理无覆盖依据的112/128和80/96。|
|5|宽屏最大宽度是否包含padding|建议角色名统一表示同一种几何含义；同一页面族先一致，再决定是否跨端同数值。|
|6|宽屏页面Dialog正文左右|16或24独立成角色；普通平板64保留，不随Dialog一起改。|
|7|小组与普通页的密度|普通页外16、普通卡内16、紧凑12；小组外20及卡内12/16单列决定，避免一次全局替换。|
|8|目录列数与工具密度|按实际可用宽度选择列数；鸿蒙工具8列是否保留，单独决定。|

建议先确定1至3，再做一批页面的排版预览。页尾、系统安全区、短窗约束和目录密度需要结合实际截图；它们的依据与风险已经列在报告中，当前没有据此修改任何页面。

## 六 后续视觉核对组合

|维度|需要对照的状态|
|---|---|
|窗口|窄手机、常规手机、横屏；平板窄窗/分屏、完整宽窗；折叠手机展开前后；手表另组。|
|首页|有组/无组/服务隐藏；有球局/空球局；有/无未结束浮条；快速开始与小组/球局同屏量标题字形到底卡片。|
|列表|正常/搜索/无结果/错误；编辑与非编辑；滚动到首卡和最后一行；长名称。|
|会员|未开通/已开通、已登录/未登录、协议多行、购买提示；正文和购买区同时量左右边界。|
|弹窗|短横窗、软键盘、错误文本、放大字号；标题/正文/关闭/底部动作均可达。|
|系统栏|Android手势/三键/横屏侧栏及键盘；鸿蒙独立路由底部；iOS系统List/Form与安全区。|
|沉浸界面|同运动同方向、样式编辑、姓名/中央计时、暂停与结束；工具返回区；观众与外接显示画幅。|

这份报告的验证为源码检索、父子容器复核、索引与引用校验。未运行原生构建，原因是本轮只生成文档、没有应用代码变动；构建本身也不能证明边距视觉通过。

## 附件

- [iOS逐文件与逐行清单](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/ios-inventory.json)
- [Android逐文件与逐行清单](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/android-inventory.json)
- [HarmonyOS逐文件与逐行清单](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/hos-inventory.json)
- [统一词法索引JSON](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/source-index.json)
- [源码快照与哈希](/Users/yangyang/Desktop/jifenqi/jifen-ios/docs/audits/layout-spacing-2026-10-19/source-snapshot.json)
