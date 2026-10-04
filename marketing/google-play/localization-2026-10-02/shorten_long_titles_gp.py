"""Shorten overflowing GP headlines to match iOS's tidy two-line look and re-export."""
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fit_pen import width, ROOT, DOC, CLI

# frame -> (new content, new fontSize, new letterSpacing); content None keeps current text.
JOBS = {
 'ru-RU · 03': ('26+ ДИСЦИПЛИН\nОДНО ТАБЛО', 96, None),
 'fr-FR · 03': (None, 84, -2.94),
 'fr-CA · 03': ('26+ SPORTS\nUN TABLEAU DE SCORES', 84, -2.94),
 'pl-PL · 03': ('26+ DYSCYPLIN\nJEDNA TABLICA', 96, None),
 'ml-IN · 03': (None, 82, None),
 'ta-IN · 03': (None, 82, None),
 'de-DE · 07': ('DEINE PUNKTETAFEL\nAUF DEM FERNSEHER', 96, -3.36),
 'ms-MY · 06': ('BERBILANG PEMAIN\nDAN PAPAN PERMAINAN', 84, -2.94),
 'ml-IN · 06': ('മൾട്ടിപ്ലെയർ\nബോർഡ് ഗെയിമുകളും', 78, None),
 'ml-IN · 07': ('സ്കോർബോർഡ്\nവലിയ സ്ക്രീനിൽ', 96, None),
 'ta-IN · 04': ('ஒவ்வொரு ஆட்டமும்\nமீண்டும் பாருங்கள்', 82, None),
 'ta-IN · 06': ('மல்டிபிளேயர்\nபலகை விளையாட்டுகள்', 68, None),
}

def main():
    doc = json.loads(DOC.read_text())
    fonts = doc['fonts']
    updates, frames, report = [], [], {}
    for frame in doc['children']:
        name = frame.get('name', '')
        if name not in JOBS: continue
        content, size, spacing = JOBS[name]
        node = next(c for c in frame['children'] if c.get('name') == 'Marketing headline')
        text = content if content is not None else node['content']
        italic = node.get('fontStyle') == 'italic'
        entry = next(f for f in fonts if f['name'] == node['fontFamily'] and (f.get('style') == 'italic') == italic and (not isinstance(f['weight'], int) or f['weight'] == int(node['fontWeight'])))
        sp = spacing if spacing is not None else node.get('letterSpacing', 0)
        ratio = node.get('lineHeight', 1)
        lines = text.split('\n')
        maxw = max(width(entry, l, size, int(node['fontWeight']), sp) for l in lines)
        if maxw > node['width'] - 30: raise RuntimeError('still overflowing: %s %d' % (name, maxw))
        props = {'fontSize': size, 'letterSpacing': sp}
        if content is not None: props['content'] = content
        updates.append({'id': node['id'], 'props': props})
        frames.append(frame)
        report[name] = {'content': text, 'fontSize': size, 'shapedMaxLineWidth': round(maxw, 2), 'estimatedHeight': round(len(lines) * size * ratio, 2)}
    missing = set(JOBS) - set(report)
    if missing: raise RuntimeError('missing frames: %s' % missing)

    commands = ['get_app_state()',
                'execute(' + json.dumps({'input': 'for(const e of %s)Update(e.id,e.props);' % json.dumps(updates, ensure_ascii=False)}, ensure_ascii=False) + ')',
                'save()']
    for frame in frames:
        lang, num = frame['name'].split(' · ')
        dest = ROOT / 'exports' / lang
        commands.append('execute(' + json.dumps({'input': 'Export(%s,"png",%s,{scale:1});' % (json.dumps([frame['id']]), json.dumps(str(dest)))}) + ')')
    commands.append('exit()')
    p = subprocess.run(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                        '--in', str(DOC), '--out', str(DOC),
                        '--preview-output', str(ROOT / 'native-preview.png')],
                       input='\n'.join(commands) + '\n', text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    (ROOT / 'pen-shorten-titles.log').write_text(p.stdout)
    if p.returncode or 'Error:' in p.stdout or 'Failure during' in p.stdout:
        raise RuntimeError(p.stdout[-2400:])

    from PIL import Image
    for frame in frames:
        lang, num = frame['name'].split(' · ')
        temp = ROOT / 'exports' / lang / (frame['id'] + '.png')
        Image.open(temp).convert('RGB').save(ROOT / 'exports' / lang / (num + '.png'))
        temp.unlink()

    adj = json.loads((ROOT / 'layout-adjustments.json').read_text())
    for row in adj:
        if row.get('frame') in report and row.get('text') == 'Marketing headline':
            row.update(report[row['frame']])
    (ROOT / 'layout-adjustments.json').write_text(json.dumps(adj, ensure_ascii=False, indent=2) + '\n')
    for name, row in sorted(report.items()):
        print('%-12s size %3d maxw %6.1f h %5.1f | %s' % (name, row['fontSize'], row['shapedMaxLineWidth'], row['estimatedHeight'], row['content'].replace('\n', ' / ')))
    print('Updated', len(frames), 'headlines.')

if __name__ == '__main__':
    main()
