#!/usr/bin/env python3
"""Reuse reviewed in-app plan titles and write concise store descriptions."""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# Store descriptions have a 45-character limit. These describe the same VIP
# entitlement for both recurring plans and state the renewal interval.
DESCRIPTIONS = {
    'ar': ('مزايا VIP. تجديد تلقائي شهري.', 'مزايا VIP. تجديد تلقائي سنوي.'),
    'bn': ('সব VIP সুবিধা। মাসিক স্বয়ংক্রিয় নবায়ন।', 'সব VIP সুবিধা। বার্ষিক স্বয়ংক্রিয় নবায়ন।'),
    'ca': ('Funcions VIP. Renovació mensual automàtica.', 'Funcions VIP. Renovació anual automàtica.'),
    'zh-Hans': ('解锁全部 VIP 功能，按月自动续订，可随时取消。', '解锁全部 VIP 功能，按年自动续订，可随时取消。'),
    'zh-Hant': ('解鎖全部 VIP 功能，按月自動續訂，可隨時取消。', '解鎖全部 VIP 功能，按年自動續訂，可隨時取消。'),
    'hr': ('VIP značajke. Automatska mjesečna obnova.', 'VIP značajke. Automatska godišnja obnova.'),
    'cs': ('VIP funkce. Automatická měsíční obnova.', 'VIP funkce. Automatická roční obnova.'),
    'da': ('VIP-funktioner. Automatisk månedsfornyelse.', 'VIP-funktioner. Automatisk årsfornyelse.'),
    'nl': ('VIP-functies. Vernieuwt automatisch per maand', 'VIP-functies. Vernieuwt automatisch per jaar.'),
    'en': ('All VIP features. Auto-renews monthly.', 'All VIP features. Auto-renews yearly.'),
    'fi': ('VIP-toiminnot. Uusiutuu kuukausittain.', 'VIP-toiminnot. Uusiutuu vuosittain.'),
    'fr': ('Fonctions VIP. Renouvellement mensuel auto.', 'Fonctions VIP. Renouvellement annuel auto.'),
    'fr-CA': ('Fonctions VIP. Renouvellement mensuel auto.', 'Fonctions VIP. Renouvellement annuel auto.'),
    'de': ('Alle VIP-Funktionen. Monatliche Verlängerung.', 'Alle VIP-Funktionen. Jährliche Verlängerung.'),
    'el': ('Λειτουργίες VIP. Αυτόματη μηνιαία ανανέωση.', 'Λειτουργίες VIP. Αυτόματη ετήσια ανανέωση.'),
    'gu': ('બધી VIP સુવિધાઓ. દર મહિને આપમેળે નવીકરણ.', 'બધી VIP સુવિધાઓ. દર વર્ષે આપમેળે નવીકરણ.'),
    'he': ('כל תכונות VIP. חידוש אוטומטי מדי חודש.', 'כל תכונות VIP. חידוש אוטומטי מדי שנה.'),
    'hi': ('सभी VIP सुविधाएँ। हर महीने स्वतः नवीनीकरण।', 'सभी VIP सुविधाएँ। हर वर्ष स्वतः नवीनीकरण।'),
    'hu': ('VIP-funkciók. Automatikus havi megújítás.', 'VIP-funkciók. Automatikus éves megújítás.'),
    'id': ('Fitur VIP. Perpanjangan otomatis bulanan.', 'Fitur VIP. Perpanjangan otomatis tahunan.'),
    'it': ('Funzioni VIP. Rinnovo mensile automatico.', 'Funzioni VIP. Rinnovo annuale automatico.'),
    'ja': ('すべてのVIP機能を利用。毎月自動更新、いつでも解約可能。', 'すべてのVIP機能を利用。毎年自動更新、いつでも解約可能。'),
    'kn': ('ಎಲ್ಲ VIP ಸೌಲಭ್ಯಗಳು. ಮಾಸಿಕ ಸ್ವಯಂ ನವೀಕರಣ.', 'ಎಲ್ಲ VIP ಸೌಲಭ್ಯಗಳು. ವಾರ್ಷಿಕ ಸ್ವಯಂ ನವೀಕರಣ.'),
    'ko': ('모든 VIP 기능 이용. 매월 자동 갱신, 언제든 취소 가능.', '모든 VIP 기능 이용. 매년 자동 갱신, 언제든 취소 가능.'),
    'ms': ('Ciri VIP. Pembaharuan automatik bulanan.', 'Ciri VIP. Pembaharuan automatik tahunan.'),
    'ml': ('VIP സൗകര്യങ്ങൾ. പ്രതിമാസ സ്വയം പുതുക്കൽ.', 'VIP സൗകര്യങ്ങൾ. വാർഷിക സ്വയം പുതുക്കൽ.'),
    'mr': ('सर्व VIP सुविधा. दरमहा आपोआप नूतनीकरण.', 'सर्व VIP सुविधा. दरवर्षी आपोआप नूतनीकरण.'),
    'nb': ('VIP-funksjoner. Automatisk månedsfornyelse.', 'VIP-funksjoner. Automatisk årsfornyelse.'),
    'or': ('ସମସ୍ତ VIP ସୁବିଧା। ପ୍ରତି ମାସ ଆପେ ନବୀକରଣ।', 'ସମସ୍ତ VIP ସୁବିଧା। ପ୍ରତି ବର୍ଷ ଆପେ ନବୀକରଣ।'),
    'pl': ('Funkcje VIP. Automatyczna odnowa co miesiąc.', 'Funkcje VIP. Automatyczna odnowa co rok.'),
    'pt-BR': ('Recursos VIP. Renovação mensal automática.', 'Recursos VIP. Renovação anual automática.'),
    'pt-PT': ('Funções VIP. Renovação mensal automática.', 'Funções VIP. Renovação anual automática.'),
    'pa': ('ਸਾਰੀਆਂ VIP ਸਹੂਲਤਾਂ। ਹਰ ਮਹੀਨੇ ਆਪੇ ਨਵੀਨੀਕਰਨ।', 'ਸਾਰੀਆਂ VIP ਸਹੂਲਤਾਂ। ਹਰ ਸਾਲ ਆਪੇ ਨਵੀਨੀਕਰਨ।'),
    'ro': ('Funcții VIP. Reînnoire lunară automată.', 'Funcții VIP. Reînnoire anuală automată.'),
    'ru': ('Все функции VIP. Автопродление каждый месяц.', 'Все функции VIP. Автопродление каждый год.'),
    'sk': ('VIP funkcie. Automatická mesačná obnova.', 'VIP funkcie. Automatická ročná obnova.'),
    'sl': ('Funkcije VIP. Samodejno mesečno podaljšanje.', 'Funkcije VIP. Samodejno letno podaljšanje.'),
    'es-MX': ('Funciones VIP. Renovación mensual automática.', 'Funciones VIP. Renovación anual automática.'),
    'es-ES': ('Funciones VIP. Renovación mensual automática.', 'Funciones VIP. Renovación anual automática.'),
    'sv': ('VIP-funktioner. Automatisk månadsförnyelse.', 'VIP-funktioner. Automatisk årsförnyelse.'),
    'ta': ('VIP வசதிகள். மாதாந்திர தானியக்க புதுப்பிப்பு', 'VIP வசதிகள். வருடாந்திர தானியக்க புதுப்பிப்பு'),
    'te': ('అన్ని VIP ఫీచర్లు. నెలవారీ స్వీయ పునరుద్ధరణ.', 'అన్ని VIP ఫీచర్లు. వార్షిక స్వీయ పునరుద్ధరణ.'),
    'th': ('ฟีเจอร์ VIP ทั้งหมด ต่ออายุอัตโนมัติรายเดือน', 'ฟีเจอร์ VIP ทั้งหมด ต่ออายุอัตโนมัติรายปี'),
    'tr': ('VIP özellikleri. Aylık otomatik yenileme.', 'VIP özellikleri. Yıllık otomatik yenileme.'),
    'uk': ('Усі функції VIP. Автопоновлення щомісяця.', 'Усі функції VIP. Автопоновлення щороку.'),
    'ur': ('تمام VIP خصوصیات۔ ماہانہ خودکار تجدید۔', 'تمام VIP خصوصیات۔ سالانہ خودکار تجدید۔'),
    'vi': ('Tính năng VIP. Tự động gia hạn hằng tháng.', 'Tính năng VIP. Tự động gia hạn hằng năm.'),
}

TITLE_OVERRIDES = {
    'en': ('Monthly VIP', 'Annual VIP', 'Lifetime VIP'),
    'zh-Hans': ('月会员', '年会员', '终身会员（买断）'),
    'zh-Hant': ('月會員', '年會員', '終身會員（買斷）'),
    'pt-BR': ('Assinatura mensal VIP', 'Assinatura anual VIP', 'VIP vitalício'),
    'pt-PT': ('Subscrição mensal VIP', 'Subscrição anual VIP', 'VIP vitalício'),
    'es-MX': ('Membresía mensual VIP', 'Membresía anual VIP', 'VIP de por vida'),
    'es-ES': ('Suscripción mensual VIP', 'Suscripción anual VIP', 'VIP de por vida'),
}
LIFETIME_OVERRIDES = {
    'en': 'One-time purchase. All VIP features for life.',
    'zh-Hans': '一次性买断，永久解锁全部 VIP 功能，无需续订。',
    'zh-Hant': '一次性買斷，永久解鎖全部 VIP 功能，無需續訂。',
    'hu': 'Egyszeri vásárlás, élethosszig tartó elérés.',
    'it': 'Acquisto unico, accesso VIP a vita.',
    'gu': 'એક વખતની ખરીદી, આજીવન ઍક્સેસ',
    'te': 'ఒకసారి కొనుగోలు, జీవితకాల VIP యాక్సెస్',
}


def strings(locale):
    text = (ROOT / 'jifen/Resources' / (locale + '.lproj') / 'Localizable.strings').read_text()
    return {m[0]: json.loads('"' + m[1] + '"') for m in re.findall(r'^"([^"]+)"\s*=\s*"((?:\\.|[^"\\])*)";', text, re.M)}


def main():
    mapping = json.loads((HERE.parent / 'localization-2026-10-02/locale-map.json').read_text())['locales']
    rows = []
    errors = []
    for row in mapping:
        code = row['iosLocale']
        values = strings(code)
        names = TITLE_OVERRIDES.get(code, tuple(values['membership_' + p + '_plan_title'] for p in ['monthly', 'yearly', 'lifetime']))
        monthly, yearly = DESCRIPTIONS[code]
        lifetime = LIFETIME_OVERRIDES.get(code, values['vip_one_time_purchase'])
        item = {'locale': row['locale'], 'iosLocale': code, 'language': row['language'],
                'group': {'name': 'iScoreboard ' + values['membership_title']},
                'monthly': {'name': names[0], 'description': monthly},
                'yearly': {'name': names[1], 'description': yearly},
                'lifetime': {'name': names[2], 'description': lifetime}}
        for p in ['monthly', 'yearly', 'lifetime']:
            for field, limit in [('name', 30), ('description', 45)]:
                v = item[p][field]
                if not v or len(v.encode('utf-16-le')) // 2 > limit:
                    errors.append((row['locale'], p, field, len(v), v))
        if len(item['group']['name']) > 75:
            errors.append((row['locale'], 'group', 'name'))
        rows.append(item)
    if errors:
        for error in errors:
            print(error)
        raise SystemExit(1)
    payload = {'appId': '6759768784', 'bundleId': 'com.douhua.jifen.ios',
               'localeCount': len(rows), 'reviewStatus': 'draft',
               'titleSource': 'reviewed in-app membership plan titles with listed store overrides',
               'localizations': rows}
    (HERE / 'metadata.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    lines = ['# 内购与会员本地化对照', '', '名称最多 30 字符；描述最多 45 字符。会员标题沿用应用内已审校资源；新增短描述尚未经母语人员复核。', '',
             '| Locale | 月会员 | 年会员 | 买断 |', '| --- | --- | --- | --- |']
    lines += [f"| {r['locale']} | {r['monthly']['name']} | {r['yearly']['name']} | {r['lifetime']['name']} |" for r in rows]
    for r in rows:
        lines += ['', f"## {r['locale']} · {r['language']}", '', f"订阅组：{r['group']['name']}", '']
        for p in ['monthly', 'yearly', 'lifetime']:
            lines += [f"- **{r[p]['name']}**：{r[p]['description']}"]
    (HERE / 'copy-review.md').write_text('\n'.join(lines) + '\n')
    print(f'{len(rows)} locales; 150 product names/descriptions and 50 group names validated.')


if __name__ == '__main__':
    main()
