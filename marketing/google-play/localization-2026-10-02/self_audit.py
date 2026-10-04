"""Apply reviewed Google Play corrections using the MCP-exported node snapshot."""
import json, csv, shutil, sys, re, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/python'))
import uharfbuzz as hb

def read(n):return json.loads((ROOT/n).read_text())
def dump(n,d):(ROOT/n).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def main():
 backup=ROOT/'before-self-audit';backup.mkdir(exist_ok=True)
 for n in ['metadata.json','copy.json','display-copy.json','layout-adjustments.json','export-manifest.json','upload-plan.json','api-verification.json','pen-nodes-snapshot.json','verification.json']:
  if not (backup/n).exists():shutil.copy2(ROOT/n,backup/n)
 changes=[];metadata=read('metadata.json');copy=read('copy.json');frames=read('pen-nodes-snapshot.json')
 def desc(locale,old,new,reason):
  entry=next(x for x in metadata['localizations'] if x['language']==locale)
  assert old in entry['fullDescription'],(locale,old)
  entry['fullDescription']=entry['fullDescription'].replace(old,new)
  changes.append(dict(locale=locale,field='fullDescription',old=old,new=new,reason=reason))
 desc('da-DK','en terningetimer','en timer til professorterninger','Clarify puzzle-cube timer; avoid dice-timer interpretation.')
 desc('th','เปลี่ยน โทรศัพท์','เปลี่ยนโทรศัพท์','Remove space splitting the Thai verb from its object.')
 desc('th','พิกเคิลบอล','พิคเคิลบอล','Use the established Thai spelling of pickleball.')
 for lang in ['fr-FR','fr-CA']:
  for label in ['Conditions d’utilisation','Politique de confidentialité']:
   desc(lang,label+':',label+' :','French typography: space before colon.')
 headings={
 'id': 'PERMAINAN MULTIPEMAIN\nDAN PERMAINAN PAPAN',
 'hu-HU':'TÖBBJÁTÉKOS JÁTÉKOK\nÉS TÁRSASJÁTÉKOK',
 'bn-BD':'একাধিক খেলোয়াড়ের গেম\nও বোর্ড গেম',
 'hi-IN':'कई खिलाड़ियों वाले गेम\nऔर बोर्ड गेम',
 'gu':'ઘણા ખેલાડીઓની રમતો\nઅને બોર્ડ ગેમ્સ',
 'mr-IN':'अनेक खेळाडूंचे गेम\nआणि बोर्ड गेम',
 'kn-IN':'ಬಹು ಆಟಗಾರರ ಆಟಗಳು\nಮತ್ತು ಬೋರ್ಡ್ ಆಟಗಳು',
 'unsupported-or-IN':'ଏକାଧିକ ଖେଳାଳିଙ୍କ ଖେଳ\nଓ ବୋର୍ଡ ଖେଳ',
 'pa':'ਕਈ ਖਿਡਾਰੀਆਂ ਵਾਲੀਆਂ ਗੇਮਾਂ\nਅਤੇ ਬੋਰਡ ਗੇਮਾਂ',
 'te-IN':'బహుళ ఆటగాళ్ల ఆటలు\nమరియు బోర్డు ఆటలు'}
 slogans={'vi':'MỖI ĐIỂM SỐ\nĐỀU\nQUAN TRỌNG','hi-IN':'हर अंक\nमायने रखता है','pa':'ਹਰ ਅੰਕ\nਮਾਇਨੇ ਰੱਖਦਾ ਹੈ','mr-IN':'प्रत्येक गुण\nमहत्त्वाचा आहे','sk':'KAŽDÝ\nBOD\nSA POČÍTA'}
 fonts=read('fonts/manifest.json');updates=[];report=read('layout-adjustments.json')
 for locale,card,new in [(k,6,v) for k,v in headings.items()]+[(k,1,v) for k,v in slogans.items()]:
  entry=next(x for x in copy['localizations'] if x['locale']==locale)
  frame=next(x for x in frames if x['name']==f'{locale} · {card:02}')
  node=next(x for x in frame['children'] if x.get('name')==('Center slogan' if card==1 else 'Marketing headline'))
  changes.append(dict(locale=locale,card=card,field='screenshotCaption',old=node['content'],new=new,reason='Keep phrase together at manual line breaks.' if card==1 else 'Correct multiplayer/board-game terminology and supply missing noun.'))
  entry['cards'][card-1]['text']=new
  family=re.sub(r'[^a-z]','',node['fontFamily'].lower());italic=node.get('fontStyle')=='italic'
  paths=[ROOT/x['file'] for x in fonts if x['family']==family and x['file'].endswith('.ttf') and ('Italic' in x['file'])==italic]
  path=next((p for p in paths if 'SemiBold' not in p.name),paths[0])
  face=hb.Face(path.read_bytes());font=hb.Font(face);font.scale=(face.upem,face.upem);font.set_variations({'wght':700})
  latin=node['fontFamily'] in ['Poppins','Montserrat','Noto Sans'];ratio=1 if latin else 1.15
  def width(s,size):
   b=hb.Buffer();b.add_str(s);b.guess_segment_properties();hb.shape(font,b)
   return sum(g.x_advance for g in b.glyph_positions)*size/face.upem+max(0,len(b.glyph_infos)-1)*(-.035*size if latin else 0)
  size=130 if card==1 else 96;lines=new.split('\n')
  while max(width(s,size) for s in lines)>node['width']-30 or len(lines)*size*ratio>node['height']-12:size-=2
  props=dict(content=new,fontSize=size,lineHeight=ratio,letterSpacing=-.035*size if latin else 0)
  updates.append(dict(frameId=frame['id'],nodeId=node['id'],frame=frame['name'],locale=locale,card=card,props=props))
  r=next(x for x in report if x['frame']==frame['name'] and x['text']==node['name'])
  r.update(content=new,fontSize=size,shapedMaxLineWidth=round(max(width(s,size) for s in lines),2),estimatedHeight=round(len(lines)*size*ratio,2))
  dest=backup/'exports'/locale;dest.mkdir(parents=True,exist_ok=True)
  if not (dest/f'{card:02}.png').exists():shutil.copy2(ROOT/'exports'/locale/f'{card:02}.png',dest/f'{card:02}.png')
 for field,value in [('platform','Google Play'),('width',1080),('height',1920)]:
  changes.append(dict(field='copy.'+field,old=copy[field],new=value,reason='Correct inherited iOS provenance fields to actual Google Play asset format.'));copy[field]=value
 dump('metadata.json',metadata);dump('copy.json',copy);dump('layout-adjustments.json',report);dump('self-audit-fixes.json',changes);dump('self-audit-native-updates.json',updates)
 for e in metadata['localizations']:dump('locales/'+(e['language'] or 'unsupported-or-IN')+'.json',e)
 with (ROOT/'names-and-descriptions.csv').open('w',newline='') as f:
  fields=['language','sourceLocale','languageName','title','shortDescription','fullDescription','uploadEligible'];w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');w.writeheader();w.writerows(metadata['localizations'])
 print(json.dumps({'corrections':len(changes),'changedFrames':len(updates),'locales':sorted(set(x['locale'] for x in changes if 'locale' in x))},ensure_ascii=False))
if __name__=='__main__':main()
