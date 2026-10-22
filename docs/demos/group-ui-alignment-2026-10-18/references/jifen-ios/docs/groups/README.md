# 小组功能评审包

2026-10-17 未提交变更审查：已逐项复核用户提供的 7 项发现。确认并修复菜单红字、持久请求清理、申请状态白名单、toast 和点击区；名称按 UTF-16 的建议与实际后端契约不符，保留 Unicode scalar 校验并补测试；401 项按当前网络层行为作防御性收紧。见 [逐项证据与验证](group-worktree-review-fixes-2026-10-17.md)。

2026-10-17 独立复查收尾：新增 5 项问题（iOS 4、Android 1）已二次核实并逐项修复，覆盖创建重试、提醒生命周期、旧失败记录的 47 语言显示和账号切换操作锁。iOS 118 项、Android 32 项定向测试通过；鸿蒙对应链路回归通过。见 [修复与验证](group-independent-fixes-2026-10-17.md)，修复前证据保留在 [三端独立复查](group-independent-review-2026-10-17.md)。未做真机完整验收或发布。

2026-10-17：已二次核实并修复三端错误提示覆盖、鸿蒙 720×920 像素海报及 iOS 全部 47 语言的小组文案与共用计数复数。逐语言结果、统计修正、103 项 iOS 小组测试及其他验证边界见 [二次复核与多语言修复](group-recheck-and-localization-2026-10-17.md)。

2026-10-15：用户确认**训练组不加入**，三端仅对齐熟人组范围；已复核旧三端比较并补齐 iOS 录分、规则选项、邀请附文、举报保护及排赛校验。当前事实、剩余差异与验证见 [熟人组三端二次对齐](ios-peer-alignment-2026-10-15.md)。此前训练组纳入建议作为历史记录保留。

2026-10-13：按国内安卓当前工作区源码逐页、逐组件对齐 iOS，原生 UI、底部状态按钮、活动多场、冻结排期、通知与持久上传的对应实现和验证见 [本轮安卓 / iOS 对照表](ios-android-parity-2026-10-13.md)。真实联调及真机关联由用户执行；本轮未提交或部署。

2026-10-06：用户要求继续完成跨端小组改版，已选择性恢复 iOS 小组源码与接入，保留当前工程的其他修改。当前工作区包含熟人组/训练组、四页签改版、二维码、训练排期和举报。恢复与验证记录见 [2026-10-06 续接记录](continuation-2026-10-06.md)。这是开发与验证状态，本轮没有提交或发布 App Store 版本；下面的 2026-10-02 发布范围作为历史记录保留。

2026-10-02：按用户要求，小组暂缓进入 iOS 3.3（61），源码及接入已移出当前发行工程并备份，详见 [本次发布范围](../ios_3_3_release_candidate_2026-10-02.md)。2026-10-01 的 [实现与验收记录](implementation-2026-10-01.md) 和 [自检与联调记录](self-review-and-cross-app-2026-10-01.md) 作为后续开发的历史证据保留；以下是 2026-09-26 的原型评审背景。

- [小组功能 PRD](PRD.md)：产品需求全集，含项目分档与首批范围、逐条功能需求、异常清单、统计口径、上线门槛与验收标准。
- [可交互 HTML demo](../demos/group-system-review.html)：直接用浏览器打开，或通过本地静态服务预览。
- [前后端设计](frontend-backend-design.md)：现有代码依据、数据模型、API、状态机、iOS 接入及跨端边界。
- [旧 demo 审查与验收](demo-review.md)：原型缺口、已补流程、演示边界及验收清单。

## 本轮已确认

首页在**现有约球（“我的球局”）版块前**放一个**横向“我的小组”入口**，点击进入小组列表；先保留现有约球版块，不新增底部标签，也不先做“接下来”聚合改版。该要求覆盖 2026-09-01 旧 PRD 的首页聚合建议。

加入明确保留两种方式：**输入固定纯数字小组号**、**扫描小组二维码**。分享对应“复制小组号”“分享二维码”，两者指向同一个组，不再生成另一套邀请码。查找或识别后统一查看小组、确认加入；创建时只选直接加入或需要审批；创建后组主才可在设置关闭/重新开放加入，已有成员不受影响。首期建议 8 位数字、默认审批，二者为实现建议。

补记比赛以**整场局分**为主（如羽毛球 2:1），“每局比分”可展开选填；有明细时必须与局分一致，缺少小分不补零。

小组简介为首版新增：创建时选填 ≤200 字，组主/管理员可改可清空，展示在概览与加入预览；**不做组公告**，临时通知留在活动详情。

## 项目范围（2026-09-26 更新）

按“比赛结果的形状”分档，不按运动个数排期：A 档（两方 + 局分，必有胜方）承载完整战绩；B 档（篮球/足球等可能平局）战绩降级为日志 + 胜/平/负；C 档（九球追分、斗地主、UNO 等 N 人混战）不提供战绩 tab。

首批项目由“仅羽毛球”扩为**羽毛球、乒乓球、网球、匹克球**（含单/双打）——它们在代码里共用同一批内核与记录模型，边际成本接近零。顶部四页签**不因项目分叉**，定制落在页签内容、局制术语与每局校验，且校验必须由服务端能力目录下发。详见 [PRD §4](PRD.md)。

## 原型阶段分支与范围（2026-09-26）

分支从当前 iOS `main` 的 HEAD `0f6423f6468a4153b8a7e5d6f54f3ff714ae0047` 创建，名称按用户指定为 `group`。创建时工作区已有多语言、页面等未提交修改，切换分支时原样保留；本轮未提交、覆盖或整理这些修改。

本轮新增内容只在 `docs/groups/` 与 `docs/demos/group-system-review.html`。后端仓库仅用于核验现状，未修改其业务代码、schema 或分支。旧安卓 demo 保留作历史参考，新版在 iOS 分支评审。

## 建议评审顺序

1. 首页横向入口 → 小组空状态（功能介绍 + 创建/加入）→ 小组列表 → 小组四页签。
2. 创建、复制小组号/分享二维码、手输或扫码加入/审批、临时成员认领。
3. 约球报名 → 选择对阵 → 完赛 → 待同步/待确认 → 排行榜。
4. 角色切换、离线、归档、移除、所有权转让。
5. 后续轮转/联赛页面与分阶段范围。

建议首期实现羽毛球/乒乓球/网球/匹克球四个 A 档项目的单打与双打基础闭环；这是评审建议，不是已确定的开发排期。轮转、联赛与 B/C 档项目保留技术扩展边界，待原型评审后确定实施范围。
# iOS 3.3 发布范围补充（2026-10-02）

用户要求本次版本以 App Store 多语言本地化为主，暂缓小组及新麻将计分板。iOS 的小组源码、入口、账号联动、记录上传和相关文案已从当前工程移出；本目录继续保存后续开发方案与历史联调证据，不代表本次发布包包含小组。

恢复材料位于 `build/release-20261002/pre-change/changed-source-and-localization.tar.gz` 与 `build/release-20261002/deferred/`。恢复开发时应按具体功能合并源码和资源，保留后续发布修正，不能整体覆盖当前工作区。Android、HarmonyOS、网页及服务端未在本轮回退。


## 小组邀请双域名接入（2026-10-11）

当前开发工作区已接入 `https://jifenqi.com/groups/join?groupNo=…` 和 `https://iscoreboard.live/groups/join?groupNo=…`。两种地址始终都可由同一个 App 接收；生成邀请采用地区优先：中国大陆 `CN` 使用 jifenqi.com，明确其他地区（含港澳台）使用 iscoreboard.live；地区缺失时，App 实际中文语言使用 jifenqi.com，其他语言使用 iscoreboard.live。系统地区来自 `Locale.current.region`，无需定位权限或网络请求，不代表实时所在地。

- iOS 与鸿蒙只接收以上两个域名的 HTTPS 邀请，不注册或兼容旧的自定义 scheme；iOS Associated Domains 同时声明两个域名。
- 加入页预填小组号并加载预览，仍需用户确认加入；二维码保留原 JSON 格式，扫码解析同时接受新邀请链接。
- 两个站点仓库均已添加 `/groups/join` 网页、`public/.well-known/apple-app-site-association` 和 `public/.well-known/applinking.json`。网页提供复制小组号与下载入口。外部点击 HTTPS 邀请由系统决定是否进入 App，网页不使用自定义 scheme 拉起。
- iOS AASA 中的应用标识为 `X9VDZZL3C3.com.douhua.jifen.ios`；鸿蒙应用标识为 `6917582499297883446`，对应已核对的生产签名 app-identifier。

发布前需部署两个站点的静态产物；国内站按网站仓库 `docs/nginx-jifenqi.conf.md` 设置关联文件的 JSON Content-Type，国际站已补 Cloudflare Pages `_headers`。关联文件必须在各自域名下直接 HTTPS 200 返回，不能通过重定向提供。两个域名的接收能力与 App Store Connect 的单个营销/支持网址独立，不需要创建两个 App。

同时核对 Apple App ID / 发布描述文件包含 Associated Domains，以及鸿蒙 AppGallery Connect 的应用链接域名登记与生产签名。App 的代码和网站文件不等于线上关联已经生效；本轮未部署网站或提交商店发布。上线后需在真实设备从消息/外部网页验证两种 HTTPS 地址，包含冷启动、再次唤起、未登录与未安装场景。

验证：iOS 三个 HTTPS 邀请链接单元测试、模拟器使用 XCUIApplication.open 分别注入两个 HTTPS 域名的冷/再次打开加入页 UI 测试通过；该测试验证 App 接收与预填，不证明线上域名关联已生效。两个网站静态构建与手机尺寸邀请页浏览器测试通过。鸿蒙链接解析、协议门禁、并发链接和小组 QR 回归测试通过；入口模块 assembleHap 编译当次被现有 GroupJoinPage / GroupActivityLineupPage 错误阻挡，本轮未修改这些错误位置。

线上只读检查（2026-10-11）：jifenqi.com 的新邀请页和两个关联文件当时返回 404；iscoreboard.live 对当前自动 HTTP 请求返回 Cloudflare 403 / 1010。这不代表普通浏览器或系统验证请求一定失败，但上线时需确认 Apple CDN 与鸿蒙域名验证请求能直接取得关联 JSON，不能仅以本地构建成功作为上线验收。

### 部署清单（HTTPS-only）

无需新增小组业务 API。两个网站需提供域名关联文件（包含隐藏的 `.well-known` 目录）。邀请网页的发布时间单独决定，不应为了关联文件而发布整个未完成工作区：

| 路径 | 用途 |
| --- | --- |
| `/.well-known/apple-app-site-association` | iOS Universal Links 域名关联，无文件扩展名 |
| `/.well-known/applinking.json` | 原生鸿蒙 App Linking 域名关联 |
| `/groups/join?groupNo=72856000` | 邀请页仅保留本地实现，用户于 2026-10-11 明确要求本轮暂不上线 |

国内当前由独立 Python 静态服务返回关联文件，已补无扩展名 AASA 的 JSON 响应类型；国际 Cloudflare Pages 部署包含 `public/_headers`。两个关联文件需 HTTPS 200、JSON Content-Type、无登录/验证码/重定向，不得被防护规则拦截。邀请页以后单独发布时，再将 Next 静态导出的 `groups/join.html` 映射到 `/groups/join`。

Apple 后台：Apple Developer → Certificates, Identifiers & Profiles → Identifiers → `com.douhua.jifen.ios`，确认 Associated Domains 能力已启用。Xcode 的 Signing & Capabilities 中保留 `applinks:jifenqi.com` 与 `applinks:iscoreboard.live`。手动签名需更新包含该能力的 provisioning profile；自动签名由 Xcode 同步能力与描述文件。无需在 App Store Connect 创建第二个 App 或添加第二个营销网址。

鸿蒙后台：AppGallery Connect → 开发与服务 → 全能计分器所在项目 → 增长 → App Linking → 应用链接（较旧界面标注 API≥12 适用）。首次使用先开通服务，为 `com.douhua.jifen` 分别创建关联的网址域名 `jifenqi.com` 和 `iscoreboard.live`，等待后台域名校验成功。使用应用链接的自有域名关联流程；当前邀请直接使用自有 HTTPS URL。后台验证必须能读取已部署的 applinking.json。

顺序：先发布两个网站 → 完成后台配置/域名校验 → 安装新签名测试版本验证两个域名 → 发布包含本次接入的新 App 版本。既有商店旧版本不会因网站上线而自动获得接收能力。真机验证从消息或外部网页点击链接，覆盖冷启动、再次唤起、未登录、未安装和国内/国际两个域名；iOS 在 Safari 的同域网站内点击同域链接可能继续浏览网页，不应当作唯一验收方式。

官方参考：
- [Apple Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- [Huawei 应用链接域名配置](https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-Guides/agc-applinking-app-link-0000001886072257)
- [Huawei 开通 App Linking 服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/applinking-enable-applinking)

### 2026-10-11 Apple 后台能力配置完成

已在用户登录的 Apple Developer 账号（团队 X9VDZZL3C3）中，为 `com.douhua.jifen.ios` 开启并保存 Associated Domains。保存后重新打开 App ID 页面，确认勾选状态为开启，Save 按钮已禁用。Apple 保存提示要求重新生成关联此 App ID 的 provisioning profiles；后续自动签名打包需同步新能力，手动签名需更新描述文件。本次只完成 Apple 后台能力开通；两个具体域名仍由 App entitlements 和各网站 AASA 双向声明。网站部署、线上真机关联验证与 App 发布尚未完成；鸿蒙后台待用户登录后配置。

### 2026-10-11 鸿蒙后台域名登记

用户已登录的新版 HDC 控制台在 `com.douhua.jifen` 的“应用链接”入口提示“暂不支持”。转至旧版 AppGallery Connect → 开发与服务 → 小工具项目（461323198430226984）→ 增长 → App Linking → 应用链接后，可正常配置。已创建两条记录：“全能计分器小组邀请（国内）”对应 `https://jifenqi.com`，“全能计分器小组邀请（国际）”对应 `https://iscoreboard.live`，关联应用 APP ID 为 6917582499297883446。

保存后刷新页面，国内与国际两条记录均显示“失败”；分别查看失败原因，后台都明确提示“下载源JSON文件失败，请确认源文件路径是否正确”。这两条记录仅证明后台登记已完成，不能视为域名关联生效。下一步部署两个站点的 `/.well-known/applinking.json`（包含生产 appIdentifier）与 iOS AASA，并确保验证服务能直接读取。邀请页根据用户后续指示暂不上线。

### 2026-10-11 网站关联文件发布完成

用户最终限定本轮只部署两个域名的 Apple/HarmonyOS 关联 JSON 与所需 JSON 响应类型，保留现有线上首页、SEO、下载页；不发布邀请页、麻将、小组管理及其他未发布改动。国内站从 `rel-20261006-125608` 复制完整线上版本并加入两个 JSON，已切换至 `rel-20261011-applinks-203529`，原有 2516 个文件哈希不变。国际站保存原部署 `6f3c8543.iscoreboard-web.pages.dev` 的 2499 个线上文件并加入关联文件及 `_headers`，已发布为 `e7e9a7bc.iscoreboard-web.pages.dev`；Cloudflare 确认仅上传 2 个新文件，2499 个文件复用。

此前用共享 API 的 WebSocket 总数暂缓发布；用户随后明确 App 连接无需等待。两个网站的网页可以连接 `api.jifenqi.com` 的 WebSocket，但静态网站自身不承载该服务，总连接数无法区分 App/网页或两个站点。此次只重启国内 `jifenqi-web`，未重启 `jifenqi-api`；API 的 PID、启动时间和重启次数前后相同，国际站发布也未改动共享 API。

验证：两个域名的 AASA 与 applinking.json 均直接 HTTPS 200 返回 application/json，无重定向，内容与源文件一致。国内静态服务 GET/HEAD 测试通过；国际站 11 个既有页面/文件与旧部署内容一致。两站邀请页、小组管理及麻将路径仍为 404。此前两个网站生产构建和脚本测试通过，本次发布使用既有线上文件及两份 JSON，未把整站新构建发布上线。

平台复核（20:40 CST）：Apple CDN 已取得国内与国际两个域名的 AASA，均返回 HTTPS 200 / application/json，应用标识正确。鸿蒙后台刷新后仍显示部署前的“下载源JSON文件失败”记录；“查看”和“失败”链接均只打开错误信息，没有观察到重新校验入口。鸿蒙域名关联生效和新签名 App 的真机测试仍待完成。本次未提交或发布 App。

## 官方系统推送

设备绑定、通知偏好与七通道协议遵循 [推送实施主文档](../../../jifen-hos/docs/groups/push-integration-plan-2026-10-18.md)。首期直连 APNs，不增加桌面角标；真实投递默认关闭，按测试名单联调。
