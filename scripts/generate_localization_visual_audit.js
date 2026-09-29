#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const [screenshotDirectory, outputDirectory] = process.argv.slice(2);
if (!screenshotDirectory || !outputDirectory) {
  console.error("Usage: generate_localization_visual_audit.js <screenshots> <output-directory>");
  process.exit(2);
}

const locales = [
  ["ja", "日语", "LTR"],
  ["ko", "韩语", "LTR"],
  ["de", "德语", "LTR"],
  ["it", "意大利语", "LTR"],
  ["nl", "荷兰语", "LTR"],
  ["sv", "瑞典语", "LTR"],
  ["fr", "法语（法国）", "LTR"],
  ["fr_CA", "法语（加拿大）", "LTR"],
  ["ru", "俄语", "LTR"],
  ["uk", "乌克兰语", "LTR"],
  ["es_MX", "西班牙语（墨西哥）", "LTR"],
  ["es_ES", "西班牙语（西班牙）", "LTR"],
  ["pt_BR", "葡萄牙语（巴西）", "LTR"],
  ["pt_PT", "葡萄牙语（葡萄牙）", "LTR"],
  ["ar", "阿拉伯语", "RTL"],
  ["he", "希伯来语", "RTL"],
  ["ur", "乌尔都语", "RTL"],
];

const screenLabels = new Map([
  ["01_home", "首页"],
  ["02_score_catalog", "计分目录"],
  ["03_pingpong_setup", "乒乓球设置"],
  ["04_timer_catalog", "计时目录"],
  ["05_me", "我的"],
  ["06_membership", "会员页"],
  ["06_membership_subscription", "会员页（订阅三项协议）"],
  ["07_faq_long_top", "超长 FAQ（上半）"],
  ["08_faq_long_continuation", "超长 FAQ（续页）"],
  ["09_record_detail_accessibility_xxxl", "记录详情（无障碍超大字体）"],
]);

fs.mkdirSync(outputDirectory, { recursive: true });
const files = fs.existsSync(screenshotDirectory)
  ? fs.readdirSync(screenshotDirectory).filter((name) => name.endsWith(".png")).sort()
  : [];
const evidenceFiles = fs.existsSync(outputDirectory)
  ? fs.readdirSync(outputDirectory).filter((name) => name.endsWith(".json")).sort()
  : [];
const reportPath = path.join(outputDirectory, "本地化UI截图审查.md");
const existingReport = fs.existsSync(reportPath) ? fs.readFileSync(reportPath, "utf8") : "";
const existingSummaryRows = new Map();
for (const match of existingReport.matchAll(/^\| ([^|]+) \| (?:LTR|RTL) \|.*$/gm)) {
  existingSummaryRows.set(match[1].trim(), match[0]);
}
const existingRTLChecklist = existingReport.match(/## RTL 专项清单\n\n([\s\S]*?)(?=\n## )/)?.[1]?.trim();
const existingIssueSection = existingReport.match(/## 问题记录\n[\s\S]*$/)?.[0];

function markdownPath(from, to) {
  return encodeURI(path.relative(from, to).split(path.sep).join("/"));
}

const lines = [
  "# iScoreboard 多语言 UI 截图审查",
  "",
  `生成时间：${new Date().toISOString()}`,
  "",
  "本报告只由已经完成逐条审核、通过确定性校验并晋级到 App 资源的语言生成。截图本身不代表通过；请在下表填写人工结论。",
  "",
  "## 审查结论",
  "",
  "| 语言 | 方向 | iPhone | iPad | 长文案 | 截断/重叠 | 结论 |",
  "| --- | --- | --- | --- | --- | --- | --- |",
  ...locales.map(([, label, direction]) => existingSummaryRows.get(label)
    ?? `| ${label} | ${direction} | ☐ | ☐ | ☐ | ☐ | 待审 |`),
  "",
  "## RTL 专项清单",
  "",
  ...(existingRTLChecklist
    ? existingRTLChecklist.split("\n")
    : [
      "- [ ] 底部导航顺序和选中态正确镜像。",
      "- [ ] 返回/前进图标、列表箭头和弹窗关闭位置符合 RTL。",
      "- [ ] 比分双方、发球方、胜者和加减分手势语义没有被错误对调。",
      "- [ ] 表单标题、输入框、开关、数字、时间、比分和百分号方向正确。",
      "- [ ] 阿拉伯语/希伯来语/乌尔都语与品牌、数字、标点混排没有跳位。",
      "- [ ] 先记录问题，未经确认不直接批量翻转自定义布局。",
    ]),
  "",
];

for (const [code, label, direction] of locales) {
  lines.push(`## ${label} · ${direction}`, "");
  const localeFiles = files.filter((name) => name.includes(`_${code}_`));
  if (localeFiles.length === 0) {
    lines.push("尚无截图。", "");
    continue;
  }
  for (const fileName of localeFiles) {
    const match = fileName.match(new RegExp(`^(iPhone|iPad)_${code}_(.+)\\.png$`));
    const device = match?.[1] ?? "设备";
    const key = match?.[2] ?? fileName;
    const title = screenLabels.get(key) ?? key;
    const absolute = path.join(screenshotDirectory, fileName);
    lines.push(`### ${device} · ${title}`, "", `![${label} ${device} ${title}](${markdownPath(outputDirectory, absolute)})`, "");
  }
  if (direction === "RTL") {
    const evidence = evidenceFiles.filter((name) => name.includes(`_${code}_rtl_metrics_`));
    if (evidence.length > 0) {
      lines.push("坐标证据：", "");
      for (const fileName of evidence) {
        lines.push(`- [${fileName}](${markdownPath(outputDirectory, path.join(outputDirectory, fileName))})`);
      }
      lines.push("");
    }
  }
}

if (existingIssueSection && !existingIssueSection.includes("尚待人工审图")) {
  lines.push(...existingIssueSection.trimEnd().split("\n"), "");
} else {
  lines.push(
    "## 问题记录",
    "",
    "| 编号 | 语言 | 设备/页面 | 严重级别 | 问题 | 建议 | 状态 |",
    "| --- | --- | --- | --- | --- | --- | --- |",
    "| — | — | — | — | 尚待人工审图 | — | 待审 |",
    ""
  );
}

fs.writeFileSync(reportPath, lines.join("\n"));
console.log(`Generated ${reportPath} with ${files.length} screenshots`);
