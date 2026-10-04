#!/usr/bin/env python3
"""Validate store copy offline; --refresh rebuilds derived bundles and review files."""
import argparse
import csv
import io
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXPECTED = set('ar-SA bn-BD ca zh-Hans zh-Hant hr cs da nl-NL en-AU en-CA en-GB en-US fi fr-FR fr-CA de-DE el gu-IN he hi hu id it ja kn-IN ko ms ml-IN mr-IN no or-IN pl pt-BR pt-PT pa-IN ro ru sk sl-SI es-MX es-ES sv ta-IN te-IN th tr uk ur-PK vi'.split())
CARD_IDS = ['slogan', 'score', 'catalog', 'recap', 'setup', 'timer', 'cast', 'watch', 'tools']

def size(value):
    return len(value.encode('utf-16-le')) // 2

def read_json(path):
    def unique(pairs):
        result = {}
        for k, v in pairs:
            if k in result:
                raise ValueError(f'{path}: duplicate JSON key {k}')
            result[k] = v
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)

def load_localizations():
    entries = [read_json(p) for p in sorted((ROOT / 'locales').glob('*.json'))]
    entries.sort(key=lambda r: r['locale'])
    return entries

def check(entries):
    errors = []
    def expect(ok, message):
        if not ok:
            errors.append(message)
    actual = {r['locale'] for r in entries}
    expect(actual == EXPECTED, f'Locale coverage: missing={sorted(EXPECTED-actual)}, extra={sorted(actual-EXPECTED)}')
    expect(len(entries) == 50 and len(actual) == 50, 'Expected 50 unique store locales')
    expect(len({r['iosLocale'] for r in entries}) == 47, 'Expected 47 iOS locales')
    for r in entries:
        code = r['locale']
        expect((ROOT / 'locales' / f'{code}.json').exists(), f'{code}: filename mismatch')
        for field, limit in [('name', 30), ('subtitle', 30), ('description', 4000)]:
            value = r.get(field, '')
            expect(isinstance(value, str) and bool(value.strip()), f'{code}: empty {field}')
            expect(size(value) <= limit, f'{code}: {field} length {size(value)} > {limit}')
            expect(value == value.strip(), f'{code}: {field} outer whitespace')
            expect(unicodedata.normalize('NFC', value) == value, f'{code}: {field} must use NFC normalization')
            expect(not re.search(r'[\x00-\x08\x0b-\x1f\u202a-\u202e\u2066-\u2069]', value), f'{code}: {field} contains control characters')
        expect(r['name'].startswith('iScoreboard: ') and len(r['name']) > 13, f'{code}: brand prefix')
        expect('\n' not in r['name'] + r['subtitle'], f'{code}: name/subtitle must be single line')
        expect(r['reviewStatus'] in ['draft', 'reviewed'], f'{code}: invalid reviewStatus')
        expect(r['direction'] == ('rtl' if r['iosLocale'] in ['ar', 'he', 'ur'] else 'ltr'), f'{code}: text direction')
        cards = r['screenshotTitles']
        expect([c['id'] for c in cards] == CARD_IDS, f'{code}: screenshot card coverage/order')
        for card in cards:
            expect(isinstance(card.get('title'), str) and bool(card['title'].strip()), f'{code}/{card["id"]}: empty title')
            expect(card.get('enabled') == (card['id'] != 'watch'), f'{code}/{card["id"]}: enabled status')
        expect('Apple Watch' not in r['description'], f'{code}: current description advertises removed Watch support')
        if r['iosLocale'] not in ['en', 'zh-Hans', 'zh-Hant']:
            expect(r['description'] != next(x['description'] for x in entries if x['locale'] == 'en-US'), f'{code}: English fallback description')
    # Preserve source titles exactly; source zh-Hans has no slogan card.
    by_code = {r['locale']:r for r in entries}
    for api, ios in [('en-US','en'), ('zh-Hans','zh-Hans')]:
        source = read_json(ROOT.parent / '2026-09' / 'locales' / f'{ios}.json')
        titles = {c['id']:c['title'] for c in by_code[api]['screenshotTitles']}
        for card in source['cards']:
            expect(titles.get(card['id']) == card['title'], f'{api}/{card["id"]}: changed source title')
    return errors

def derived(entries):
    overview = ['# App Store 本地化名称与副标题', '', '2026-10-02 · 全部 50 个商店语言／地区 · 文案草稿', '', '长度按 Unicode 码点计数；校验另外使用较保守的 UTF-16 长度。', '', '| Locale | 语言 | Name | 长度 | Subtitle | 长度 |', '| --- | --- | --- | ---: | --- | ---: |']
    detail = ['# App Store 本地化文案核对稿', '', '正文、截图标题均为草稿。watch 为历史卡片，当前不能出图或上传。换行是排版建议，尚未做视觉适配。截图中其他小字、辅助文案及 App 画面需在后续出图时处理。', '']
    report = []
    csv_file = io.StringIO()
    writer = csv.writer(csv_file)
    writer.writerow(['locale','language','name','nameCharacters','subtitle','subtitleCharacters','descriptionCharacters','reviewStatus'])
    for r in entries:
        code = r['locale']
        overview.append(f'| {code} | {r["language"]} | {r["name"]} | {len(r["name"])} | {r["subtitle"]} | {len(r["subtitle"])} |')
        writer.writerow([code,r['language'],r['name'],len(r['name']),r['subtitle'],len(r['subtitle']),len(r['description']),r['reviewStatus']])
        detail += [f'## {code} · {r["language"]}', '', f'**Name:** {r["name"]}', '', f'**Subtitle:** {r["subtitle"]}', '', '**Description:**', '', r['description'], '', '**截图 Title:**', '', '| 卡片 ID | Title | 使用状态 |', '| --- | --- | --- |']
        for c in r['screenshotTitles']:
            title = c['title'].replace('\n', '<br>')
            detail.append(f'| {c["id"]} | {title} | {"待出图" if c["enabled"] else "禁用：历史 Apple Watch 卡片"} |')
        detail.append('')
        report.append({'locale':code,'characters':{f:len(r[f]) for f in ['name','subtitle','description']},'utf16Units':{f:size(r[f]) for f in ['name','subtitle','description']},'translatedTitleCount':len(r['screenshotTitles']),'enabledTitleCount':sum(c['enabled'] for c in r['screenshotTitles'])})
    return {'names-and-subtitles.md':'\n'.join(overview)+'\n','copy-review.md':'\n'.join(detail)+'\n','names-and-subtitles.csv':'\ufeff'+csv_file.getvalue(),'validation-report.json':json.dumps({'status':'passed','checkedAt':'2026-10-02','scope':'Offline structure, locale coverage, length, source-title fidelity and disabled Watch status; not linguistic or visual certification.','localeCount':len(entries),'translatedTitleCount':450,'enabledTitleCount':400,'locales':report},ensure_ascii=False,indent=2)+'\n'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true', help='Rebuild metadata, titles and review outputs from locales/*.json')
    args = parser.parse_args()
    entries = load_localizations()
    errors = check(entries)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    bundle = read_json(ROOT / 'metadata.json')
    titles = {'schemaVersion':1,'status':'text-only-draft','source':'metadata.json','localizations':[{k:r[k] for k in ['locale','iosLocale','direction','screenshotTitles']} for r in entries]}
    mapping = read_json(ROOT / 'locale-map.json')
    if {r['locale']:r['iosLocale'] for r in mapping['locales']} != {r['locale']:r['iosLocale'] for r in entries}:
        print('locale-map.json disagrees with locale files', file=sys.stderr)
        return 1
    if args.refresh:
        bundle['localizations'] = entries
        (ROOT / 'metadata.json').write_text(json.dumps(bundle,ensure_ascii=False,indent=2)+'\n')
        (ROOT / 'screenshot-titles.json').write_text(json.dumps(titles,ensure_ascii=False,indent=2)+'\n')
        for filename, content in derived(entries).items():
            (ROOT / filename).write_text(content)
    else:
        if bundle['localizations'] != entries or read_json(ROOT / 'screenshot-titles.json') != titles:
            print('Derived JSON is stale; run validate.py --refresh', file=sys.stderr)
            return 1
    print(f'PASS: {len(entries)} store locales / 47 iOS locales; 450 titles (400 enabled, 50 legacy Watch); all metadata within limits.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
