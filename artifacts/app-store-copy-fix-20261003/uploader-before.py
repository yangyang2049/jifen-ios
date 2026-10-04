#!/usr/bin/env python3
"""Plan, upload, resume, and verify iOS localized App Store screenshots.

Default invocation is read-only. --apply uploads PNGs, without submitting a
version for review. Only APP_IPHONE_65 sets of the selected manifest locales
can be changed. zh-Hans, zh-Hant, and all other display targets are protected.

Official Apple API references checked 2026-10-02:
https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect
https://developer.apple.com/documentation/appstoreconnectapi/app-screenshot-sets
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
"""
import argparse
import hashlib
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

import requests
from PIL import Image

from app_store_localization import API as AuthAPI, BASE, EDITABLE

ROOT = Path(__file__).resolve().parents[1]
TARGET_APP = '6759768784'
TARGET_BUNDLE = 'com.douhua.jifen.ios'
TARGET_VERSION = '3.2.3'  # renamed from 3.3 on ASC 2026-10-03; version id unchanged (a118dc62-…)
TARGET_DISPLAY = 'APP_IPHONE_65'
PROTECTED = {'zh-Hans'}
PRINT_LOCK = threading.Lock()


def now():
    return datetime.now(timezone.utc).isoformat()


def say(message):
    with PRINT_LOCK:
        print(message, flush=True)


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def state(resource):
    return (resource.get('attributes', {}).get('assetDeliveryState') or {}).get('state')


def checksum(resource):
    return (resource.get('attributes', {}).get('sourceFileChecksum') or '').lower()


def snapshot(resource):
    """Persist only public metadata; never upload URLs, JWTs, or headers."""
    attrs = resource.get('attributes', {})
    allowed = ('locale', 'screenshotDisplayType', 'fileName', 'fileSize',
               'sourceFileChecksum', 'assetDeliveryState')
    clean = {k: attrs[k] for k in allowed if k in attrs}
    if isinstance(clean.get('assetDeliveryState'), dict):
        clean['assetDeliveryState'] = {
            'state': clean['assetDeliveryState'].get('state'),
            'errorCodes': [x.get('code') for x in
                           (clean['assetDeliveryState'].get('errors') or [])]}
    asset = attrs.get('imageAsset')
    if asset:
        clean['imageAsset'] = {k: asset[k] for k in ('width', 'height') if k in asset}
    return {'id': resource['id'], 'type': resource['type'], 'attributes': clean}


class APIError(RuntimeError):
    def __init__(self, method, path, status=None, codes=None, network=False):
        self.status = status
        self.network = network
        self.codes = codes or []
        # Deliberately omit server detail and exception text, which can contain
        # presigned URLs or other material not suitable for persistent logs.
        super().__init__('{} {}: {}{}'.format(
            method, path, 'temporary network error' if network else 'HTTP ' + str(status),
            ' (' + ', '.join(self.codes) + ')' if self.codes else ''))


class VerificationError(RuntimeError):
    def __init__(self, message, resources=(), expected_ids=None):
        super().__init__(message)
        # Only snapshot()'s public metadata is persisted, never complete API
        # responses containing image URLs or upload authorization.
        self.diagnostics = {'observedResources': [snapshot(x) for x in resources]}
        if expected_ids is not None:
            self.diagnostics['expectedIds'] = list(expected_ids)


def retry_delay(response, attempt):
    try:
        return min(30, max(1, float(response.headers.get('Retry-After', 2 ** attempt))))
    except (TypeError, ValueError):
        return min(30, 2 ** attempt)


class API(AuthAPI):
    def request(self, method, path, body=None):
        url = path if path.startswith('https://') else BASE + path
        parsed = urlsplit(url)
        if (parsed.scheme != 'https' or parsed.netloc != 'api.appstoreconnect.apple.com'
                or not parsed.path.startswith('/v1/') or parsed.username or parsed.password):
            raise RuntimeError('Refusing an API request outside the official HTTPS API')
        safe_path = parsed.path
        attempts = 1 if method == 'POST' else 6
        for attempt in range(attempts):
            self.authenticate()
            try:
                response = self.session.request(method, url, json=body, timeout=(20, 80),
                                                allow_redirects=False)
            except requests.RequestException:
                if attempt + 1 == attempts:
                    raise APIError(method, safe_path, network=True) from None
                time.sleep(min(20, 2 ** attempt))
                continue
            if response.status_code == 204:
                return {}
            if response.ok:
                try:
                    return response.json()
                except ValueError:
                    raise APIError(method, safe_path, status=response.status_code,
                                   codes=['INVALID_RESPONSE'], network=True) from None
            if response.status_code == 429 or response.status_code >= 500:
                if attempt + 1 < attempts:
                    time.sleep(retry_delay(response, attempt))
                    continue
            try:
                codes = [str(x.get('code', 'UNKNOWN'))
                         for x in response.json().get('errors', [])]
            except ValueError:
                codes = ['NON_JSON_RESPONSE']
            raise APIError(method, safe_path, response.status_code, codes)
        raise RuntimeError('API retries exhausted')


def make_api(config):
    return API(Path(config['privateKeyFile']).expanduser(), config['keyId'],
               config.get('issuerId'))


def read_images(manifest_path, selected):
    manifest = json.loads(manifest_path.read_text())
    rows = manifest['localizations']
    codes = [x['locale'] for x in rows]
    if len(codes) != 49 or len(set(codes)) != 49 or set(codes) & PROTECTED:
        raise RuntimeError('Manifest must contain the 49 unique non-zh-Hans locales')
    if selected and set(selected) - set(codes):
        raise RuntimeError('Requested locale is absent from the manifest')
    result = []
    for row in rows:
        if selected and row['locale'] not in selected:
            continue
        if len(row['cards']) != 7:
            raise RuntimeError('{}: expected seven screenshots'.format(row['locale']))
        images = []
        for index, card in enumerate(row['cards'], 1):
            path = (manifest_path.parent / card['file']).resolve()
            if manifest_path.parent.resolve() not in path.parents or path.suffix != '.png':
                raise RuntimeError('Screenshot path must be a PNG inside the export directory')
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if digest != card['sha256']:
                raise RuntimeError('{} image {}: manifest SHA256 mismatch'.format(row['locale'], index))
            with Image.open(path) as image:
                if image.format != 'PNG' or image.size != (1284, 2778):
                    raise RuntimeError('{} image {}: expected PNG 1284x2778'.format(row['locale'], index))
                if (image.mode in ('RGBA', 'LA', 'PA') or 'transparency' in image.info):
                    # These exports retain an all-255 alpha channel. Apple has
                    # accepted the unchanged canary PNG. Reject actual transparency.
                    if image.convert('RGBA').getchannel('A').getextrema() != (255, 255):
                        raise RuntimeError('{} image {}: PNG contains transparency'.format(row['locale'], index))
                image.load()
            md5 = hashlib.md5(data).hexdigest()
            images.append({'index': index, 'path': str(path), 'sha256': digest,
                           'md5': md5, 'fileSize': len(data), 'width': 1284, 'height': 2778,
                           'fileName': '{}-{:02d}-{}.png'.format(row['locale'], index, md5[:16])})
        result.append({'locale': row['locale'], 'images': images})
    return result


def inventory_locale(api, localization):
    sets = api.list('/appStoreVersionLocalizations/{}/appScreenshotSets'.format(localization['id']))
    result = {'locale': localization['attributes']['locale'], 'localizationId': localization['id'], 'sets': []}
    for resource in sets:
        images = api.list('/appScreenshotSets/{}/appScreenshots'.format(resource['id']))
        result['sets'].append({'set': snapshot(resource), 'screenshots': [snapshot(x) for x in images]})
    return result


def inventory_all(config, localizations, jobs):
    result = {}
    def fetch(localization):
        api = make_api(config)
        try:
            return inventory_locale(api, localization)
        finally:
            api.session.close()
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        pending = [executor.submit(fetch, x) for x in localizations]
        for future in as_completed(pending):
            item = future.result()
            result[item['locale']] = item
    return result


def target_set(locale_inventory):
    targets = [x for x in locale_inventory['sets']
               if x['set']['attributes']['screenshotDisplayType'] == TARGET_DISPLAY]
    if len(targets) > 1:
        raise RuntimeError('Duplicate 6.5-inch screenshot sets require inspection')
    return targets[0] if targets else None


def uncertain(error):
    return error.network or error.status == 429 or error.status == 409 or (
        error.status is not None and error.status >= 500)


def reconciled_post(api, path, body, find):
    """Re-read the parent after an unknown POST result before another POST."""
    for attempt in range(5):
        existing = find()
        if existing:
            return existing
        try:
            return api.request('POST', path, body)['data']
        except APIError as error:
            if not uncertain(error):
                raise
            for read in range(3):
                time.sleep(min(10, 2 ** (attempt + read)))
                existing = find()
                if existing:
                    return existing
            if attempt == 4:
                raise
    raise RuntimeError('Reservation retries exhausted')


def ensure_set(api, localization_id):
    def find():
        sets = api.list('/appStoreVersionLocalizations/{}/appScreenshotSets'.format(localization_id))
        matches = [x for x in sets if x['attributes']['screenshotDisplayType'] == TARGET_DISPLAY]
        if len(matches) > 1:
            raise RuntimeError('Duplicate target sets')
        return matches[0] if matches else None
    body = {'data': {'type': 'appScreenshotSets',
                     'attributes': {'screenshotDisplayType': TARGET_DISPLAY},
                     'relationships': {'appStoreVersionLocalization': {
                         'data': {'type': 'appStoreVersionLocalizations', 'id': localization_id}}}}}
    return reconciled_post(api, '/appScreenshotSets', body, find)


def list_shots(api, set_id):
    return api.list('/appScreenshotSets/{}/appScreenshots'.format(set_id))


def complete_match(shots, image, used=None):
    used = used or set()
    return next((x for x in shots if x['id'] not in used and state(x) == 'COMPLETE'
                 and checksum(x) == image['md5']), None)


def pending_match(shots, image):
    return next((x for x in shots if x['attributes'].get('fileSize') == image['fileSize']
                 and ((state(x) == 'UPLOAD_COMPLETE' and checksum(x) == image['md5']) or
                      (state(x) == 'AWAITING_UPLOAD' and
                       x['attributes'].get('fileName') == image['fileName']))), None)


def delete_shot(api, set_id, shot_id):
    try:
        api.request('DELETE', '/appScreenshots/' + shot_id)
    except APIError as error:
        if error.status != 404:
            # Idempotent DELETE can finish on Apple's side before connection loss.
            if any(x['id'] == shot_id for x in list_shots(api, set_id)):
                raise


def upload_binary(resource, image):
    data = Path(image['path']).read_bytes()
    if len(data) != image['fileSize'] or hashlib.md5(data).hexdigest() != image['md5']:
        raise RuntimeError('Local binary changed since validation')
    operations = resource['attributes'].get('uploadOperations') or []
    if not operations:
        raise RuntimeError('Reservation lacks upload operations')
    ranges = sorted((int(x['offset']), int(x['length'])) for x in operations)
    position = 0
    for offset, length in ranges:
        if offset != position or length <= 0:
            raise RuntimeError('Upload operations do not cover the binary exactly')
        position += length
    if position != len(data):
        raise RuntimeError('Upload operation size differs from the binary')
    # A completely separate session never inherits App Store authorization.
    with requests.Session() as session:
        session.trust_env = False  # Also prevents implicit .netrc authorization.
        for operation in operations:
            url = operation['url']
            parsed = urlsplit(url)
            if (parsed.scheme != 'https' or not parsed.hostname or parsed.username
                    or parsed.password or parsed.fragment):
                raise RuntimeError('Upload operation must use the given HTTPS URL')
            method = operation['method'].upper()
            if method not in ('PUT', 'POST'):
                raise RuntimeError('Unexpected binary upload method')
            headers = {x['name']: x['value'] for x in operation.get('requestHeaders', [])}
            if any(k.lower() in ('authorization', 'proxy-authorization', 'cookie') for k in headers):
                raise RuntimeError('Unexpected authorization header in upload operation')
            offset, length = int(operation['offset']), int(operation['length'])
            part = data[offset:offset + length]
            for attempt in range(6):
                try:
                    response = session.request(method, url, headers=headers, data=part,
                                               timeout=(20, 120), allow_redirects=False)
                except requests.RequestException:
                    if attempt == 5:
                        raise RuntimeError('Binary upload exhausted temporary network retries') from None
                    time.sleep(min(20, 2 ** attempt))
                    continue
                if response.ok:
                    break
                if (response.status_code == 429 or response.status_code >= 500) and attempt < 5:
                    time.sleep(retry_delay(response, attempt))
                    continue
                raise RuntimeError('Binary upload failed: HTTP ' + str(response.status_code))


def await_complete(api, resource_id, timeout, expected_image):
    deadline = time.monotonic() + timeout
    metadata_deadline = None
    mismatch = None
    while True:
        resource = api.request('GET', '/appScreenshots/' + resource_id)['data']
        status = state(resource)
        if status == 'COMPLETE':
            if metadata_deadline is None:
                metadata_deadline = min(deadline, time.monotonic() + 60)
            try:
                verify_image(resource, expected_image)
                return resource
            except RuntimeError as error:
                # COMPLETE can become visible before the checksum, dimensions,
                # and byte count. Keep all checks strict while they converge.
                mismatch = str(error)
        if status == 'FAILED':
            codes = [str(x.get('code', 'UNKNOWN')) for x in
                     ((resource['attributes'].get('assetDeliveryState') or {}).get('errors') or [])]
            raise VerificationError('Apple screenshot processing FAILED: ' + ', '.join(codes), [resource])
        remaining = min(deadline, metadata_deadline or deadline) - time.monotonic()
        if remaining <= 0:
            if metadata_deadline is not None:
                raise VerificationError('Screenshot COMPLETE metadata did not converge: ' + mismatch,
                                        [resource])
            raise VerificationError('Screenshot processing timeout; safe to resume later', [resource])
        time.sleep(min(3, remaining))


def deliver(api, set_id, image, processing_timeout):
    shots = list_shots(api, set_id)
    resource = complete_match(shots, image)
    if resource:
        return resource, 'reused'
    resource = pending_match(shots, image)
    retired = set()
    body = {'data': {'type': 'appScreenshots',
                     'attributes': {'fileName': image['fileName'], 'fileSize': image['fileSize']},
                     'relationships': {'appScreenshotSet': {
                         'data': {'type': 'appScreenshotSets', 'id': set_id}}}}}

    def find():
        current = [x for x in list_shots(api, set_id) if x['id'] not in retired]
        return complete_match(current, image) or pending_match(current, image)

    for recreation in range(5):
        if resource is None:
            resource = reconciled_post(api, '/appScreenshots', body, find)
        # Preserve instructions from the successful reservation POST. Apple's
        # current GET endpoint may omit uploadOperations even when selected.
        if state(resource) != 'AWAITING_UPLOAD' or resource['attributes'].get('uploadOperations'):
            break
        resource = api.request('GET', '/appScreenshots/' + resource['id'] +
                               '?fields[appScreenshots]=fileSize,fileName,sourceFileChecksum,'
                               'imageAsset,assetDeliveryState,uploadOperations')['data']
        if state(resource) != 'AWAITING_UPLOAD' or resource['attributes'].get('uploadOperations'):
            break
        attributes = resource['attributes']
        if (attributes.get('fileName') != image['fileName'] or
                attributes.get('fileSize') != image['fileSize']):
            raise RuntimeError('Refusing to recreate a reservation that does not match this upload')
        # Rebuild only the exact uncommitted reservation belonging to this
        # binary. COMPLETE and UPLOAD_COMPLETE resources are never recreated.
        retired.add(resource['id'])
        delete_shot(api, set_id, resource['id'])
        resource = None
    if resource is None:
        raise RuntimeError('Reservation instructions unavailable after safe recreation retries')
    if state(resource) == 'AWAITING_UPLOAD':
        upload_binary(resource, image)
        body = {'data': {'type': 'appScreenshots', 'id': resource['id'],
                         'attributes': {'uploaded': True, 'sourceFileChecksum': image['md5']}}}
        try:
            api.request('PATCH', '/appScreenshots/' + resource['id'], body)
        except APIError:
            committed = api.request('GET', '/appScreenshots/' + resource['id'])['data']
            if state(committed) not in ('UPLOAD_COMPLETE', 'COMPLETE') or checksum(committed) != image['md5']:
                raise
    complete = await_complete(api, resource['id'], processing_timeout, image)
    return complete, 'uploaded'


def verify_image(resource, image):
    attrs = resource['attributes']
    asset = attrs.get('imageAsset') or {}
    if state(resource) != 'COMPLETE' or checksum(resource) != image['md5']:
        raise RuntimeError('Screenshot did not finish with the expected MD5')
    if (asset.get('width'), asset.get('height')) != (image['width'], image['height']):
        raise RuntimeError('Processed screenshot dimensions differ from source')
    if attrs.get('fileSize') != image['fileSize']:
        raise RuntimeError('Processed screenshot file size differs from source')


def reorder(api, set_id, ids):
    deadline = time.monotonic() + 60
    body = {'data': [{'type': 'appScreenshots', 'id': x} for x in ids]}
    try:
        api.request('PATCH', '/appScreenshotSets/{}/relationships/appScreenshots'.format(set_id), body)
    except APIError:
        # Reconcile a PATCH with an unknown outcome through the ordered relation.
        pass
    consecutive_matches = 0
    attempt = 0
    while True:
        shots = list_shots(api, set_id)
        consecutive_matches = consecutive_matches + 1 if [x['id'] for x in shots] == ids else 0
        if consecutive_matches >= 2:
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise VerificationError('Screenshot order failed verification after consistency retries',
                                    shots, ids)
        if attempt == 3 and not consecutive_matches:
            # Apple's ordered GET may lag a successful PATCH by several seconds.
            # Re-applying the same order is idempotent if it has not converged.
            try:
                api.request('PATCH', '/appScreenshotSets/{}/relationships/appScreenshots'.format(set_id), body)
            except APIError:
                pass  # Reconcile an unknown PATCH outcome through the next GET.
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise VerificationError('Screenshot order failed verification after consistency retries',
                                    shots, ids)
        time.sleep(min(2, remaining))
        attempt += 1


def await_locale_verified(api, localization, before, set_id, ids, images):
    deadline = time.monotonic() + 60
    while True:
        actual = inventory_locale(api, localization)
        try:
            actual_target = target_set(actual)
            if not actual_target or actual_target['set']['id'] != set_id:
                raise RuntimeError('Target locale/display/set association failed verification')
            shots = actual_target['screenshots']
            if [x['id'] for x in shots] != ids or len(shots) != 7:
                raise RuntimeError('Target seven-screenshot order failed verification')
            for resource, image in zip(shots, images):
                verify_image(resource, image)
            other_before = [x for x in before['sets'] if x['set']['attributes']['screenshotDisplayType'] != TARGET_DISPLAY]
            other_after = [x for x in actual['sets'] if x['set']['attributes']['screenshotDisplayType'] != TARGET_DISPLAY]
            if sorted(other_before, key=lambda x: x['set']['id']) != sorted(other_after, key=lambda x: x['set']['id']):
                raise RuntimeError('Another display target changed unexpectedly')
            return actual_target
        except RuntimeError as error:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                resources = [resource for item in actual['sets']
                             for resource in [item['set']] + item['screenshots']]
                raise VerificationError(str(error), resources, ids) from None
        time.sleep(min(2, remaining))


def restoration_image(resource, restore_dir, local_images=None):
    attrs = resource['attributes']
    path = restore_dir / (resource['id'] + '.png')
    if not path.is_file():
        local = next((x for x in (local_images or []) if x['md5'] == checksum(resource)), None)
        if local:
            path = Path(local['path'])
        else:
            raise RuntimeError('Original screenshot binary backup is missing: ' + resource['id'])
    data = path.read_bytes()
    digest = hashlib.md5(data).hexdigest()
    asset = attrs.get('imageAsset') or {}
    expected_digest, expected_size = checksum(resource), attrs['fileSize']
    manifest_path = restore_dir / 'manifest.json'
    if manifest_path.is_file():
        entries = json.loads(manifest_path.read_text())
        entry = next((x for x in entries if x.get('id') == resource['id']), None)
        if entry:
            if entry.get('sourceFileChecksum') != checksum(resource):
                raise RuntimeError('Original binary backup manifest does not match the recorded source: ' + resource['id'])
            expected_digest, expected_size = entry['backupMD5'], entry['bytes']
            if hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise RuntimeError('Original binary backup SHA256 mismatch: ' + resource['id'])
    # Apple may re-encode the download. A processed full-size visual backup
    # therefore has its own verified checksum and is committed with that MD5.
    if digest != expected_digest or len(data) != expected_size:
        raise RuntimeError('Original screenshot binary backup checksum/size mismatch: ' + resource['id'])
    with Image.open(path) as image:
        if image.format != 'PNG' or image.size != (asset.get('width'), asset.get('height')):
            raise RuntimeError('Original binary backup dimensions mismatch: ' + resource['id'])
        image.load()
    return {'path': str(path.resolve()), 'md5': digest, 'fileSize': len(data),
            'width': asset.get('width'), 'height': asset.get('height'),
            'fileName': attrs['fileName']}


def rollback(api, set_id, original_shots, restore_dir, timeout, local_images=None):
    original_images = [restoration_image(x, restore_dir, local_images) for x in original_shots]
    current = list_shots(api, set_id)
    wanted = {x['md5'] for x in original_images} | {checksum(x) for x in original_shots}
    for resource in current:
        if checksum(resource) not in wanted or state(resource) != 'COMPLETE':
            delete_shot(api, set_id, resource['id'])
    restored = []
    for original, image in zip(original_shots, original_images):
        surviving = next((x for x in list_shots(api, set_id) if x['id'] == original['id']
                          and state(x) == 'COMPLETE' and checksum(x) == checksum(original)), None)
        restored.append(surviving['id'] if surviving else deliver(api, set_id, image, timeout)[0]['id'])
    # Ensure duplicates left by an unknown network outcome cannot remain.
    for resource in list_shots(api, set_id):
        if resource['id'] not in restored:
            delete_shot(api, set_id, resource['id'])
    reorder(api, set_id, restored)
    return restored


def process_locale(config, args, row, before, version_id):
    code = row['locale']
    if code in PROTECTED:
        raise RuntimeError('Protected Chinese localization cannot be changed')
    api = make_api(config)
    checkpoint = args.out_dir / 'checkpoints' / (code + '.json')
    record = {'locale': code, 'startedAt': now(), 'status': 'running', 'images': [], 'deletedIds': []}
    save(checkpoint, record)
    old = target_set(before)
    baseline_path = args.out_dir / 'locale-backups' / ('baseline-' + code + '.json')
    if baseline_path.is_file():
        baseline = json.loads(baseline_path.read_text())
        if (baseline.get('versionId') != version_id or baseline.get('localizationId') != before['localizationId']):
            raise RuntimeError('Existing locale backup belongs to a different target version')
        original_shots = baseline['screenshots']
    else:
        # Keep an immutable baseline across resumed runs. Pending reservations
        # are not viewable old screenshots and do not require binary recovery.
        original_shots = [x for x in (old['screenshots'] if old else []) if state(x) == 'COMPLETE']
        save(baseline_path, {'locale': code, 'versionId': version_id,
                             'localizationId': before['localizationId'], 'screenshots': original_shots})
    set_id = None
    deleted_original = False
    try:
        version = api.request('GET', '/appStoreVersions/' + version_id)['data']
        if version['attributes'].get('appStoreState') not in EDITABLE:
            raise RuntimeError('Target version is no longer editable')
        locale_resource = api.request('GET', '/appStoreVersionLocalizations/' + before['localizationId'])['data']
        if locale_resource['attributes'].get('locale') != code:
            raise RuntimeError('Localization identity changed')
        resource = ensure_set(api, before['localizationId'])
        set_id = resource['id']
        record['setId'] = set_id
        # This immutable per-run backup records the pre-upload order and does
        # not contain uploadOperations, image URLs, or asset authorization.
        backup = args.out_dir / 'locale-backups' / (args.run_stamp + '-' + code + '.json')
        save(backup, {'locale': code, 'localizationId': before['localizationId'],
                      'display': TARGET_DISPLAY, 'originalSet': old,
                      'restoreDir': str(args.restore_dir.resolve()), 'createdAt': now()})
        record['backup'] = str(backup.resolve())
        ids = []
        used = set()
        for image in row['images']:
            current = list_shots(api, set_id)
            found = complete_match(current, image, used)
            if found:
                verify_image(found, image)
                action = 'reused'
            else:
                # Resuming one's own outstanding reservation needs no new slot.
                pending = pending_match(current, image)
                if not pending and len(current) >= 10:
                    future_hashes = {x['md5'] for x in row['images']}
                    expendable = [x for x in current if x['id'] not in used
                                  and not (state(x) == 'COMPLETE' and checksum(x) in future_hashes)]
                    if not expendable:
                        raise RuntimeError('No safe screenshot slot available below Apple limit of ten')
                    candidate = expendable[-1]
                    original = next((x for x in original_shots if x['id'] == candidate['id']), None)
                    if original:
                        # Validate ALL original binaries before the first removal
                        # so the complete previous ordered set can be restored.
                        for original_resource in original_shots:
                            restoration_image(original_resource, args.restore_dir, row['images'])
                        deleted_original = True
                    delete_shot(api, set_id, candidate['id'])
                    record['deletedIds'].append(candidate['id'])
                    save(checkpoint, record)
                found, action = deliver(api, set_id, image, args.processing_timeout)
            ids.append(found['id'])
            used.add(found['id'])
            record['images'].append({'index': image['index'], 'id': found['id'],
                                     'md5': image['md5'], 'action': action, 'state': 'COMPLETE'})
            save(checkpoint, record)
            say('{} {}/7: {} COMPLETE'.format(code, image['index'], action))
        # All seven target images are COMPLETE before unnecessary originals are
        # removed. Until this point we retain them whenever Apple's limit permits.
        for resource in list_shots(api, set_id):
            if resource['id'] not in used:
                original = next((x for x in original_shots if x['id'] == resource['id']), None)
                if original:
                    for original_resource in original_shots:
                        restoration_image(original_resource, args.restore_dir, row['images'])
                    deleted_original = True
                delete_shot(api, set_id, resource['id'])
                record['deletedIds'].append(resource['id'])
                save(checkpoint, record)
        reorder(api, set_id, ids)
        actual_target = await_locale_verified(api, locale_resource, before, set_id, ids, row['images'])
        record.update({'status': 'verified', 'verified': True, 'completedAt': now(), 'after': actual_target})
        say('{}: PASS (7 images, MD5, dimensions, locale, order)'.format(code))
    except Exception as error:
        # Only known deliberately sanitized errors may reach stdout/disk.
        message = str(error) if isinstance(error, (APIError, RuntimeError)) else type(error).__name__
        record.update({'status': 'failed', 'verified': False, 'error': message, 'completedAt': now()})
        if isinstance(error, VerificationError):
            record['verificationDiagnostics'] = error.diagnostics
        if deleted_original and set_id:
            say('{}: restoring the previous screenshots after a failure'.format(code))
            try:
                record['restoredIds'] = rollback(api, set_id, original_shots, args.restore_dir,
                                                args.processing_timeout, row['images'])
                record['rollback'] = 'verified'
            except Exception as restore_error:
                record['rollback'] = 'failed'
                record['rollbackError'] = (str(restore_error) if isinstance(restore_error, (APIError, RuntimeError))
                                           else type(restore_error).__name__)
                if isinstance(restore_error, VerificationError):
                    record['rollbackDiagnostics'] = restore_error.diagnostics
        say('{}: FAIL: {}'.format(code, message))
    finally:
        save(checkpoint, record)
        api.session.close()
    return record


def preserved_view(inventory, selected):
    """Compare every untouched locale and display target, including order."""
    return {code: {'localizationId': entry['localizationId'],
                   'sets': sorted([x for x in entry['sets'] if code not in selected or
                                   x['set']['attributes']['screenshotDisplayType'] != TARGET_DISPLAY],
                                  key=lambda x: x['set']['id'])}
            for code, entry in inventory.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'marketing/app-store/ios-screenshots-pen-2026-10-02/export-manifest.json')
    parser.add_argument('--credentials', type=Path, default=Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json'))
    parser.add_argument('--app-id', default=TARGET_APP)
    parser.add_argument('--expected-bundle-id', default=TARGET_BUNDLE)
    parser.add_argument('--version', default=TARGET_VERSION)
    parser.add_argument('--out-dir', type=Path, default=ROOT / 'artifacts/app-store-screenshots-20261002/upload')
    parser.add_argument('--restore-dir', type=Path, default=ROOT / 'artifacts/app-store-screenshots-20261002/originals')
    parser.add_argument('--locale', action='append', help='Select one locale; repeat for a batch; default all 48')
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--processing-timeout', type=int, default=600)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Upload screenshots and verify; default is read-only')
    mode.add_argument('--plan', action='store_true', help='Explicitly request the default read-only plan')
    args = parser.parse_args()
    if (args.app_id, args.expected_bundle_id, args.version) != (TARGET_APP, TARGET_BUNDLE, TARGET_VERSION):
        parser.error('This uploader is restricted to iScoreboard com.douhua.jifen.ios iOS ' + TARGET_VERSION)
    if not 1 <= args.jobs <= 6:
        parser.error('--jobs must be 1 through 6')
    rows = read_images(args.manifest.resolve(), args.locale)
    config = json.loads(args.credentials.read_text())
    key_path = Path(config['privateKeyFile']).expanduser()
    if not key_path.is_absolute():
        key_path = args.credentials.resolve().parent / key_path
    config['privateKeyFile'] = str(key_path.resolve())
    api = make_api(config)
    app = api.request('GET', '/apps/' + args.app_id)['data']
    if app['attributes'].get('bundleId') != args.expected_bundle_id:
        raise RuntimeError('Live app bundle ID does not match the requested target')
    versions = [x for x in api.list('/apps/{}/appStoreVersions'.format(args.app_id))
                if x['attributes'].get('platform') == 'IOS' and x['attributes'].get('versionString') == args.version]
    if len(versions) != 1 or versions[0]['attributes'].get('appStoreState') not in EDITABLE:
        raise RuntimeError('Expected exactly one editable iOS ' + TARGET_VERSION + ' version')
    version = versions[0]
    localizations = api.list('/appStoreVersions/{}/appStoreVersionLocalizations'.format(version['id']))
    localization_map = {x['attributes']['locale']: x for x in localizations}
    if any(row['locale'] not in localization_map for row in rows):
        raise RuntimeError('A requested locale has no existing Store Localization; no locale will be created')
    api.session.close()
    args.run_stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    before = inventory_all(config, localizations, args.jobs)
    backup_file = args.out_dir / ('before-' + args.run_stamp + '.json')
    save(backup_file, {'appId': args.app_id, 'bundleId': args.expected_bundle_id,
                       'version': args.version, 'versionId': version['id'], 'createdAt': now(), 'locales': before})
    plan = {'appId': args.app_id, 'bundleId': args.expected_bundle_id,
            'version': args.version, 'versionId': version['id'], 'display': TARGET_DISPLAY,
            'apply': args.apply, 'backup': str(backup_file.resolve()), 'locales': []}
    for row in rows:
        old = target_set(before[row['locale']])
        shots = old['screenshots'] if old else []
        reused = sum(bool(complete_match(shots, image)) for image in row['images'])
        plan['locales'].append({'locale': row['locale'], 'targetCount': 7,
                                'existingCount': len(shots), 'reusableCount': reused,
                                'uploadCount': 7 - reused, 'images': row['images']})
    save(args.out_dir / ('plan-' + args.run_stamp + '.json'), plan)
    say('Target: {} / iOS {} / {}. {} locales, {} screenshots.'.format(
        args.expected_bundle_id, args.version, TARGET_DISPLAY, len(rows), len(rows) * 7))
    say('Existing assets backed up; planning {} binary uploads.'.format(
        sum(x['uploadCount'] for x in plan['locales'])))
    if not args.apply:
        say('Read-only plan saved; App Store Connect was not changed.')
        return 0
    # Validate the old binaries before starting a batch that may remove them.
    for row in rows:
        old = target_set(before[row['locale']])
        if old:
            desired = {x['md5'] for x in row['images']}
            removing = [x for x in old['screenshots'] if state(x) == 'COMPLETE' and checksum(x) not in desired]
            if removing:
                for resource in old['screenshots']:
                    if state(resource) == 'COMPLETE':
                        restoration_image(resource, args.restore_dir, row['images'])
    report = {'appId': args.app_id, 'bundleId': args.expected_bundle_id,
              'version': args.version, 'versionId': version['id'], 'startedAt': now(),
              'backup': str(backup_file.resolve()), 'results': [],
              'submittedForReview': False, 'released': False}
    report_path = args.out_dir / ('upload-report-' + args.run_stamp + '.json')
    save(report_path, report)
    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = [executor.submit(process_locale, config, args, row, before[row['locale']], version['id']) for row in rows]
        for future in as_completed(futures):
            report['results'].append(future.result())
            save(report_path, report)
            save(args.out_dir / 'upload-report.json', report)
    after = inventory_all(config, localizations, args.jobs)
    save(args.out_dir / ('after-' + args.run_stamp + '.json'), {'locales': after, 'createdAt': now()})
    selected = {x['locale'] for x in rows}
    preserved = preserved_view(before, selected) == preserved_view(after, selected)
    report.update({'completedAt': now(), 'preservedOtherLocalesAndDisplays': preserved,
                   'verified': preserved and len(report['results']) == len(rows) and
                   all(x.get('verified') for x in report['results']),
                   'verifiedLocaleCount': sum(bool(x.get('verified')) for x in report['results']),
                   'targetLocaleCount': len(rows), 'targetScreenshotCount': len(rows) * 7})
    save(report_path, report)
    save(args.out_dir / 'upload-report.json', report)
    say('Verification: {}; {}/{} locales; protected locales and other displays {}.'.format(
        'PASS' if report['verified'] else 'FAIL', report['verifiedLocaleCount'], len(rows),
        'preserved' if preserved else 'FAILED'))
    return 0 if report['verified'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        message = str(error) if isinstance(error, (APIError, RuntimeError)) else type(error).__name__
        say('ERROR: ' + message)
        sys.exit(1)
