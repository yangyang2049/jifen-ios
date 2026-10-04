"""Update existing cards 4/5 and add the Simplified Chinese listing.
Back up before mutations; preserve existing listing text and other images.
Commit is a separate explicit CLI action, with a fresh complete readback.
"""
import argparse, datetime, hashlib, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError
import play_api as api

ROOT=api.ROOT
STATE=ROOT/'localized-ui-api-state.json'
FIELDS=('language','title','shortDescription','fullDescription')
def sha(data): return hashlib.sha256(data).hexdigest()
def stamp(): return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def verify_remote_locale(client,path,lang,expected,phase):
    listing=client.call('GET',path+'/listings/'+lang)
    images=client.call('GET',path+f'/listings/{lang}/phoneScreenshots').get('images',[])
    if any(listing.get(k)!=v for k,v in expected['listing'].items()) or [im.get('sha256') for im in images]!=expected['hashes']:
        raise ValueError(phase+' readback mismatch: '+lang)
    return lang
class ReliableClient(api.Client):
    def call(self,method,path,body=None,image=None):
        attempts=4 if method in ('GET','PUT','DELETE') or path.endswith(':validate') else 1
        for attempt in range(attempts):
            try:return super().call(method,path,body=body,image=image)
            except (URLError,TimeoutError,RuntimeError) as err:
                transient=isinstance(err,(URLError,TimeoutError)) or any(f'HTTP {code}:' in str(err) for code in (409,429,500,502,503,504))
                if not transient or attempt==attempts-1:raise
                time.sleep(2**attempt)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials',type=Path,required=True)
    parser.add_argument('--commit',action='store_true')
    parser.add_argument('--resume',action='store_true')
    args=parser.parse_args()
    package,plan=api.local_plan(None)
    client=ReliableClient(api.token(args.credentials))
    base=f'/applications/{package}/edits'
    if args.commit:
        state=api.read(STATE)
        if state['committed'] or not state['validated']: raise ValueError('No validated uncommitted edit')
        path=base+'/'+state['editId']
        client.call('GET',path)
        for e in plan:
            if [im['sha256'] for im in e['images']]!=state['expected'][e['language']]['hashes']:
                raise ValueError('Local files changed since validation: '+e['language'])
        def check_staged(item):
            lang,expected=item
            return verify_remote_locale(client,path,lang,expected,'Pre-commit')
        with ThreadPoolExecutor(max_workers=3) as pool:
            for _ in pool.map(check_staged,state['expected'].items()):pass
        client.call('POST',path+':validate')
        state['commitResponse']=client.call('POST',path+':commit')
        state.update(committed=True,committedAt=stamp())
        api.dump(STATE,state)
        inspect=client.call('POST',base,{})
        inspectpath=base+'/'+inspect['id']
        try:
            def check_saved(item):
                lang,expected=item
                return verify_remote_locale(client,inspectpath,lang,expected,'Post-commit')
            with ThreadPoolExecutor(max_workers=3) as pool:
                checked=0
                for _ in pool.map(check_saved,state['expected'].items()):
                    checked+=1
                    if checked%10==0:print(f'Post-commit readback: {checked}/49',flush=True)
            state.update(postCommitReadbackVerified=True,verifiedAt=stamp())
            api.dump(STATE,state)
        finally: client.call('DELETE',inspectpath)
        report={k:state[k] for k in ('editId','committed','committedAt','verifiedAt','validated','postCommitReadbackVerified')}
        oldcount=len(plan)-len(state['fullReplaceLocales'])
        report.update(packageName=package,localeCount=len(plan),simplifiedChineseLocale='zh-CN',simplifiedChineseScreenshotCount=7,createdListingLocales=state['createdListingLocales'],fullyUploadedLocales=state['fullReplaceLocales'],updatedExistingScreenshotCount=2*oldcount,preservedExistingScreenshotCount=5*oldcount,existingListingTextPreservedExceptSimplifiedChinese=True,phoneScreenshotOrderAndHashesVerified=True,expected=state['expected'])
        api.dump(ROOT/'zh-cn-and-localized-ui-upload-verification.json',report)
        local=api.read(ROOT/'localized-ui-verification.json');local.update(googlePlayUploaded=True,uploadReport='zh-cn-and-localized-ui-upload-verification.json');api.dump(ROOT/'localized-ui-verification.json',local)
        print(f'COMMITTED and read back: {len(plan)} locales / {len(plan)*7} screenshots; {len(state["createdListingLocales"])} missing listings added; zh-CN listing + 7 screenshots updated.',flush=True)
        return
    if args.resume:
        state=api.read(STATE)
        if state.get('committed'):raise ValueError('Cannot resume a committed edit')
        path=base+'/'+state['editId'];client.call('GET',path)
        backup=api.read(ROOT/f'console-backup-localized-ui-{state["editId"]}.json')
        listingmap={e['language']:{k:e.get(k,'') for k in FIELDS} for e in backup['listings'].get('listings',[])}
        for lang in state['fullReplaceLocales']:
            if lang in listingmap and lang!='zh-CN':state['expected'][lang]['listing']=listingmap[lang]
        simplified=next(e for e in plan if e['language']=='zh-CN')
        currenthashes=[im['sha256'] for im in simplified['images']]
        if currenthashes!=state['expected']['zh-CN']['hashes']:
            ip=path+'/listings/zh-CN/phoneScreenshots'
            remote=client.call('GET',ip).get('images',[])
            if [im['sha256'] for im in remote]!=currenthashes:
                if [im['sha256'] for im in remote[:5]]!=currenthashes[:5]:raise ValueError('Simplified Chinese prefix changed')
                for im in remote[5:]:client.call('DELETE',ip+'/'+im['id'])
                for im in simplified['images'][5:]:client.call('POST',ip+'?uploadType=media',image=Path(im['file']).read_bytes())
            state['expected']['zh-CN']['hashes']=currenthashes
        for e in plan:
            lang=e['language'];expected=state['expected'][lang]
            listing=client.call('GET',path+'/listings/'+lang)
            images=client.call('GET',path+f'/listings/{lang}/phoneScreenshots').get('images',[])
            if any(listing.get(k)!=v for k,v in expected['listing'].items()):raise ValueError('Listing mismatch: '+lang)
            if [im['sha256'] for im in images]!=expected['hashes']:raise ValueError('Incomplete images: '+lang)
            if lang not in state['completedLocales']:state['completedLocales'].append(lang)
        client.call('POST',path+':validate');state.update(validated=True,validatedAt=stamp());api.dump(STATE,state)
        print('RESUMED: all 49 locales read back and validated.',flush=True)
        return
    if STATE.exists():
        previous=api.read(STATE)
        if not previous.get('committed'):
            try:client.call('DELETE',base+'/'+previous['editId'])
            except RuntimeError as err:
                if 'HTTP 404:' not in str(err):raise
    edit=client.call('POST',base,body={})
    path=base+'/'+edit['id']
    state={'editId':edit['id'],'expiryTimeSeconds':edit['expiryTimeSeconds'],'committed':False,'validated':False,'startedAt':stamp(),'expected':{},'completedLocales':[]}
    api.dump(STATE,state)
    backup={'edit':edit,'listings':client.call('GET',path+'/listings'),'images':{}}
    listingmap={e['language']:{k:e.get(k,'') for k in FIELDS} for e in backup['listings'].get('listings',[])}
    state['createdListingLocales']=[e['language'] for e in plan if e['language'] not in listingmap]
    state['fullReplaceLocales']=state['createdListingLocales']+(['zh-CN'] if 'zh-CN' in listingmap else [])
    def back_up(e):
        lang=e['language']
        if lang not in listingmap:
            return lang,[]
        return lang,client.call('GET',path+f'/listings/{lang}/phoneScreenshots').get('images',[])
    with ThreadPoolExecutor(max_workers=3) as pool:
        for lang,images in pool.map(back_up,plan): backup['images'][lang]=images
    api.dump(ROOT/f'console-backup-localized-ui-{edit["id"]}.json',backup)
    for e in plan:
        lang=e['language'];old=backup['images'][lang]
        if lang in state['fullReplaceLocales']:continue
        if len(old)!=7 or any(e['images'][i]['sha256']!=old[i]['sha256'] for i in (0,1,2,5,6)):
            state['fullReplaceLocales'].append(lang)
    tails=ROOT/'before-localized-ui/remote-preserved';tails.mkdir(parents=True,exist_ok=True)
    for e in plan:
        lang=e['language'];old=backup['images'][lang]
        if lang in state['fullReplaceLocales']:
            targetlisting=e['listing'] if lang in state['createdListingLocales'] or lang=='zh-CN' else listingmap[lang]
            state['expected'][lang]={'listing':targetlisting,'hashes':[im['sha256'] for im in e['images']]};continue
        if len(old)!=7: raise ValueError(f'{lang}: expected 7 remote screenshots, got {len(old)}')
        for number in (6,7):
            local=Path(e['images'][number-1]['file']).read_bytes()
            if sha(local)==old[number-1]['sha256']: data=local
            else:
                with urlopen(old[number-1]['url'],timeout=60) as response: data=response.read()
                if sha(data)!=old[number-1]['sha256']: raise ValueError('Cannot preserve remote original: '+lang)
            (tails/f'{lang}-{number:02d}.png').write_bytes(data)
        state['expected'][lang]={'listing':listingmap[lang],'hashes':[im['sha256'] for im in old[:3]]+[im['sha256'] for im in e['images'][3:5]]+[im['sha256'] for im in old[5:]]}
    api.dump(STATE,state)
    lock=threading.Lock()
    def update(e):
        lang=e['language'];ip=path+f'/listings/{lang}/phoneScreenshots';expected=state['expected'][lang]
        if lang in state['createdListingLocales'] or lang=='zh-CN': client.call('PUT',path+'/listings/'+lang,e['listing'])
        for attempt in range(3):
            try:
                remote=client.call('GET',ip).get('images',[])
                if [im['sha256'] for im in remote]!=expected['hashes']:
                    if lang in state['fullReplaceLocales']:
                        client.call('DELETE',ip)
                        uploads=[Path(im['file']) for im in e['images']]
                    else:
                        if [im['sha256'] for im in remote[:3]]!=expected['hashes'][:3]: raise ValueError('Preserved prefix changed: '+lang)
                        allowed={im['sha256'] for im in backup['images'][lang][3:]}|set(expected['hashes'][3:])
                        if any(im['sha256'] not in allowed for im in remote[3:]): raise ValueError('Unexpected remote tail: '+lang)
                        for im in remote[3:]: client.call('DELETE',ip+'/'+im['id'])
                        uploads=[Path(im['file']) for im in e['images'][3:5]]+[tails/f'{lang}-06.png',tails/f'{lang}-07.png']
                    for image in uploads: client.call('POST',ip+'?uploadType=media',image=image.read_bytes())
                listing=client.call('GET',path+'/listings/'+lang)
                images=client.call('GET',ip).get('images',[])
                if any(listing.get(k)!=v for k,v in expected['listing'].items()): raise ValueError('Listing changed: '+lang)
                if [im['sha256'] for im in images]!=expected['hashes']: raise RuntimeError('Image readback mismatch: '+lang)
                with lock:
                    state['completedLocales'].append(lang);api.dump(STATE,state)
                    print(f'Verified {lang}: {len(state["completedLocales"])}/{len(plan)}',flush=True)
                return
            except ValueError: raise
            except Exception:
                if attempt==2: raise
                time.sleep(2**attempt)
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures=[pool.submit(update,e) for e in plan]
        for f in as_completed(futures): f.result()
    client.call('POST',path+':validate');state.update(validated=True,validatedAt=stamp());api.dump(STATE,state)
    print('STAGED and VALIDATED; commit not yet sent.',flush=True)
if __name__=='__main__': main()
