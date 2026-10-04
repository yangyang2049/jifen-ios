"""Simplify card-3 headlines (26+ first, one scoreboard second) across GP locales."""
import json, os, select, subprocess, time, re, shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parent
CLI = '/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC = ROOT / 'iScoreboard-GooglePlay-localized.pen'
BASE_SIZE, MAX_H = 96, 250

NEW = {
 'ca': '26+ ESPORTS\nUN MARCADOR',
 'cs-CZ': '26+ SPORTŮ\nJEDNA TABULE',
 'da-DK': '26+ SPORTSGRENE\nÉN MÅLTAVLE',
 'de-DE': '26+ SPORTARTEN\nEINE PUNKTETAFEL',
 'el-GR': '26+ ΑΘΛΗΜΑΤΑ\nΕΝΑΣ ΠΙΝΑΚΑΣ ΣΚΟΡ',
 'es-419': '26+ DEPORTES\nUN MARCADOR',
 'es-ES': '26+ DEPORTES\nUN MARCADOR',
 'fr-CA': '26+ SPORTS\nUN TABLEAU DE POINTAGE',
 'fr-FR': '26+ SPORTS\nUN TABLEAU DE SCORES',
 'hr': '26+ SPORTOVA\nJEDAN SEMAFOR',
 'hu-HU': '26+ SPORTHOZ\nEGY EREDMÉNYJELZŐ',
 'id': '26+ OLAHRAGA\nSATU PAPAN SKOR',
 'ml-IN': '26+ കായിക ഇനങ്ങൾ\nഒരു സ്കോർബോർഡ്',
 'ms-MY': '26+ SUKAN\nSATU PAPAN SKOR',
 'nl-NL': '26+ SPORTEN\nEÉN SCOREBORD',
 'pl-PL': '26+ DYSCYPLIN\nJEDNA TABLICA WYNIKÓW',
 'pt-BR': '26+ ESPORTES\nUM PLACAR',
 'pt-PT': '26+ DESPORTOS\nUM MARCADOR',
 'ro': '26+ DE SPORTURI\nO SINGURĂ TABELĂ',
 'ru-RU': '26+ ВИДОВ СПОРТА\nОДНО ТАБЛО',
 'sk': '26+ ŠPORTOV\nJEDNA TABUĽA',
 'sl': '26+ ŠPORTOV\nEN SEMAFOR',
 'ta-IN': '26+ விளையாட்டுகள்\nஒரே ஸ்கோர்போர்டு',
 'th': 'กีฬากว่า 26 ประเภท\nกระดานเดียว',
 'uk': '26+ ВИДІВ СПОРТУ\nОДНЕ ТАБЛО',
 'ur': '26+ کھیل\nایک اسکور بورڈ',
 'vi': '26+ MÔN THỂ THAO\nMỘT BẢNG ĐIỂM',
}

def main():
    doc = json.loads(DOC.read_text())
    jobs = {}
    for f in doc['children']:
        name = f.get('name', '')
        if '· 03' not in name: continue
        lang = name.split(' · ')[0]
        if lang not in NEW: continue
        head = next((c for c in f.get('children', []) if c.get('name') == 'Marketing headline'), None)
        if head: jobs[lang] = head['id']
    missing = set(NEW) - set(jobs)
    if missing: raise RuntimeError('missing headline nodes: %s' % missing)

    p = subprocess.Popen(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                          '--in', str(DOC), '--out', str(DOC),
                          '--preview-output', str(ROOT / 'native-preview.png')],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
    log = (ROOT / 'pen-simplify-card3.log').open('ab')

    def call(command=None):
        if command is not None:
            p.stdin.write((command + '\n').encode()); p.stdin.flush()
        output = b''; deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            if select.select([p.stdout], [], [], 1)[0]:
                chunk = os.read(p.stdout.fileno(), 65536)
                if not chunk: raise RuntimeError('CLI exited: ' + output.decode(errors='replace'))
                log.write(chunk); log.flush(); output += chunk
                if re.sub(rb'\x1b\[[0-9;]*m', b'', output).endswith(b'pen > '):
                    result = output.decode(errors='replace')
                    if 'Error:' in result or 'Failure during' in result: raise RuntimeError(result)
                    return result
        raise TimeoutError(output.decode(errors='replace'))

    try:
        call(); state = call('get_app_state()')
        if str(DOC) not in state: raise RuntimeError('Unexpected Pen document')
        dest = ROOT / 'exports'
        for lang, hid in sorted(jobs.items()):
            frame_id = next(f['id'] for f in doc['children'] if f.get('name') == f'{lang} · 03')
            code = ('const id=%s;Update(id,{content:%s,fontSize:%d});'
                    'let h=Get(id,(n,c)=>c.bounds.height)[0];'
                    'let size=%d;'
                    'while(h>%d&&size>24){size-=2;Update(id,{fontSize:size});h=Get(id,(n,c)=>c.bounds.height)[0];}'
                    'Update(id,{y:172+(%d-h)/2});Print({lang:%s,size});'
                    ) % (json.dumps(hid), json.dumps(NEW[lang], ensure_ascii=False),
                         BASE_SIZE, BASE_SIZE, MAX_H, MAX_H, json.dumps(lang))
            call('execute(' + json.dumps({'input': code}, ensure_ascii=False) + ')')
            call('save()')
            call('execute(' + json.dumps({'input': 'Export(%s,"png",%s,{scale:1});' % (json.dumps([frame_id]), json.dumps(str(dest)))}, ensure_ascii=False) + ')')
            exported = dest / (frame_id + '.png')
            if not exported.exists(): raise FileNotFoundError(exported)
            Image_fix(exported, dest / lang / '03.png')
            print('done', lang, flush=True)
        print('All card-3 simplifications exported.', flush=True)
    finally:
        p.terminate(); log.close()

def Image_fix(src, dst):
    from PIL import Image
    im = Image.open(src).convert('RGB')
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst)
    src.unlink()

if __name__ == '__main__':
    main()
