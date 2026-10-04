"""Re-export only the · 03 card for every locale after the Edit-button asset repair."""
import json, os, select, subprocess, time, re
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CLI='/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC=ROOT/'iScoreboard-GooglePlay-localized.pen'

def main():
 p=subprocess.Popen(['node','--import',str(ROOT/'offline-fonts.mjs'),CLI,'interactive','--in',str(DOC),'--out',str(DOC),'--preview-output',str(ROOT/'native-preview.png')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
 log=(ROOT/'pen-reexport-03.log').open('ab')
 def call(command=None):
  if command is not None:p.stdin.write((command+'\n').encode());p.stdin.flush()
  output=b'';deadline=time.monotonic()+120
  while time.monotonic()<deadline:
   if select.select([p.stdout],[],[],1)[0]:
    chunk=os.read(p.stdout.fileno(),65536)
    if not chunk:raise RuntimeError('CLI exited: '+output.decode(errors='replace'))
    log.write(chunk);log.flush();output+=chunk
    if re.sub(rb'\x1b\[[0-9;]*m',b'',output).endswith(b'pen > '):
     result=output.decode(errors='replace')
     if 'Error:' in result or 'Failure during' in result:raise RuntimeError(result)
     return result
  raise TimeoutError(output.decode(errors='replace'))
 try:
  call();state=call('get_app_state()')
  if str(DOC) not in state:raise RuntimeError('Unexpected Pen document')
  doc=json.loads(DOC.read_text())
  cards=[n for n in doc['children'] if n.get('name','').endswith('· 03')]
  print(f'Re-exporting {len(cards)} card-03 frames',flush=True)
  for n in cards:
   lang=n['name'].split(' · ')[0]
   dest=ROOT/'exports'/lang;dest.mkdir(parents=True,exist_ok=True)
   code='Export('+json.dumps([n['id']])+',"png",'+json.dumps(str(dest))+',{scale:1});'
   call('execute('+json.dumps({'input':code},ensure_ascii=False)+')')
   exported=dest/(n['id']+'.png')
   if not exported.exists():raise FileNotFoundError(exported)
   exported.rename(dest/'03.png')
   print('Finished '+lang,flush=True)
  print('All card-03 exports complete.',flush=True)
 finally:p.terminate();log.close()
if __name__=='__main__':main()
