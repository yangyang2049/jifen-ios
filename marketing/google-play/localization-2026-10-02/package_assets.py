"""Bundle only reviewable metadata, fonts, design, and screenshots; never keys."""
from pathlib import Path
import zipfile
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent

def preview(filename,languages):
 out=Image.new('RGB',(1512,len(languages)*420),'#222');d=ImageDraw.Draw(out)
 for row,lang in enumerate(languages):
  d.text((8,row*420+8),lang,fill='white')
  for i in range(7):
   x=Image.open(ROOT/'exports'/lang/f'{i+1:02}.png');x.thumbnail((216,384));out.paste(x,(i*216,row*420+30))
 out.save(ROOT/filename)

def main():
 preview('preview-major.png',['en-US','ja-JP','ar','ru-RU','ko-KR','hi-IN'])
 preview('preview-scripts.png',['iw-IL','ur','th','bn-BD','kn-IN','ml-IN','ta-IN','te-IN','gu','pa'])
 dest=ROOT/'package';dest.mkdir(exist_ok=True)
 allowed={'exports','fonts','assets','locales'}
 files=['metadata.json','copy.json','locale-map.json','names-and-descriptions.csv','iScoreboard-GooglePlay-localized.pen','README.md','verification.json','export-manifest.json','layout-adjustments.json','auth-status.json','play_api.py','upload-plan.json','api-verification.json','basketball-teams.json','basketball-verification.json','basketball-update-template.js','refresh_basketball_api.py','pen-nodes-snapshot.json','verify_assets.py','preview-basketball-update.png','preview-major.png','preview-scripts.png','self-audit-report.json','self-audit-fixes.json','self-audit-native-updates.json','self-audit-native-measurements.json','refresh_self_audit_api.py','self_audit.py','preview-self-audit.png']
 with zipfile.ZipFile(dest/'iScoreboard-GooglePlay-localization-2026-10-02.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=4) as z:
  for p in sorted(ROOT.rglob('*')):
   rel=p.relative_to(ROOT)
   if p.is_file() and (rel.parts[0] in allowed or str(rel) in files):z.write(p,arcname='iScoreboard-GooglePlay/'+str(rel))
 print('Packaged final material:',(dest/'iScoreboard-GooglePlay-localization-2026-10-02.zip').stat().st_size,'bytes')
if __name__=='__main__':main()
