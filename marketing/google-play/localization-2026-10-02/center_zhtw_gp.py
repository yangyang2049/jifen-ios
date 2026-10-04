"""Normalize zh-TW text-node layout props to the en-US reference and re-export."""
import json, shutil, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parent
CLI = '/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC = ROOT / 'iScoreboard-GooglePlay-localized.pen'
BACKUP = ROOT.parents[1] / 'artifacts/google-play-copy-fix-20261003/before-zhtw-centering' / DOC.name
PROPS = ('textGrowth', 'height', 'textAlignVertical', 'y')

def snap(frame):
    return {c['name']: c for c in frame.get('children', []) if c.get('type') == 'text'}

def main():
    doc = json.loads(DOC.read_text())
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        shutil.copy2(DOC, BACKUP)
    by_num = {}
    for frame in doc['children']:
        name = frame.get('name', '')
        if '·' not in name: continue
        lang, num = [x.strip() for x in name.split('·')]
        by_num.setdefault(num, {})[lang] = frame
    updates, changed = [], []
    for num, langs in sorted(by_num.items()):
        zh = langs.get('zh-TW')
        en = langs.get('en-US')
        if not zh or not en: continue
        en_nodes, zh_nodes = snap(en), snap(zh)
        for node_name, zh_node in zh_nodes.items():
            en_node = en_nodes.get(node_name)
            if not en_node: continue
            props = {k: en_node.get(k) for k in PROPS if zh_node.get(k) != en_node.get(k)}
            if props:
                updates.append({'id': zh_node['id'], 'props': props})
                changed.append((f'zh-TW · {num}', node_name, props))
    if not changed:
        print('Nothing to change.'); return
    commands = ['get_app_state()',
                'execute(' + json.dumps({'input': 'for(const e of %s)Update(e.id,e.props);' % json.dumps(updates, ensure_ascii=False)}, ensure_ascii=False) + ')',
                'save()']
    zh_frames = {num: langs['zh-TW'] for num, langs in by_num.items() if 'zh-TW' in langs}
    for num, frame in sorted(zh_frames.items()):
        dest = ROOT / 'exports' / 'zh-TW'
        commands.append('execute(' + json.dumps({'input': 'Export(%s,"png",%s,{scale:1});' % (json.dumps([frame['id']]), json.dumps(str(dest)))}) + ')')
    commands.append('exit()')
    p = subprocess.run(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                        '--in', str(DOC), '--out', str(DOC),
                        '--preview-output', str(ROOT / 'native-preview.png')],
                       input='\n'.join(commands) + '\n', text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    (ROOT / 'pen-center-zhtw.log').write_text(p.stdout)
    if p.returncode or 'Error:' in p.stdout or 'Failure during' in p.stdout:
        raise RuntimeError(p.stdout[-2400:])
    from PIL import Image
    for num, frame in sorted(zh_frames.items()):
        temp = ROOT / 'exports' / 'zh-TW' / (frame['id'] + '.png')
        final = ROOT / 'exports' / 'zh-TW' / (num + '.png')
        Image.open(temp).convert('RGB').save(final)
        temp.unlink()
    for name, node, props in changed:
        print('%-12s %-30s %s' % (name, node, props))
    print('Normalized', len(changed), 'zh-TW nodes; re-exported', len(zh_frames), 'frames.')

if __name__ == '__main__':
    main()
