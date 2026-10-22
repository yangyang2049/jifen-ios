"""Upload the approved header and attach it to the editable iOS 3.3 localizations.

Only adds a CREATIVE_ASSETS image and PRODUCT_PAGE_HEADER_ASSET placements.
Never submits a version for review, releases, deletes, or replaces an existing header.
Re-running reconciles resources using a file-hash-bound reference name.
"""
import hashlib
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from app_store_localization import API

HERE = Path(__file__).resolve().parent
OUT = HERE / 'upload'
APP = '6759768784'
VERSION = '468e2fdc-fa21-4f06-b87c-3006c4d37aa7'
KIND = 'PRODUCT_PAGE_HEADER_ASSET'


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def clean(resource):
    value = json.loads(json.dumps(resource))
    value.get('attributes', {}).pop('uploadOperations', None)
    return value


def main():
    OUT.mkdir(exist_ok=True)
    folder = Path('/Users/yangyang/Documents/CERTIFICATES')
    config = json.loads((folder / 'AppStoreConnect_iScoreboard-localization.json').read_text())
    api = API(folder / config['privateKeyFile'], config['keyId'], config['issuerId'])
    app = api.request('GET', '/apps/' + APP)['data']
    assert app['attributes']['bundleId'] == 'com.douhua.jifen.ios'
    version = api.request('GET', '/appStoreVersions/' + VERSION)['data']
    assert version['attributes']['versionString'] == '3.3'
    assert version['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION'
    locs = api.list('/appStoreVersions/' + VERSION + '/appStoreVersionLocalizations')
    assert len(locs) == 50
    library = api.request('GET', '/apps/' + APP + '/assetLibrary')['data']['id']
    ref = api.request('GET', '/appAssetLibraryRefData')['data'][0]['attributes']
    mapping = next(x for x in ref['placementTypes'] if x['placementTypeId'] == KIND)
    assert 'CREATIVE_ASSETS' in mapping['acceptsAssetCategories']
    group = next(x for x in mapping['specMappings'] if x['placementGroupId'] == 'DEFAULT_PROFILE')
    spec = next(x for x in ref['imageSpecs'] if x['specId'] in group['specs']
                and x['dimensions'].get('minWidth') == 3840 and x['dimensions'].get('minHeight') == 1646)
    path = HERE / '02-sculpted-sports-v3-relaxed.png'
    with Image.open(path) as im:
        assert im.size == (3840, 1646) and im.mode == 'RGB'
    data = path.read_bytes()
    assert len(data) < spec['maxFileSize']
    sha = hashlib.sha256(data).hexdigest()
    name = 'iScoreboard header relaxed ' + sha[:16]

    def placements(loc):
        rows = api.list('/appStoreVersionLocalizations/' + loc['id'] + '/placements?filter[placementType]=' + KIND + '&include=image')
        return {'id': loc['id'], 'locale': loc['attributes']['locale'], 'placements': rows}

    api.authenticate()
    with ThreadPoolExecutor(max_workers=5) as pool:
        baseline = list(pool.map(placements, locs))
    if not (OUT / 'headers-before.json').exists():
        save('headers-before.json', baseline)
    images = api.list('/appAssetLibraries/' + library + '/images?filter[referenceName]=' + requests.utils.quote(name))
    images = [x for x in images if x['attributes'].get('referenceName') == name]
    assert len(images) <= 1
    image = images[0] if images else None
    for row in baseline:
        for p in row['placements']:
            assert image and p['relationships']['image']['data']['id'] == image['id'], 'An existing different header needs review'
    save('upload-plan.json', {'appId': APP, 'versionId': VERSION, 'version': '3.3',
        'sha256': sha, 'fileName': path.name, 'fileSize': len(data), 'specId': spec['specId'],
        'placementType': KIND, 'placementGroup': 'DEFAULT_PROFILE',
        'locales': [x['locale'] for x in baseline], 'submitForReview': False})
    print('Verified target, image specification and all 50 header slots.', flush=True)
    if image is None:
        image = api.request('POST', '/appAssetLibraryImages', {'data': {'type': 'appAssetLibraryImages',
            'attributes': {'fileName': path.name, 'fileSize': len(data), 'category': 'CREATIVE_ASSETS', 'referenceName': name},
            'relationships': {'assetLibrary': {'data': {'type': 'appAssetLibraries', 'id': library}}}}})['data']
    save('image-checkpoint.json', clean(image))
    if image['attributes']['state'] == 'AWAITING_UPLOAD':
        ops = sorted(image['attributes']['uploadOperations'], key=lambda op: op['offset'])
        offset = 0
        for op in ops:
            assert op['offset'] == offset and op['length'] > 0
            host = urlsplit(op['url'])
            assert host.scheme == 'https' and host.hostname.endswith('.apple.com')
            offset += op['length']
        assert offset == len(data)
        for op in ops:
            headers = {x['name']: x['value'] for x in op['requestHeaders']}
            response = requests.request(op['method'], op['url'], headers=headers,
                data=data[op['offset']:op['offset'] + op['length']], timeout=90, allow_redirects=False)
            if not response.ok:
                raise RuntimeError('Asset binary upload HTTP ' + str(response.status_code))
        image = api.request('PATCH', '/appAssetLibraryImages/' + image['id'], {'data': {
            'type': 'appAssetLibraryImages', 'id': image['id'], 'attributes': {'uploaded': True}}})['data']
        save('image-checkpoint.json', clean(image))
        print('Image uploaded and committed; waiting for Apple processing.', flush=True)
    for attempt in range(40):
        image = api.request('GET', '/appAssetLibraryImages/' + image['id'])['data']
        save('image-checkpoint.json', clean(image))
        state = image['attributes']['state']
        if state in ('PREPARE_FOR_SUBMISSION', 'APPROVED'):
            break
        if state not in ('UPLOAD_COMPLETE',):
            raise RuntimeError('Unexpected asset processing state: ' + state)
        time.sleep(3)
    else:
        raise RuntimeError('Asset remains processing; resume this script later')
    attrs = image['attributes']
    assert attrs['specId'] == spec['specId']
    assert (attrs['imageAsset']['width'], attrs['imageAsset']['height']) == (3840, 1646)
    print('Apple processed image successfully: ' + image['id'], flush=True)
    results = []
    for row in baseline:
        current = placements({'id': row['id'], 'attributes': {'locale': row['locale']}})['placements']
        if not current:
            api.request('POST', '/appAssetLibraryPlacements', {'data': {'type': 'appAssetLibraryPlacements',
                'attributes': {'placementType': KIND, 'placementGroup': 'DEFAULT_PROFILE'},
                'relationships': {'image': {'data': {'type': 'appAssetLibraryImages', 'id': image['id']}},
                    'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': row['id']}}}}})
        checked = placements({'id': row['id'], 'attributes': {'locale': row['locale']}})
        assert len(checked['placements']) == 1
        p = checked['placements'][0]
        assert p['relationships']['image']['data']['id'] == image['id']
        assert p['attributes']['placementGroup'] == 'DEFAULT_PROFILE'
        assert p['attributes']['state'] in ('ACTIVE', 'PARENT_PREPARE_FOR_SUBMISSION')
        results.append({'locale': row['locale'], 'placementId': p['id'], 'verified': True, 'state': p['attributes']['state']})
        save('placement-progress.json', results)
        print('Verified header placement ' + row['locale'], flush=True)
    after = api.request('GET', '/appStoreVersions/' + VERSION)['data']
    assert after['attributes']['appStoreState'] == version['attributes']['appStoreState']
    save('upload-report.json', {'appId': APP, 'version': '3.3', 'versionId': VERSION,
        'asset': clean(image), 'sha256': sha, 'results': results,
        'verifiedLocaleCount': len(results), 'versionState': after['attributes']['appStoreState'],
        'submittedForReview': False, 'released': False})
    print('DONE: all 50 header placements verified; version remains PREPARE_FOR_SUBMISSION.', flush=True)


if __name__ == '__main__':
    main()
