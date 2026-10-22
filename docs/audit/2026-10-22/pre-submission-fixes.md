# 提审复核问题二次确认与修复（2026-10-22）

**3 项问题均经二次确认并修复，最终整批自动验证通过。** 下面保留修复前证据、最终实现和验证范围。

## 逐项结果

| 问题 | 二次确认 | 最终修复 |
| --- | --- | --- |
| UNO 预设值丢失 | 修改前重新执行原生 UI，600 → 1000 → 自定义仍错误显示 500 | 用独立 `unoCustomTargetSelected` 状态决定编辑器显示和写入权限；选择预设先关闭自定义模式，旧编辑回调不能覆盖预设。初始自定义分数仍按保存值恢复。 |
| 白色测试误判 | 修改前颜色测试再次因 sRGB 白色与灰度白色对象不相等而失败 | 用 `getRed` 提取 RGBA 后按 0.0001 容差比较，保留浅/深色白色预期和原有 4.5 对比度断言；产品颜色未改。 |
| 采集哈希来源错误 | 临时 XCTest 产品的端到端脚本测试实际得到默认构建目录的哈希 | 从所选 xctestrun 的 UI target 解析应用、宿主和测试包路径，读取 `CFBundleExecutable` 计算真实文件哈希，并记录调试 dylib、配置路径与配置 SHA256；缺少必需文件直接失败。 |

相关源码：[UNO 设置](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Features/Home/Components/MultiScoreSetupDialogView.swift)、[颜色测试](/Users/yangyang/Desktop/jifenqi/jifen-ios/jifenTests/GroupPortParityTests.swift)、[采集脚本](/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/capture_duo_layout.py)。

UNO 的写入权限使用独立选择状态，不能依赖异步变化的焦点；仅增加焦点检查的中间版本仍未通过测试，其失败日志保留。最终回归除原有的“重新打开仍为 1000”外，还覆盖重新输入 850 后选择 1000、键盘消失、开始按钮可用，并实际开赛检查计分板目标为 1000。

## 自动验证

| 验证 | 结果 |
| --- | --- |
| 最终完整应用单测 | 715 项登记，714 通过、1 个真实 APNs opt-in 探针跳过，零失败 |
| UNO 最终状态定向 UI | 最终实现连续两次通过，包含实际开赛目标 1000 的新增断言 |
| 最终整批 9 项 UI | 9/9 通过；与上方完整应用单测在同一最终构建中执行，xcodebuild exit 0 |
| 采集脚本回归 | 3/3 通过：自定义构建的完整清单、v2 配置忽略禁用项、缺失测试二进制时在访问设备前失败 |
| 采集脚本真实运行 | 使用自定义 DerivedData 的 xctestrun；1 项原生 UI、7 个截图检查点通过；配置与全部 4 个二进制哈希均现场比对一致 |
| Release 真机架构编译 | 独立 DerivedData 从空输出目录构建及最终源码增量编译均成功，零编译错误；36 类告警消息均为既有类别，无新增 |

新增脚本回归位于 [test_capture_duo_layout.py](/Users/yangyang/Desktop/jifenqi/jifen-ios/scripts/test_capture_duo_layout.py)。其临时产品文件真实落盘，设备/Xcode 进程通过模拟接口驱动；另有真实模拟器采集验证，不把模拟进程当作原生执行。

真实采集使用普通 iPhone 模拟器，不能当作折叠屏或真机验收。所选配置位于 Xcode 默认 DerivedData，而旧脚本固定读取的目录位于仓库 `build/duo/DerivedData`，二者明确不同。清单保存绝对产品路径，已有脚本中没有依赖旧相对键格式的消费方。

最终 `git diff --check` 通过；旧的固定哈希目录、UIColor 对象相等断言和由焦点推导自定义选择状态的模式均已移除。原有脏文件哈希核对确认本轮没有额外改写其他文件。可复核的[验证摘要](evidence/pre-submission-fixes-validation.json)和[真实采集清单](evidence/pre-submission-fixed-capture-session.json)一并保存。

工作期间另有外部任务修改了 3 个原本干净的篮球布局/测试文件，本轮未编辑或回退它们。这些修改发生于 22:07–22:09，早于最终编译和测试；最终完整单测中新的 `testBasketballButtonColumnsStaySymmetricWhileNamesRespectTheSafeEdge` 也通过。相关文件哈希另记入验证摘要，避免将外部改动归为本轮修复。

## 证据与范围

- 修复前重新确认：[日志](/tmp/jifen-fix-before-20261022.log)、[结果包](/tmp/jifen-fix-before-20261022.xcresult)。
- UNO 最终状态首次通过：[日志](/tmp/jifen-fix-uno-v2-20261022.log)。
- 最终整批单测/UI：[日志](/tmp/jifen-fix-final-20261022.log)、[结果包](/tmp/jifen-fix-final-20261022.xcresult)。
- 脚本回归：[修复前](/tmp/jifen-fix-capture-before-20261022.log)、[修复后](/tmp/jifen-fix-capture-after-20261022.log)。
- 真实采集：[运行日志](/tmp/jifen-fix-capture-real-20261022.log)、[清单](/tmp/jifen-fix-capture-20261022/ordinary/provenance/session.json)、[哈希复核](/tmp/jifen-fix-capture-audit-20261022.json)。
- Release：[从空目录构建](/tmp/jifen-fix-release-20261022.log)、[最终源码构建](/tmp/jifen-fix-release-final-20261022.log)。

改动前对相关脏文件和测试基线单独备份至 `/tmp/jifen-preflight-fix-backup-20261022/`，并记录原有 152 个未提交路径的哈希。已有业务修改保留，本轮不提交、不上传。

本轮完成范围是这 3 项代码/测试/采集问题。签名 Archive、App Store 包校验和真机验收不在此次自动验证结果内；此前记录的发布前真机回归要求继续适用。
