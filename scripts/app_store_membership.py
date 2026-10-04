#!/usr/bin/env python3
"""Localize the three existing VIP products and their group in metadata drafts.

Uses Apple's version-based API. Never submits review, promotes a purchase,
changes pricing/availability, or edits the released app. JWTs stay in memory.
"""
import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests
from PIL import Image
from app_store_localization import API

HOST = 'https://api.appstoreconnect.apple.com'
APP_ID = '6759768784'
BUNDLE_ID = 'com.douhua.jifen.ios'
TARGETS = {
    'lifetime': {'id': '6807102027', 'parent': 'inAppPurchases', 'api': 'v2',
                 'productId': 'iscoreboard_lifetime_vip', 'relation': 'inAppPurchase',
                 'versionType': 'inAppPurchaseVersions', 'localeType': 'inAppPurchaseLocalizations',
                 'imageType': 'inAppPurchaseImages'},
    'monthly': {'id': '6807103111', 'parent': 'subscriptions', 'api': 'v1',
                'productId': 'iscoreboard_monthly_vip', 'relation': 'subscription',
                'versionType': 'subscriptionVersions', 'localeType': 'subscriptionLocalizations',
                'imageType': 'subscriptionImages', 'period': 'ONE_MONTH'},
    'yearly': {'id': '6807106491', 'parent': 'subscriptions', 'api': 'v1',
               'productId': 'iscoreboard_yearly_vip', 'relation': 'subscription',
               'versionType': 'subscriptionVersions', 'localeType': 'subscriptionLocalizations',
               'imageType': 'subscriptionImages', 'period': 'ONE_YEAR'},
    'group': {'id': '22348946', 'parent': 'subscriptionGroups', 'api': 'v1',
              'relation': 'subscriptionGroup', 'versionType': 'subscriptionGroupVersions',
              'localeType': 'subscriptionGroupLocalizations'},
}


def save(path, value):
    def clean(x):
        if isinstance(x, dict):
            return {k: clean(v) for k, v in x.items() if k != 'uploadOperations'}
        if isinstance(x, list):
            return [clean(v) for v in x]
        return x
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(clean(value), ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


class Error(RuntimeError):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


class Client:
    def __init__(self, config_path):
        config = json.loads(config_path.read_text())
        self.auth = API(config_path.parent / config['privateKeyFile'], config['keyId'], config['issuerId'])

    def request(self, method, path, data=None):
        url = path if path.startswith('https://') else HOST + path
        parsed = urlparse(url)
        if parsed.scheme != 'https' or parsed.netloc != 'api.appstoreconnect.apple.com' or not parsed.path.startswith(('/v1/', '/v2/')):
            raise ValueError('Credentials may only be sent to the Apple API host')
        # The mutation surface is deliberately limited to draft metadata/assets.
        if method != 'GET':
            kind = parsed.path.split('/')[2]
            allowed = {t['versionType'] for t in TARGETS.values()} | {t['localeType'] for t in TARGETS.values()} | {'inAppPurchaseImages', 'subscriptionImages'}
            if method not in {'POST', 'PATCH'} or kind not in allowed:
                raise ValueError('Refusing a mutation outside membership draft metadata')
        self.auth.authenticate()
        for attempt in range(4):
            response = self.auth.session.request(method, url, json=data, timeout=40, allow_redirects=False)
            if response.status_code == 429 and attempt < 3:
                time.sleep(min(20, max(1, int(response.headers.get('Retry-After', 2 ** attempt)))))
                continue
            if not response.ok:
                try:
                    errors = [{k: e.get(k) for k in ['code', 'detail', 'source']} for e in response.json().get('errors', [])]
                except ValueError:
                    errors = [{'code': 'NON_JSON_RESPONSE'}]
                raise Error(response.status_code, f'{method} {parsed.path}: HTTP {response.status_code}: {json.dumps(errors, ensure_ascii=False)}')
            return response.json() if response.content else {}
        raise RuntimeError('Rate-limit retries exhausted')

    def list(self, path):
        url = path + ('&' if '?' in path else '?') + 'limit=200'
        rows = []
        while url:
            response = self.request('GET', url)
            rows.extend(response['data'])
            url = response.get('links', {}).get('next')
        return rows

    def create(self, path, payload, list_path, matches):
        # Reconcile uncertain POST outcomes through GET before attempting again.
        for attempt in range(3):
            try:
                return self.request('POST', path, payload)['data']
            except (requests.RequestException, Error) as error:
                if isinstance(error, Error) and error.status not in {409, 429, 500, 502, 503, 504}:
                    raise
                current = [r for r in self.list(list_path) if matches(r)]
                if len(current) == 1:
                    return current[0]
                if current or attempt == 2:
                    raise
        raise RuntimeError('Uncertain POST could not be reconciled')


def parent_path(target):
    return f"/{target['api']}/{target['parent']}/{target['id']}"


def version_path(target, version_id):
    return f"/v1/{target['versionType']}/{version_id}"


def inspect(client):
    app = client.request('GET', f'/v1/apps/{APP_ID}')['data']
    if app['attributes']['bundleId'] != BUNDLE_ID:
        raise ValueError('Unexpected app bundle ID')
    snapshot = {'app': app, 'targets': {}}
    for label, target in TARGETS.items():
        parent = client.request('GET', parent_path(target))['data']
        attributes = parent['attributes']
        if target.get('productId') and attributes['productId'] != target['productId']:
            raise ValueError(f'Unexpected {label} product ID')
        if target.get('period') and attributes['subscriptionPeriod'] != target['period']:
            raise ValueError(f'Unexpected {label} subscription period')
        if label == 'lifetime' and attributes['inAppPurchaseType'] != 'NON_CONSUMABLE':
            raise ValueError('Lifetime product must be non-consumable')
        versions = client.list(parent_path(target) + '/versions')
        item = {'parent': parent, 'versions': versions, 'metadata': {}}
        for version in versions:
            path = version_path(target, version['id'])
            item['metadata'][version['id']] = {'localizations': client.list(path + '/localizations')}
            if label != 'group':
                item['metadata'][version['id']]['images'] = client.list(path + '/images')
        snapshot['targets'][label] = item
    return snapshot


def draft_for(client, target, before):
    versions_path = parent_path(target) + '/versions'
    drafts = [r for r in before['versions'] if r['attributes']['state'] == 'PREPARE_FOR_SUBMISSION']
    if len(drafts) > 1:
        raise RuntimeError('More than one editable metadata draft; refusing to choose')
    if drafts:
        return drafts[0], 'reused'
    if any(r['attributes']['state'] in {'READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW'} for r in before['versions']):
        raise RuntimeError('A metadata version is currently in review')
    payload = {'data': {'type': target['versionType'], 'relationships': {
        target['relation']: {'data': {'type': target['parent'], 'id': target['id']}}
    }}}
    draft = client.create('/v1/' + target['versionType'], payload, versions_path,
                          lambda r: r['attributes']['state'] == 'PREPARE_FOR_SUBMISSION')
    return draft, 'created'


def upload_image(client, target, draft, path):
    with Image.open(path) as image:
        if image.size != (1024, 1024) or image.mode not in {'RGB', 'RGBA'}:
            raise ValueError(f'Expected a 1024x1024 RGB promotional image: {path}')
        if image.mode == 'RGBA' and image.getchannel('A').getextrema() != (255, 255):
            raise ValueError('Promotional images must be opaque')
    content = path.read_bytes()
    checksum = hashlib.md5(content).hexdigest()
    remote_name = f'{path.stem}-{checksum[:10]}{path.suffix}'
    kind = target['imageType']
    list_path = version_path(target, draft['id']) + '/images'
    existing = client.list(list_path)
    matches = [r for r in existing if r['attributes'].get('fileName') == remote_name]
    if len(matches) > 1 or (existing and not matches):
        raise RuntimeError('Unexpected existing draft image; refusing to replace it')
    if matches:
        resource = matches[0]
    else:
        payload = {'data': {'type': kind, 'attributes': {'fileName': remote_name, 'fileSize': len(content)},
                            'relationships': {'version': {'data': {'type': target['versionType'], 'id': draft['id']}}}}}
        resource = client.create('/v2/' + kind, payload, list_path,
                                 lambda r: r['attributes'].get('fileName') == remote_name)
    resource_path = f"/v2/{kind}/{resource['id']}"
    attributes = resource['attributes']
    state = attributes.get('assetDeliveryState', {}).get('state')
    if state not in {'COMPLETE', 'UPLOAD_COMPLETE'}:
        # Use a clean request session for Apple's presigned storage URLs. Never
        # forward the JWT or print/store these URLs or their upload headers.
        for op in attributes.get('uploadOperations', []):
            if urlparse(op['url']).scheme != 'https':
                raise ValueError('Upload operation must use HTTPS')
            headers = {h['name']: h['value'] for h in op['requestHeaders']}
            chunk = content[op['offset']:op['offset'] + op['length']]
            if len(chunk) != op['length']:
                raise ValueError('Invalid upload operation range')
            response = requests.request(op['method'], op['url'], headers=headers, data=chunk,
                                        timeout=60, allow_redirects=False)
            if not response.ok:
                raise RuntimeError(f'Asset storage upload failed: HTTP {response.status_code}')
        client.request('PATCH', resource_path, {'data': {'type': kind, 'id': resource['id'],
                       'attributes': {'uploaded': True}}})
    resource = client.request('GET', resource_path)['data']
    return {'id': resource['id'], 'path': str(path), 'md5': checksum, 'resource': resource}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--images', action='store_true')
    args = parser.parse_args()
    metadata_bytes = args.metadata.read_bytes()
    metadata = json.loads(metadata_bytes)
    rows = metadata['localizations']
    locales = {r['locale'] for r in rows}
    if metadata['appId'] != APP_ID or metadata['bundleId'] != BUNDLE_ID or len(rows) != 50 or len(locales) != 50:
        raise ValueError('Unexpected localization target or locale inventory')
    for row in rows:
        for label in ['monthly', 'yearly', 'lifetime']:
            for field, limit in [('name', 30), ('description', 45)]:
                value = row[label][field]
                if not value or len(value.encode('utf-16-le')) // 2 > limit:
                    raise ValueError(f"Invalid {row['locale']} {label} {field}")
    client = Client(args.config)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    before = inspect(client)
    save(args.out_dir / f'before-{stamp}.json', before)
    if not args.apply:
        print('Read-only inventory backed up; target: 3 VIP products and 1 group, 50 locales.')
        return
    report = {'appId': APP_ID, 'bundleId': BUNDLE_ID, 'startedAt': stamp, 'localeCount': 50,
              'metadataSHA256': hashlib.sha256(metadata_bytes).hexdigest(),
              'submittedForReview': False, 'promotedPurchasesChanged': False,
              'pricingChanged': False, 'targets': {}, 'errors': []}
    for label, target in TARGETS.items():
        entry = report['targets'][label] = {'productId': target.get('productId'), 'updates': [], 'image': None}
        try:
            draft, action = draft_for(client, target, before['targets'][label])
            entry.update({'draftId': draft['id'], 'draftAction': action})
            path = version_path(target, draft['id'])
            current = {r['attributes']['locale']: r for r in client.list(path + '/localizations')}
            for index, row in enumerate(rows, 1):
                fields = row[label]
                existing = current.get(row['locale'])
                if existing and all(existing['attributes'].get(k) == v for k, v in fields.items()):
                    action = 'unchanged'
                elif existing:
                    client.request('PATCH', f"/v2/{target['localeType']}/{existing['id']}",
                                   {'data': {'type': target['localeType'], 'id': existing['id'], 'attributes': fields}})
                    action = 'PATCH'
                else:
                    payload = {'data': {'type': target['localeType'], 'attributes': {'locale': row['locale'], **fields},
                                        'relationships': {'version': {'data': {'type': target['versionType'], 'id': draft['id']}}}}}
                    current[row['locale']] = client.create('/v2/' + target['localeType'], payload, path + '/localizations',
                                                           lambda r, locale=row['locale']: r['attributes']['locale'] == locale)
                    action = 'POST'
                entry['updates'].append({'locale': row['locale'], 'action': action})
                save(args.out_dir / 'upload-report.json', report)
                if index % 10 == 0:
                    print(f'{label}: {index}/50 locales saved.', flush=True)
            if args.images and label != 'group':
                entry['image'] = upload_image(client, target, draft, args.metadata.parent / 'images' / f'{label}.png')
                print(f'{label}: promotional image uploaded.', flush=True)
        except (RuntimeError, ValueError, requests.RequestException) as error:
            entry['error'] = str(error)
            report['errors'].append({'target': label, 'error': str(error)})
            print(f'{label}: ERROR: {error}', flush=True)
        save(args.out_dir / 'upload-report.json', report)
    after = inspect(client)
    save(args.out_dir / f'after-{stamp}.json', after)
    mismatches = []
    for label, entry in report['targets'].items():
        draft_id = entry.get('draftId')
        if not draft_id:
            mismatches.append({'target': label, 'reason': 'draft missing'})
            continue
        actual_rows = after['targets'][label]['metadata'][draft_id]['localizations']
        actual = {r['attributes']['locale']: r for r in actual_rows}
        for row in rows:
            for field, value in row[label].items():
                if actual.get(row['locale'], {}).get('attributes', {}).get(field) != value:
                    mismatches.append({'target': label, 'locale': row['locale'], 'field': field})
        if set(actual) != locales:
            mismatches.append({'target': label, 'reason': 'locale inventory differs'})
        versions = after['targets'][label]['versions']
        draft_state = next(r['attributes']['state'] for r in versions if r['id'] == draft_id)
        entry['draftState'] = draft_state
        entry['verifiedLocaleCount'] = len(actual)
        if draft_state != 'PREPARE_FOR_SUBMISSION':
            mismatches.append({'target': label, 'reason': 'draft state changed unexpectedly'})
        if args.images and label != 'group':
            images = after['targets'][label]['metadata'][draft_id]['images']
            entry['imageStates'] = [r['attributes'].get('assetDeliveryState') for r in images]
            if len(images) != 1 or not entry.get('image'):
                mismatches.append({'target': label, 'reason': 'promotional image missing'})
            else:
                a = images[0]['attributes']
                expected_name = f"{label}-{entry['image']['md5'][:10]}.png"
                if a.get('fileName') != expected_name or a.get('fileSize') != Path(entry['image']['path']).stat().st_size or a.get('assetDeliveryState', {}).get('state') != 'COMPLETE':
                    mismatches.append({'target': label, 'reason': 'image file identity, size or processing state differs'})
        # Check stable product configuration and each previously approved
        # metadata version, including the currently available English/Chinese.
        if before['targets'][label]['parent']['attributes'] != after['targets'][label]['parent']['attributes']:
            mismatches.append({'target': label, 'reason': 'parent attributes changed'})
        for version in before['targets'][label]['versions']:
            if version['attributes']['state'] == 'APPROVED':
                previous_id = version['id']
                if before['targets'][label]['metadata'][previous_id] != after['targets'][label]['metadata'][previous_id]:
                    mismatches.append({'target': label, 'reason': 'approved metadata changed'})
                current_version = next(r for r in versions if r['id'] == previous_id)
                if current_version['attributes'] != version['attributes']:
                    mismatches.append({'target': label, 'reason': 'approved version state changed'})
    report['mismatches'] = mismatches
    report['verified'] = not report['errors'] and not mismatches
    report['completedAt'] = datetime.now(timezone.utc).isoformat()
    save(args.out_dir / 'upload-report.json', report)
    print(f"Verified: {report['verified']}; errors={len(report['errors'])}; mismatches={len(mismatches)}", flush=True)
    if not report['verified']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
