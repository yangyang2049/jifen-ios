"""Capture localized production scenes on the dedicated landscape iPad simulator."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat

HERE = Path(__file__).resolve().parent
BUNDLE = 'com.douhua.jifen.ios'
SCENES = ['snooker', 'basketball', 'record', 'setup', 'home']


def simctl(sim, *args, check=True):
    return subprocess.run(['xcrun', 'simctl', args[0], sim, *args[1:]],
                          check=check, capture_output=True, text=True)


def capture(sim, entry, scene, index):
    code = entry['locale']
    folder = HERE / 'exports' / code
    folder.mkdir(parents=True, exist_ok=True)
    dest = folder / ('{:02d}-{}.png'.format(index, scene))
    simctl(sim, 'terminate', BUNDLE, check=False)
    args = ['-AppleLanguages', '(' + entry['appleLanguage'] + ')',
            '-AppleLocale', entry['appleLocale'], '-UITestSkipLegalConsent', 'YES',
            '-UITestSkipScoreboardUsageHints', 'YES', '-UITestScreenshotMode', '1',
            '-UITestRecordFixtures', '-UITestRecordTeamName1', entry['names'][0],
            '-UITestRecordTeamName2', entry['names'][1], '-jifen-v2.appAppearanceMode', 'light']
    if scene != 'home':
        args += ['-MarketingScreenshotFixture', scene]
    names = entry['basketballTeams'] + entry['names'][2:] if scene == 'basketball' else entry['names']
    for number, name in enumerate(names, 1):
        args += ['-UITestSetupName' + str(number), name]
    simctl(sim, 'launch', BUNDLE, *args)
    time.sleep(3)
    for attempt in range(8):
        simctl(sim, 'io', 'screenshot', str(dest))
        with Image.open(dest) as image:
            image.load()
            if image.size != (2752, 2064):
                raise RuntimeError('Dedicated simulator lost its landscape orientation: ' + str(image.size))
            stat = ImageStat.Stat(image.convert('RGB').resize((256, 192)))
            if max(stat.mean) > 35 and max(stat.stddev) > 10:
                break
        time.sleep(2)
    else:
        raise RuntimeError('Screenshot remained blank or at launch screen: ' + code + '/' + scene)
    data = dest.read_bytes()
    return {'index': index, 'scene': scene, 'file': str(dest.relative_to(HERE)),
            'width': 2752, 'height': 2064, 'sha256': hashlib.sha256(data).hexdigest(),
            'capture': 'production SwiftUI via simctl',
            **({'teamNames': entry['basketballTeams']} if scene == 'basketball' else {})}


def matches_configuration(row, entry):
    return all(row.get(key) == entry.get(key) for key in (
        'locale', 'appleLanguage', 'appleLocale', 'names', 'basketballTeams'))


def card_is_current(card):
    path = (HERE / card['file']).resolve()
    return (HERE in path.parents and path.is_file()
            and hashlib.sha256(path.read_bytes()).hexdigest() == card['sha256'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sim', default='7230B956-03E3-4A0B-9322-B555C35F76F0')
    parser.add_argument('--locales', help='Comma-separated locale codes')
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    entries = json.loads((HERE / 'capture-config.json').read_text())['localizations']
    chosen = set(args.locales.split(',')) if args.locales else None
    if chosen and chosen - {entry['locale'] for entry in entries}:
        parser.error('Requested locale is absent from the capture configuration')
    for entry in entries:
        code = entry['locale']
        if chosen and code not in chosen:
            continue
        path = HERE / 'captures' / (code + '.json')
        path.parent.mkdir(exist_ok=True)
        prior = json.loads(path.read_text()) if args.resume and path.exists() else {}
        cards = {x['scene']: x for x in prior.get('cards', [])} if matches_configuration(prior, entry) else {}
        for index, scene in enumerate(SCENES, 1):
            old = cards.get(scene)
            if old and card_is_current(old):
                continue
            cards[scene] = capture(args.sim, entry, scene, index)
            row = {**entry, 'simulator': args.sim, 'cards': [cards[x] for x in SCENES if x in cards]}
            temporary = path.with_suffix('.tmp')
            temporary.write_text(json.dumps(row, ensure_ascii=False, indent=2) + '\n')
            temporary.replace(path)
            print('{} iPad {}/5 {}'.format(code, index, scene), flush=True)
        print('COMPLETE ' + code, flush=True)
    all_rows = []
    for entry in entries:
        path = HERE / 'captures' / (entry['locale'] + '.json')
        if not path.exists():
            break
        row = json.loads(path.read_text())
        if (not matches_configuration(row, entry)
                or [card['scene'] for card in row['cards']] != SCENES
                or not all(card_is_current(card) for card in row['cards'])):
            break
        all_rows.append(row)
    if len(all_rows) == len(entries):
        manifest = {'platform': 'iOS', 'device': 'iPad Pro 13-inch (M5)',
                    'screenshotDisplayType': 'APP_IPAD_PRO_3GEN_129',
                    'width': 2752, 'height': 2064, 'localeCount': len(entries), 'screenshotCount': len(entries) * len(SCENES),
                    'excludedLocales': ['zh-Hans'],
                    'statusBarHiddenInIsolatedCaptureBuild': True, 'localizations': all_rows}
        temporary = HERE / ('export-manifest-' + args.sim + '.tmp')
        temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(HERE / 'export-manifest.json')
        print(f'All {len(entries)} iPad packs / {len(entries) * len(SCENES)} screenshots ready.', flush=True)


if __name__ == '__main__':
    main()
