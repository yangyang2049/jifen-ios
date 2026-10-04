"""Set the zh-TW card-1 slogan to the full couplet and re-export."""
import json, shutil, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parent
CLI = '/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC = ROOT / 'iScoreboard-GooglePlay-localized.pen'
BACKUP = ROOT.parents[1] / 'artifacts/google-play-copy-fix-20261003/before-zhtw-slogan' / DOC.name
CONTENT = '每一分都值得\n每一場都精彩'
SIZE = 108  # shaped 648px <= 650 usable (box 680 - 30), HarfBuzz-verified

def main():
    doc = json.loads(DOC.read_text())
    copy = json.loads((ROOT / 'copy.json').read_text())
    current = next(entry for entry in copy['localizations'] if entry['locale'] == 'zh-TW')
    if current['cards'][0]['text'] != CONTENT:
        raise RuntimeError('Historical two-line slogan script is superseded by current copy.json; no artwork changed')
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        shutil.copy2(DOC, BACKUP)
    frame = next(f for f in doc['children'] if f.get('name') == 'zh-TW · 01')
    node = next(c for c in frame['children'] if c.get('name') == 'Center slogan')
    commands = ['get_app_state()',
                'execute(' + json.dumps({'input': 'Update(%s,{content:%s,fontSize:%d});' % (json.dumps(node['id']), json.dumps(CONTENT, ensure_ascii=False), SIZE)}, ensure_ascii=False) + ')',
                'save()',
                'execute(' + json.dumps({'input': 'Export(%s,"png",%s,{scale:1});' % (json.dumps([frame['id']]), json.dumps(str(ROOT / 'exports' / 'zh-TW')))}) + ')',
                'exit()']
    p = subprocess.run(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                        '--in', str(DOC), '--out', str(DOC),
                        '--preview-output', str(ROOT / 'native-preview.png')],
                       input='\n'.join(commands) + '\n', text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    (ROOT / 'pen-zhtw-slogan.log').write_text(p.stdout)
    if p.returncode or 'Error:' in p.stdout or 'Failure during' in p.stdout:
        raise RuntimeError(p.stdout[-2400:])
    from PIL import Image
    temp = ROOT / 'exports' / 'zh-TW' / (frame['id'] + '.png')
    Image.open(temp).convert('RGB').save(ROOT / 'exports' / 'zh-TW' / '01.png')
    temp.unlink()
    print('zh-TW · 01 slogan ->', CONTENT.replace('\n', ' / '), 'at', SIZE, 'pt; re-exported 01.png')

if __name__ == '__main__':
    main()
