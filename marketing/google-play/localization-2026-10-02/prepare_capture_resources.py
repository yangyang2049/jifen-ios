"""Prepare emulator-only APK resource translations from reviewed project strings.
Keeps the original dex files, release code and marketing copy unchanged.
"""
import json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parent
IOS=Path('/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Resources')
RES=ROOT/'tools/apk-localization/decoded/res'
REVIEWED=Path('/Users/yangyang/Desktop/jifenqi/jifen-android-google/app/src/main/res')
sys.path.insert(0,'/Users/yangyang/Desktop/jifenqi/jifen-android-google/scripts')
from port_ios_locales import load_ios,ios_unescape,convert_format,format_signature,android_escape

def xml_values(path):
    if not path.exists():return {}
    return {x.get('name'):''.join(x.itertext()) for x in ET.parse(path).getroot() if x.tag=='string'}

def display(v):return v.strip('"').replace("\\'", "'").replace('\\"','"')

def main():
    default=xml_values(RES/'values/strings.xml')
    ien=load_ios(IOS/'en.lproj/Localizable.strings')
    mapping={k:k for k in default if k in ien}
    bytext={}
    for k,v in ien.items():bytext.setdefault(ios_unescape(v).casefold(),k)
    for k,v in default.items():
        if k not in mapping and display(v).casefold() in bytext:mapping[k]=bytext[display(v).casefold()]
    mapping.update({
      'tab_badminton':'game_badminton','tab_tennis':'game_tennis','tab_pingpong':'game_pingpong',
      'sports_setup_serving_side':'setup_serving_side','scoreboard_voice_announcement':'voice_announcement',
      'setup_set_unit':'game_short','setup_match_completion_classic':'match_completion_classic',
      'record_detail_score_trend':'score_trend','record_detail_recap':'record_recap',
      'record_detail_timeline':'record_details','record_total_sets':'set_count',
      'record_start_time':'start','record_end_time':'end','record_end_reason':'game_ended',
      'record_format_best_of_games':'record_format_sets','record_format_points_per_game':'record_format_points_per_set',
      'record_format_target_score':'record_format_points_per_set',
      'record_detail_game_title':'record_recap_set_format',
      'game_over_new_game':'home_new_game_short','record_total_matches':'match_completion_sets',
    })
    # Read only labels needed by screenshot navigation/verification.
    labelkeys=['tab_score','tab_records','tab_badminton','cancel','record_detail_score_trend']
    aliases={'iw-IL':'he','no-NO':'nb','es-419':'es-MX','zh-TW':'zh-Hant','zh-CN':'zh-Hans','fr-FR':'fr','fr-CA':'fr-CA','pt-PT':'pt-PT','pt-BR':'pt-BR','es-ES':'es-ES','unsupported-or-IN':'or'}
    labels,report={},{}
    copy=json.loads((ROOT/'copy.json').read_text())['localizations']
    for loc in [x['locale'] for x in copy]:
        iloc=aliases.get(loc,loc.split('-')[0]); iloc='en' if loc.startswith('en-') else iloc
        source=load_ios(IOS/f'{iloc}.lproj/Localizable.strings')
        android={'iw-IL':'he-IL','no-NO':'nb-NO','unsupported-or-IN':'or-IN'}.get(loc,loc)
        base=android.split('-')[0]
        reviewed=xml_values(REVIEWED/f'values-{base}/strings.xml')
        if '-' in android:reviewed.update(xml_values(REVIEWED/f'values-{base}-r{android.split("-")[1]}/strings.xml'))
        compatible_reviewed={key:display(v) for key,v in reviewed.items() if key in default and format_signature(v)==format_signature(default[key])}
        values={};effective=dict(default)
        if not loc.startswith('en-'):
            values.update(compatible_reviewed)
            for key,ik in mapping.items():
                if key not in default:continue
                if key in compatible_reviewed:
                    values[key]=compatible_reviewed[key];continue
                raw=source.get(ik)
                if raw is None:continue
                v=convert_format(ios_unescape(raw),key)
                if format_signature(v)!=format_signature(default[key]):continue
                values[key]=v
            # Best-of summary is already reviewed on Android for existing languages.
            for n in (1,3,5,7):
                key='record_format_sets_best_of_'+str(n)
                if key in default and key not in values:
                    ik='pingpong_set_option_best_of_'+str(n)
                    if ik in source:values[key]=ios_unescape(source[ik])
        if not loc.startswith('en-'):
            if 'record_format_best_of_games' not in compatible_reviewed:
                values['record_format_best_of_games']=ios_unescape(source['pingpong_set_option_best_of_3'])
            if 'record_format_points_per_game' not in compatible_reviewed:
                values['record_format_points_per_game']=convert_format(ios_unescape(source['record_format_points_per_set']),'record_format_points_per_game')
            values['record_wins']=ios_unescape(source['winner_wins']).replace('%@','').strip()
            start_end={
             'de':('Startzeit','Endzeit'),'it':('Inizio','Fine'),'hi':('शुरू होने का समय','समाप्ति का समय'),
             'nl':('Starttijd','Eindtijd'),'tr':('Başlangıç saati','Bitiş saati'),'id':('Waktu mulai','Waktu selesai'),
             'vi':('Bắt đầu','Kết thúc'),'th':('เวลาเริ่ม','เวลาสิ้นสุด'),'bn':('শুরুর সময়','শেষের সময়'),
             'ca':('Hora d’inici','Hora de finalització'),'cs':('Začátek','Konec'),'da':('Starttid','Sluttid'),
             'el':('Ώρα έναρξης','Ώρα λήξης'),'fi':('Alkamisaika','Päättymisaika'),'gu':('શરૂઆતનો સમય','સમાપ્તિનો સમય'),
             'hr':('Vrijeme početka','Vrijeme završetka'),'hu':('Kezdés','Befejezés'),'kn':('ಆರಂಭದ ಸಮಯ','ಮುಕ್ತಾಯದ ಸಮಯ'),
             'ml':('ആരംഭ സമയം','അവസാന സമയം'),'mr':('सुरुवातीची वेळ','समाप्तीची वेळ'),'ms':('Masa mula','Masa tamat'),
             'nb':('Starttid','Sluttid'),'or':('ଆରମ୍ଭ ସମୟ','ଶେଷ ସମୟ'),'pa':('ਸ਼ੁਰੂ ਹੋਣ ਦਾ ਸਮਾਂ','ਸਮਾਪਤੀ ਦਾ ਸਮਾਂ'),
             'pl':('Początek','Koniec'),'ro':('Ora de început','Ora de sfârșit'),'sk':('Začiatok','Koniec'),
             'sl':('Začetek','Konec'),'sv':('Starttid','Sluttid'),'ta':('தொடக்க நேரம்','முடிவு நேரம்'),'te':('ప్రారంభ సమయం','ముగింపు సమయం')}
            if iloc in start_end:
                values['record_start_time'],values['record_end_time']=start_end[iloc]
        if not loc.startswith('en-'):
            formats={'el':'Μορφή','hi':'प्रारूप','bn':'খেলার ধরন','gu':'રમતનું સ્વરૂપ','kn':'ಪಂದ್ಯದ ಮಾದರಿ','ml':'മത്സരരീതി','mr':'सामन्याचे स्वरूप','pa':'ਮੈਚ ਦਾ ਫਾਰਮੈਟ','ta':'போட்டி முறை','te':'ఆట విధానం','th':'รูปแบบ','vi':'Thể thức'}
            if iloc in formats:values['tennis_format_label']=formats[iloc]
            rounds={'el':'Σετ %1$d','hi':'सेट %1$d','bn':'সেট %1$d','gu':'સેટ %1$d','kn':'ಸೆಟ್ %1$d','ml':'സെറ്റ് %1$d','mr':'सेट %1$d','pa':'ਸੈੱਟ %1$d','ta':'செட் %1$d','te':'సెట్ %1$d','th':'เซต %1$d','vi':'Ván %1$d','ur':'سیٹ %1$d','nb':'Sett %1$d'}
            if iloc in rounds:
                for k in ('record_detail_game_title','record_detail_set_title'):values[k]=rounds[iloc]
        if iloc=='he':values['record_wins']='ניצח'
        if iloc=='ur':values['record_wins']='جیت گیا'
        # Fixed screenshot summaries and locale-specific overrides must obey the
        # same APK formatting contract as reviewed and iOS-derived values.
        values={key:v for key,v in values.items() if key in default and format_signature(v)==format_signature(default[key])}
        effective.update({k:display(v) for k,v in values.items()})
        parts=android.split('-')
        resource_base={'he':'iw','id':'in'}.get(parts[0],parts[0])
        dirname='values-'+resource_base+(('-r'+parts[1]) if len(parts)==2 and len(parts[1])==2 else '')
        if len(parts)==2 and len(parts[1])!=2:dirname='values-b+'+android.replace('-','+')
        d=RES/dirname;d.mkdir(exist_ok=True)
        if (d/'strings.xml').exists():
            tree=ET.parse(d/'strings.xml');container=tree.getroot()
            for n in list(container):
                if n.tag=='string' and n.get('name') in values:container.remove(n)
            tree.write(d/'strings.xml',encoding='utf-8',xml_declaration=True)
        out=['<?xml version="1.0" encoding="utf-8"?>','<resources>']
        for k,v in sorted(values.items()):
            out.append(f'    <string name="{k}">{android_escape(display(v))}</string>')
        out.append('</resources>');(d/'gp_capture_strings.xml').write_text('\n'.join(out)+'\n')
        labels[loc]={k:effective[k] for k in labelkeys}
        report[loc]={'source':iloc,'androidLocale':android,'resources':len(values)}
    (ROOT/'capture-labels.json').write_text(json.dumps(labels,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'capture-resource-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('Prepared',len(report),'locale resource overlays; common/equivalent keys',len(mapping))

if __name__=='__main__':main()
