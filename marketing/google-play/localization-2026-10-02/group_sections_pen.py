"""Arrange both Pen canvases into region/language-family sections with divider frames."""
import json, shutil, string, random, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parent
CLI = '/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
GP = ROOT / 'iScoreboard-GooglePlay-localized.pen'
IOS = Path('/Users/yangyang/Desktop/jifenqi/jifen-ios/marketing/app-store/ios-screenshots-pen-2026-10-02/iScoreboard-iOS-localized.pen')

ZH = {
 'english': '英語區', 'east': '東亞區', 'se': '東南亞區', 'south': '南亞區', 'west': '西亞區',
 'germanic': '日耳曼語族', 'romance': '拉丁語族', 'slavic': '斯拉夫語族', 'other': '歐洲其他語言'}
EN = {
 'english': 'English', 'east': 'East Asia', 'se': 'Southeast Asia', 'south': 'South Asia', 'west': 'West Asia',
 'germanic': 'Germanic', 'romance': 'Romance', 'slavic': 'Slavic', 'other': 'Other European'}
GP_SECTIONS = {
 'english': ['en-US', 'en-GB', 'en-AU', 'en-CA'],
 'east': ['zh-CN', 'zh-TW', 'ja-JP', 'ko-KR'],
 'se': ['th', 'vi', 'id', 'ms-MY'],
 'south': ['hi-IN', 'bn-BD', 'ta-IN', 'te-IN', 'mr-IN', 'gu', 'pa', 'kn-IN', 'ml-IN', 'ur', 'unsupported-or-IN'],
 'west': ['ar', 'iw-IL', 'tr-TR'],
 'germanic': ['de-DE', 'nl-NL', 'da-DK', 'sv-SE', 'no-NO'],
 'romance': ['fr-FR', 'fr-CA', 'es-ES', 'es-419', 'pt-BR', 'pt-PT', 'ca', 'it-IT', 'ro'],
 'slavic': ['ru-RU', 'uk', 'pl-PL', 'cs-CZ', 'sk', 'hr', 'sl'],
 'other': ['fi-FI', 'hu-HU', 'el-GR'],
}
IOS_SECTIONS = {
 'english': ['en-US', 'en-GB', 'en-AU', 'en-CA'],
 'east': ['zh-Hant', 'ja', 'ko'],
 'se': ['th', 'vi', 'id', 'ms'],
 'south': ['hi', 'bn-BD', 'ta-IN', 'te-IN', 'mr-IN', 'gu-IN', 'pa-IN', 'kn-IN', 'ml-IN', 'ur-PK', 'or-IN'],
 'west': ['ar-SA', 'he', 'tr'],
 'germanic': ['de-DE', 'nl-NL', 'da', 'sv', 'no'],
 'romance': ['fr-FR', 'fr-CA', 'es-ES', 'es-MX', 'pt-BR', 'pt-PT', 'ca', 'it', 'ro'],
 'slavic': ['ru', 'uk', 'pl', 'cs', 'sk', 'hr', 'sl-SI'],
 'other': ['fi', 'hu', 'el'],
}
CONFIGS = [
 (GP, GP_SECTIONS, dict(frame_w=1080, frame_h=1920, col_pitch=1200, row_pitch=2100, div_h=240, div_gap=200, tail=280, font_size=96, text_x=60, fill='#1466F4', backup='google-play-copy-fix-20261003/before-section-groups')),
 (IOS, IOS_SECTIONS, dict(frame_w=1284, frame_h=2778, col_pitch=1436, row_pitch=3100, div_h=320, div_gap=240, tail=380, font_size=120, text_x=80, fill='#0B61FB', backup='ios-screenshots-20261002/before-section-groups')),
]

def new_id(existing):
    alphabet = string.ascii_letters + string.digits
    while True:
        candidate = ''.join(random.choices(alphabet, k=6))
        if candidate not in existing:
            existing.add(candidate)
            return candidate

def process(doc_path, sections, cfg):
    doc = json.loads(doc_path.read_text())
    backup = doc_path.parents[2] / 'artifacts' / cfg['backup'] / doc_path.name
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        shutil.copy2(doc_path, backup)
    ids = {doc['fileToken']}
    def collect(node):
        ids.add(node.get('id'))
        for c in node.get('children', []):
            collect(c)
    for f in doc['children']:
        collect(f)
    rows = {}
    others = []
    for frame in doc['children']:
        name = frame.get('name', '')
        if name.startswith('Divider · '):
            continue  # drop dividers from a previous run so the script is idempotent
        if ' · ' in name and name.split(' · ')[1].strip().isdigit():
            rows.setdefault(name.split(' · ')[0].strip(), []).append(frame)
        else:
            others.append(frame)
    for frames in rows.values():
        frames.sort(key=lambda f: int(f['name'].split(' · ')[1]))
    assigned = {lang for group in sections.values() for lang in group}
    missing = set(rows) - assigned
    extra = assigned - set(rows)
    if missing or extra:
        raise RuntimeError('%s: unmatched locales missing=%s extra=%s' % (doc_path.name, missing, extra))

    columns = max(len(v) for v in rows.values())
    row_width = columns * cfg['frame_w'] + (columns - 1) * (cfg['col_pitch'] - cfg['frame_w'])
    ordered, y = [], 0
    for key, langs in sections.items():
        label = {'type': 'frame', 'id': new_id(ids), 'name': 'Divider · %s · %s' % (ZH[key], EN[key]),
                 'x': 0, 'y': y, 'width': row_width, 'height': cfg['div_h'], 'clip': True, 'layout': 'none',
                 'fill': cfg['fill'],
                 'children': [{'type': 'text', 'id': new_id(ids), 'name': 'Section label', 'x': cfg['text_x'], 'y': 0,
                               'width': row_width - 2 * cfg['text_x'], 'height': cfg['div_h'], 'fill': '#FFFFFF',
                               'textGrowth': 'fixed-width-height', 'textAlignVertical': 'middle', 'textAlign': 'left',
                               'content': '%s · %s · %d' % (ZH[key], EN[key], len(langs)), 'lineHeight': 1,
                               'fontFamily': 'Noto Sans TC', 'fontSize': cfg['font_size'], 'fontWeight': '700',
                               'letterSpacing': 0}]}
        ordered.append(label)
        y += cfg['div_h'] + cfg['div_gap']
        for i, lang in enumerate(langs):
            for col, frame in enumerate(rows[lang]):
                frame['x'] = col * cfg['col_pitch']
                frame['y'] = y + i * cfg['row_pitch']
            ordered.extend(rows[lang])
        y += (len(langs) - 1) * cfg['row_pitch'] + cfg['frame_h'] + cfg['tail']
    ordered.extend(others)
    doc['children'] = ordered
    doc_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + '\n')
    print('%s: %d sections, %d locale rows, canvas height %d' % (doc_path.name, len(sections), len(rows), y))

def main():
    for doc_path, sections, cfg in CONFIGS:
        process(doc_path, sections, cfg)
    for doc_path, _, _ in CONFIGS:
        p = subprocess.run(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                            '--in', str(doc_path), '--out', str(doc_path),
                            '--preview-output', '/tmp/sections-preview.png'],
                           input='get_app_state()\nexit()\n', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        if p.returncode or 'Error:' in p.stdout or 'Failure during' in p.stdout:
            raise RuntimeError(doc_path.name + ': ' + p.stdout[-1200:])
        print(doc_path.name, 'loads in Pen OK')

if __name__ == '__main__':
    main()
