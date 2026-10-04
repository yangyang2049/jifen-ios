"""Export the approved icon pair with consistent transparent padding."""
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPOS = ROOT.parents[2]
SOURCES = {
    'whistle': '/Users/yangyang/.codex/generated_images/01a10516-b9ad-7393-976a-9f8f9aa76ebe/exec-8eea046b-d358-4dbc-ab9d-df80a95c4e07.png',
    'buzzer': '/Users/yangyang/.codex/generated_images/01a10516-b9ad-7393-976a-9f8f9aa76ebe/exec-c42c8106-a912-4aff-90b3-8d9f4f05942f.png',
}
records = []

def preserve(path):
    if path.exists():
        backup = ROOT / 'before' / path.relative_to(REPOS)
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)

def save(image, path):
    preserve(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == '.webp':
        image.save(path, lossless=True, quality=100, method=6, exact=True)
    else:
        image.save(path, optimize=True)
    with Image.open(path) as check:
        assert check.mode == 'RGBA' and check.getchannel('A').getextrema() == (0, 255)
        assert check.size == image.size
    records.append({'path': str(path), 'size': list(image.size), 'bytes': path.stat().st_size})

for key, source in SOURCES.items():
    master = ROOT / 'masters' / (key + '.png')
    master.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, master)
    image = Image.open(master).convert('RGBA')
    assert image.getchannel('A').getextrema() == (0, 255)
    # Size/padding normalization only: retain the generated pixels and alpha.
    box = image.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    cropped = image.crop(box)
    def scaled(size):
        factor = size * 0.84 / max(cropped.size)
        artwork = cropped.resize((round(cropped.width * factor), round(cropped.height * factor)), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (size, size))
        canvas.paste(artwork, ((size - artwork.width) // 2, (size - artwork.height) // 2))
        return canvas
    ios = REPOS / 'jifen-ios/jifen/Assets.xcassets' / ('icon_3d_' + key + '.imageset')
    images = []
    for scale in (1, 2, 3):
        filename = f'{key}@{scale}x.png'
        save(scaled(128 * scale), ios / filename)
        images.append({'filename': filename, 'idiom': 'universal', 'scale': f'{scale}x'})
    contents = ios / 'Contents.json'
    preserve(contents)
    contents.write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    for repo in ('jifen-android', 'jifen-android-google'):
        save(scaled(384), REPOS / repo / 'app/src/main/res/drawable-nodpi' / ('jf3d_' + key + '.webp'))
    save(scaled(384), REPOS / 'jifen-hos/entry/src/main/resources/base/media' / ('icon3d_' + key + '.png'))
    save(scaled(384), REPOS / 'jifen-wechat/assets/icons/3d' / (key + '.webp'))

for repo, relative in (
    ('jifen-ios', 'jifen/Features/Tools/WhistleToolView.swift'),
    ('jifen-android', 'app/src/main/java/com/douhua/jifen/screen/tools/WhistleToolScreen.kt'),
    ('jifen-android-google', 'app/src/main/java/com/douhua/jifen/screen/tools/WhistleToolScreen.kt'),
    ('jifen-hos', 'entry/src/main/ets/pages/tools/WhistleTool.ets'),
    ('jifen-wechat', 'pages/tools/whistle/index.wxml'),
    ('jifen-wechat', 'pages/tools/whistle/index.wxss'),
):
    preserve(REPOS / repo / relative)

(ROOT / 'export-report.json').write_text(json.dumps(records, indent=2) + '\n')
print(f'Exported {len(records)} RGBA assets across five projects; transparency and dimensions verified.')
