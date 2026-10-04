#!/usr/bin/env python3
"""Reviewed sports voice catalogs, isolated from the ordinary UI translation corpus.

English phrases are semantic IDs, never text to replace at playback time. Native
sentence frames author the announcements; positional substitution here only binds
arguments in their native order. Catalog hashes gate promotion into ScoreVoice.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RESOURCE_ROOT = ROOT / 'jifen/Resources'
CATALOG_ROOT = Path(__file__).with_name('voice_catalogs')
PACKS = Path(__file__).with_name('voice-phrases.json')
MANIFEST = Path(__file__).with_name('locales.json')
NUMBER_WORDS = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen'.split()
TERMS = 'and game set match deuce game_point match_point game_ball match_ball interval timeout time half_time change_ends service_over second_server hand_out star_point win_by_two games sets minute minutes set_unit sets_unit point resume'.split()
PATTERNS = 'serve serve_to opening_squash serve_play wins advantage leads deciding golden games_match tied download_title download_guide'.split()

DOCUMENTED_CALLS = {'pingpong.love.all': 'Love all',
 'score.numbers': '%1$@, %2$@',
 'score.numbers.three': '%1$@, %2$@, %3$@',
 'badminton.critical.all': '%1$@, %2$@, all',
 'softtennis.opening': '%1$@ game match, play ball',
 'softtennis.score.all': '%1$@ all',
 'softtennis.deuce': 'Deuce',
 'softtennis.deuce.again': 'Deuce again',
 'softtennis.advantage.server': 'Advantage, server',
 'softtennis.advantage.receiver': 'Advantage, receiver',
 'softtennis.game.set': 'Game set',
 'softtennis.change.sides': 'Change sides',
 'softtennis.no.time': 'No time',
 'softtennis.time': 'Time',
 'squash.game.to': '%1$@, game to %2$@',
 'squash.games.all': '%1$@ games all',
 'squash.leads': '%1$@ leads %2$@ %3$@ to %4$@',
 'squash.game.unit': 'game',
 'squash.games.unit': 'games',
 'squash.match.to': '%1$@, match to %2$@, %3$@ games to %4$@, %5$@',
 'padel.advantage.number': 'Advantage %1$@, %2$@',
 'softtennis.number.0': 'zero',
 'softtennis.number.1': 'one',
 'softtennis.number.2': 'two',
 'softtennis.number.3': 'three',
 'softtennis.number.4': 'four',
 'softtennis.number.5': 'five',
 'softtennis.number.6': 'six',
 'tennis.deuce.first': 'Deuce',
 'tennis.deuce.again': 'Deuce',
 'tennis.advantage.name': 'Advantage %1$@',
 'tennis.deciding.point': "Deciding point, receiver's choice",
 'pingpong.score.all': '%1$@ all',
 'softtennis.game': 'Game',
 'squash.zero': 'love',
 'squash.score.all': '%1$@ all',
 'squash.hand.out': 'Hand out, %1$@',
 'squash.two.clear': 'a player must win by 2 points',
 'squash.game.ball': 'Game ball',
 'squash.match.ball': 'Match ball',
 'tennis.opening': '%1$@ to serve, play',
 'softtennis.match.games.7': '7',
 'softtennis.match.games.9': '9'}


def bind(value, *indices):
    return re.sub(r'%(\d+)\$@', lambda m: '%%%d$@' % indices[int(m.group(1))-1], value)

def native_table(pack):
    words=pack['terms'].split('|'); frames=pack['patterns']
    if len(words)!=len(TERMS) or len(frames)!=len(PATTERNS): raise ValueError('native frame inventory mismatch')
    t=dict(zip(TERMS,words)); p=dict(zip(PATTERNS,frames))
    w=lambda index:bind(p['wins'],index)
    g=lambda index:bind(pack['game_number'],index)
    st=lambda index:bind(pack['set_number'],index)
    lead=lambda a,b,c:bind(p['leads'],a,b,c)
    score='%1$@–%2$@'
    game_end=t['game']+'. '
    match_end=t['match']+'. '
    result={
      ' and ':t['and'], '%1$@':'%1$@', '%1$@ %2$@':'%1$@ %2$@',
      '%1$@ games to %2$@':t['games']+': '+score,
      '%1$@ serves, 0-0':p['serve']+', 0–0',
      '%1$@ to serve to %2$@, love all, play':p['serve_to']+', 0–0',
      '%1$@ to serve, %2$@ to receive, best of %3$@ games, love all':p['opening_squash'],
      '%1$@ to serve, love all':p['serve']+', 0–0',
      '%1$@ to serve, love all, play':p['serve_play']+', 0–0',
      '%1$@ to serve, play':p['serve_play'],
      '%1$@, %2$@':'%1$@, %2$@', '%1$@, %2$@, %3$@':'%1$@, %2$@, %3$@',
      '%1$@, play':'%1$@. '+t['resume'], '%1$@-%2$@':score,
      '%1$@-%2$@ %3$@':score+', %3$@', '%1$@-all':p['tied'],
      '%1$@ to %2$@':score,
      '%1$@-game match, play ball':p['games_match'],
      '%1$@. %2$@ to serve':'%1$@. '+bind(p['serve'],2),
      '%1$@. Game and match to %2$@. %3$@ wins %4$@ games to %5$@':'%1$@. '+game_end+w(2)+'. '+match_end+w(3)+'. '+t['games']+': %4$@–%5$@',
      '%1$@. Game to %2$@':'%1$@. '+game_end+w(2), '%1$@th':'%1$@',
      ', ':', ', ', %1$@':', %1$@', ', a player must win by 2 points':', '+t['win_by_two'],
      ', change ends':', '+t['change_ends'], ', interval':', '+t['interval'], '. ':'. ',
      '. %1$@ games all':'. '+t['games']+': '+p['tied'], '. One game all':'. '+t['games']+': '+p['tied'].replace('%1$@','1'),
      '10-point match tie-break':t['match']+'. '+t['deciding'] if 'deciding' in t else t['match']+'. 10',
      '15 seconds':'15', '20 seconds':'20', '7-point tie-break match':t['match']+'. 7',
      'Advantage %1$@':p['advantage'], 'Change ends':t['change_ends'],
      "Deciding point, receiver's choice":p['deciding'], 'Deuce':t['deuce'],
      'Deuce 1':t['deuce']+' 1', 'Deuce 2':t['deuce']+' 2', 'Deuce 3, Star point':t['deuce']+' 3, '+t['star_point'],
      'Game':t['game'], 'Game %1$@. %2$@ games all':game_end+w(1)+'. '+t['games']+': '+bind(p['tied'],2),
      'Game %1$@. %2$@ games all. Tie-break':game_end+w(1)+'. '+t['games']+': '+bind(p['tied'],2)+'. '+t.get('tie_break',''),
      'Game %1$@. %2$@ leads %3$@ games to %4$@, %5$@ set':game_end+w(1)+'. '+lead(2,3,4)+'. '+st(5),
      'Game %1$@. %2$@-%3$@':game_end+w(1)+'. %2$@–%3$@',
      'Game and %1$@ set %2$@, %3$@':game_end+st(1)+'. '+w(2)+', %3$@',
      'Game ball':t['game_ball'], 'Game over':t['game'],
      'Game set. Match to %1$@, %2$@':game_end+t['set']+'. '+match_end+w(1)+', %2$@',
      'Game, set and match %1$@, %2$@ sets to %3$@, %4$@':game_end+t['set']+'. '+match_end+w(1)+'. '+t['sets']+': %2$@–%3$@, %4$@',
      'Game. %1$@ game won by %2$@, %3$@':g(1)+'. '+w(2)+', %3$@',
      'Game. Match won by %1$@, %2$@':game_end+match_end+w(1)+', %2$@',
      "Golden point, receiver's choice":p['golden'], 'Half-time':t['half_time'], 'Hand out, %1$@':t['hand_out']+', %1$@',
      'Interval, %1$@':t['interval']+', %1$@', 'Match %1$@, %2$@':match_end+w(1)+', %2$@',
      'Match %1$@, %2$@ %3$@ to %4$@':match_end+w(1)+'. %2$@ %3$@, %4$@',
      'Match ball':t['match_ball'], 'Match over':t['match'], 'Match start, %1$@ to serve':p['serve_play'],
      'Match to %1$@. %2$@ wins %3$@ games to %4$@':match_end+w(1)+'. '+w(2)+'. '+t['games']+': %3$@–%4$@',
      'Match won by %1$@':match_end+w(1), 'Match. %1$@ wins':match_end+w(1),
      'Point. Game. %1$@. %2$@ wins':t['point']+'. '+game_end+'%1$@. '+w(2),
      'Point. Game. Match. %1$@. %2$@ wins':t['point']+'. '+game_end+match_end+'%1$@. '+w(2),
      'Second server, %1$@':t['second_server']+', %1$@', 'Service over, %1$@':t['service_over']+', %1$@',
      'Set over':t['set'], 'Side out, %1$@':t['service_over']+', %1$@', 'Time':t['time'],
      'Time in, %1$@':t['resume']+', %1$@', 'Time-out':t['timeout'],
      'Time. Game %1$@, %2$@ serves, 0-0':t['time']+'. '+g(1)+'. '+bind(p['serve'],2)+', 0–0',
      'Time. Game %1$@. %2$@ serves, love all':t['time']+'. '+g(1)+'. '+bind(p['serve'],2)+', 0–0',
      'Time. Game %1$@. %2$@ to serve, love all':t['time']+'. '+g(1)+'. '+bind(p['serve'],2)+', 0–0',
      'game point':t['game_point'], 'love':'0', 'match point':t['match_point'],
      'minute':t['minute'], 'minutes':t['minutes'], 'set':t['set_unit'], 'sets':t['sets_unit'],
      'first':'1', 'second':'2', 'third':'3', 'fourth':'4', 'fifth':'5',
      'thirty':'30', 'forty':'40',
      'voice_download_title':p['download_title'], 'voice_download_guide':p['download_guide'],
    }
    result.update({word:str(n) for n,word in enumerate(NUMBER_WORDS)})
    # Additional native sports terms carry their own inflection, not English substitutions.
    result['7-point tie-break match']=pack['tie_break_7']
    result['10-point match tie-break']=pack['tie_break_10']
    result['15 seconds']=pack['seconds_15'];result['20 seconds']=pack['seconds_20']
    result['Game %1$@. %2$@ games all. Tie-break']=game_end+w(1)+'. '+t['games']+': '+bind(p['tied'],2)+'. '+pack['tie_break']
    result.update({'set_unit.'+category:value for category,value in pack['set_units'].items()})
    # Sport-specific vocabulary prevents tennis's loanwords from changing
    # pickleball numbers, or Japanese badminton calls from changing other sports.
    result.update({'tennis.point.'+word:result[word] for word in ('love','fifteen','thirty','forty')})
    result['tennis.score.all']=p['tied']
    result.update({'badminton.number.'+str(n):str(n) for n in range(31)})
    # Semantic IDs for documented calls and the universal numeric fallback.
    result.update(DOCUMENTED_CALLS)
    result.update(pack.get('standard_templates',{}))
    # Do not hand a written score separator to speech synthesis.
    result={key:re.sub(r'(%\d+\$@)[–-](%\d+\$@)', r'\1, \2', value) for key,value in result.items()}
    return result

def source_table(locale='en'):
    data=json.loads(PACKS.read_text())
    table=native_table({k:v for k,v in data['zh-Hans'].items() if k!='standard_templates'})
    result={key:(("set" if key == "set_unit.one" else "sets") if key.startswith("set_unit.") else (key if not key.startswith('voice_download_') else data['en'][key])) for key in table}
    # Spoken English is authored separately from legacy phrase IDs. A score's
    # written hyphen is punctuation, never a word in an umpire's announcement.
    result.update(data['en'].get('standard_templates', {}))
    if locale in ('zh-Hans','zh-Hant'):result.update(data['zh-Hans']['standard_templates'])
    return result

def digest(value):return hashlib.sha256(value.encode()).hexdigest()
def encode(value):return json.dumps(value,ensure_ascii=False)
def validate(locale, sources, rows):
    errors=[]
    if set(rows)!=set(sources): errors.append('phrase key set differs')
    for key,source in sources.items():
        row=rows.get(key,{})
        if row.get('source_hash')!=digest(source) or row.get('status')!='reviewed': errors.append('unreviewed/stale '+key)
        value=row.get('value')
        if not isinstance(value,str) or not value:errors.append('empty '+key);continue
        if set(re.findall(r'%\d+\$@',source))!=set(re.findall(r'%\d+\$@',value)): errors.append('argument mismatch '+key)
        if '%' in re.sub(r'%\d+\$@','',value):errors.append('unsafe format '+key)
    return errors

def main(argv=None):
    parser=argparse.ArgumentParser();parser.add_argument('command',choices=['validate','promote']);parser.add_argument('--locale',action='append');parser.add_argument('--dry-run',action='store_true');args=parser.parse_args(argv)
    failed=False
    expected={row['ios'] for row in json.loads(MANIFEST.read_text())['locales']} - {'ur'}
    available={path.stem for path in CATALOG_ROOT.glob('*.json')}
    selected=set(args.locale) if args.locale else expected
    unknown=selected-expected
    missing=selected-available
    extra=available-expected if not args.locale else set()
    if unknown or missing or extra:
        print('catalog inventory blockers:', {'unknown':sorted(unknown),'missing':sorted(missing),'extra':sorted(extra)})
        return 1
    for locale in sorted(selected):
        sources=source_table(locale)
        path=CATALOG_ROOT/(locale+'.json')
        payload=json.loads(path.read_text());errors=validate(path.stem,sources,payload['entries'])
        if payload.get('locale') != locale: errors.append('catalog locale differs')
        if errors:
            failed=True;print(path.stem,errors);continue
        if args.command=='promote' and not args.dry_run:
            output=RESOURCE_ROOT/(path.stem+'.lproj')/'ScoreVoice.strings'
            output.write_text('/* Reviewed sports announcement templates; user names remain arguments. */\n'+ '\n'.join(encode(k)+' = '+encode(payload['entries'][k]['value'])+';' for k in sorted(sources))+'\n')
            subprocess.run(['plutil','-lint',str(output)],check=True,capture_output=True)
        if args.command=='validate':
            output=RESOURCE_ROOT/(path.stem+'.lproj')/'ScoreVoice.strings'
            if not output.is_file():
                failed=True;print(path.stem,'missing promoted ScoreVoice.strings');continue
            resource=json.loads(subprocess.run(['plutil','-convert','json','-o','-',str(output)],check=True,capture_output=True,text=True).stdout)
            if resource!={key:row['value'] for key,row in payload['entries'].items()}:
                failed=True;print(path.stem,'promoted resource differs from reviewed catalog');continue
        print(path.stem,len(sources),'reviewed phrases, 0 blockers')
    return int(failed)
if __name__=='__main__':raise SystemExit(main())
