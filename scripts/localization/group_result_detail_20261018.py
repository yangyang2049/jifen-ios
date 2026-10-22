#!/usr/bin/env python3
"""Localize the result-detail sections using the app's existing 47 locale catalogs."""
import hashlib
import json
from pathlib import Path
import localize

ROOT = Path(__file__).resolve().parents[2]
KEYS = ('group_result_information', 'group_result_actions', 'group_peer_confirmation')
COPY = {
    'ar': ('معلومات المباراة', 'إجراءات النتيجة', 'تأكيد الخصم'),
    'bn': ('ম্যাচের তথ্য', 'ফলাফলের কার্যক্রম', 'প্রতিপক্ষের নিশ্চিতকরণ'),
    'ca': ('Informació del partit', 'Accions del resultat', 'Confirmació del rival'),
    'cs': ('Informace o zápase', 'Akce s výsledkem', 'Potvrzení soupeřem'),
    'da': ('Kampoplysninger', 'Resultathandlinger', 'Bekræftet af modstanderen'),
    'de': ('Spielinformationen', 'Ergebnisaktionen', 'Bestätigung durch den Gegner'),
    'el': ('Πληροφορίες αγώνα', 'Ενέργειες αποτελέσματος', 'Επιβεβαίωση αντιπάλου'),
    'en': ('Match information', 'Result actions', 'Opponent confirmation'),
    'es-ES': ('Información del partido', 'Acciones del resultado', 'Confirmación del rival'),
    'es-MX': ('Información del partido', 'Acciones del resultado', 'Confirmación del rival'),
    'fi': ('Ottelun tiedot', 'Tuloksen toiminnot', 'Vastustajan vahvistus'),
    'fr': ('Informations du match', 'Actions sur le résultat', 'Confirmation de l’adversaire'),
    'fr-CA': ('Renseignements sur le match', 'Actions sur le résultat', 'Confirmation de l’adversaire'),
    'gu': ('મેચની માહિતી', 'પરિણામની ક્રિયાઓ', 'પ્રતિસ્પર્ધી દ્વારા પુષ્ટિ'),
    'he': ('פרטי המשחק', 'פעולות בתוצאה', 'אישור היריב'),
    'hi': ('मैच की जानकारी', 'परिणाम की कार्रवाइयाँ', 'प्रतिद्वंद्वी की पुष्टि'),
    'hr': ('Podaci o meču', 'Radnje s rezultatom', 'Potvrda protivnika'),
    'hu': ('Mérkőzés adatai', 'Eredményműveletek', 'Ellenfél megerősítése'),
    'id': ('Informasi pertandingan', 'Tindakan hasil', 'Konfirmasi lawan'),
    'it': ('Informazioni sulla partita', 'Azioni sul risultato', 'Conferma dell’avversario'),
    'ja': ('試合情報', '試合結果の操作', '対戦相手による確認'),
    'kn': ('ಪಂದ್ಯದ ಮಾಹಿತಿ', 'ಫಲಿತಾಂಶದ ಕ್ರಮಗಳು', 'ಎದುರಾಳಿಯ ದೃಢೀಕರಣ'),
    'ko': ('경기 정보', '경기 결과 관리', '상대방 확인'),
    'ml': ('മത്സര വിവരങ്ങൾ', 'ഫലവുമായി ബന്ധപ്പെട്ട പ്രവർത്തനങ്ങൾ', 'എതിരാളിയുടെ സ്ഥിരീകരണം'),
    'mr': ('सामन्याची माहिती', 'निकालावरील कृती', 'प्रतिस्पर्ध्याची पुष्टी'),
    'ms': ('Maklumat perlawanan', 'Tindakan keputusan', 'Pengesahan lawan'),
    'nb': ('Kampinformasjon', 'Resultathandlinger', 'Bekreftet av motstanderen'),
    'nl': ('Wedstrijdinformatie', 'Resultaatacties', 'Bevestiging door tegenstander'),
    'or': ('ମ୍ୟାଚ୍ ସୂଚନା', 'ଫଳାଫଳ ସମ୍ବନ୍ଧୀୟ କାର୍ଯ୍ୟ', 'ପ୍ରତିପକ୍ଷଙ୍କ ନିଶ୍ଚିତକରଣ'),
    'pa': ('ਮੈਚ ਦੀ ਜਾਣਕਾਰੀ', 'ਨਤੀਜੇ ਦੀਆਂ ਕਾਰਵਾਈਆਂ', 'ਵਿਰੋਧੀ ਵੱਲੋਂ ਪੁਸ਼ਟੀ'),
    'pl': ('Informacje o meczu', 'Działania na wyniku', 'Potwierdzenie przez przeciwnika'),
    'pt-BR': ('Informações da partida', 'Ações do resultado', 'Confirmação do adversário'),
    'pt-PT': ('Informações do jogo', 'Ações do resultado', 'Confirmação do adversário'),
    'ro': ('Informații despre meci', 'Acțiuni pentru rezultat', 'Confirmarea adversarului'),
    'ru': ('Информация о матче', 'Действия с результатом', 'Подтверждение соперником'),
    'sk': ('Informácie o zápase', 'Akcie s výsledkom', 'Potvrdenie súperom'),
    'sl': ('Podatki o tekmi', 'Dejanja z rezultatom', 'Potrditev nasprotnika'),
    'sv': ('Matchinformation', 'Resultatåtgärder', 'Motståndarens bekräftelse'),
    'ta': ('போட்டித் தகவல்', 'முடிவுக்கான செயல்கள்', 'எதிரணியின் உறுதிப்படுத்தல்'),
    'te': ('మ్యాచ్ సమాచారం', 'ఫలితంపై చర్యలు', 'ప్రత్యర్థి నిర్ధారణ'),
    'th': ('ข้อมูลการแข่งขัน', 'การจัดการผลการแข่งขัน', 'การยืนยันโดยคู่แข่ง'),
    'tr': ('Maç bilgileri', 'Sonuç işlemleri', 'Rakip onayı'),
    'uk': ('Інформація про матч', 'Дії з результатом', 'Підтвердження суперником'),
    'ur': ('میچ کی معلومات', 'نتیجے کی کارروائیاں', 'حریف کی تصدیق'),
    'vi': ('Thông tin trận đấu', 'Thao tác kết quả', 'Đối thủ xác nhận'),
    'zh-Hans': ('比赛信息', '赛果操作', '对方确认'),
    'zh-Hant': ('比賽資訊', '賽果操作', '對方確認'),
}


def apply():
    assert set(COPY) == set(localize.locale_map())
    for locale, values in COPY.items():
        path = ROOT / f'jifen/Resources/{locale}.lproj/Localizable.strings'
        text = path.read_text()
        existing = {row.key for row in localize.parse_strings(path, 'Localizable')}
        for key, value in zip(KEYS, values):
            if key not in existing:
                text += f'"{key}" = "{localize.encode_apple_string(value)}";\n'
        path.write_text(text)
        if locale in {'en', 'zh-Hans', 'zh-Hant'}:
            continue
        path = ROOT / f'scripts/localization/catalogs/{locale}.jsonl'
        text = path.read_text()
        existing = {json.loads(line)['key'] for line in text.splitlines() if line.strip()}
        for key, english, value in zip(KEYS, COPY['en'], values):
            if key in existing:
                continue
            digest = hashlib.sha256(('Localizable\0' + key + '\0' + english).encode()).hexdigest()[:16]
            row = dict(table='Localizable', key=key, source_hash=digest, final=value, status='reviewed', flags=[], issues=[],
                       note='Result detail copy authored and reviewed by Codex 2026-10-18; no external translation provider',
                       azure=None, google_web=None, google=None, machine_provider=None)
            text += json.dumps(row, ensure_ascii=False, separators=(',', ':')) + '\n'
        path.write_text(text)
    print(f'PASS result-detail copy: {len(KEYS)} keys in {len(COPY)} locales and review catalogs')


if __name__ == '__main__':
    apply()
