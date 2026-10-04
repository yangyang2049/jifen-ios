"""Build/export an isolated editable Pen document with the official headless CLI."""
import json, os, select, subprocess, time, re, argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CLI='/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC=ROOT/'iScoreboard-GooglePlay-localized.pen'

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--locales',nargs='+');args=parser.parse_args()
 p=subprocess.Popen(['node','--import',str(ROOT/'offline-fonts.mjs'),CLI,'interactive','--in',str(DOC),'--out',str(DOC),'--preview-output',str(ROOT/'native-preview.png')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
 log=(ROOT/'pen-build.log').open('ab')
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
  copy=json.loads((ROOT/'copy.json').read_text());existing={n['name'] for n in json.loads(DOC.read_text())['children']}
  for row,locale in enumerate(copy['localizations']):
   lang=locale['locale']
   if args.locales and lang not in args.locales:continue
   dest=ROOT/'exports'/lang;dest.mkdir(parents=True,exist_ok=True)
   if f'{lang} · 01' not in existing:
    values={'locale':lang,'font':locale['fontFamily'],'cards':locale['cards'],'names':[locale['playerNames']['score'],locale['playerNames']['catalog']],'row':row}
    code='const v='+json.dumps(values,ensure_ascii=False)+';'
    code+='''const ids=[];function addText(frame,name,content,x,y,width,maxHeight,size,weight,center,italic){
      const latin=v.font==="Poppins"||v.font==="Montserrat"||v.font==="Noto Sans";
      const props={type:"text",name,content,x,y,width,textGrowth:"fixed-width",fontFamily:v.font,fontSize:size,fontWeight:weight,fill:"#FFFFFF",textAlign:"center",lineHeight:latin?1:1.15};
      if(italic&&latin)props.fontStyle="italic";
      if(latin)props.letterSpacing=-size*0.035;
      const id=Insert(frame,props);
      let height=Get(id,(n,c)=>c.bounds.height)[0];
      while(height>maxHeight&&size>24){size-=2;Update(id,{fontSize:size,...(latin?{letterSpacing:-size*0.035}:{})});height=Get(id,(n,c)=>c.bounds.height)[0];}
      if(height>maxHeight)throw new Error("Text overflow: "+name+" "+v.locale);
      if(center)Update(id,{y:y+(maxHeight-height)/2});
      return id;
    }
    for(let i=0;i<7;i++){
      const frame=Insert(document,{type:"frame",name:v.locale+" · "+String(i+1).padStart(2,"0"),x:i*1200,y:v.row*2100,width:1080,height:1920,clip:true,layout:"none",placeholder:true,fill:{type:"image",enabled:true,url:"assets/google-play-background-"+(i+1)+".png",mode:"stretch"}});
      if(i===0)addText(frame,"Center slogan",v.cards[i].text,200,690,680,520,160,"700",true,false);
      else addText(frame,"Marketing headline",v.cards[i].text,40,172,1000,250,96,"700",false,true);
      if(i===1||i===2)addText(frame,"Localized player name",v.names[i-1],(i===1?589:496)-380,748,760,168,104,"600",true,false);
      if(i===6){addText(frame,"TV left name",v.names[0],110,630,400,90,44,"600",true,false);addText(frame,"TV right name",v.names[1],570,630,400,90,44,"600",true,false);}
      Update(frame,{placeholder:false});ids.push(frame);
    }Print({locale:v.locale,ids});'''
    call('execute('+json.dumps({'input':code},ensure_ascii=False)+')');call('save()')
   doc=json.loads(DOC.read_text());nodes=[next(n for n in doc['children'] if n['name']==f'{lang} · {i:02}') for i in range(1,8)]
   ids=[n['id'] for n in nodes]
   if not all((dest/f'{i:02}.png').exists() for i in range(1,8)):
    for fid in ids:
     code='Export('+json.dumps([fid])+',"png",'+json.dumps(str(dest))+',{scale:1});'
     call('execute('+json.dumps({'input':code})+')')
    for i,n in enumerate(nodes,1):
     exported=dest/(n['id']+'.png')
     if not exported.exists():raise FileNotFoundError(exported)
     exported.rename(dest/f'{i:02}.png')
   print('Finished '+lang,flush=True)
  print('All selected locale exports complete.',flush=True)
 finally:p.terminate();log.close()
if __name__=='__main__':main()
