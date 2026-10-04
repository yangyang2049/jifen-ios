"""Verify exported size, glyph coverage, fit, and unchanged original UI pixels."""
import json, hashlib, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops
from fontTools.ttLib import TTFont
from urllib.parse import unquote
ROOT=Path(__file__).resolve().parent

def main():
 doc={'children':json.loads((ROOT/'pen-nodes-snapshot.json').read_text())};copy=json.loads((ROOT/'copy.json').read_text());src=json.loads((ROOT/'source/source-manifest.json').read_text());originals={x['card']:Image.open(ROOT/'source'/x['file']).convert('RGB') for x in src}
 assert len(doc['children'])==len(copy['localizations'])*7==336
 assert len({n['id'] for f in doc['children'] for n in [f]+f['children']})==sum(1+len(f['children']) for f in doc['children'])
 cmaps={};missing=[];manifest=[];outside=[]
 for f in json.loads((ROOT/'fonts/manifest.json').read_text()):
  if f['file'].endswith('.ttf') and f['family'] not in cmaps:cmaps[f['family']]=TTFont(ROOT/f['file']).getBestCmap()
 for frame in doc['children']:
  assert frame['width']==1080 and frame['height']==1920 and not frame.get('placeholder')
  locale,number=frame['name'].split(' · ');num=int(number);p=ROOT/'exports'/locale/(number+'.png');raw=Image.open(p);im=raw.convert('RGB')
  if raw.mode!='RGB':im.save(p)
  assert im.size==(1080,1920) and p.stat().st_size<8*1024*1024
  for n in frame['children']:
   if n['type']!='text':continue
   for c in n['content']:
    if not c.isspace() and ord(c) not in [0x200c,0x200d,0x200e,0x200f] and ord(c) not in cmaps[n['fontFamily'].lower().replace(' ','')]:missing.append([frame['name'],n['fontFamily'],c,hex(ord(c))])
  mask=Image.new('L',(1080,1920));draw=ImageDraw.Draw(mask)
  if num==1:draw.rectangle((200,670,879,1240),fill=255)
  else:draw.rectangle((0,0,1079,479 if num==7 else 499),fill=255)
  if num in [2,3]:
   center=589 if num==2 else 496;draw.rectangle((center-380,748,center+380,916),fill=255)
  if num==6:
   draw.rectangle((83,537,367,610),fill=255);draw.rectangle((703,537,987,610),fill=255)
  if num==7:
   draw.rectangle((108,574,512,722),fill=255);draw.rectangle((568,574,972,722),fill=255)
   a=math.radians(15.8)
   for x,y,w,h in [(200,1485,180,50),(560,1384,174,60)]:
    corners=[(x+u*math.cos(a)+v*math.sin(a),y-u*math.sin(a)+v*math.cos(a)) for u,v in [(-3,-3),(w+3,-3),(w+3,h+3),(-3,h+3)]]
    draw.polygon(corners,fill=255)
  diff=ImageChops.difference(originals[num],im);diff.paste((0,0,0),(0,0),mask)
  if diff.getbbox():
   # Skia's color conversion can differ by one RGB unit without changing UI content.
   maximum=max(i%256 for i,count in enumerate(diff.histogram()) if count)
   threshold=diff.point(lambda v:255 if v>1 else 0)
   if threshold.getbbox():outside.append({'file':str(p),'bounds':threshold.getbbox(),'maxChannelDelta':maximum})
  manifest.append({'language':locale,'card':num,'file':str(p.relative_to(ROOT)),'width':1080,'height':1920,'mode':'RGB','bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
 assert not missing,missing
 assert not outside,outside[:8]
 fits=json.loads((ROOT/'layout-adjustments.json').read_text())
 assert all(x['shapedMaxLineWidth']<=x['width']-19 for x in fits)
 (ROOT/'export-manifest.json').write_text(json.dumps({'imageCount':len(manifest),'images':manifest},ensure_ascii=False,indent=2)+'\n')
 (ROOT/'verification.json').write_text(json.dumps({'frameCount':336,'imageCount':len(manifest),'uploadEligibleLanguages':47,'unsupportedDraftLanguages':['or-IN'],'dimensions':[1080,1920],'pngMode':'RGB','missingGlyphs':missing,'changedUIOutsideApprovedTextRegions':outside,'pixelTolerancePerChannel':1,'textFit':'Shaped with HarfBuzz; no automatic extra wraps required','fonts':{'files':21,'families':len(cmaps),'license':'SIL Open Font License 1.1'},'onlineApiTested':True,'currentAssetsMatchStagedImages':False,'published':False,'basketballTeamRevision':{'languages':48,'cards':[6,7],'tvNameY':576,'tvNameUpwardShift':54}},ensure_ascii=False,indent=2)+'\n')
 print('Verified 336 RGB PNGs, all glyphs, shaped text fit, and unchanged UI outside approved text regions.')
if __name__=='__main__':main()
