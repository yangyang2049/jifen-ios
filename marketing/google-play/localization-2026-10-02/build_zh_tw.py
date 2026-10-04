"""Build the zh-TW row (7 cards, incl. basketball layers) in the local Play pen doc and export PNGs."""
import json, os, select, subprocess, time, re, hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parent
CLI = '/Users/yangyang/.codex/tools/pen-localization/node_modules/.bin/pen'
DOC = ROOT / 'iScoreboard-GooglePlay-localized.pen'

copy = json.loads((ROOT / 'copy.json').read_text())
loc = next(x for x in copy['localizations'] if x['locale'] == 'zh-TW')
row = copy['localizations'].index(loc)
values = {'locale': loc['locale'], 'font': loc['fontFamily'], 'cards': loc['cards'],
          'names': [loc['playerNames']['score'], loc['playerNames']['catalog']],
          'teams': loc['basketballTeamNames'], 'row': row}

def main():
    p = subprocess.Popen(['node', '--import', str(ROOT / 'offline-fonts.mjs'), CLI, 'interactive',
                          '--in', str(DOC), '--out', str(DOC),
                          '--preview-output', str(ROOT / 'native-preview.png')],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
    log = (ROOT / 'pen-build-zhtw.log').open('ab')

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
        doc = json.loads(DOC.read_text())
        if any(n['name'] == 'zh-TW · 01' for n in doc['children']):
            raise RuntimeError('zh-TW row already exists')
        code = 'const v=' + json.dumps(values, ensure_ascii=False) + ';'
        code += '''const ids=[];function addText(frame,name,content,x,y,width,maxHeight,size,weight,center,italic){
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
      if(i===5){for(let side=0;side<2;side++){const x=side===0?85:705;Insert(frame,{type:"rectangle",name:"Basketball team background · "+side,x,y:539,width:280,height:69,fill:side===0?"#C62828":"#007AFF"});addText(frame,"Basketball team name · "+side,v.teams[side],x,540,280,65,44,"600",true,false);}}
      if(i===6){addText(frame,"TV left name",v.teams[0],110,576,400,90,44,"600",true,false);addText(frame,"TV right name",v.teams[1],570,576,400,90,44,"600",true,false);
        for(let side=0;side<2;side++){const x=side===0?200:560;const y=side===0?1485:1384;const w=side===0?180:174;const h=side===0?50:60;
          Insert(frame,{type:"rectangle",name:"Phone basketball team background · "+side,x,y,width:w,height:h,rotation:15.8,fill:side===0?"#C62828":"#007AFF"});
          addText(frame,"Phone basketball team name · "+side,v.teams[side],x,y,w,h,28,"600",true,false);}}
      Update(frame,{placeholder:false});ids.push(frame);
    }Print({locale:v.locale,ids});'''
        call('execute(' + json.dumps({'input': code}, ensure_ascii=False) + ')')
        call('save()')
        doc = json.loads(DOC.read_text())
        nodes = [next(n for n in doc['children'] if n['name'] == 'zh-TW · %02d' % (i + 1)) for i in range(7)]
        dest = ROOT / 'exports' / 'zh-TW'; dest.mkdir(parents=True, exist_ok=True)
        for n in nodes:
            code = 'Export(' + json.dumps([n['id']]) + ',"png",' + json.dumps(str(dest)) + ',{scale:1});'
            call('execute(' + json.dumps({'input': code}) + ')')
            exported = dest / (n['id'] + '.png')
            if not exported.exists(): raise FileNotFoundError(exported)
            exported.rename(dest / ('%02d.png' % (nodes.index(n) + 1)))
        print('zh-TW row built and exported.', flush=True)
    finally:
        p.terminate(); log.close()

if __name__ == '__main__':
    main()
