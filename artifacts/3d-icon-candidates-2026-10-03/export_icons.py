#!/usr/bin/env python3
"""Produce platform assets from preserved selected masters; no lossy encoding."""
import hashlib
import json
from pathlib import Path
from shutil import copy2

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent
DATA = json.loads((ROOT / 'selections.json').read_text())
OUT = ROOT / 'exports'
MASTER = ROOT / 'selected-masters'
MASTER.mkdir(exist_ok=True)
records = []
resample = getattr(Image, 'Resampling', Image).LANCZOS

for asset in DATA['assets']:
    key = asset['id']
    source = Path(asset['source'])
    master = MASTER / (key + '.png')
    copy2(source, master)
    with Image.open(source) as original:
        original.load()
        rgba = original.convert('RGBA')
        sizes = {}
        for size in (64, 128, 192, 256):
            sizes[size] = rgba.resize((size, size), resample=resample)
        files = []
        imageset = OUT / 'ios' / ('icon_3d_' + key + '.imageset')
        imageset.mkdir(parents=True, exist_ok=True)
        images = []
        for scale, size in ((1, 64), (2, 128), (3, 192)):
            filename = f'{key}@{scale}x.png'
            output = imageset / filename
            sizes[size].save(output, format='PNG', optimize=True, compress_level=9)
            images.append({'filename': filename, 'idiom': 'universal', 'scale': f'{scale}x'})
            files.append({'platform': 'ios', 'scale': scale, 'size': size, 'path': str(output.relative_to(ROOT)), 'bytes': output.stat().st_size})
        (imageset / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}, 'properties': {'preserves-vector-representation': False}}, indent=2))
        for platform, size, prefix, extension in (('android', 256, 'jf3d_', '.webp'), ('wechat', 192, '', '.webp'), ('harmonyos', 256, 'icon3d_', '.png')):
            folder = OUT / platform
            folder.mkdir(parents=True, exist_ok=True)
            output = folder / (prefix + key + extension)
            image = sizes[size]
            if extension == '.webp':
                image.save(output, format='WEBP', lossless=True, quality=100, method=6, exact=True)
                with Image.open(output) as check:
                    check.load()
                    # Hidden RGB at alpha=0 has no visible effect; compare premultiplied RGBA.
                    visible_equal = all(bounds == (0, 0) for bounds in ImageChops.difference(image.convert('RGBa'), check.convert('RGBA').convert('RGBa')).getextrema())
                if not visible_equal:
                    raise RuntimeError('Lossless WebP verification failed: ' + str(output))
            else:
                image.save(output, format='PNG', optimize=True, compress_level=9)
                with Image.open(output) as check:
                    check.load()
                    if image.tobytes() != check.convert('RGBA').tobytes():
                        raise RuntimeError('PNG verification failed: ' + str(output))
            files.append({'platform': platform, 'size': size, 'path': str(output.relative_to(ROOT)), 'bytes': output.stat().st_size, 'encoding': 'lossless'})
        records.append({'id': key, 'source': str(source), 'source_size': list(original.size), 'source_bytes': source.stat().st_size, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'outputs': files})

summary = {'icons': len(records), 'masters_bytes': sum(x['source_bytes'] for x in records), 'platform_bytes': {platform: sum(f['bytes'] for row in records for f in row['outputs'] if f['platform'] == platform) for platform in ('ios', 'android', 'wechat', 'harmonyos')}}
(ROOT / 'export-report.json').write_text(json.dumps({'summary': summary, 'records': records}, ensure_ascii=False, indent=2))
print(json.dumps(summary, ensure_ascii=False))
