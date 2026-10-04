"""Validate locally, inspect Play, or stage listing edits. Commits only with explicit --commit."""
import argparse, base64, hashlib, json, time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
ROOT = Path(__file__).resolve().parent
API = 'https://androidpublisher.googleapis.com/androidpublisher/v3'
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'

def read(path): return json.loads(path.read_text())
def dump(path, value): path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def local_plan(locales):
 from PIL import Image
 data=read(ROOT/'metadata.json'); selected=[e for e in data['localizations'] if e['uploadEligible'] and (not locales or e['language'] in locales)]
 if locales and set(locales)-{e['language'] for e in selected}: raise ValueError('Unknown or unsupported locale selection')
 plan=[]
 for e in selected:
  for key,limit in data['limits'].items():
   if not 0<len(e[key])<=limit: raise ValueError(f"{e['language']} {key} exceeds limit")
  files=sorted((ROOT/e['screenshotFolder']).glob('[0-9][0-9].png'))
  if len(files)!=7: raise ValueError(f"{e['language']}: expected seven screenshots, found {len(files)}")
  hashes=[]
  for p in files:
   with Image.open(p) as im:
    if im.size!=(1080,1920) or im.mode!='RGB': raise ValueError(f'Invalid image: {p}')
   if p.stat().st_size>8*1024*1024: raise ValueError(f'Image exceeds 8 MB: {p}')
   hashes.append({'file':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
  plan.append({'language':e['language'],'listing':{k:e[k] for k in ['language','title','shortDescription','fullDescription']},'images':hashes})
 return data['packageName'],plan

def token(credentials):
 from cryptography.hazmat.primitives import hashes, serialization
 from cryptography.hazmat.primitives.asymmetric import padding
 c=read(credentials)
 if c.get('type')!='service_account':raise ValueError('Expected a Google service-account JSON key, not google-services.json')
 enc=lambda b:base64.urlsafe_b64encode(b).rstrip(b'=')
 now=int(time.time()); header=enc(json.dumps({'alg':'RS256','typ':'JWT'},separators=(',',':')).encode())
 claims=enc(json.dumps({'iss':c['client_email'],'scope':SCOPE,'aud':'https://oauth2.googleapis.com/token','iat':now,'exp':now+3600},separators=(',',':')).encode())
 unsigned=header+b'.'+claims
 key=serialization.load_pem_private_key(c['private_key'].encode(),password=None)
 assertion=unsigned+b'.'+enc(key.sign(unsigned,padding.PKCS1v15(),hashes.SHA256()))
 from urllib.parse import urlencode
 body=urlencode({'grant_type':'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion':assertion.decode()}).encode()
 with urlopen(Request('https://oauth2.googleapis.com/token',data=body,headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=60) as r:return json.load(r)['access_token']

class Client:
 def __init__(self,access_token):self.access_token=access_token
 def call(self,method,path,body=None,image=None):
  headers={'Authorization':'Bearer '+self.access_token}
  if image is not None: data=image;headers['Content-Type']='image/png';base=UPLOAD
  else: data=json.dumps(body).encode() if body is not None else None;headers['Content-Type']='application/json';base=API
  try:
   with urlopen(Request(base+path,data=data,headers=headers,method=method),timeout=60) as r:
    raw=r.read();return json.loads(raw) if raw else {}
  except HTTPError as e:
   # Google error messages do not include our credential or bearer token.
   raise RuntimeError(f'Google Play HTTP {e.code}: '+e.read().decode()[:1800]) from None

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--credentials',type=Path);p.add_argument('--locales',nargs='+');p.add_argument('--stage',action='store_true');p.add_argument('--inspect',action='store_true');p.add_argument('--resume',action='store_true');p.add_argument('--commit',action='store_true');p.add_argument('--workers',type=int,choices=range(1,5),default=1);args=p.parse_args()
 package,plan=local_plan(args.locales);dump(ROOT/'upload-plan.json',{'packageName':package,'locales':plan})
 print(f'Validated {len(plan)} locales / {sum(len(e["images"]) for e in plan)} PNGs. Package: {package}')
 if not (args.stage or args.inspect): print('Dry run complete. No Google API calls.');return
 if not args.credentials:p.error('--credentials is required for --inspect or --stage')
 client=Client(token(args.credentials));base=f'/applications/{package}/edits'
 if args.resume:
  if not args.stage:p.error('--resume requires --stage')
  state=read(ROOT/'api-edit-state.json');eid=state['editId'];path=base+'/'+eid
  if state.get('committed') or state.get('deletedAfterInspection'):raise ValueError('Cannot resume committed or deleted edit')
  client.call('GET',path)
  backup=read(ROOT/f'console-backup-{eid}.json')
 else:
  edit=client.call('POST',base,{});eid=edit['id'];path=base+'/'+eid
  backup={'packageName':package,'edit':edit,'listings':client.call('GET',path+'/listings'),'images':{}}
  state={'editId':eid,'expiryTimeSeconds':edit.get('expiryTimeSeconds'),'committed':False,'validated':False,'completedLocales':[],'verifiedLocales':[],'uploadedImages':0}
 # Write recovery information before mutations; an edit is temporary until committed.
 dump(ROOT/'api-edit-state.json',state)
 try:
  existing={e['language'] for e in backup['listings'].get('listings',[])}
  for e in ([] if args.resume else plan):
   lang=e['language'];ip=path+f'/listings/{lang}/phoneScreenshots'
   if lang not in existing:
    backup['images'][lang]={'images':[]};continue
   try: backup['images'][lang]=client.call('GET',ip)
   except RuntimeError as err:
    # Listing/image list may not exist yet. Keep the error in the backup.
    backup['images'][lang]={'readError':str(err)}
  if not args.resume:dump(ROOT/f'console-backup-{eid}.json',backup)
  if args.inspect:
   client.call('DELETE',path);state['deletedAfterInspection']=True;dump(ROOT/'api-edit-state.json',state);print('Saved listing snapshot; temporary inspection edit deleted.');return
  lock=threading.Lock()
  def stage_locale(e):
   lang=e['language'];client.call('PUT',path+f'/listings/{lang}',e['listing']);ip=path+f'/listings/{lang}/phoneScreenshots'
   old=backup['images'][lang]
   if 'readError' in old: raise RuntimeError(f'Cannot safely replace {lang} images: backup read failed')
   client.call('DELETE',ip)
   for image in e['images']:
    client.call('POST',ip+'?uploadType=media',image=Path(image['file']).read_bytes())
    print(f"Uploaded {lang} {Path(image['file']).name}",flush=True)
   listing=client.call('GET',path+f'/listings/{lang}')
   if any(listing.get(k)!=v for k,v in e['listing'].items()):raise RuntimeError(f'Listing readback mismatch: {lang}')
   remote=client.call('GET',ip).get('images',[])
   if [im.get('sha256') for im in remote]!=[im['sha256'] for im in e['images']]:raise RuntimeError(f'Image count, order or hash mismatch: {lang}')
   with lock:
    if lang not in state['verifiedLocales']:state['verifiedLocales'].append(lang)
    if lang not in state['completedLocales']:state['completedLocales'].append(lang)
    state['uploadedImages']=len(state['completedLocales'])*7
    dump(ROOT/'api-edit-state.json',state)
    print(f"Verified {lang}: {len(state['completedLocales'])}/{len(plan)} locales",flush=True)
  pending=[]
  for e in plan:
   if e['language'] in state['completedLocales']:
    ip=path+f"/listings/{e['language']}/phoneScreenshots"
    listing=client.call('GET',path+f"/listings/{e['language']}")
    remote=client.call('GET',ip).get('images',[])
    if any(listing.get(k)!=v for k,v in e['listing'].items()) or [im.get('sha256') for im in remote]!=[im['sha256'] for im in e['images']]:raise RuntimeError(f"Completed locale changed: {e['language']}")
   else:pending.append(e)
  failed=[]
  with ThreadPoolExecutor(max_workers=args.workers) as pool:
   futures={pool.submit(stage_locale,e):e for e in pending}
   for future in as_completed(futures):
    try:future.result()
    except Exception as err:
     e=futures[future];failed.append(e);print(f"Retry pending for {e['language']}: {err}",flush=True)
  # Retry whole incomplete languages sequentially. Delete first to reconcile
  # uncertain media upload responses without ever appending duplicate images.
  for e in failed:
   for attempt in range(3):
    try:stage_locale(e);break
    except Exception:
     if attempt==2:raise
     time.sleep(2**attempt)
  client.call('POST',path+':validate');state['validated']=True;state['finishedAt']=int(time.time())
  if args.commit:
   client.call('POST',path+':commit');state['committed']=True;dump(ROOT/'api-edit-state.json',state)
   print(f'Committed edit {eid}. Store listing and screenshots are live for the staged locales.')
  else:
   dump(ROOT/'api-edit-state.json',state)
   print('Validated temporary edit '+eid+'. NOT committed or sent for review. Edit expires; upload again if expired.')
 except Exception:
  state['incomplete']=True;dump(ROOT/'api-edit-state.json',state);raise

if __name__=='__main__':main()
