"""Capture native localized UI and player names for GP cards 4/5.
Uses an emulator-only accessibility helper for Unicode input and fresh trees.
Restores a fixed demo database per locale so scores and event history match.
"""
import argparse, base64, html, json, re, shutil, subprocess, sys, time
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
from capture_evidence import invalidate_capture, seal_capture_report, write_capture_report, upgrade_evidence

ADB = '/Users/yangyang/Library/Android/sdk/platform-tools/adb'
DEVICE = 'emulator-5554'
PKG = 'com.bolo.jifen'
HELPER = 'dev.screenshots.input/.SetNames'
ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'captures'
RTL = {'ar', 'ur', 'iw-IL'}
COPY = {e['locale']: e for e in json.loads((ROOT / 'copy.json').read_text())['localizations']}
LABELS = json.loads((ROOT / 'capture-labels.json').read_text()) if (ROOT / 'capture-labels.json').exists() else {}

class StepError(RuntimeError): pass

def sh(*args, binary=False, timeout=30):
    p = subprocess.run([ADB, '-s', DEVICE, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if p.returncode:
        raise StepError(p.stderr.decode(errors='replace')[:200])
    return p.stdout if binary else p.stdout.decode(errors='replace')

def dump():
    s = sh('shell','am','instrument','-w','-e','mode','dump',HELPER)
    m = re.search(r'xml_b64=(\S+)', s)
    if not m: raise StepError('Fresh hierarchy unavailable: '+s[:180])
    return base64.b64decode(m.group(1)).decode()

def nodes(xml):
    return [n for n in ET.fromstring(xml).iter('node')]

def texts(xml): return [n.get('text','') for n in nodes(xml)]

def find(xml, label, contains=False):
    for n in nodes(xml):
        t = n.get('text','')
        if (label in t) if contains else (t == label):
            b = list(map(int, re.findall(r'\d+', n.get('bounds',''))))
            if len(b)==4: return b
    raise StepError('UI label missing: '+label)

def tap_label(xml,label,contains=False,settle=.8):
    x1,y1,x2,y2 = find(xml,label,contains)
    sh('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(settle)

def screenshot(path):
    data=sh('exec-out','screencap','-p',binary=True)
    path.write_bytes(data)
    with Image.open(path) as im:
        if im.size != (1080,1920):raise StepError('Unexpected resolution: '+str(im.size))

def check_names(xml, names):
    tx=texts(xml)
    if not all(any(name in t for t in tx) for name in names):raise StepError('Localized names missing')
    if any(t in ('Sam','Steven','Stevenx') for t in tx):raise StepError('English demo names left')

def seed_database(loc,names):
    sh('shell','am','force-stop',PKG)
    p=OUT/'.demo.sqlite'
    for suffix in ('','-wal','-shm'):Path(str(p)+suffix).unlink(missing_ok=True)
    shutil.copy2(ROOT/'before-localized-ui/demo.sqlite',p)
    with sqlite3.connect(p) as db:
        db.execute('DELETE FROM dual_track_snapshots')
        db.execute('DELETE FROM dual_track_events')
        db.execute('UPDATE scoreboard_records SET team1Name=?,team2Name=?', names)
        start=1790990400000
        actions=[];set1=set2=0;t=start
        for number,(a,b) in enumerate([(11,7),(9,11),(11,8)],1):
            left=right=0
            actions.append({'actionType':'GAME_RESET' if number>1 else 'GAME_START','description':'set_start','team1Score':0,'team2Score':0,'team1SetScore':set1,'team2SetScore':set2,'timestamp':t})
            # Interleave points, ending each game with the winner's final point.
            winner=1 if a>b else 2
            seq=[]
            for i in range(max(a,b)):
                if i<a-(winner==1):seq.append(1)
                if i<b-(winner==2):seq.append(2)
            seq.append(winner)
            for team in seq:
                left+=team==1;right+=team==2;t+=12000
                actions.append({'actionType':'SCORE_ADD','description':'score_add','scoreChange':1,'team':'TEAM'+str(team),'team1Score':left,'team2Score':right,'team1SetScore':set1,'team2SetScore':set2,'timestamp':t})
            set1+=winner==1;set2+=winner==2
            actions.append({'actionType':'SET_END','description':'set_end','team1Score':left,'team2Score':right,'team1SetScore':set1,'team2SetScore':set2,'timestamp':t})
            t+=90000
        extra={'autoChangeSides':True,'currentSet':3,'initialServingSide':'left','matchCompletionMode':'best_of','maxSets':3,'pingpongMode':'singles','pointsPerSet':11,'voiceAnnouncementEnabled':False}
        db.execute("UPDATE scoreboard_records SET status='finished',startTime=?,endTime=?,duration=?,team1FinalScore=11,team2FinalScore=8,team1SetScore=2,team2SetScore=1,winner='TEAM1',actions=?,extra_data=?,totalScoreChanges=?",(start,t,t-start,json.dumps(actions),json.dumps(extra),sum(x['actionType']=='SCORE_ADD' for x in actions)))
        db.commit()
        db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    db.close()
    sh('push',str(p),'/data/local/tmp/gp_demo.sqlite')
    sh('shell',"run-as com.bolo.jifen sh -c 'cp /data/local/tmp/gp_demo.sqlite databases/jifen_db && rm -f databases/jifen_db-wal databases/jifen_db-shm'")
    p.unlink()

def capture_locale(loc):
    d=OUT/loc;d.mkdir(parents=True,exist_ok=True)
    invalidate_capture(d)
    names=[COPY[loc]['playerNames'][k] for k in ('score','catalog')]
    labels=LABELS[loc];rtl=loc in RTL
    seed_database(loc,names)
    android_loc={'iw-IL':'he-IL','no-NO':'nb-NO'}.get(loc,loc)
    sh('shell','cmd','locale','set-app-locales',PKG,'--user','0','--locales',android_loc)
    sh('shell','cmd','uimode','night','no')
    sh('shell','monkey','-p',PKG,'-c','android.intent.category.LAUNCHER','1');time.sleep(2)
    for command,extra in [('enter',()),('clock',('-e','hhmm','0941')),('battery',('-e','level','100','-e','plugged','false')),('network',('-e','wifi','show','-e','level','4'))]:
        sh('shell','am','broadcast','-a','com.android.systemui.demo','-e','command',command,*extra)
    xml=dump()
    if labels.get('later') and labels['later'] in texts(xml):tap_label(xml,labels['later']);xml=dump()
    tap_label(xml,labels['tab_score']);xml=dump()
    tap_label(xml,labels['tab_badminton']);xml=dump()
    if not any(labels['tab_badminton'] in t for t in texts(xml)):raise StepError('Badminton setup did not open')
    args=['shell','am','instrument','-w','-e','rtl',str(rtl).lower()]
    for i,name in enumerate(names):args+=['-e','name'+str(i),base64.b64encode(name.encode()).decode()]
    result=sh(*args,HELPER)
    if 'status=names set' not in result:raise StepError('Unicode input failed: '+result[:180])
    time.sleep(.5)
    if 'mInputShown=true' in sh('shell','dumpsys','input_method'):
        sh('shell','input','keyevent','4');time.sleep(.5)
    xml=dump();check_names(xml,names)
    if labels['cancel'] not in texts(xml):raise StepError('Setup is not visible')
    (d/'05.xml').write_text(xml);screenshot(d/'05.png')
    tap_label(xml,labels['cancel']);xml=dump()
    tap_label(xml,labels['tab_records']);xml=dump()
    tap_label(xml,names[0],contains=True);xml=dump()
    check_names(xml,names)
    if labels['record_detail_score_trend'] not in texts(xml):raise StepError('Detail trend missing')
    if loc != 'en-US' and not loc.startswith('en-') and labels['record_detail_score_trend']=='Score trend':raise StepError('English trend fallback')
    (d/'04.xml').write_text(xml);screenshot(d/'04.png')
    sh('shell','input','swipe','540','1600','540','1050','450');time.sleep(.8)
    trend_xml=dump()
    if labels['record_detail_score_trend'] not in texts(trend_xml):raise StepError('Trend moved outside capture')
    (d/'04-trend.xml').write_text(trend_xml);screenshot(d/'04-trend.png')
    report={'locale':loc,'names':names,'androidLocale':sh('shell','cmd','locale','get-app-locales',PKG,'--user','0').strip(),'labels':labels,'status':'verified'}
    write_capture_report(d,seal_capture_report(d,report,loc,names,labels))
    print('captured',loc,flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('locales',nargs='*')
    parser.add_argument('--upgrade-evidence',action='store_true',help='Offline metadata migration; requires an existing trusted audit inventory')
    parser.add_argument('--inventory',type=Path)
    parser.add_argument('--backup-dir',type=Path)
    args=parser.parse_args()
    eligible=[e['language'] for e in json.loads((ROOT/'metadata.json').read_text())['localizations'] if e.get('uploadEligible')]
    selected=args.locales or eligible
    for loc in selected:
        if loc not in eligible:raise SystemExit('not eligible: '+loc)
    if args.upgrade_evidence:
        if args.inventory is None or args.backup_dir is None:parser.error('--upgrade-evidence requires --inventory and --backup-dir')
        count=upgrade_evidence(ROOT,selected,COPY,LABELS,args.inventory,args.backup_dir)
        print('Upgraded capture evidence offline:',count,flush=True)
        return
    if args.inventory is not None or args.backup_dir is not None:parser.error('--inventory and --backup-dir require --upgrade-evidence')
    failed=[]
    for loc in selected:
        for attempt in range(2):
            try:
                capture_locale(loc);break
            except Exception as e:
                print('retry',loc,attempt,type(e).__name__,str(e)[:220],flush=True)
                try:screenshot(OUT/loc/f'FAILED-{attempt}.png')
                except Exception:pass
        else:failed.append(loc)
    print('done; failed:',failed or 'none',flush=True)
    if failed:raise SystemExit(1)

if __name__=='__main__':main()
