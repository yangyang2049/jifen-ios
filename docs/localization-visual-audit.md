# iScoreboard 多语言 UI 审查门禁

重点语言在逐条文案审核和单语言晋级之后，必须再通过可视化审查。当前矩阵覆盖：

- 长文案重点：日语、韩语、德语、法语（法国/加拿大）、西班牙语（墨西哥/西班牙）、葡萄牙语（巴西/葡萄牙）、俄语。
- RTL 重点：阿拉伯语、希伯来语、乌尔都语。
- 设备：窄屏 iPhone 与 iPad 各一轮。
- 页面：首页、计分目录、乒乓球设置、计时目录、我的、会员、超长 FAQ、无障碍超大字体记录详情。

运行命令：

```sh
scripts/run_localization_visual_audit.sh
```

只复测已晋级的部分语言：

```sh
LOCALIZATION_VISUAL_AUDIT_LOCALES=de,ar scripts/run_localization_visual_audit.sh
```

可用 `LOCALIZATION_VISUAL_AUDIT_DIR` 指定独立输出目录，保留历史截图及人工结论。

脚本会先逐语言执行 `validate --require-reviewed`，并确认正式 `.lproj` 已生成；任一语言仍是机器初稿或未晋级时都会停止，不会用英文回退伪造通过结果。

完成后打开：

```text
build/localization/visual-audit/本地化UI截图审查.md
```

阿拉伯语、希伯来语和乌尔都语除截图外还会导出关键元素坐标 JSON。第一轮只取证和分类，不自动翻转自定义布局；确认问题后再区分系统可自动镜像的控件、需要使用 leading/trailing 的布局，以及比分双方/手势语义不能机械镜像的场景。
