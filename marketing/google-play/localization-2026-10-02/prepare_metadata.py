"""Adapt approved App Store copy to Android and verified Play language codes."""
import csv, json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IOS = ROOT.parents[1] / 'app-store/localization-2026-10-02'
IMAGES = ROOT.parents[1] / 'app-store/ios-screenshots-pen-2026-10-02'
MAPPING = {
 'ar-SA':'ar', 'bn-BD':'bn-BD', 'ca':'ca', 'cs':'cs-CZ', 'da':'da-DK',
 'de-DE':'de-DE', 'el':'el-GR', 'en-AU':'en-AU', 'en-CA':'en-CA',
 'en-GB':'en-GB', 'en-US':'en-US', 'es-ES':'es-ES', 'es-MX':'es-419',
 'fi':'fi-FI', 'fr-CA':'fr-CA', 'fr-FR':'fr-FR', 'gu-IN':'gu', 'he':'iw-IL',
 'hi':'hi-IN', 'hr':'hr', 'hu':'hu-HU', 'id':'id', 'it':'it-IT', 'ja':'ja-JP',
 'kn-IN':'kn-IN', 'ko':'ko-KR', 'ml-IN':'ml-IN', 'mr-IN':'mr-IN', 'ms':'ms-MY',
 'nl-NL':'nl-NL', 'no':'no-NO', 'or-IN':None, 'pa-IN':'pa', 'pl':'pl-PL',
 'pt-BR':'pt-BR', 'pt-PT':'pt-PT', 'ro':'ro', 'ru':'ru-RU', 'sk':'sk',
 'sl-SI':'sl', 'sv':'sv-SE', 'ta-IN':'ta-IN', 'te-IN':'te-IN', 'th':'th',
 'tr':'tr-TR', 'uk':'uk', 'ur-PK':'ur', 'vi':'vi'
}
REPLACEMENTS = {
 'ar-SA':('iPhone أو iPad','جهاز Android'),
 'bn-BD':('iPhone বা iPad-কে','Android ফোন বা ট্যাবলেটকে'),
 'ca':('el teu iPhone o iPad','el teu dispositiu Android'),
 'cs':('iPhone nebo iPad','zařízení s Androidem'),
 'da':('din iPhone eller iPad','din Android-enhed'),
 'de-DE':('dein iPhone oder iPad','dein Android-Gerät'),
 'el':('το iPhone ή το iPad','τη συσκευή σας Android'),
 'es-ES':('tu iPhone o iPad','tu teléfono o tableta Android'),
 'es-MX':('tu iPhone o iPad','tu teléfono o tablet Android'),
 'fi':('iPhone tai iPad','Android-laitteesi'),
 'fr-CA':('votre iPhone ou iPad','votre téléphone ou tablette Android'),
 'fr-FR':('votre iPhone ou iPad','votre téléphone ou tablette Android'),
 'gu-IN':('તમારા iPhone અથવા iPadને','તમારા Android ઉપકરણને'),
 'he':('ה-iPhone או ה-iPad','מכשיר ה-Android שלכם'),
 'hi':('अपने iPhone या iPad को','अपने Android डिवाइस को'),
 'hr':('iPhone ili iPad','svoj Android uređaj'),
 'hu':('iPhone-odat vagy iPadedet','Android-eszközödet'),
 'id':('iPhone atau iPad','perangkat Android Anda'),
 'it':('il tuo iPhone o iPad','il tuo dispositivo Android'),
 'ja':('iPhone や iPad が','Android のスマートフォンやタブレットが'),
 'kn-IN':('ನಿಮ್ಮ iPhone ಅಥವಾ iPad ಅನ್ನು','ನಿಮ್ಮ Android ಸಾಧನವನ್ನು'),
 'ko':('iPhone과 iPad를','Android 휴대전화나 태블릿을'),
 'ml-IN':('നിങ്ങളുടെ iPhone അല്ലെങ്കിൽ iPad','നിങ്ങളുടെ Android ഉപകരണം'),
 'mr-IN':('तुमचा iPhone किंवा iPad','तुमचे Android डिव्हाइस'),
 'ms':('iPhone atau iPad anda','peranti Android anda'),
 'nl-NL':('je iPhone of iPad','je Android-telefoon of -tablet'),
 'no':('iPhone eller iPad','Android-telefonen eller -nettbrettet ditt'),
 'or-IN':('ଆପଣଙ୍କ iPhone କିମ୍ବା iPadକୁ','ଆପଣଙ୍କ Android ଉପକରଣକୁ'),
 'pa-IN':('ਆਪਣੇ iPhone ਜਾਂ iPad ਨੂੰ','ਆਪਣੇ Android ਡਿਵਾਈਸ ਨੂੰ'),
 'pl':("iPhone'a lub iPada",'telefon lub tablet z Androidem'),
 'pt-BR':('seu iPhone ou iPad','seu celular ou tablet Android'),
 'pt-PT':('o teu iPhone ou iPad','o teu telemóvel ou tablet Android'),
 'ro':('iPhone-ul sau iPad-ul','telefonul sau tableta Android'),
 'ru':('iPhone или iPad','свой телефон или планшет Android'),
 'sk':('iPhone alebo iPad','svoje zariadenie s Androidom'),
 'sl-SI':('iPhone ali iPad','svoj telefon ali tablico Android'),
 'sv':('din iPhone eller iPad','din Android-telefon eller -surfplatta'),
 'ta-IN':('உங்கள் iPhone அல்லது iPad-ஐ','உங்கள் Android சாதனத்தை'),
 'te-IN':('మీ iPhone లేదా iPadను','మీ Android పరికరాన్ని'),
 'th':('iPhone หรือ iPad','โทรศัพท์หรือแท็บเล็ต Android'),
 'tr':("iPhone veya iPad'inizi",'Android telefonunuzu veya tabletinizi'),
 'uk':('iPhone або iPad','свій телефон або планшет Android'),
 'ur-PK':('اپنے iPhone یا iPad کو','اپنے Android فون یا ٹیبلیٹ کو'),
 'vi':('iPhone hoặc iPad','điện thoại hoặc máy tính bảng Android')
}

def write_json(path, obj):
 path.parent.mkdir(parents=True, exist_ok=True)
 path.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n')

def main():
 copy=json.loads((IMAGES/'copy.json').read_text())
 entries=[]; mapping=[]
 for image in copy['localizations']:
  locale=image['locale']; d=json.loads((IOS/'locales'/f'{locale}.json').read_text())
  paragraphs=d['description'].split('\n\n')
  assert 'apple.com/legal' in paragraphs[-1]
  paragraphs.pop()
  before, after=('iPhone or iPad','Android phone or tablet') if locale.startswith('en-') else REPLACEMENTS[locale]
  assert before in paragraphs[0], locale
  paragraphs[0]=paragraphs[0].replace(before,after)
  # Keep two local-only feature sentences; replace remote-sharing claim.
  display=json.loads((ROOT/'display-copy.json').read_text())[locale]
  separator='。' if locale=='ja' else ('। ' if locale in ['hi','bn-BD','or-IN','pa-IN'] else ('۔ ' if locale=='ur-PK' else '. '))
  if locale=='th':
   prefix=paragraphs[2].split(' แสดงกระดานคะแนน')[0]+' '
  else:
   parts=paragraphs[2].split(separator)
   assert len(parts)>=3,(locale,parts)
   prefix=separator.join(parts[:2])+separator
  paragraphs[2]=prefix+display
  full='\n\n'.join(paragraphs)
  assert not any(word in full for word in ['iPhone','iPad','Apple','apple.com'])
  data={'sourceLocale':locale,'language':MAPPING[locale], 'languageName':d['language'],
   'direction':d['direction'],'reviewStatus':'adapted-draft',
   'title':d['name'],'shortDescription':d['subtitle'],'fullDescription':full,
   'screenshotFolder':f"exports/{MAPPING[locale] or ('unsupported-'+locale)}",
   'uploadEligible':MAPPING[locale] is not None}
  assert data['title'].startswith('iScoreboard: ')
  for key, limit in [('title',30),('shortDescription',80),('fullDescription',4000)]:
   assert len(data[key])<=limit,(locale,key,len(data[key]))
  if not data['uploadEligible']: data['note']='Odia is absent from the official Google Play supported-language list. Retained as a draft; omitted from API upload.'
  if locale=='es-MX':data['note']='Mexican Spanish App Store copy mapped to Google Play Spanish (Latin America), es-419.'
  write_json(ROOT/'locales'/f"{MAPPING[locale] or ('unsupported-'+locale)}.json",data)
  entries.append(data)
  image['sourceLocale']=locale;image['locale']=MAPPING[locale] or ('unsupported-'+locale)
  mapping.append({'appStoreLocale':locale,'googlePlayLocale':MAPPING[locale],'uploadEligible':data['uploadEligible']})
 result={'platform':'Google Play','packageName':'com.bolo.jifen','defaultLanguage':'en-US',
  'preparedLocaleCount':len(entries),'uploadEligibleLocaleCount':sum(e['uploadEligible'] for e in entries),
  'excludedAppStoreLocales':['zh-Hans','zh-Hant'],'limits':{'title':30,'shortDescription':80,'fullDescription':4000},
  'localizations':entries}
 write_json(ROOT/'metadata.json',result);write_json(ROOT/'copy.json',copy)
 write_json(ROOT/'locale-map.json',{'verifiedAt':'2026-10-02','source':'https://support.google.com/googleplay/android-developer/answer/9844778?hl=en','locales':mapping})
 with (ROOT/'names-and-descriptions.csv').open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=['language','sourceLocale','title','shortDescription','fullDescription','uploadEligible']);w.writeheader();w.writerows({k:e[k] for k in w.fieldnames} for e in entries)
 print(f"Prepared {len(entries)} locales, {sum(e['uploadEligible'] for e in entries)} upload-eligible. Android adaptation and length checks passed.")

if __name__=='__main__':main()
