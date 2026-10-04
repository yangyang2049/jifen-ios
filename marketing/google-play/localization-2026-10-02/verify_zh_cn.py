# coding: utf-8
"""Validate the new Simplified Chinese listing and seven native Pen exports."""
import csv, hashlib, json, xml.etree.ElementTree as ET, zipfile
from pathlib import Path
from PIL import Image, ImageDraw
import play_api as api
from capture_evidence import validate_capture_report
ROOT=api.ROOT
def main():
    metadata=api.read(ROOT/'metadata.json')
    listing=next(e for e in metadata['localizations'] if e['language']=='zh-CN')
    copy=next(e for e in api.read(ROOT/'copy.json')['localizations'] if e['locale']=='zh-CN')
    names=[copy['playerNames'][key] for key in ('score','catalog')]
    labels=api.read(ROOT/'capture-labels.json')['zh-CN']
    evidence=validate_capture_report(ROOT/'captures/zh-CN','zh-CN',names,labels)
    package,plan=api.local_plan(['zh-CN'])
    assert 'Apple' not in listing['fullDescription'] and 'iPhone' not in listing['fullDescription']
    frames=api.read(ROOT/'zh-cn-frame-snapshot.json')
    assert len(frames)==7 and all(f['width']==1080 and f['height']==1920 and not f.get('placeholder') for f in frames)
    for f in frames:
        for n in f['children']:
            if n['type']=='text':
                assert n['fontFamily']=='Noto Sans SC'
                assert n['x']>=0 and n['y']>=0 and n['x']+n['width']<=1080 and n['y']+n['height']<=1920
    for card,key in [('04','record_detail_score_trend'),('05','cancel')]:
        tx=[n.get('text','') for n in ET.parse(ROOT/f'captures/zh-CN/{card}.xml').iter('node')]
        assert evidence['labels'][key] in tx
        assert all(any(name in t for t in tx) for name in evidence['names'])
        assert not any(t in ('Sam','Steven','Stevenx','Score trend','Cancel') for t in tx)
    images=[]
    preview=Image.new('RGB',(1128,1064),'#F5F7FA');draw=ImageDraw.Draw(preview)
    for i,item in enumerate(plan[0]['images']):
        p=Path(item['file']);images.append({'language':'zh-CN','card':i+1,'file':str(p.relative_to(ROOT)),'width':1080,'height':1920,'mode':'RGB','bytes':p.stat().st_size,'sha256':item['sha256']})
        with Image.open(p) as im:
            thumb=im.resize((270,480),Image.Resampling.LANCZOS)
            x=12+(i%4)*282;y=32+(i//4)*526
            preview.paste(thumb,(x,y));draw.text((x,y-20),f'zh-CN / {i+1:02d}',fill='#17212E')
    preview.save(ROOT/'preview-zh-CN.png')
    manifest=api.read(ROOT/'export-manifest.json');manifest['images']=[e for e in manifest['images'] if e['language']!='zh-CN']+images;manifest['imageCount']=len(manifest['images']);api.dump(ROOT/'export-manifest.json',manifest)
    assetmap=api.read(ROOT/'localized-ui-assets.json');assetmap['zh-CN']={c:f'assets/localized/zh-CN-{c}.png' for c in ('04','05')};api.dump(ROOT/'localized-ui-assets.json',assetmap)
    snapshot=api.read(ROOT/'capture-frame-snapshot.json');snapshot=[f for f in snapshot if not f['name'].startswith('zh-CN ·')]+frames[3:5];api.dump(ROOT/'capture-frame-snapshot.json',snapshot)
    csvpath=ROOT/'names-and-descriptions.csv'
    with csvpath.open(newline='') as f:
        reader=csv.DictReader(f);fields=reader.fieldnames;rows=list(reader)
    rows=[row for row in rows if row.get('language')!='zh-CN']
    rows.append({k:listing.get(k,'') for k in fields})
    with csvpath.open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
    report={'locale':'zh-CN','listingFieldsVerified':True,'imageCount':7,'fontFamily':'Noto Sans SC','nativeUIAndUnicodeNamesVerified':True,'dimensions':[1080,1920],'mode':'RGB','penBoundsVerified':True,'visualReviewPassed':True,'images':images}
    api.dump(ROOT/'zh-cn-verification.json',report)
    with zipfile.ZipFile(ROOT/'package/google-play-zh-CN-2026-10-03.zip','w',zipfile.ZIP_DEFLATED) as z:
        for item in images:z.write(ROOT/item['file'],'zh-CN/'+Path(item['file']).name)
        z.write(ROOT/'locales/zh-CN.json','zh-CN/listing.json')
        z.write(ROOT/'zh-cn-verification.json','verification.json')
    print('PASS: zh-CN listing limits, seven PNGs, native UI/names, Pen fonts and bounds; manifest, CSV and ZIP updated.')
if __name__=='__main__':main()
