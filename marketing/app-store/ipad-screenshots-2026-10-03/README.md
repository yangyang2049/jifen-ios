# iPad App Store 截图，2026-10-03

> 2026-10-04 清理说明：试拍结果、测试结果包、预览拼图和运行日志已清理；当前 `exports/` 定稿、manifest、配置、上传记录、原始恢复素材和采集/上传脚本均保留。下文预览、QA 和旧日志路径属于历史操作记录。

> **最终材料索引（2026-10-04 离线自检）。** [现有 manifest](export-manifest.json) 记录 **49 套、245 张**，包含繁体中文、排除简体中文；[已有上传报告](upload/upload-report.json) 记录 49 套核验通过。该报告仍使用当时的 3.3 名称；同一版本 ID 后续更名为 **3.2.3**，见 [商店草稿状态](../localization-2026-10-02/upload-state.json)。下文 48 套／240 张为早期上传快照；[local-validation.json](local-validation.json) 的 `verified` 仅覆盖该早期 48 套，不能用作全部 49 套或本次代码修改的视觉验收。本次没有在线回读、上传或重拍；3.3（61）截图采集包不会自动包含 2026-10-04 的工作树修复。

本目录保存 48 个语言／地区的 iPad 截图，每套 5 张，共 240 张。

已于北京时间 2026-10-03 01:10 完成上传与完整回读核验：48／48 套、240／240 张的状态、校验值、尺寸、文件大小及顺序通过；其他设备的截图集和中文本地化截图保持不变。

- 应用：全能计分器，App ID `6759768784`，Bundle ID `com.douhua.jifen.ios`。
- 目标：iOS `3.3` 草稿各语言的 `APP_IPAD_PRO_3GEN_129` 截图集。
- 尺寸：横向 `2752 × 2064`，不透明 PNG。
- 顺序：斯诺克、篮球、比赛详情、网球设置、首页，与现有英文 iPad 截图一致。
- 语言范围：与本轮 iPhone 本地化素材相同的 48 个非中文语言／地区。

截图由真实 SwiftUI 页面在专用 iPad Pro 13-inch 模拟器中生成。使用隔离的 3.3 (61) Debug 工程副本与现有截图演示数据；仅在该副本隐藏系统状态栏，以免出现设备原有中文日期。篮球使用各语言的主队／客队称呼，其他姓名沿用当前素材配置。

`exports/<locale>/` 为原始截图，`export-manifest.json` 记录截图顺序、尺寸与 SHA256。`capture-build.json` 记录构建来源，`local-validation.json` 保存本地文件及视觉核验结果，`preview.png` 为英文、日文、阿拉伯语预览，`qa/` 保存全部语言的页面总览。

`upload/plan.json` 为上传计划，`upload/checkpoints/` 为各语言进度，`upload/upload-report.json` 为上传与回读核验结果。英文旧截图保存在 `upload/originals/en-US/`。上传脚本只操作此轮目标语言的 iPad 截图集。
