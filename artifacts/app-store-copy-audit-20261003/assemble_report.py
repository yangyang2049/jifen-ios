# -*- coding: utf-8 -*-
"""Assemble existing independent reviews without editing any source copy."""
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path('/Users/yangyang/Desktop/jifenqi/jifen-ios')
OUT = ROOT / 'artifacts/app-store-copy-audit-20261003'
SOURCE = ROOT / 'marketing/app-store/localization-2026-10-02/locales'
COPY = ROOT / 'marketing/app-store/ios-screenshots-pen-2026-10-02/copy.json'
EXPORTS = COPY.parent / 'exports'
STRUCT = json.loads((OUT / 'structural-audit.json').read_text())
STRUCTURES = {r['locale']: r for r in STRUCT['rows']}
LIVE = json.loads((OUT / 'live-descriptions-before.json').read_text())
LIVE_ROWS = {r['attributes']['locale']: r['attributes'] for r in LIVE['localizations']}
COPY_ROWS = {r['locale']: r for r in json.loads(COPY.read_text())['localizations']}
CARDS = dict(zip(['slogan', 'score', 'catalog', 'recap', 'setup', 'multiplayer', 'cast'],
                 ['01-slogan.png', '02-score.png', '03-catalog.png', '04-recap.png',
                  '05-setup.png', '06-multiplayer.png', '07-cast.png']))
SEVERITIES = {'P2': 'error', 'definite_error': 'error', 'error': 'error',
              'P3': 'suggestion', 'suggestion': 'suggestion',
              'high_confidence_suggestion': 'suggestion', 'native-review': 'native-review'}
STATES = {'NEEDS_FIX': '需修正', 'PASS': '未见问题',
          'SUGGESTION': '有优化建议', 'NATIVE_REVIEW': '待母语确认'}
LABELS = {'error': '需修正', 'suggestion': '可选优化', 'native-review': '待母语确认'}
CONFIDENCE = {'certain': '确定', 'high': '高', 'medium': '中'}
WESTERN_REASONS = {
    'screenshotTitles.score.title': 'at a glance 表示快速看清信息，与 See every score 搭配更自然。当前 PNG 已使用 SEE EVERY SCORE，仅建议同步 JSON 的旧标题。',
    'description.footerLabels': '三个法律链接标签的冒号前缺少法语所需空格。建议插入不换行空格 U+00A0；保留 URL 独立行及现有段落。正文已有普通空格，也可统一为不换行空格。',
    'description.cubeTimer': '丹麦语 terning 可以表示骰子或立方体，未明确魔方。可采用词典中的 professorterning 明确对象；属于术语清晰度建议，完整表达可再由母语者确认。',
}


def link(label, path):
    return f'[{label}]({path})'


def block(value):
    return '```text\n' + value + '\n```'


def cell(value):
    return value.replace('|', '\\|').replace('\n', '<br>')


rows = []
for region in ['western', 'central', 'asia']:
    for row in json.loads((OUT / (region + '.json')).read_text())['locales']:
        row['reviewGroup'] = region
        rows.append(row)
assert len(rows) == 50 and len({r['locale'] for r in rows}) == 50
assert {r['locale'] for r in rows} == {p.stem for p in SOURCE.glob('*.json')} == set(STRUCTURES) == set(LIVE_ROWS)

for row in rows:
    locale = row['locale']
    path = SOURCE / (locale + '.json')
    data = json.loads(path.read_text())
    assert hashlib.sha256(path.read_bytes()).hexdigest() == STRUCTURES[locale]['sha256'], locale
    assert data['description'] == LIVE_ROWS[locale]['description'], locale
    row.update(language=data['language'], sourceFile=str(path), structuralChecks=STRUCTURES[locale],
               descriptionMatchesLive=True, actualPngTitlesReviewed=locale in COPY_ROWS,
               reportFile=str(OUT / 'locales' / (locale + '.md')))
    for number, finding in enumerate(row['findings'], 1):
        finding['originalSeverity'] = finding['severity']
        finding['severity'] = SEVERITIES[finding['severity']]
        finding['id'] = f'{locale}-{number}'
        finding['sources'] = [str(ROOT / p.strip()) if not p.strip().startswith('/') else p.strip()
                              for p in finding.get('source', str(path)).split(';')]
        if row['reviewGroup'] == 'western':
            finding['reasonOriginal'] = finding['reason']
            finding['reason'] = WESTERN_REASONS.get(finding['field'], finding['reason'])
        finding['affectedPngs'] = []
        field = finding['field']
        card = None
        if field.startswith(('cards.', 'renderedTitles.')):
            card = field.split('.')[1]
        elif field == 'renderedSlogan':
            card = 'slogan'
        elif 'cards.recap' in field:
            card = 'recap'
        if card in CARDS and locale in COPY_ROWS:
            finding['affectedPngs'] = [str(EXPORTS / locale / CARDS[card])]
        if locale == 'ur-PK' and field == 'renderedTitles.catalog':
            finding['oldDisplayNote'] = '代码块为逻辑源字符串，视觉错序请查看 PNG；源字符串的逻辑顺序正确。'
        if locale == 'ja' and field == 'renderedSlogan':
            finding['severity'] = 'suggestion'
            finding['reason'] = '实际 PNG 将「得点」拆成「得 / 点」。日语一般汉字之间可换行，这不构成拼写或禁则错误；但短标题可读性较差，建议改为三行「すべての / 得点に / 意味がある」，再测量字号和文本框。'
            finding['reference'] = 'https://www.w3.org/TR/jlreq/'
            finding['classificationNote'] = '独立复核后降为可读性建议；不以西方单词断行规则套用日语。'

    def status(predicate):
        matches = [f for f in row['findings'] if predicate(f['field'])]
        if any(f['severity'] == 'error' for f in matches):
            return 'NEEDS_FIX'
        if any(f['severity'] == 'native-review' for f in matches):
            return 'NATIVE_REVIEW'
        return 'SUGGESTION' if matches else 'PASS'

    row['descriptionStatus'] = status(lambda f: f.startswith('description'))
    row['sloganStatus'] = status(lambda f: 'slogan' in f.lower())
    row['subtitleStatus'] = status(lambda f: f.startswith('subtitle'))
    row['otherTitlesStatus'] = status(lambda f: not f.startswith(('description', 'subtitle')) and 'slogan' not in f.lower())
    row['overallStatus'] = status(lambda f: True)

rows.sort(key=lambda r: r['locale'])
counts = collections.Counter(f['severity'] for r in rows for f in r['findings'])
error_pngs = sorted({p for r in rows for f in r['findings'] if f['severity'] == 'error' for p in f['affectedPngs']})
summary = {
    'localeFilesReviewed': 50, 'descriptionLiveMatches': 50, 'subtitlesReviewed': 50,
    'pngLocaleSetsReviewed': 48, 'pngTitleImagesReviewed': 336, 'structuralErrors': len(STRUCT['issues']),
    'definiteIssueLocales': [r['locale'] for r in rows if r['overallStatus'] == 'NEEDS_FIX'],
    'descriptionFixLocales': [r['locale'] for r in rows if r['descriptionStatus'] == 'NEEDS_FIX'],
    'pngFixLocales': sorted({Path(p).parent.name for p in error_pngs}), 'pngFixImages': error_pngs,
    'findingCounts': dict(counts), 'sourceModified': False, 'remoteModified': False,
    'penModified': False, 'pngModified': False,
}
master = {
    'auditDate': '2026-10-03', 'appId': LIVE['appId'], 'versionId': LIVE['versionId'], 'version': LIVE['version'],
    'scope': '逐文件逐语言审校 Description、subtitle、启用截图标题及 48 套 PNG 实际营销标题；不含整个游戏 UI 的逐字审校。',
    'method': '独立语义审读、实际 PNG 标题检视、结构校验；疑似省略或术语清晰度单列建议/母语待确认。PASS 表示本轮未发现问题，不等于母语专家认证。',
    'summary': summary, 'locales': rows,
}
(OUT / 'audit-report.json').write_text(json.dumps(master, ensure_ascii=False, indent=2) + '\n')
(OUT / 'locales').mkdir(exist_ok=True)

for row in rows:
    locale = row['locale']
    data = json.loads(Path(row['sourceFile']).read_text())
    actual = COPY_ROWS.get(locale)
    structure = row['structuralChecks']
    lines = [f'# {locale} — {data["language"]} 文案审校', '',
             '审校日期：2026-10-03。结论：' + STATES[row['overallStatus']] + '。源文案及 App Store 均未修改。', '',
             link('返回总报告', OUT / 'audit-report.md') + ' · ' + link('语言源文件', row['sourceFile']), '',
             '## 检查范围与结论', '', '| 项目 | 结果 |', '| --- | --- |']
    for label, field in [('Description', 'descriptionStatus'), ('Slogan（首图标题）', 'sloganStatus'),
                         ('App Store subtitle（副标题）', 'subtitleStatus'), ('其他截图标题', 'otherTitlesStatus')]:
        lines.append(f'| {label} | {STATES[row[field]]} |')
    lines += ['', f'Description 与当前 App Store 3.3 完全一致；{structure["descriptionParagraphCount"]} 个段落，{structure["descriptionUTF16"]} 个 UTF-16 单元。三个法律 URL 完整且各占独立一行。无字面量 \\n、异常 CR/tab、段尾空格或多余空段；长度在限制内。', '',
              f'已逐段核对运动名、iPhone／iPad／Apple、围棋及魔方计时语境、功能支持范围。副标题单独审读，{structure["subtitleUTF16"]} 个 UTF-16 单元。', '',
              '实际 PNG 检查范围：' + ('七张营销标题；首图原图/总览与 2–7 张标题裁切。' if actual else '本批没有该语言 PNG，仅检查 JSON 文案。'), '',
              'PASS 表示本轮未发现问题。地区常用词差异、合理外来词变格、日语一般汉字间断行不直接判为拼写错误。', '',
              '## 发现与具体建议', '']
    if not row['findings']:
        lines += ['本轮未发现需要修正或单独复核的问题。', '']
    for finding in row['findings']:
        lines += [f'### {finding["id"]} · {LABELS[finding["severity"]]} · {finding["field"]}', '',
                  '置信度：' + CONFIDENCE.get(finding.get('confidence'), '未标注') + '。' + finding['reason'], '',
                  ('原文（逻辑字符串；视觉错序见 PNG）：' if finding.get('oldDisplayNote') else '原文／实际排版：'), '', block(finding['old']), '',
                  '建议文案／目标排版：', '', block(finding['new']), '']
        for path in finding['sources']:
            lines += [link('定位源文件', path), '']
        for path in finding['affectedPngs']:
            lines += [link('查看实际 PNG', path), '']
        if finding.get('reference'):
            lines += [link('术语或排版依据', finding['reference']), '']
        if finding.get('classificationNote'):
            lines += [finding['classificationNote'], '']
    lines += ['## Description 原文', '', block(data['description']), '',
              '## Subtitle 与 Slogan 原文', '', 'Subtitle：' + data['subtitle'], '',
              'JSON 中的 Slogan：', '', block(next(t['title'] for t in data['screenshotTitles'] if t['id'] == 'slogan')), '']
    if actual:
        lines += ['截图文案源中的 Slogan（PNG 可能另有自动换行）：', '',
                  block(next(c['text'] for c in actual['cards'] if c['id'] == 'slogan')), '',
                  link('首图 PNG', EXPORTS / locale / '01-slogan.png'), '',
                  '## 本批七张截图营销标题', '', '| 张数 | 标题 ID | 文案源（人工换行） | 实际图片 |', '| --- | --- | --- | --- |']
        for card in actual['cards']:
            lines.append(f'| {CARDS[card["id"]][:2]} | {card["id"]} | {cell(card["text"])} | {link("PNG", EXPORTS / locale / CARDS[card["id"]])} |')
        lines += ['', '表格展示 copy.json 的人工换行；实际自动换行已另行看图，不以表格替代视觉检查。', '']
    lines += ['## JSON 中启用的全部标题', '', '| 标题 ID | 文案 |', '| --- | --- |']
    for title in data['screenshotTitles']:
        if title.get('enabled'):
            lines.append(f'| {title["id"]} | {cell(title["title"])} |')
    lines += ['', '停用的 watch 标题未作为当前发布文案。当前截图采用 multiplayer；旧 JSON 中 timer/tools 不等同于本批第 6/7 张标题。', '',
              '源文件 SHA-256：`' + structure['sha256'] + '`。', '']
    Path(row['reportFile']).write_text('\n'.join(lines))

main = ['# App Store Description 与 Slogan 逐语言审校', '',
        '2026-10-03 · iScoreboard／全能计分器 · App Store 3.3 · app ID ' + LIVE['appId'], '',
        '已逐文件审读 50 个语言的 Description、副标题及启用标题；逐张检视本批 48 个语言共 336 张 PNG 的营销标题。生成 50 份独立语言报告，保留原文、建议、置信度和文件定位。', '',
        '## 本轮结论', '',
        '- 3 个语言的 Description 需修正：fr-FR、fr-CA、ur-PK。法语法律标签补冒号前不换行空格；乌尔都语改正“支持该功能的项目”的表达。',
        '- 6 个语言共 12 张 PNG 存在确定排版问题：el、ml-IN、ms、ta-IN、uk、ur-PK。希腊语 7 张处理全大写重音，乌尔都语第 3 张修正 RTL 数字顺序，其余为首图词内断行。',
        '- 日语首图「得 / 点」列为可读性优化。日语一般汉字之间可换行，不按西方单词规则判为拼写错误。',
        '- 全部 50 个 Description 与当前线上草稿完全一致，均为 7 个段落、3 个独立完整 URL。结构、长度和副标题检查通过；其余优化/待确认项见逐语言报告。', '',
        '本轮未修改源文案、Pen、PNG 或 App Store 内容。先前截图上传的技术验证通过，仍需处理本报告中的文案／排版问题。', '',
        '## 需要修正的项', '', '| 语言 | 位置 | 问题与处理方向 |', '| --- | --- | --- |']
fixes = [
    ('fr-FR', 'Description（fr-CA 同样）', '三个法律标签的冒号前补 U+00A0；URL 继续独立成行。'),
    ('fr-CA', 'Description', '同上。'),
    ('ur-PK', 'Description；03-catalog.png', '支持范围表达不准；26 落在 RTL 句子的错误一端。修正段落方向，RLM 候选方案须重新渲染验证。'),
    ('el', '七张 PNG 标题', '全大写希腊语删除普通 tonos，保留需要的分音符；不改正常大小写 JSON 的重音。'),
    ('uk', '01-slogan.png', 'ВАЖЛИВЕ 被拆为 ВАЖЛИВ / Е。'),
    ('ms', '01-slogan.png', 'BERMAKNA 被拆为 BERMAKN / A。'),
    ('ml-IN', '01-slogan.png', 'പോയിന്റും、പ്രധാനമാണ് 词内自动断行。'),
    ('ta-IN', '01-slogan.png', 'ஒவ்வொரு、புள்ளியும் 被拆开。'),
]
for locale, field, reason in fixes:
    main.append(f'| {link(locale, OUT / "locales" / (locale + ".md"))} | {field} | {reason} |')
main += ['',
         '法语依据：' + link('OQLF 两点号规范', 'https://vitrinelinguistique.oqlf.gouv.qc.ca/23325/la-ponctuation/deux-points/emplois-courants-du-deux-points') + '。希腊语依据：' + link('官方现代希腊语语法 3.2', 'https://ebooks.edu.gr/ebooks/v/html/8547/2334/Grammatiki-Neas-Ellinikis-Glossas_A-B-G-Gymnasiou_html-apli/index_B_03.html') + '。日语分类依据：' + link('W3C JLREQ', 'https://www.w3.org/TR/jlreq/') + '。', '',
         '## 每个语言的独立报告', '', '| 语言代码 | 语言 | Description | Slogan | 其他标题 | 完整报告 |', '| --- | --- | --- | --- | --- | --- |']
for row in rows:
    main.append(f'| {row["locale"]} | {row["language"]} | {STATES[row["descriptionStatus"]]} | {STATES[row["sloganStatus"]]} | {STATES[row["otherTitlesStatus"]]} | {link("查看", row["reportFile"])} |')
main += ['', 'zh-Hans／zh-Hant 为 JSON 文案审校，不属于本批 48 套 PNG，未检查中文截图的实际自动换行。', '',
         '## 证据与复核范围', '',
         '- ' + link('机器可读合并报告', OUT / 'audit-report.json') + '：全部 50 个语言、old/new、置信度及原图链接。',
         '- ' + link('结构检查', OUT / 'structural-audit.json') + '、' + link('当前线上 Description 快照', OUT / 'live-descriptions-before.json') + '、' + link('功能范围核对', OUT / 'feature-facts.json') + '。',
         '- 首图实际渲染总览：' + ' / '.join(link(str(i), OUT / f'slogan-preview-{i}.jpg') for i in range(1, 4)) + '。',
         '- 区域独立记录：' + ' / '.join(link(r, OUT / (r + '.json')) for r in ['western', 'central', 'asia']) + '。合并报告对日语断行作独立分类调整，以合并报告为准。', '',
         '本轮检查营销文案及标题，不含截图内整个游戏 UI 的逐字审校。功能说明对照当前代码与目录，未重新做设备操作测试。PASS 表示本轮未发现问题；需母语确认的表达单独标记。', '']
(OUT / 'audit-report.md').write_text('\n'.join(main))
assert len(summary['descriptionFixLocales']) == 3
assert len(summary['pngFixLocales']) == 6 and len(error_pngs) == 12
print(json.dumps(summary, ensure_ascii=False, indent=2))
print('Wrote 50 individual reports plus audit-report.md and audit-report.json.')
