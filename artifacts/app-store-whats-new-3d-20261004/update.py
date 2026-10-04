#!/usr/bin/env python3
"""Update only six What's New fields, then verify all 50 localizations."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
COPY = ROOT / 'marketing/app-store/whats-new-3.2.3-2026-10-04'
sys.path.insert(0, str(ROOT / 'scripts'))
from app_store_localization import API

APP = '6759768784'
VERSION = 'a118dc62-4303-4c03-ae92-b358c60438d5'
FIRST_LINES = {
    'en-US': 'Refreshed the interface with new 3D sports and tool icons.',
    'en-GB': 'Refreshed the interface with new 3D sports and tool icons.',
    'en-CA': 'Refreshed the interface with new 3D sports and tool icons.',
    'en-AU': 'Refreshed the interface with new 3D sports and tool icons.',
    'zh-Hans': '全新 3D 运动与工具图标，让界面更生动直观。',
    'zh-Hant': '全新 3D 運動與工具圖示，讓介面更生動直覺。',
}

def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

def main():
    config_path = Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json')
    config = json.loads(config_path.read_text())
    api = API(config_path.parent / config['privateKeyFile'], config['keyId'], config['issuerId'])
    app = api.request('GET', f'/apps/{APP}')['data']
    version = api.request('GET', f'/appStoreVersions/{VERSION}')['data']
    assert app['attributes']['bundleId'] == 'com.douhua.jifen.ios'
    assert version['attributes']['versionString'] == '3.2.3'
    assert version['attributes']['platform'] == 'IOS'
    assert version['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION'
    path = f'/appStoreVersions/{VERSION}/appStoreVersionLocalizations'
    before = api.list(path)
    current = {x['attributes']['locale']: x for x in before}
    original = json.loads((OUT / 'before.json').read_text())
    original_map = {x['attributes']['locale']: x for x in original['localizations']}
    assert len(current) == 50
    notes = {}
    for locale, first_line in FIRST_LINES.items():
        previous = original_map[locale]['attributes']['whatsNew']
        notes[locale] = first_line + '\n' + previous
        assert current[locale]['attributes']['whatsNew'] in (previous, notes[locale]), f'Unexpected concurrent edit: {locale}'
        assert len(notes[locale].encode('utf-16-le')) // 2 <= 4000
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = f'before-{stamp}.json'
    save(OUT / backup, {'app': app, 'appStoreVersion': version, 'localizations': before})
    COPY.mkdir(parents=True, exist_ok=True)
    save(COPY / 'metadata.json', {'appId': APP, 'appStoreVersionId': VERSION, 'version': '3.2.3', 'localizations': [{'locale': k, 'whatsNew': v} for k, v in notes.items()]})
    md = ['# iOS 3.2.3 — What’s New', '', '2026-10-04：仅更新英文四个地区、简体中文和繁体中文的 What’s New。以 App Store Connect 现有内容为基础，第一条补充新 3D 图标，其余条目保留。', '', '这是当前 3.2.3 的六语言更新源；`localization-2026-10-02/release-fields-3.3.*` 为较早材料。', '']
    for locale, value in notes.items():
        md += [f'## {locale}', '', value, '']
    md += ['已通过 API 保存至 App Store Connect 草稿，回读校验见 [verification.json](../../../artifacts/app-store-whats-new-3d-20261004/verification.json)。']
    (COPY / 'README.md').write_text('\n'.join(md) + '\n')
    report = {'appId': APP, 'version': '3.2.3', 'backup': backup, 'results': [], 'errors': [], 'submittedForReview': False}
    for locale, value in notes.items():
        row = current[locale]
        try:
            _, action = api.upsert('appStoreVersionLocalizations', 'appStoreVersion', VERSION, locale, {'whatsNew': value}, row)
            report['results'].append({'locale': locale, 'id': row['id'], 'action': action})
            print(f'{locale}: {action}', flush=True)
        except Exception as error:
            report['errors'].append({'locale': locale, 'error': str(error)})
        save(OUT / 'update-report.json', report)
    after = api.list(path)
    version_after = api.request('GET', f'/appStoreVersions/{VERSION}')['data']
    save(OUT / 'after.json', {'appStoreVersion': version_after, 'localizations': after})
    after_map = {x['attributes']['locale']: x for x in after}
    mismatches = []
    other_changes = []
    if set(current) != set(after_map):
        mismatches.append('Locale inventory changed')
    for locale, old in current.items():
        new = after_map.get(locale)
        if not new:
            mismatches.append(f'Missing locale: {locale}')
            continue
        expected = dict(old['attributes'])
        if locale in notes:
            expected['whatsNew'] = notes[locale]
        if new['id'] != old['id']:
            mismatches.append(f'Changed resource ID: {locale}')
        for key in set(expected) | set(new['attributes']):
            if expected.get(key) != new['attributes'].get(key):
                change = {'locale': locale, 'field': key}
                (mismatches if key == 'whatsNew' else other_changes).append(change)
    version_unchanged = version_after['attributes'] == version['attributes']
    verification = {'verified': not report['errors'] and not mismatches and not other_changes and version_unchanged, 'appId': APP, 'version': '3.2.3', 'verifiedLocales': list(notes), 'verifiedLocaleCount': len(notes), 'untouchedLocaleCount': len(current) - len(notes), 'mismatches': mismatches, 'otherFieldChanges': other_changes, 'versionAttributesUnchanged': version_unchanged, 'appStoreState': version_after['attributes']['appStoreState'], 'submittedForReview': False, 'completedAt': datetime.now(timezone.utc).isoformat()}
    save(OUT / 'verification.json', verification)
    report['verified'] = verification['verified']
    save(OUT / 'update-report.json', report)
    print(json.dumps(verification, ensure_ascii=False), flush=True)
    return 0 if verification['verified'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
