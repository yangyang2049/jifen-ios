#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const [baseDirectory, outputDirectory, ...attachmentDirectories] = process.argv.slice(2);

if (!baseDirectory || !outputDirectory || attachmentDirectories.length === 0) {
  console.error(
    "Usage: generate_ui_review_document.js <base-screenshots> <output-directory> <attachment-directory>..."
  );
  process.exit(2);
}

fs.mkdirSync(outputDirectory, { recursive: true });

function copyScreenshot(source, fileName) {
  const destination = path.join(outputDirectory, fileName);
  if (path.resolve(source) !== path.resolve(destination)) {
    fs.copyFileSync(source, destination);
  }
}

for (const fileName of fs.readdirSync(baseDirectory)) {
  if (!fileName.endsWith(".png")) continue;
  copyScreenshot(path.join(baseDirectory, fileName), fileName);
}

for (const attachmentDirectory of attachmentDirectories) {
  const manifestPath = path.join(attachmentDirectory, "manifest.json");
  const groups = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  for (const group of groups) {
    for (const attachment of group.attachments || []) {
      if (!attachment.exportedFileName.endsWith(".png")) continue;
      const readableName = attachment.suggestedHumanReadableName.replace(
        /_0_[0-9A-F-]{36}\.png$/i,
        ".png"
      );
      copyScreenshot(
        path.join(attachmentDirectory, attachment.exportedFileName),
        readableName
      );
    }
  }
}

const screenshots = fs
  .readdirSync(outputDirectory)
  .filter((fileName) => fileName.endsWith(".png"))
  .sort((left, right) => left.localeCompare(right, "en"));

function escapeHTML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function section(title, files) {
  if (files.length === 0) return "";
  const cards = files
    .map(
      (fileName) => `
        <figure>
          <a href="${encodeURI(fileName)}" target="_blank" rel="noreferrer">
            <img src="${encodeURI(fileName)}" loading="lazy" alt="${escapeHTML(fileName)}">
          </a>
          <figcaption>${escapeHTML(fileName)}</figcaption>
        </figure>`
    )
    .join("");
  return `<section><h2>${escapeHTML(title)} <small>${files.length} 张</small></h2><div class="grid">${cards}</div></section>`;
}

const priority = screenshots.filter((fileName) => /_(70|71|72|73)_/.test(fileName));
const regular = screenshots.filter((fileName) => !/_(70|71|72|73)_/.test(fileName));
const generatedAt = new Intl.DateTimeFormat("zh-CN", {
  dateStyle: "long",
  timeStyle: "short",
  timeZone: "Asia/Shanghai",
}).format(new Date());

const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>iOS UI 测试截图审查</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; padding: 24px; background: #111; color: #f5f5f7; }
    header { max-width: 1000px; margin: 0 auto 32px; }
    h1 { margin-bottom: 8px; }
    h2 { margin-top: 36px; border-bottom: 1px solid #333; padding-bottom: 10px; }
    small, p { color: #aaa; font-weight: normal; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 18px; }
    figure { margin: 0; padding: 10px; background: #1d1d1f; border: 1px solid #303033; border-radius: 12px; }
    img { display: block; width: 100%; height: 300px; object-fit: contain; background: #000; border-radius: 7px; }
    figcaption { margin-top: 9px; color: #ccc; font-size: 12px; line-height: 1.35; overflow-wrap: anywhere; }
    a:focus-visible img { outline: 3px solid #30d158; }
  </style>
</head>
<body>
  <header>
    <h1>iOS UI 测试截图审查</h1>
    <p>生成时间：${escapeHTML(generatedAt)}；共 ${screenshots.length} 张。点击缩略图可查看原图。</p>
    <p>重点覆盖：乒乓球、羽毛球、网球的单打/双打，以及掼蛋；同时保留全部计分板与二、三级页面截图。</p>
  </header>
  ${section("重点项目 · iPhone", priority.filter((fileName) => fileName.startsWith("iPhone_")))}
  ${section("重点项目 · iPad", priority.filter((fileName) => fileName.startsWith("iPad_")))}
  ${section("完整页面 · iPhone", regular.filter((fileName) => fileName.startsWith("iPhone_")))}
  ${section("完整页面 · iPad", regular.filter((fileName) => fileName.startsWith("iPad_")))}
</body>
</html>`;

fs.writeFileSync(path.join(outputDirectory, "UI测试截图审查.html"), html);
console.log(`Generated ${screenshots.length} screenshots and UI测试截图审查.html in ${outputDirectory}`);
