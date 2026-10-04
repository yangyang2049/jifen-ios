# iPad 多语言视觉复核（2026-09-30）

已实际检查 22 种语言各 11 张最终构建图，共 242 张有效 iPad 图，22 种语言的本次可见区域全部通过，0 个未闭环问题。ro／vi／id／ms 补修后的 44 张最终图已重新逐页实际查看，原先 5 张问题图均已确认修复。242 个当前原图 SHA-256 全部匹配逐图审核记录。XCTest 的 PASS 仅作为测试执行结果，不作为视觉通过依据。

覆盖语言：ca、pl、ro、cs、sk、sl、hr、da、nb、fi、hu、el、hi、bn、mr、gu、pa、tr、vi、th、id、ms。G6 的 ta／te／kn／ml／or 两设备图由 G5 代理单独负责，不计入本报告。最终截图原图在 `build/localization/deep-review-20260930/final-screenshots`。

每种语言均实际看：首页、运动目录、乒乓球设置、设置底部功能卡片、计时目录、个人页、终身会员、订阅会员、FAQ 长文顶部、FAQ 滚动后续、辅助功能 XXXL 记录详情。联系人页每页最多三张截图，每张 820 像素宽，标注源文件名；关键设置卡片、会员协议和疑似问题另看原分辨率局部。原图为 1668 × 2420 纵向 iPad 模拟器图。

联系人页和局部图在 `ipad-review/final-g345`、`ipad-review/final-retry` 与 `ipad-review/final-closure`。首批 132 张中 11 张旧 da 图因修正文案重拍被替代，有效首批为其余 11 种语言的 121 张；重拍和补齐的 11 种语言为另外 121 张，其中 ro／vi／id／ms 的 44 张再次由补修最终图替代。有效最终覆盖仍为 242 张，不将重拍重复计数。合并逐图记录 `ipad-review/final-visual-review.json` 包含绝对源路径、SHA-256、联系人页、实际查看标记和结论；统计在 `ipad-review/coverage.json`。补修 44 张独立记录为 `ipad-review/final-closure/visual-review.json`，5 张原问题图额外保留旧 SHA、旧问题和原分辨率闭环局部。生成时及审核后均核对 SHA。

## 补修闭环

四种语言的 44 张补拍图全部重新实际查看；以下五个旧问题图已闭环，其他页面无新增问题。

| 语言／页面 | 旧问题 | 最终实际确认 | 证据 |
| --- | --- | --- | --- |
| ro／首页工具 | 随机分队入口省略为 `Împărțire aleatorie în e…` | 实际首页复用 `tool_random_team`，最终显示 `Echipe aleatorii`，两行完整无省略 | `final-screenshots/iPad_ro_01_home.png`；`ipad-review/final-closure/iPad_ro_01_home-closure.png` |
| vi／两张会员页面 | 年费标题末尾被绿色推荐角标覆盖 | `Gói tháng`／`Gói năm` 在明确会员页语境下显示完整，与 `Được đề xuất` 角标分离 | 两张 `iPad_vi_06_membership*.png`；对应 `final-closure/*-closure.png` |
| id／XXXL 记录详情 | 全场分段标签省略为 `Pertandingan P…` | 记录概览首段标签 `Semua` 单行完整，与逐 set 选项区分清楚 | `iPad_id_09_record_detail_accessibility_xxxl.png`；对应 `final-closure/*-closure.png` |
| ms／XXXL 记录详情 | 全场分段标签省略为 `Perlawanan Pe…` | `Semua` 单行完整无省略 | `iPad_ms_09_record_detail_accessibility_xxxl.png`；对应 `final-closure/*-closure.png` |

`Semua` 表示全部范围，适合 recap 全场标签，不限定 set；本次截图直接验证记录概览标签，未声称检查了回放全场标题交互状态。

## 已由最终图确认的修复

ca／pl／ro 两种会员页的协议分隔空格完整，订阅三链接可读，无粘连或覆盖。pl 第三个协议链接自然换行，保持完整。

da 的设置语音播报已显示 `Oplæsning`，03 与 03b 页面完整可读；旧版 `Stemmemeddel`／`else` 断词仅留历史。fi 的两种会员页面前缀已显示 `Olen lukenut ja hyväksyn: `，列举协议链接语法和空间正常。el 的五个顶部页签均展示，首页 `Πρόκληση 10 δευτ.` 两行完整，旧长页签折叠、工具标题省略问题已闭环。

cs／sk／sl／hr／nb／hu／hi／bn／mr／gu／pa 以及 ca／pl／ro／da／fi／el／tr／vi／th／id／ms 的本次 11 个页面可见区域未发现裁字、重叠、意外英文回退或异常换行。南亚文字及泰文设置卡片、订阅协议另以原分辨率局部检查，未见附加符号裁切。长 FAQ 两段内容及滚动后续正常；其余记录页的标题、比分、图例、分段标签、按钮和事件行可读。

## 历史与范围限制

另实际查看 ca／pl／ro 共 33 张 pilot 图，证据保存在 `ipad-review/pilot`；pilot 发现协议粘连及 ro 首页省略，其中协议与 ro 首页均已由最终重拍闭环。旧 da 11 张、fi 冒号修正前 11 张、el 失败时仅 6 张，以及补修前 ro／vi／id／ms 44 张均不计有效最终覆盖；pilot 不能替代最终图。生成脚本 `ipad-review/contact_sheets.py` 仅创建检查用图，不修改原图。

首页历史中的中文选手名来自测试数据，iScoreboard／VIP／AirPlay／Go 和运动名称借词保留，不按英文回退计。系统状态栏中文不属于应用文案。滚动视口边缘的下一条目和滚动后的顶部模糊内容不作为正文裁切；自然多行完整文本不要求无理由缩短。

本报告只证明所给纵向模拟器截图的可见区域；不证明横屏、分屏、所有交互状态或真机均通过。XXXL 覆盖为记录详情测试场景，不代表全部页面大字号检查。视觉代理没有修改源代码、UI 测试、目录或晋级资源。
