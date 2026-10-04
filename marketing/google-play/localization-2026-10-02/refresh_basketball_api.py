"""Replace only screenshots 6 and 7 in an existing temporary edit; never commit."""
import argparse, json, threading, time, datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.error import URLError
import play_api as api

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--credentials',type=Path,required=True);args=p.parse_args()
 root=api.ROOT;package,plan=api.local_plan(None);state=api.read(root/'api-edit-state.json')
 if state.get('committed') or int(state['expiryTimeSeconds'])<=time.time():raise RuntimeError('The temporary edit has expired or was committed')
 client=api.Client(api.token(args.credentials));path=f"/applications/{package}/edits/{state['editId']}"
 old={e['language']:e for e in api.read(root/'before-basketball-teams/upload-plan.json')['locales']}
 def call(method,url,**kwargs):
  for attempt in range(4):
   try:return client.call(method,url,**kwargs)
   except (URLError,TimeoutError,RuntimeError) as err:
    message=str(err)
    if method=='DELETE' and 'HTTP 404:' in message:return {}
    transient=isinstance(err,(URLError,TimeoutError)) or any(f'HTTP {code}:' in message for code in [409,429,500,502,503,504])
    if not transient or attempt==3:raise
    time.sleep(2**attempt)
 call('GET',path)
 progress={'editId':state['editId'],'completedLanguages':[],'validated':False,'committed':False,'preservedCards':[1,2,3,4,5],'replacedCards':[6,7]};lock=threading.Lock()
 state['validated']=False;api.dump(root/'api-edit-state.json',state)
 api.dump(root/'upload-plan.json',{'packageName':package,'locales':plan})
 def update(e):
  lang=e['language'];ip=path+f'/listings/{lang}/phoneScreenshots';expected=[i['sha256'] for i in e['images']]
  assert expected[:5]==[i['sha256'] for i in old[lang]['images'][:5]],'Local images 1–5 changed'
  for attempt in range(4):
   try:
    remote=call('GET',ip).get('images',[])
    hashes=[i['sha256'] for i in remote]
    if hashes!=expected:
     if len(remote)<5 or hashes[:5]!=expected[:5]:raise ValueError(f'{lang}: unexpected first five remote screenshots')
     allowed=set(expected[5:]+[i['sha256'] for i in old[lang]['images'][5:]])
     if any(h not in allowed for h in hashes[5:]):raise ValueError(f'{lang}: unexpected remote screenshots; stop to preserve other edits')
     for image in remote[5:]:call('DELETE',ip+'/'+image['id'])
     for image in e['images'][5:]:client.call('POST',ip+'?uploadType=media',image=Path(image['file']).read_bytes())
     remote=call('GET',ip).get('images',[])
     if [i['sha256'] for i in remote]!=expected:raise RuntimeError(f'{lang}: image readback mismatch')
    listing=call('GET',path+f'/listings/{lang}')
    if any(listing.get(k)!=v for k,v in e['listing'].items()):raise ValueError(f'{lang}: listing text changed')
    with lock:
     progress['completedLanguages'].append(lang);api.dump(root/'basketball-api-state.json',progress)
     print(f"Verified updated {lang}: {len(progress['completedLanguages'])}/{len(plan)}",flush=True)
    return
   except ValueError:raise
   except Exception:
    if attempt==3:raise
    print(f'Reconciling incomplete image tail for {lang}',flush=True);time.sleep(2**attempt)
 failures=[]
 with ThreadPoolExecutor(max_workers=3) as pool:
  futures={pool.submit(update,e):e for e in plan}
  for f in as_completed(futures):
   try:f.result()
   except Exception as err:failures.append((futures[f]['language'],str(err)))
 if failures:
  progress['failures']=failures;api.dump(root/'basketball-api-state.json',progress);raise RuntimeError(str(failures))
 call('POST',path+':validate');progress['validated']=True;api.dump(root/'basketball-api-state.json',progress)
 now=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
 state.update({'validated':True,'finishedAt':int(time.time()),'assetRevision':'basketball-teams-2026-10-03'});api.dump(root/'api-edit-state.json',state)
 report=api.read(root/'api-verification.json');report.update({'verifiedAt':now,'assetRevision':'basketball-teams-2026-10-03','currentAssetsMatchStagedImages':True,'replacedScreenshotCount':94,'preservedScreenshotCount':235,'updatedCards':[6,7],'listingFieldReadbackMatches':True,'phoneScreenshotCountsOrderAndSHA256Match':True,'validatedByGooglePlay':True});api.dump(root/'api-verification.json',report)
 verification=api.read(root/'verification.json');verification.update({'currentAssetsMatchStagedImages':True,'onlineApiReport':'api-verification.json'});api.dump(root/'verification.json',verification)
 auth=api.read(root/'auth-status.json');auth.update({'verifiedAt':now,'status':'Temporary edit revalidated after basketball team update: 47 locales / 329 screenshots; not committed'});api.dump(root/'auth-status.json',auth)
 print('Updated 94 screenshots, preserved 235 screenshots and all listing text; edit validated. NOT committed.',flush=True)

if __name__=='__main__':main()
