"""Keep the prior export pixels outside the two approved app-UI regions.
Native Pen provides the changed UI; unchanged headlines/artwork reuse their
existing pixels so font renderer/cache differences do not widen the diff.
"""
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent

def main():
    selected=set(sys.argv[1:])
    for frame in json.loads((ROOT/'capture-frame-snapshot.json').read_text()):
        loc,c=frame['name'].split(' · ')
        if selected and loc not in selected:continue
        if loc=='unsupported-or-IN':continue
        dest=ROOT/'exports'/loc
        native=dest/(frame['id']+'.png')
        if not native.exists():native=dest/(c+'.png')
        new=Image.open(native).convert('RGB');old=Image.open(ROOT/'before-localized-ui/exports'/loc/(c+'.png')).convert('RGB')
        mask=Image.new('L',new.size);d=ImageDraw.Draw(mask)
        if c=='04':
            d.rectangle((37,508,1055,1183),fill=255);d.rectangle((124,1286,955,1919),fill=255)
        else:d.rectangle((40,523,1039,1919),fill=255)
        old.paste(new,(0,0),mask);old.save(dest/(c+'.png'))
        if native.name!=c+'.png':native.unlink()
if __name__=='__main__':main()
