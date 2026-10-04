"""Place real localized Android captures into original GP card 4/5 artwork.
All UI text and names are rendered by Android; no raster text substitution.
Marketing headlines remain editable in the existing Pen document.
"""
import json,re,sys,xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image,ImageDraw
from capture_evidence import validate_capture_report
ROOT=Path(__file__).resolve().parent
CAPS=ROOT/'captures';ASSETS=ROOT/'assets/localized'
C5_INNER=(60,543,1020,1920)
C4_CARD=(49,520,1044,1171)
C4_PHONE_INNER=(140,1302,940,1920)
LABELS=json.loads((ROOT/'capture-labels.json').read_text())
COPY={e['locale']:e for e in json.loads((ROOT/'copy.json').read_text())['localizations']}

def rounded_mask(size,radius,sides='top'):
    m=Image.new('L',size,0);d=ImageDraw.Draw(m)
    d.rounded_rectangle((0,0,size[0]-1,size[1]-1),radius=radius,fill=255)
    if sides=='top':d.rectangle((0,radius,size[0]-1,size[1]-1),fill=255)
    return m

def bounds(n):return tuple(map(int,re.findall(r'\d+',n.get('bounds',''))))

def composite_04(loc):
    cap=Image.open(CAPS/loc/'04.png').convert('RGB')
    trend=Image.open(CAPS/loc/'04-trend.png').convert('RGB')
    nodes=list(ET.parse(CAPS/loc/'04-trend.xml').iter('node'))
    header=next(n for n in nodes if n.get('text')==LABELS[loc]['record_detail_score_trend'])
    hy=bounds(header)[1]
    names=list(COPY[loc]['playerNames'].values())
    legends=[bounds(n) for n in nodes if n.get('text') in names and bounds(n)[1]>hy]
    if len(legends)!=2:raise RuntimeError(loc+': incomplete trend legend')
    bottom=max(b[3] for b in legends)+18
    if bottom>1880:raise RuntimeError(loc+': legend too close to bottom navigation')
    band=trend.crop((36,hy-28,1044,bottom))
    bg=Image.open(ROOT/'assets/google-play-background-4.png').convert('RGB')
    x1,y1,x2,y2=C4_CARD;cw,ch=x2-x1,y2-y1
    card=Image.new('RGB',(cw,ch),'white')
    width=cw-48;scale=width/band.width
    scaled=band.resize((width,round(band.height*scale)),Image.Resampling.LANCZOS)
    if scaled.height>ch-40:raise RuntimeError(loc+': trend does not fit')
    card.paste(scaled,(24,(ch-scaled.height)//2))
    bg.paste(card,(x1,y1),rounded_mask((cw,ch),46,'all'))
    content=cap.crop((0,118,1080,1200))
    x1,y1,x2,y2=C4_PHONE_INNER;w=x2-x1
    scaled=content.resize((w,round(content.height*w/content.width)),Image.Resampling.LANCZOS)
    h=y2-y1;bg.paste(scaled.crop((0,0,w,h)),(x1,y1),rounded_mask((w,h),30))
    return bg

def composite_05(loc):
    cap=Image.open(CAPS/loc/'05.png').convert('RGB')
    bg=Image.open(ROOT/'assets/google-play-background-5.png').convert('RGB')
    x1,y1,x2,y2=C5_INNER;w=x2-x1;h=y2-y1
    scaled=cap.resize((w,round(cap.height*w/cap.width)),Image.Resampling.LANCZOS)
    bg.paste(scaled.crop((0,0,w,h)),(x1,y1),rounded_mask((w,h),80))
    return bg

def main():
    locales=sys.argv[1:] or [e['language'] for e in json.loads((ROOT/'metadata.json').read_text())['localizations'] if e.get('uploadEligible')]
    for loc in locales:
        names=[COPY[loc]['playerNames'][key] for key in ('score','catalog')]
        validate_capture_report(CAPS/loc,loc,names,LABELS[loc])
    ASSETS.mkdir(parents=True,exist_ok=True)
    for loc in locales:
        for card,func in [('04',composite_04),('05',composite_05)]:func(loc).save(ASSETS/f'{loc}-{card}.png')
        print('composited',loc,flush=True)
if __name__=='__main__':main()
