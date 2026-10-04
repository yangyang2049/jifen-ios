"""Synchronize reviewed corrections to a temporary Play edit, preserving image order."""
import argparse,time,datetime,threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
from urllib.error import URLError
import play_api as api

def main():
 p=argparse.ArgumentParser();p.add_argument('--credentials',type=Path,required=True);args=p.parse_args()
 root=api.ROOT;package,plan=api.local_plan(None);state=api.read(root/'api-edit-state.json')
 if state.get('committed') or int(state['expiryTimeSeconds'])<=time.time():raise RuntimeError('Temporary edit is expired or committed')
 client=api.Client(api.token(args.credentials));base=f"/applications/{package}/edits/{state['editId']}"
 old={x['language']:x for x in api.read(root/'before-self-audit/upload-plan.json')['locales']}
 def call(method,path,**kw):
  for attempt in range(4):
   try:return client.call(method,path,**kw)
   except (URLError,TimeoutError,RuntimeError) as err:
    message=str(err)
    if method=='DELETE' and 'HTTP 404:' in message:return {}
    if attempt==3 or not (isinstance(err,(URLError,TimeoutError)) or any(f'HTTP {x}:' in message for x in [409,429,500,502,503,504])):raise
    time.sleep(2**attempt)
 call('GET',base);state['validated']=False;api.dump(root/'api-edit-state.json',state)
 api.dump(root/'upload-plan.json',{'packageName':package,'locales':plan})
 progress={'editId':state['editId'],'completedLanguages':[],'validated':False,'committed':False};lock=threading.Lock()
 def sync(e):
  lang=e['language'];previous=old[lang];listingpath=base+'/listings/'+lang;ip=listingpath+'/phoneScreenshots'
  expected=[x['sha256'] for x in e['images']];prior=[x['sha256'] for x in previous['images']]
  changed=[i for i in range(7) if expected[i]!=prior[i]];start=min(changed) if changed else 7
  for attempt in range(4):
   try:
    remote=call('GET',listingpath)
    for key,val in e['listing'].items():
     if remote.get(key) not in [val,previous['listing'][key]]:raise ValueError(lang+': unrelated remote listing change')
    if any(remote.get(k)!=v for k,v in e['listing'].items()):call('PUT',listingpath,body=e['listing'])
    images=call('GET',ip).get('images',[]);hashes=[x['sha256'] for x in images]
    if hashes!=expected:
     if start==7 or hashes[:start]!=expected[:start] or len(images)<start:raise ValueError(lang+': unexpected remote image prefix')
     if any(x not in set(expected[start:]+prior[start:]) for x in hashes[start:]):raise ValueError(lang+': unrelated remote image change')
     for image in images[start:]:call('DELETE',ip+'/'+image['id'])
     for image in e['images'][start:]:client.call('POST',ip+'?uploadType=media',image=Path(image['file']).read_bytes())
     images=call('GET',ip).get('images',[])
    assert [x['sha256'] for x in images]==expected,lang+': image readback mismatch'
    listing=call('GET',listingpath)
    assert all(listing.get(k)==v for k,v in e['listing'].items()),lang+': listing readback mismatch'
    with lock:
     progress['completedLanguages'].append(lang);api.dump(root/'self-audit-api-state.json',progress)
     print('Verified '+lang+': '+str(len(progress['completedLanguages']))+'/47',flush=True)
    return
   except ValueError:raise
   except Exception:
    if attempt==3:raise
    time.sleep(2**attempt)
 failures=[]
 with ThreadPoolExecutor(max_workers=3) as pool:
  futures={pool.submit(sync,e):e['language'] for e in plan}
  for f in as_completed(futures):
   try:f.result()
   except Exception as err:failures.append((futures[f],str(err)))
 if failures:progress['failures']=failures;api.dump(root/'self-audit-api-state.json',progress);raise RuntimeError(str(failures))
 call('POST',base+':validate');progress['validated']=True;api.dump(root/'self-audit-api-state.json',progress)
 now=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
 state.update(validated=True,finishedAt=int(time.time()),assetRevision='self-audit-2026-10-03');api.dump(root/'api-edit-state.json',state)
 report=api.read(root/'api-verification.json');report.update(verifiedAt=now,assetRevision='self-audit-2026-10-03',currentAssetsMatchStagedImages=True,listingFieldReadbackMatches=True,phoneScreenshotCountsOrderAndSHA256Match=True,validatedByGooglePlay=True,selfAuditChangedImageCount=sum(sum(a['sha256']!=b['sha256'] for a,b in zip(e['images'],old[e['language']]['images'])) for e in plan),selfAuditChangedListingCount=sum(e['listing']!=old[e['language']]['listing'] for e in plan));api.dump(root/'api-verification.json',report)
 verification=api.read(root/'verification.json');verification.update(currentAssetsMatchStagedImages=True,onlineApiReport='api-verification.json');api.dump(root/'verification.json',verification)
 print('All 47 listings and 329 image hashes/order verified; Google validation passed; NOT committed.',flush=True)
if __name__=='__main__':main()
