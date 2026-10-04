"""Fit real shaped text before native Pen export, avoiding orphan automatic wraps."""
import sys, json, os, select, subprocess, time, re, math
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/python'))
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from urllib.parse import unquote
DOC=ROOT/'iScoreboard-GooglePlay-localized.pen'
CLI='/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
fontcache={}
def face(entry):
 p=ROOT/unquote(entry['url'].split('http://127.0.0.1:8771/')[-1]);key=str(p)
 if key not in fontcache:fontcache[key]=hb.Face(p.read_bytes())
 return fontcache[key]
def width(entry,text,size,weight,spacing=0):
 f=hb.Font(face(entry));f.scale=(f.face.upem,f.face.upem);f.set_variations({'wght':weight})
 b=hb.Buffer();b.add_str(text);b.guess_segment_properties();hb.shape(f,b)
 return sum(g.x_advance for g in b.glyph_positions)*size/f.face.upem+max(0,len(b.glyph_infos)-1)*spacing

def main():
 doc=json.loads(DOC.read_text());fonts=doc['fonts'];changes=[];report=[]
 originals={e['locale']:e['cards'][0]['text'] for e in json.loads((ROOT/'copy.json').read_text())['localizations']}
 for frame in doc['children']:
  for node in frame['children']:
   italic=node.get('fontStyle')=='italic';entry=next(f for f in fonts if f['name']==node['fontFamily'] and (f.get('style')=='italic')==italic and (not isinstance(f['weight'],int) or f['weight']==int(node['fontWeight'])))
   content=node['content'];first=node['name']=='Center slogan';limit=520 if first else (250 if node['name']=='Marketing headline' else (168 if node['name']=='Localized player name' else 90))
   initial=130 if first else (96 if node['name']=='Marketing headline' else (104 if node['name']=='Localized player name' else 44))
   latin=node['fontFamily'] in ['Poppins','Montserrat','Noto Sans'];ratio=1 if latin else 1.15
   spacing=lambda size:-size*.035 if latin else 0
   if first:
    content=originals[frame['name'].split(' · ')[0]]
    if frame['name'].startswith('ja-JP '):content='すべての\n得点に\n意味がある'
    else:
     lines=[]
     for line in content.split('\n'):
      paragraph=[]
      parts=line.split(' ');out=''
      for word in parts:
       trial=(out+' '+word).strip()
       if out and width(entry,trial,initial,int(node['fontWeight']),spacing(initial))>node['width']-30:paragraph.append(out);out=word
       else:out=trial
      paragraph.append(out)
      if len(paragraph)>1 and len(paragraph[-2].split(' '))>1 and width(entry,paragraph[-1],initial,int(node['fontWeight'])) < width(entry,paragraph[-2],initial,int(node['fontWeight']))*.45:
       words=paragraph[-2].split(' ');paragraph[-1]=words.pop()+' '+paragraph[-1];paragraph[-2]=' '.join(words)
      lines.extend(paragraph)
     content='\n'.join(lines)
   size=initial;lines=content.split('\n');weight=int(node['fontWeight'])
   while max(width(entry,x,size,weight,spacing(size)) for x in lines)>node['width']-30 or len(lines)*size*ratio>limit-12:
    size-=2
    if size<24:raise ValueError('Cannot fit '+frame['name']+' '+node['name'])
   top=690 if first else (172 if node['name']=='Marketing headline' else (748 if node['name']=='Localized player name' else 630))
   height=len(lines)*size*ratio
   # Native fixed-height preserves the intended manual line breaks and centering.
   props={'content':content,'fontSize':size,'letterSpacing':spacing(size),'lineHeight':ratio,'textGrowth':'fixed-width-height','height':limit,'y':top,'textAlignVertical':'middle' if node['name']!='Marketing headline' else 'top'}
   changes.append({'id':node['id'],'props':props})
   report.append({'frame':frame['name'],'text':node['name'],'content':content,'fontSize':size,'width':node['width'],'shapedMaxLineWidth':round(max(width(entry,x,size,weight,spacing(size)) for x in lines),2),'boxHeight':limit,'estimatedHeight':round(height,2)})
 (ROOT/'layout-adjustments.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 p=subprocess.Popen(['node','--import',str(ROOT/'offline-fonts.mjs'),CLI,'interactive','--in',str(DOC),'--out',str(DOC),'--preview-output',str(ROOT/'native-preview.png')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
 log=(ROOT/'pen-fit.log').open('ab')
 def call(command=None):
  if command:p.stdin.write((command+'\n').encode());p.stdin.flush()
  output=b'';deadline=time.monotonic()+120
  while time.monotonic()<deadline:
   if select.select([p.stdout],[],[],1)[0]:
    chunk=os.read(p.stdout.fileno(),65536)
    if not chunk:raise RuntimeError('CLI exited')
    output+=chunk;log.write(chunk);log.flush()
    if re.sub(rb'\x1b\[[0-9;]*m',b'',output).endswith(b'pen > '):
     result=output.decode(errors='replace')
     if 'Error:' in result or 'Failure during' in result:raise RuntimeError(result)
     return result
  raise TimeoutError(output.decode(errors='replace'))
 try:
  call();call('get_app_state()')
  for start in range(0,len(changes),80):
   code='for(const e of '+json.dumps(changes[start:start+80],ensure_ascii=False)+')Update(e.id,e.props);'
   call('execute('+json.dumps({'input':code},ensure_ascii=False)+')')
  call('save()')
  for locale in json.loads((ROOT/'copy.json').read_text())['localizations']:
   lang=locale['locale'];dest=ROOT/'exports'/lang;nodes=[f for f in doc['children'] if f['name'].startswith(lang+' · ')]
   code='Export('+json.dumps([f['id'] for f in nodes])+',"png",'+json.dumps(str(dest))+',{scale:1});'
   call('execute('+json.dumps({'input':code})+')')
   for frame in nodes:(dest/(frame['id']+'.png')).replace(dest/(frame['name'].split(' · ')[1]+'.png'))
   print('Fitted/exported '+lang,flush=True)
 finally:p.terminate();log.close()
if __name__=='__main__':main()
