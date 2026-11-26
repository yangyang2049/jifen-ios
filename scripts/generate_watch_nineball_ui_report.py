#!/usr/bin/env python3
"""从手表九球 UI 测试的 xcresult 导出附件生成 HTML 走查报告。

用法：
  xcrun xcresulttool export attachments --path <run>.xcresult --output-path <att>
  python3 scripts/generate_watch_nineball_ui_report.py <att>       docs/verification/watch-nineball-ui-2026-11-24 <批次名>

截图写入 <输出目录>/shots/；每张图的「页面 + 状态」取自测试进程写出的 captions 附件。
"""
import json
import pathlib
import re
import shutil
import sys
from html import escape

att_dir = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2])
run_label = escape(sys.argv[3] if len(sys.argv) > 3 else "")

manifest = json.loads((att_dir / "manifest.json").read_text())
captions, shapes = {}, {}
for test in manifest:
    for att in test["attachments"]:
        name = att.get("suggestedHumanReadableName") or ""
        exported = att_dir / pathlib.Path(att["exportedFileName"]).name
        if name.startswith("captions_0_") and exported.suffix == ".txt":
            for line in exported.read_text(errors="replace").splitlines():
                parts = line.split("|")
                if len(parts) >= 3:
                    captions[parts[0]] = (parts[1].strip(), "|".join(parts[2:]).strip())

shots_dir = out_dir / "shots"
shots_dir.mkdir(parents=True, exist_ok=True)
for test in manifest:
    for att in test["attachments"]:
        name = att.get("suggestedHumanReadableName") or ""
        if not name.startswith("shot_"):
            continue
        exported = att_dir / pathlib.Path(att["exportedFileName"]).name
        if exported.suffix != ".png":
            continue
        shot = name.split("_0_")[0][len("shot_"):]
        if not re.fullmatch(r"[234]p_[a-z0-9_]+", shot):
            continue
        shutil.copy(exported, shots_dir / f"{shot}.png")
        shapes[shot] = exported.stat().st_size

missing = sorted(set(captions) - set(shapes))
extra = sorted(set(shapes) - set(captions))

SECTIONS = [
    ("3p", "场景 A · 3 人局（主流程）",
     "从首页进入九球 3 人局：开球人徽标 → 事件面板 → 普通胜/小金/让杆的一步式选人 → 长按菜单切换开球人 → 大金直出 → 完赛遮罩。"),
    ("4p", "场景 B · 4 人局（2×2 棋盘）",
     "4 人棋盘布局下的同一套规则：一步式付分人、开球人切换、小金推荐「开球」。"),
    ("2p", "场景 C · 2 人局（对齐手机端的小金置灰）",
     "2 人单人付分时，开球人的「小金」置灰；非开球人小金直接出分，不弹二级选人。"),
]

COVERAGE = [
    ("开球人徽标（计分板姓名左侧）", "3p_04 / 3p_10 / 4p_01 / 4p_07 / 2p_01"),
    ("开球人徽标（事件面板标题「开球」）", "3p_05 / 3p_16 / 2p_02"),
    ("长按菜单 → 本局开球人", "3p_08 / 3p_09 / 4p_05 / 4p_06"),
    ("3–4 人普通胜 → 选择付分人（推荐上家）", "3p_06 / 4p_03"),
    ("3–4 人小金 → 选择付分人（推荐开球）", "3p_12 / 4p_08"),
    ("3 人让杆 → 选择继续击球人（推荐下家）", "3p_14"),
    ("大金 1 步直出（仅开球人可点）", "3p_16 / 3p_17 / 3p_11"),
    ("2 人开球人小金置灰", "2p_02 / 2p_03 / 2p_04"),
    ("完赛确认与完赛遮罩", "3p_18 / 3p_19"),
    ("设置页首屏与滚动", "3p_03 / 3p_03b / 4p_00 / 4p_00b"),
]

ISSUES = [
    ("P2", "「选择人数」弹层里「4 人」按钮超出卡片底部，点下缘会把弹层关掉",
     ["无障碍树里 <code>Button '4 人'</code> 的 frame 是 <code>{{28,180},{152,68}}</code>（pt），即按钮从 180pt 一直延到 248pt 屏幕底；"
      "而卡片背景在 233.5pt 处收边（截图 <code>3p_02</code> 中间列像素扫描：y≈467px 之后已回到遮罩色）。",
      "UI 测试第一版按元素中心 <code>tap()</code> 时直接失败——弹层被遮罩关掉、停在首页；改成点按钮上部坐标后才稳定进入设置页。",
      "建议：三个选项放进等分高度或可滚动容器，卡片底部留 8–10pt 内边距，别让最后一行压到卡片圆角外。"]),
    ("P2", "九球 3/4 人设置页首屏看不到第 3（4）名选手的名称行",
     ["设置页 ScrollView 行高 52pt，行起点 112 / 164 / 216pt，而「开始」按钮悬浮在 188–248pt，正好把第 3 行整块盖住："
      "截图 <code>3p_03_setup</code> 首屏只有选手 1、2 与绿色「开始」；向上滚动后才露出选手 3（<code>3p_03b_setup_scrolled</code>）。",
      "4 人局同理（<code>4p_00_setup</code> / <code>4p_00b_setup_scrolled</code>）：首屏只能看到前两行。",
      "影响：开 3/4 人局时第一眼以为只有 2 个名字框，需要额外一次滚动才发现还要填第 3、4 人。",
      "建议：名称行改紧凑（行高 44pt 或折叠成「选手」入口），或让「开始」只占内容高度、不覆盖最后一行。"]),
    ("P3", "4 人棋盘下球杆徽标偏小，辨识度低于 2 人布局",
     ["徽标白色笔画实测 bbox：4 人布局 16×16px（≈8×8pt），2 人布局 20×20px（≈10×10pt）。",
      "3 人布局里 OCR 会把徽标和姓名连读成「／ 选手1」（<code>3p_04</code>），说明笔画已经细到接近文字噪点级别。",
      "建议：4 人布局下徽标不小于 10pt，或在比分下方补一条「开球」文字标签。"]),
    ("P3", "事件面板标题里「开球」胶囊与姓名几乎贴在一起",
     ["<code>3p_16</code> 的 OCR 把标题读成一整串「● 选手2开球」，说明 4pt 的间距在 9pt 胶囊下视觉上粘连。",
      "建议：间距提到 6–8pt，或加一个分隔点。"]),
    ("P3", "普通胜 / 小金 结算后开球人自动轮转，界面没有任何提示",
     ["<code>3p_07</code> 得分后球杆徽标已经从选手 1 跑到选手 2，<code>3p_09</code> 的开球人面板对勾也落在选手 2"
      "（规则见 <code>ScoreCore/NineBallChaseTransfers.swift:73-77</code>：普通胜/小金结束后 breaker 轮到下家，大金/金九保留）。",
      "但计分板上没有任何「开球人已轮转」的反馈，用户容易以为徽标在乱跳。",
      "建议：结算后 toast 一句「开球人 → 选手 2」，或在开球人面板标题补「本局 · 第 N 局」。"]),
    ("观察", "2 人单人付分时开球人的「小金」直接置灰，没有任何文字解释",
     ["截图 <code>2p_02</code>：小金格子区域最大亮度 73（禁用）；<code>2p_03</code> 同一位置最大亮度 255（可用），置灰确实生效。",
      "与手机端行为一致，属于预期；但手表屏幕小，建议禁用时补一句「小金需非开球人」或在 2 人单人付分下直接隐藏该按钮。"]),
]

cards_by_prefix = {}
for shot in sorted(shapes):
    prefix = shot.split("_")[0]
    cards_by_prefix.setdefault(prefix, []).append(shot)


def card_html(shot: str) -> str:
    page, state = map(escape, captions.get(shot, ("（缺少说明）", "")))
    number = shot.split("_")[1]
    return f"""
      <figure class="card" id="{shot}">
        <a href="shots/{shot}.png" target="_blank" rel="noopener">
          <img src="shots/{shot}.png" alt="{page}" loading="lazy">
        </a>
        <figcaption>
          <div class="shot-no">{number}</div>
          <div class="shot-page">{page}</div>
          <div class="shot-state">{state}</div>
          <div class="shot-file">shots/{shot}.png</div>
        </figcaption>
      </figure>"""


sections_html = []
for prefix, title, lead in SECTIONS:
    shots = cards_by_prefix.get(prefix, [])
    if not shots:
        continue
    sections_html.append(f"""
  <section>
    <h2>{title}</h2>
    <p class="lead">{lead}</p>
    <div class="grid">{''.join(card_html(s) for s in shots)}
    </div>
  </section>""")

coverage_rows = "".join(
    f"<tr><td>{feature}</td><td class='mono'>{shots}</td></tr>" for feature, shots in COVERAGE
)

issues_html = "".join(
    f"""
    <article class="issue">
      <div class="issue-head"><span class="sev {'p2' if sev == 'P2' else ('p3' if sev == 'P3' else 'obs')}">{sev}</span>{title}</div>
      <ul>{''.join(f'<li>{line}</li>' for line in lines)}</ul>
    </article>"""
    for sev, title, lines in ISSUES
)

rows = "".join(
    f"<tr><td class='mono'>{shot}</td><td>{escape(captions.get(shot, ('',''))[0])}</td><td>{escape(captions.get(shot, ('',''))[1])}</td></tr>"
    for shot in sorted(shapes)
)

html = f"""<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>手表端九球（追分）3–4 人交互与开球人切换 · UI 走查</title>
<style>
  :root {{ color-scheme: dark; }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 44px 34px 90px; background: #0a0c0f; color: #e8ecf1;
    font: 15px/1.68 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif;
  }}
  h1 {{ font-size: 27px; margin: 0 0 8px; letter-spacing: .2px; }}
  h2 {{ font-size: 20px; margin: 0 0 6px; }}
  h3 {{ font-size: 16px; margin: 30px 0 10px; }}
  .sub {{ color: #8b949e; margin: 0 0 26px; font-size: 14px; }}
  section {{ margin: 0 0 52px; padding-top: 10px; border-top: 1px solid #1d242c; }}
  .lead {{ color: #99a3ae; margin: 4px 0 22px; font-size: 14px; }}
  .meta {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 24px; padding: 0; list-style: none; }}
  .meta li {{ background: #11151a; border: 1px solid #1e252d; border-radius: 10px; padding: 8px 12px; font-size: 13px; color: #b7c0c9; }}
  .meta b {{ color: #eef2f6; font-weight: 600; margin-right: 4px; }}
  .pass {{ background: #0f1d14; border: 1px solid #24512f; color: #8ce6ac; border-radius: 12px; padding: 12px 16px; font-size: 13.5px; margin: 0 0 26px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(228px, 1fr)); gap: 22px; }}
  .card {{ margin: 0; background: #11151a; border: 1px solid #1e252d; border-radius: 14px; overflow: hidden; display: flex; flex-direction: column; }}
  .card img {{ width: 100%; display: block; background: #000; }}
  figcaption {{ padding: 12px 14px 14px; }}
  .shot-no {{ display: inline-block; font-size: 11px; font-weight: 700; color: #08090a; background: #30d158; border-radius: 6px; padding: 1px 7px; margin-bottom: 8px; }}
  .shot-page {{ font-weight: 600; margin-bottom: 6px; font-size: 14px; }}
  .shot-state {{ color: #99a3ae; font-size: 13px; }}
  .shot-file {{ margin-top: 8px; font-family: "SF Mono", ui-monospace, monospace; font-size: 11px; color: #4d5964; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
  th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid #1a212a; vertical-align: top; }}
  th {{ color: #8b949e; font-weight: 600; }}
  .mono {{ font-family: "SF Mono", ui-monospace, monospace; color: #7ee2a8; }}
  .issues {{ background: #12100c; border: 1px solid #46331a; border-radius: 16px; padding: 20px 24px; }}
  .issues h2 {{ color: #ffb86b; }}
  .issue {{ border-top: 1px dashed #2c2418; padding: 14px 0 4px; }}
  .issue:first-of-type {{ border-top: none; }}
  .issue-head {{ font-weight: 600; font-size: 14.5px; margin-bottom: 6px; }}
  .issue ul {{ margin: 0; padding-left: 20px; color: #b7c0c9; font-size: 13.5px; }}
  .issue li {{ margin-bottom: 6px; }}
  .sev {{ font-size: 11px; padding: 1px 7px; border-radius: 5px; margin-right: 8px; font-weight: 700; vertical-align: 1px; }}
  .p2 {{ background: #ff9f5a; color: #2a1400; }}
  .p3 {{ background: #ffd479; color: #241a00; }}
  .obs {{ background: #6aa9ff; color: #001733; }}
  code {{ background: #1b222a; padding: 1px 5px; border-radius: 5px; font-size: 12.5px; }}
  details {{ margin-top: 16px; }}
  summary {{ cursor: pointer; color: #8b949e; font-size: 13px; }}
  a {{ color: #7ee2a8; }}
</style>
</head>
<body>
  <h1>手表端九球（追分）3–4 人交互与开球人切换 · UI 走查</h1>
  <p class="sub">Apple Watch 模拟器实跑：XCTest 驱动真实点击/长按，逐步截图；每张图下方标注「第几页 · 哪个页面 · 哪种状态」。共 {len(shapes)} 张。</p>

  <ul class="meta">
    <li><b>用例</b>jifenWatch Watch AppUITests / WatchNineBallUITests</li>
    <li><b>附件</b>{len(shapes)} 张截图</li>
  </ul>

  <p class="pass">截图覆盖开球徽标、二级选人、置灰状态和比分变化。用例结果与测试设备可在对应批次的 xcresult 中查看。</p>

  <h3>覆盖矩阵</h3>
  <table>
    <thead><tr><th>交互点</th><th>对应截图</th></tr></thead>
    <tbody>{coverage_rows}</tbody>
  </table>

  <h3>2026-11-24 走查记录</h3>
  <div class="issues">
    <h2>{len(ISSUES)} 条</h2>
    {issues_html}
  </div>

  {''.join(sections_html)}

  <section>
    <h2>截图清单</h2>
    <table>
      <thead><tr><th>文件</th><th>页面</th><th>状态</th></tr></thead>
      <tbody>{rows}</tbody>
    </table>
    <details>
      <summary>生成信息</summary>
      <p>测试批次：<code>{run_label}</code>（14 天保留策略，过期自动清理）。截图在本报告旁的 <code>shots/</code> 目录。</p>
      <p>缺失说明：{escape(', '.join(missing) or '无')}；无说明的截图：{escape(', '.join(extra) or '无')}。</p>
    </details>
  </section>
</body>
</html>
"""
(out_dir / "index.html").write_text(html)
print(f"wrote {out_dir/'index.html'} shots={len(shapes)} missing={len(missing)} extra={len(extra)}")
