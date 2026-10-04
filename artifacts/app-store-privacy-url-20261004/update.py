#!/usr/bin/env python3
"""Set the English privacy URL on non-Chinese App Info draft localizations."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from app_store_localization import API, write_json

APP_ID = '6759768784'
EXPECTED_BUNDLE = 'com.douhua.jifen.ios'
PRIVACY_URL = 'https://jifenqi.com/en/privacy'
EXCLUDED = {'zh-Hans', 'zh-Hant'}


def main():
    config_path = Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json')
    config = json.loads(config_path.read_text())
    api = API(config_path.parent / config['privateKeyFile'], config['keyId'], config['issuerId'])
    app = api.request('GET', '/apps/' + APP_ID)['data']
    if app['attributes']['bundleId'] != EXPECTED_BUNDLE:
        raise ValueError('Unexpected app bundle ID')
    infos = api.list('/apps/' + APP_ID + '/appInfos')
    editable = [r for r in infos if r['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION']
    if len(editable) != 1:
        raise ValueError('Expected one App Info draft')
    info = editable[0]
    path = '/appInfos/' + info['id'] + '/appInfoLocalizations'
    before = api.list(path)
    locales = {r['attributes']['locale'] for r in before}
    if len(before) != 50 or not EXCLUDED.issubset(locales):
        raise ValueError('Unexpected locale inventory')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    write_json(HERE / f'before-{stamp}.json', {'app': app, 'appInfo': info, 'localizations': before})
    report = {'appId': APP_ID, 'appInfoId': info['id'], 'startedAt': stamp,
              'expectedURL': PRIVACY_URL, 'excludedLocales': sorted(EXCLUDED),
              'submittedForReview': False, 'results': []}
    for index, row in enumerate(before, 1):
        code = row['attributes']['locale']
        if code in EXCLUDED:
            action = 'preserved'
        elif row['attributes'].get('privacyPolicyUrl') == PRIVACY_URL:
            action = 'unchanged'
        else:
            api.request('PATCH', '/appInfoLocalizations/' + row['id'], {
                'data': {'type': 'appInfoLocalizations', 'id': row['id'],
                         'attributes': {'privacyPolicyUrl': PRIVACY_URL}}})
            action = 'PATCH'
        report['results'].append({'locale': code, 'action': action})
        write_json(HERE / 'verification.json', report)
        if index % 10 == 0:
            print(f'{index}/50 App Info locales processed.', flush=True)
    after = api.list(path)
    after_map = {r['attributes']['locale']: r for r in after}
    mismatch = []
    other_changes = []
    if set(after_map) != locales:
        mismatch.append({'reason': 'locale inventory changed'})
    for row in before:
        code = row['attributes']['locale']
        actual = after_map.get(code, {}).get('attributes', {})
        expected = row['attributes']['privacyPolicyUrl'] if code in EXCLUDED else PRIVACY_URL
        if actual.get('privacyPolicyUrl') != expected:
            mismatch.append({'locale': code, 'field': 'privacyPolicyUrl'})
        for field, value in row['attributes'].items():
            if field != 'privacyPolicyUrl' and actual.get(field) != value:
                other_changes.append({'locale': code, 'field': field})
    info_after = api.request('GET', '/appInfos/' + info['id'])['data']
    report.update({'completedAt': datetime.now(timezone.utc).isoformat(),
                   'verifiedLocaleCount': len(after),
                   'verifiedEnglishURLCount': sum(r['attributes']['privacyPolicyUrl'] == PRIVACY_URL for r in after if r['attributes']['locale'] not in EXCLUDED),
                   'changedLocaleCount': sum(r['action'] == 'PATCH' for r in report['results']),
                   'preservedChineseURLs': {code: after_map[code]['attributes']['privacyPolicyUrl'] for code in sorted(EXCLUDED)},
                   'mismatches': mismatch, 'otherFieldChanges': other_changes,
                   'appInfoStateUnchanged': info_after['attributes'] == info['attributes']})
    report['verified'] = not mismatch and not other_changes and report['appInfoStateUnchanged'] and report['verifiedEnglishURLCount'] == 48
    write_json(HERE / 'after.json', {'appInfo': info_after, 'localizations': after})
    write_json(HERE / 'verification.json', report)
    print('Verified:', report['verified'], 'English URLs:', report['verifiedEnglishURLCount'],
          'Changed:', report['changedLocaleCount'], flush=True)
    if not report['verified']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
