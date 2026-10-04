"""Give long headlines more readable type using complete-word line breaks."""
import json, subprocess
from pathlib import Path
from PIL import Image
from fit_pen import width, ROOT, DOC, CLI

def main():
 doc=json.loads(DOC.read_text());report=json.loads((ROOT/'layout-adjustments.json').read_text());targets={x['frame']:x for x in report if x['text']=='Marketing headline' and x['fontSize']<66};updates=[];frames=[]
 for f in doc['children']:
  if f['name'] not in targets:continue
  n=next(n for n in f['children'] if n['name']=='Marketing headline');italic=n.get('fontStyle')=='italic';entry=next(e for e in doc['fonts'] if e['name']==n['fontFamily'] and (e.get('style')=='italic')==italic and (not isinstance(e['weight'],int) or e['weight']==700));latin=n['fontFamily'] in ['Poppins','Montserrat','Noto Sans'];ratio=n['lineHeight'];chosen=None
  for size in range(96,25,-2):
   spacing=-size*.035 if latin else 0;lines=[]
   for line in n['content'].split('\n'):
    out=''
    for word in line.split(' '):
     trial=(out+' '+word).strip()
     if out and width(entry,trial,size,700,spacing)>970:lines.append(out);out=word
     else:out=trial
    lines.append(out)
   if len(lines)*size*ratio<=238 and max(width(entry,line,size,700,spacing) for line in lines)<=970:
    chosen=(size,spacing,lines);break
  if not chosen or chosen[0]<n['fontSize']+4:continue
  size,spacing,lines=chosen;props={'fontSize':size,'letterSpacing':spacing,'content':'\n'.join(lines)};updates.append({'id':n['id'],'props':props});frames.append(f)
  x=targets[f['name']];x.update({'content':props['content'],'fontSize':size,'shapedMaxLineWidth':round(max(width(entry,line,size,700,spacing) for line in lines),2),'estimatedHeight':round(len(lines)*size*ratio,2)})
  print(f['name'],n['fontSize'],'→',size,flush=True)
 commands=['get_app_state()','execute('+json.dumps({'input':'for(const e of '+json.dumps(updates,ensure_ascii=False)+')Update(e.id,e.props);'},ensure_ascii=False)+')','save()']
 for f in frames:
  lang=f['name'].split(' · ')[0];commands.append('execute('+json.dumps({'input':'Export('+json.dumps([f['id']])+',"png",'+json.dumps(str(ROOT/'exports'/lang))+',{scale:1});'})+')')
 commands.append('exit()')
 p=subprocess.run(['node','--import',str(ROOT/'offline-fonts.mjs'),CLI,'interactive','--in',str(DOC),'--out',str(DOC),'--preview-output',str(ROOT/'native-preview.png')],input='\n'.join(commands)+'\n',text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
 (ROOT/'pen-title-refinement.log').write_text(p.stdout)
 if p.returncode or 'Error:' in p.stdout:raise RuntimeError(p.stdout[-2400:])
 for f in frames:
  lang,num=f['name'].split(' · ');folder=ROOT/'exports'/lang;temp=folder/(f['id']+'.png');Image.open(temp).convert('RGB').save(folder/(num+'.png'));temp.unlink()
 (ROOT/'layout-adjustments.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('Refined',len(frames),'headlines.')
if __name__=='__main__':main()
