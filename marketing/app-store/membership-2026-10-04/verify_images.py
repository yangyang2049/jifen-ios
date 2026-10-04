#!/usr/bin/env python3
"""Read Apple-hosted draft promotional images and compare their decoded pixels."""
import hashlib
import io
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

import requests
from PIL import Image, ImageChops, ImageStat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from app_store_membership import Client, TARGETS, save, version_path


def main():
    config = Path('/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json')
    directory = ROOT / 'artifacts/app-store-membership-20261004'
    report = json.loads((directory / 'upload-report.json').read_text())
    if not report.get('verified'):
        raise RuntimeError('Finish the metadata upload and verification first')
    client = Client(config)
    outputs = directory / 'apple-processed-images'
    outputs.mkdir(exist_ok=True)
    rows = []
    for label in ['monthly', 'yearly', 'lifetime']:
        target = TARGETS[label]
        entry = report['targets'][label]
        resource = client.request('GET', f"/v2/{target['imageType']}/{entry['image']['id']}")['data']
        selected = client.request('GET', version_path(target, entry['draftId']) + '/image')['data']
        if not selected or selected['id'] != resource['id']:
            raise RuntimeError(f'{label}: uploaded image is not selected on the draft')
        attributes = resource['attributes']
        if attributes['assetDeliveryState']['state'] != 'COMPLETE':
            raise RuntimeError(f'{label}: Apple image processing is not complete')
        asset = attributes['imageAsset']
        if (asset['width'], asset['height']) != (1024, 1024):
            raise RuntimeError(f'{label}: unexpected Apple image dimensions')
        template = asset['templateUrl']
        url = template.replace('{w}', '1024').replace('{h}', '1024').replace('{f}', 'png')
        parsed = urlparse(url)
        if parsed.scheme != 'https' or not parsed.hostname.endswith('.mzstatic.com') or '{' in url:
            raise ValueError('Unexpected Apple image URL')
        # Fetch the public Apple image without the API session or its JWT.
        response = requests.get(url, timeout=40, allow_redirects=False)
        if not response.ok:
            raise RuntimeError(f'{label}: Apple image download returned HTTP {response.status_code}')
        remote = response.content
        with Image.open(io.BytesIO(remote)) as downloaded, Image.open(HERE / 'images' / f'{label}.png') as original:
            if downloaded.size != original.size:
                raise RuntimeError(f'{label}: downloaded dimensions differ')
            difference = ImageChops.difference(original.convert('RGB'), downloaded.convert('RGB'))
            pixels_identical = difference.getbbox() is None
            mean_error = sum(ImageStat.Stat(difference).mean) / 3
        source = (HERE / 'images' / f'{label}.png').read_bytes()
        (outputs / f'{label}.png').write_bytes(remote)
        row = {'plan': label, 'imageId': resource['id'], 'draftSelectedImageId': selected['id'],
               'assetState': 'COMPLETE', 'dimensions': [1024, 1024],
               'sourceMD5': hashlib.md5(source).hexdigest(), 'applePNGMD5': hashlib.md5(remote).hexdigest(),
               'pixelsIdentical': pixels_identical, 'meanAbsoluteRGBError': mean_error,
               'applePNGPath': str(outputs / f'{label}.png')}
        rows.append(row)
        print(f'{label}: selected draft image, COMPLETE, 1024x1024; pixels identical={pixels_identical}, mean RGB error={mean_error:.5f}', flush=True)
    result = {'verified': all(r['pixelsIdentical'] for r in rows), 'images': rows}
    save(directory / 'image-verification.json', result)
    if not result['verified']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
