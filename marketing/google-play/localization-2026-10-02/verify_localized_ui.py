"""Verify only the two changed screenshots and their capture evidence."""
import hashlib,json,re,sys,xml.etree.ElementTree as ET,zipfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageChops
from capture_evidence import validate_capture_report
ROOT=Path(__file__).resolve().parent

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    eligible=[x['language'] for x in json.loads((ROOT/'metadata.json').read_text())['localizations'] if x.get('uploadEligible')]
    eligible=sys.argv[1:] or [loc for loc in eligible if loc != 'zh-CN']
    copy={x['locale']:x for x in json.loads((ROOT/'copy.json').read_text())['localizations']}
    labels=json.loads((ROOT/'capture-labels.json').read_text())
    evidence_by_locale={}
    for loc in eligible:
        names=[copy[loc]['playerNames'][key] for key in ('score','catalog')]
        evidence_by_locale[loc]=validate_capture_report(ROOT/'captures'/loc,loc,names,labels[loc])
    baseline=json.loads((ROOT/'before-localized-ui/hashes.json').read_text())
    frames=json.loads((ROOT/'capture-frame-snapshot.json').read_text())
    snapshots={f['name']:f for f in frames};assets=[];outside=[];fallback=[]
    for loc in eligible:
        d=ROOT/'captures'/loc
        evidence=evidence_by_locale[loc]
        names=[copy[loc]['playerNames'][x] for x in ('score','catalog')]
        assert evidence['names']==names
        for c in ('04','05'):
            nodes=list(ET.parse(d/(c+'.xml')).iter('node'));tx=[n.get('text','') for n in nodes]
            assert all(any(name in t for t in tx) for name in names),(loc,c,'names')
            assert not any(t in ('Sam','Steven','Stevenx') for t in tx),(loc,c,'old names')
            if c=='04':
                assert evidence['labels']['record_detail_score_trend'] in tx
            else:
                assert evidence['labels']['cancel'] in tx
            p=ROOT/'exports'/loc/(c+'.png')
            with Image.open(p) as im:
                assert im.size==(1080,1920) and im.mode=='RGB' and p.stat().st_size<8*1024*1024
                old=Image.open(ROOT/'before-localized-ui'/Path('exports')/loc/(c+'.png')).convert('RGB')
                mask=Image.new('L',im.size);draw=ImageDraw.Draw(mask)
                if c=='04':
                    draw.rectangle((37,508,1055,1183),fill=255)
                    draw.rectangle((124,1286,955,1919),fill=255)
                else:draw.rectangle((40,523,1039,1919),fill=255)
                diff=ImageChops.difference(old,im);diff.paste((0,0,0),(0,0),mask)
                if diff.point(lambda v:255 if v>1 else 0).getbbox():outside.append(str(p.relative_to(ROOT)))
                assert sha(p)!=baseline[str(p.relative_to(ROOT))]
            frame=snapshots[loc+' · '+c]
            assert frame['fill']['url']==json.loads((ROOT/'localized-ui-assets.json').read_text())[loc][c],(loc,c,'Pen background')
            assets.append({'locale':loc,'card':int(c),'file':str(p.relative_to(ROOT)),'sha256':sha(p),'bytes':p.stat().st_size})
        if not loc.startswith('en-'):
            if evidence['labels']['record_detail_score_trend']=='Score trend':fallback.append(loc)
    unchanged=[]
    for path,expected in baseline.items():
        p=ROOT/path
        if p.stem not in ('04','05') or p.parent.name not in eligible:
            assert sha(p)==expected,('unrelated image changed',path)
            unchanged.append(path)
    assert not outside,outside
    assert not fallback,fallback
    report={'localeCount':len(eligible),'updatedImageCount':len(assets),'unchangedImageCount':len(unchanged),'dimensions':[1080,1920],'mode':'RGB','nativeUnicodeNames':True,'englishTrendFallback':fallback,'changedPixelsOutsideUIRegions':outside,'assets':assets,'verification':'Capture UI labels, names, PNG dimensions/mode, Pen background paths, approved pixel regions, and hashes of every untouched export passed.','googlePlayUploaded':False}
    (ROOT/'localized-ui-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    # Refresh image manifest hashes without disturbing the earlier marketing-fit report.
    manifest=json.loads((ROOT/'export-manifest.json').read_text())
    for e in manifest['images']:
        p=ROOT/e['file']
        if p.exists():e.update(sha256=sha(p),bytes=p.stat().st_size)
    (ROOT/'export-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    dest=ROOT/'package/google-play-localized-cards-04-05-2026-10-03.zip';dest.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for e in assets:z.write(ROOT/e['file'],e['locale']+'/'+Path(e['file']).name)
        z.write(ROOT/'localized-ui-verification.json','verification.json')
    print(f"PASS: {len(eligible)} locales, {len(assets)} updated images, {len(unchanged)} untouched exports; no pixel changes outside UI regions.")
if __name__=='__main__':main()
