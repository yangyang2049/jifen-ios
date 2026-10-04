"""Upload the verified five-page iPad screenshot packs to the editable iOS draft."""
import argparse
import hashlib
import io
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed, wait
from datetime import datetime, timezone
from pathlib import Path

import requests
from PIL import Image

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
sys.path.insert(0, str(PROJECT / 'scripts'))
import app_store_screenshots as asc

asc.TARGET_DISPLAY = 'APP_IPAD_PRO_3GEN_129'
SCENES = ['snooker', 'basketball', 'record', 'setup', 'home']


def load_rows():
    manifest = json.loads((HERE / 'export-manifest.json').read_text())
    rows = manifest['localizations']
    if len(rows) != 49 or len({x['locale'] for x in rows}) != 49:
        raise RuntimeError('Expected 49 distinct locales')
    if {x['locale'] for x in rows} & asc.PROTECTED:
        raise RuntimeError('Chinese localizations are outside this pack')
    result = []
    for row in rows:
        if [x['scene'] for x in row['cards']] != SCENES:
            raise RuntimeError('Unexpected page order for ' + row['locale'])
        images = []
        for index, card in enumerate(row['cards'], 1):
            path = (HERE / card['file']).resolve()
            if HERE not in path.parents or path.suffix != '.png':
                raise RuntimeError('Screenshot path is outside the pack')
            data = path.read_bytes()
            sha = hashlib.sha256(data).hexdigest()
            if sha != card['sha256']:
                raise RuntimeError('Screenshot SHA256 mismatch')
            with Image.open(path) as image:
                image.load()
                if image.format != 'PNG' or image.size != (2752, 2064):
                    raise RuntimeError('Expected a 2752x2064 PNG')
                if image.convert('RGBA').getchannel('A').getextrema() != (255, 255):
                    raise RuntimeError('Screenshot contains transparency')
            md5 = hashlib.md5(data).hexdigest()
            images.append({'index': index, 'path': str(path), 'sha256': sha,
                           'md5': md5, 'fileSize': len(data), 'width': 2752, 'height': 2064,
                           'fileName': '{}-ipad-{:02d}-{}-{}.png'.format(
                               row['locale'], index, card['scene'], md5[:12])})
        result.append({'locale': row['locale'], 'images': images})
    return result


def backup_originals(api, resource, directory):
    directory.mkdir(parents=True, exist_ok=True)
    manifest_path = directory / 'manifest.json'
    saved = json.loads(manifest_path.read_text()) if manifest_path.is_file() else []
    records = {record['id']: record for record in saved}
    for shot in asc.list_shots(api, resource['id']):
        if asc.state(shot) != 'COMPLETE':
            continue
        previous = records.get(shot['id'])
        if previous:
            if previous['sourceFileChecksum'] != asc.checksum(shot):
                raise RuntimeError('Original screenshot backup belongs to a different source')
            if (directory / (shot['id'] + '.png')).is_file():
                asc.restoration_image(shot, directory)
                continue
        attrs = shot['attributes']
        asset = attrs['imageAsset']
        url = asset['templateUrl'].replace('{w}', str(asset['width'])).replace(
            '{h}', str(asset['height'])).replace('{f}', 'png')
        if not url.startswith('https://'):
            raise RuntimeError('Original screenshot download must use HTTPS')
        for attempt in range(5):
            try:
                response = requests.get(url, timeout=(20, 60))
                response.raise_for_status()
                data = response.content
                path = directory / (shot['id'] + '.png')
                with Image.open(io.BytesIO(data)) as image:
                    image.load()
                    if image.format != 'PNG' or image.size != (asset['width'], asset['height']):
                        raise RuntimeError('Original screenshot backup dimensions differ')
                temporary = path.with_suffix('.png.tmp')
                temporary.write_bytes(data)
                temporary.replace(path)
                break
            except requests.RequestException:
                if attempt == 4:
                    raise RuntimeError('Original screenshot download failed') from None
                time.sleep(2 ** attempt)
        records[shot['id']] = {'id': shot['id'], 'sourceFileChecksum': asc.checksum(shot),
                        'backupMD5': hashlib.md5(data).hexdigest(), 'bytes': len(data),
                        'sha256': hashlib.sha256(data).hexdigest(),
                        'copyType': 'Apple processed PNG at original dimensions'}
        # Persist each complete backup and retain entries for originals that a
        # previous interrupted run has already removed from App Store Connect.
        asc.save(manifest_path, list(records.values()))
    asc.save(manifest_path, list(records.values()))


def prepare_baseline(before, version_id, code, out_dir, images, persist=True):
    return asc.prepare_screenshot_baseline(
        out_dir / 'baselines' / (code + '.json'),
        out_dir / 'checkpoints' / (code + '.json'), before, version_id, code, images,
        legacy_backup_path=out_dir / 'backups' / (code + '.json'), persist=persist,
        recovery_dir=out_dir / 'originals' / code)


def deliver_with_consistent_metadata(api, set_id, image):
    try:
        return asc.deliver(api, set_id, image, 600)
    except RuntimeError as error:
        if str(error) not in (
            'Screenshot did not finish with the expected MD5',
            'Processed screenshot dimensions differ from source',
            'Processed screenshot file size differs from source',
        ):
            raise
        # Apple's first COMPLETE response can precede the updated checksum.
        # Read the exact reservation again instead of creating another image.
        for attempt in range(10):
            matches = [shot for shot in asc.list_shots(api, set_id)
                       if shot['attributes'].get('fileName') == image['fileName']
                       and shot['attributes'].get('fileSize') == image['fileSize']]
            for shot in matches:
                try:
                    asc.verify_image(shot, image)
                    return shot, 'uploaded'
                except RuntimeError:
                    pass
            if attempt < 9:
                time.sleep(3)
        raise RuntimeError('Processed screenshot metadata did not converge') from None


def process(config, row, before, version_id, args, deliveries):
    api = asc.make_api(config)
    code = row['locale']
    path = args.out_dir / 'checkpoints' / (code + '.json')
    record = {'locale': code, 'status': 'running', 'images': [], 'deletedIds': [],
              'startedAt': asc.now()}
    wanted_hashes = {image['md5'] for image in row['images']}
    originals = []
    restore = args.out_dir / 'originals' / code
    removed = False
    set_id = None
    pending = []
    batch = None
    checkpoint_started = False
    try:
        version = api.request('GET', '/appStoreVersions/' + version_id)['data']
        if version['attributes']['appStoreState'] not in asc.EDITABLE:
            raise RuntimeError('Version is no longer editable')
        locale = api.request('GET', '/appStoreVersionLocalizations/' + before['localizationId'])['data']
        if locale['attributes']['locale'] != code or code in asc.PROTECTED:
            raise RuntimeError('Localization identity differs')
        batch = prepare_baseline(before, version_id, code, args.out_dir, row['images'])
        originals = batch['screenshots']
        record.update({'batchId': batch['batchId'], 'targetFingerprint': batch['targetFingerprint']})
        asc.save(path, record)
        checkpoint_started = True
        replacing = [shot for shot in originals if asc.checksum(shot) not in wanted_hashes]
        resource = asc.ensure_set(api, before['localizationId'])
        set_id = resource['id']
        record['setId'] = set_id
        backup_path = args.out_dir / 'backups' / (code + '.json')
        if not backup_path.exists():
            asc.save(backup_path, before)
        current = asc.list_shots(api, set_id)
        # A prior run may have removed originals before interruption. Its
        # durable baseline remains the rollback target for this resumed run.
        current_ids = {shot['id'] for shot in current if asc.state(shot) == 'COMPLETE'}
        removed = any(shot['id'] not in current_ids for shot in originals)
        if len(current) == 5 and [asc.checksum(shot) for shot in current] == [
                image['md5'] for image in row['images']]:
            for shot, image in zip(current, row['images']):
                asc.verify_image(shot, image)
                record['images'].append({'index': image['index'], 'id': shot['id'],
                                         'md5': image['md5'], 'action': 'reused', 'state': 'COMPLETE'})
            record.update({'status': 'verified', 'verified': True, 'completedAt': asc.now(),
                           'after': [asc.snapshot(shot) for shot in current]})
            asc.finish_screenshot_baseline(args.out_dir / 'baselines' / (code + '.json'), batch, 'verified')
            asc.say('{} iPad PASS: 5 images, checksum, size, order'.format(code))
            return record
        missing = [image for image in row['images'] if not (
            asc.complete_match(current, image) or asc.pending_match(current, image))]
        if len(current) + len(missing) > 10:
            raise RuntimeError('More than ten screenshots would be required; existing images retained')
        if replacing:
            backup_originals(api, resource, restore)
            for original in originals:
                asc.restoration_image(original, restore, row['images'])

        def deliver(image):
            worker_api = asc.make_api(config)
            try:
                shot, action = deliver_with_consistent_metadata(worker_api, set_id, image)
                return image, shot, action
            finally:
                worker_api.session.close()

        for image in row['images']:
            pending.append(deliveries.submit(deliver, image))
        completed = {}
        for future in as_completed(pending):
            image, shot, action = future.result()
            completed[image['index']] = shot
            record['images'].append({'index': image['index'], 'id': shot['id'],
                                     'md5': image['md5'], 'action': action, 'state': 'COMPLETE'})
            asc.save(path, record)
            asc.say('{} iPad {}/5 COMPLETE'.format(code, image['index']))
        ids = [completed[x['index']]['id'] for x in row['images']]
        for shot in asc.list_shots(api, set_id):
            if shot['id'] not in ids:
                if shot['id'] in {x['id'] for x in originals}:
                    for original in originals:
                        if asc.state(original) == 'COMPLETE':
                            asc.restoration_image(original, restore, row['images'])
                    removed = True
                asc.delete_shot(api, set_id, shot['id'])
                record['deletedIds'].append(shot['id'])
                asc.save(path, record)
        asc.reorder(api, set_id, ids)
        actual = asc.list_shots(api, set_id)
        if [x['id'] for x in actual] != ids or len(actual) != 5:
            raise RuntimeError('iPad screenshot count or order differs')
        for shot, image in zip(actual, row['images']):
            asc.verify_image(shot, image)
        asc.finish_screenshot_baseline(args.out_dir / 'baselines' / (code + '.json'), batch, 'verified')
        record.update({'status': 'verified', 'verified': True, 'completedAt': asc.now(),
                       'after': [asc.snapshot(x) for x in actual]})
        asc.say('{} iPad PASS: 5 images, checksum, size, order'.format(code))
    except Exception as error:
        # Stop this locale's writers before rollback changes the same set.
        # Running deliveries must finish; the shared pool serves other locales.
        for future in pending:
            future.cancel()
        wait(pending)
        message = str(error) if isinstance(error, (asc.APIError, RuntimeError)) else type(error).__name__
        record.update({'status': 'failed', 'verified': False, 'error': message})
        if removed and set_id:
            try:
                record['restoredIds'] = asc.rollback(api, set_id, originals, restore, 600, row['images'])
                asc.finish_screenshot_baseline(args.out_dir / 'baselines' / (code + '.json'), batch, 'rolledBack')
                record['rollback'] = 'verified'
            except Exception:
                record['rollback'] = 'failed'
        asc.say(code + ' iPad FAIL: ' + message)
    finally:
        if checkpoint_started:
            asc.save(path, record)
        api.session.close()
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--out-dir', type=Path, default=HERE / 'upload')
    parser.add_argument('--locale-jobs', type=int, choices=range(1, 4), default=2)
    parser.add_argument('--image-jobs', type=int, choices=range(1, 9), default=4)
    args = parser.parse_args()
    rows = load_rows()
    credential_path = Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json')
    config = json.loads(credential_path.read_text())
    key = Path(config['privateKeyFile']).expanduser()
    config['privateKeyFile'] = str(key if key.is_absolute() else credential_path.parent / key)
    api = asc.make_api(config)
    app = api.request('GET', '/apps/' + asc.TARGET_APP)['data']
    if app['attributes']['bundleId'] != asc.TARGET_BUNDLE:
        raise RuntimeError('Wrong app bundle')
    versions = [x for x in api.list('/apps/' + asc.TARGET_APP + '/appStoreVersions')
                if x['attributes']['platform'] == 'IOS' and x['attributes']['versionString'] == asc.TARGET_VERSION]
    if len(versions) != 1 or versions[0]['attributes']['appStoreState'] not in asc.EDITABLE:
        raise RuntimeError('Expected an editable iOS 3.2.3 version')
    version = versions[0]
    localizations = api.list('/appStoreVersions/' + version['id'] + '/appStoreVersionLocalizations')
    before = asc.inventory_all(config, localizations, args.locale_jobs)
    if any(x['locale'] not in before for x in rows):
        raise RuntimeError('Missing Store Localization')
    asc.save(args.out_dir / 'before.json', before)
    if not (args.out_dir / 'initial-before.json').exists():
        asc.save(args.out_dir / 'initial-before.json', before)
    report = {'appId': asc.TARGET_APP, 'bundleId': asc.TARGET_BUNDLE, 'version': asc.TARGET_VERSION,
              'versionId': version['id'], 'display': asc.TARGET_DISPLAY,
              'startedAt': asc.now(), 'targetLocaleCount': 49, 'targetScreenshotCount': 245,
              'submittedForReview': False, 'released': False, 'results': []}
    asc.say('iPad: 49 locales, 245 screenshots, editable iOS 3.2.3 draft.')
    if not args.apply:
        asc.save(args.out_dir / 'plan.json', {'target': report, 'localizations': rows})
        asc.say('Read-only plan verified.')
        return 0
    # Reject mismatched or ambiguous recovery batches before any locale writes.
    for row in rows:
        prepare_baseline(before[row['locale']], version['id'], row['locale'], args.out_dir,
                         row['images'], persist=False)
    with ThreadPoolExecutor(max_workers=args.image_jobs) as deliveries, ThreadPoolExecutor(max_workers=args.locale_jobs) as locales:
        pending = [locales.submit(process, config, row, before[row['locale']], version['id'], args, deliveries)
                   for row in rows]
        for future in as_completed(pending):
            report['results'].append(future.result())
            asc.save(args.out_dir / 'upload-report.json', report)
    after = asc.inventory_all(config, localizations, args.locale_jobs)
    asc.save(args.out_dir / 'after.json', after)
    selected = {row['locale'] for row in rows}
    protected = asc.preserved_view(before, selected) == asc.preserved_view(after, selected)
    final_checks = []
    for row in rows:
        target = asc.target_set(after[row['locale']])
        valid = bool(target) and len(target['screenshots']) == 5
        if valid:
            try:
                for shot, image in zip(target['screenshots'], row['images']):
                    asc.verify_image(shot, image)
            except RuntimeError:
                valid = False
        final_checks.append({'locale': row['locale'], 'verified': valid})
    report.update({'completedAt': asc.now(), 'protectedChineseLocalesPreserved': protected,
                   'preservedOtherLocalesAndDisplays': protected,
                   'verifiedLocaleCount': sum(x.get('verified', False) for x in report['results']),
                   'finalInventoryChecks': final_checks,
                   'verified': protected and len(report['results']) == 49 and
                               all(x.get('verified', False) for x in report['results']) and
                               all(x['verified'] for x in final_checks)})
    asc.save(args.out_dir / 'upload-report.json', report)
    asc.say('iPad verification {}: {}/49 locales, 245 images.'.format(
        'PASS' if report['verified'] else 'FAIL', report['verifiedLocaleCount']))
    return 0 if report['verified'] else 1


if __name__ == '__main__':
    sys.exit(main())
