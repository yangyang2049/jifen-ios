"""Plan or apply the prepared zh-Hant listing to the editable iOS version."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import app_store_screenshots as asc

ROOT = Path(__file__).resolve().parents[1]
CREDS = Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json')
LOCALE = 'zh-Hant'


def update_listing(api, row, *, apply=False, out_dir=None):
    app = api.request('GET', f'/apps/{asc.TARGET_APP}')['data']
    if app['attributes'].get('bundleId') != asc.TARGET_BUNDLE:
        raise RuntimeError('Unexpected app bundle; no metadata changed')
    versions = [x for x in api.list(f'/apps/{asc.TARGET_APP}/appStoreVersions')
                if x['attributes'].get('platform') == 'IOS'
                and x['attributes'].get('versionString') == asc.TARGET_VERSION]
    infos = [x for x in api.list(f'/apps/{asc.TARGET_APP}/appInfos')
             if x['attributes'].get('appStoreState') in asc.EDITABLE]
    if len(versions) != 1 or versions[0]['attributes'].get('appStoreState') not in asc.EDITABLE or len(infos) != 1:
        raise RuntimeError('Expected one editable AppInfo and iOS version; no metadata changed')
    info_id, version_id = infos[0]['id'], versions[0]['id']
    info_path = f'/appInfos/{info_id}/appInfoLocalizations'
    version_path = f'/appStoreVersions/{version_id}/appStoreVersionLocalizations'
    info_before, version_before = api.list(info_path), api.list(version_path)
    fields = {'name': row['name'], 'subtitle': row['subtitle']}
    version_fields = {'description': row['description']}
    if row.get('promotionalText'):
        version_fields['promotionalText'] = row['promotionalText']
    if not apply:
        return {'applied': False, 'version': asc.TARGET_VERSION, 'locale': LOCALE,
                'appInfo': fields, 'appStoreVersion': version_fields}
    if out_dir is None:
        raise RuntimeError('A backup directory is required before writing')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    asc.save(out_dir / f'before-{stamp}.json', {'appInfoId': info_id, 'versionId': version_id,
                                             'appInfoLocalizations': info_before,
                                             'appStoreVersionLocalizations': version_before})
    existing = next((x for x in info_before if x['attributes']['locale'] == LOCALE), None)
    api.upsert('appInfoLocalizations', 'appInfo', info_id, LOCALE, fields, existing)
    # Creating an AppInfo locale can create its version counterpart as well.
    existing = next((x for x in api.list(version_path) if x['attributes']['locale'] == LOCALE), None)
    api.upsert('appStoreVersionLocalizations', 'appStoreVersion', version_id, LOCALE,
               version_fields, existing)
    for path, expected in [(info_path, fields), (version_path, version_fields)]:
        actual = next((x['attributes'] for x in api.list(path)
                       if x['attributes']['locale'] == LOCALE), {})
        if any(actual.get(k) != value for k, value in expected.items()):
            raise RuntimeError('zh-Hant listing readback mismatch')
    return {'applied': True, 'verified': True, 'version': asc.TARGET_VERSION, 'locale': LOCALE}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--credentials', type=Path, default=CREDS)
    parser.add_argument('--out-dir', type=Path, default=ROOT / 'artifacts/zh-hant-listing')
    args = parser.parse_args()
    meta = json.loads((ROOT / 'marketing/app-store/localization-2026-10-02/metadata.json').read_text())
    row = next(x for x in meta['localizations'] if x['locale'] == LOCALE)
    config = json.loads(args.credentials.read_text())
    key = Path(config['privateKeyFile']).expanduser()
    config['privateKeyFile'] = str(key if key.is_absolute() else args.credentials.resolve().parent / key)
    api = asc.make_api(config)
    try:
        print(json.dumps(update_listing(api, row, apply=args.apply, out_dir=args.out_dir), ensure_ascii=False))
    finally:
        api.session.close()


if __name__ == '__main__':
    main()
