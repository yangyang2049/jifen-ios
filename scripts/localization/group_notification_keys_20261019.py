#!/usr/bin/env python3
"""Complete notification copy in shipped locale tables and their review catalogs."""
import hashlib
import json
import shutil
from pathlib import Path
import localize

ROOT = Path(__file__).resolve().parents[2]
KEYS = ('group_notice_target_unavailable', 'group_push_enabled', 'group_push_group_enabled',
        'group_push_inbox_kept', 'group_push_permission', 'group_push_settings')
DATA = '''
ar|هذا المحتوى غير متاح أو لم تعد لديك صلاحية الوصول إليه.|إشعارات المجموعة|تلقي إشعارات هذه المجموعة|يؤدي إيقاف هذه الخيارات إلى الاحتفاظ بالإشعارات داخل التطبيق وتذكيرات الأنشطة الحالية.|تفعيل إشعارات النظام|إعدادات الإشعارات
bn|এই বিষয়বস্তু উপলভ্য নেই অথবা আপনার আর এটি দেখার অনুমতি নেই।|গ্রুপের বিজ্ঞপ্তি|এই গ্রুপের বিজ্ঞপ্তি পান|এগুলি বন্ধ করলেও অ্যাপের ভেতরের বিজ্ঞপ্তি ও বিদ্যমান কার্যক্রমের রিমাইন্ডার থাকবে।|সিস্টেমের বিজ্ঞপ্তি চালু করুন|বিজ্ঞপ্তির সেটিংস
ca|Aquest contingut no està disponible o ja no hi tens accés.|Notificacions del grup|Rep notificacions d'aquest grup|Desactivar aquestes opcions manté les notificacions dins de l'app i els recordatoris d'activitats existents.|Activa les notificacions del sistema|Configuració de notificacions
cs|Tento obsah není dostupný nebo k němu již nemáte přístup.|Oznámení skupiny|Přijímat oznámení této skupiny|Vypnutím těchto možností zůstanou oznámení v aplikaci a stávající připomenutí aktivit zachována.|Povolit systémová oznámení|Nastavení oznámení
da|Dette indhold er ikke tilgængeligt, eller du har ikke længere adgang.|Gruppenotifikationer|Modtag notifikationer fra denne gruppe|Hvis du slår disse fra, bevares notifikationer i appen og eksisterende aktivitetspåmindelser.|Aktivér systemnotifikationer|Notifikationsindstillinger
de|Dieser Inhalt ist nicht verfügbar oder du hast keinen Zugriff mehr.|Gruppenbenachrichtigungen|Benachrichtigungen dieser Gruppe erhalten|Benachrichtigungen in der App und bestehende Aktivitätserinnerungen bleiben beim Ausschalten erhalten.|Systembenachrichtigungen aktivieren|Benachrichtigungseinstellungen
el|Αυτό το περιεχόμενο δεν είναι διαθέσιμο ή δεν έχετε πλέον πρόσβαση.|Ειδοποιήσεις ομάδας|Λήψη ειδοποιήσεων αυτής της ομάδας|Η απενεργοποίηση διατηρεί τις ειδοποιήσεις στην εφαρμογή και τις υπάρχουσες υπενθυμίσεις δραστηριοτήτων.|Ενεργοποίηση ειδοποιήσεων συστήματος|Ρυθμίσεις ειδοποιήσεων
es-ES|Este contenido no está disponible o ya no tienes acceso.|Notificaciones del grupo|Recibir notificaciones de este grupo|Al desactivarlas, se conservan las notificaciones de la app y los recordatorios de actividades existentes.|Activar notificaciones del sistema|Ajustes de notificaciones
es-MX|Este contenido no está disponible o ya no tienes acceso.|Notificaciones del grupo|Recibir notificaciones de este grupo|Al desactivarlas, se conservan las notificaciones de la app y los recordatorios de actividades existentes.|Activar notificaciones del sistema|Configuración de notificaciones
fi|Tämä sisältö ei ole saatavilla tai sinulla ei enää ole siihen pääsyä.|Ryhmän ilmoitukset|Vastaanota tämän ryhmän ilmoituksia|Näiden poistaminen käytöstä säilyttää sovelluksen sisäiset ilmoitukset ja nykyiset toimintamuistutukset.|Ota järjestelmäilmoitukset käyttöön|Ilmoitusasetukset
fr|Ce contenu est indisponible ou vous n’y avez plus accès.|Notifications du groupe|Recevoir les notifications de ce groupe|La désactivation conserve les notifications dans l’app et les rappels d’activité existants.|Activer les notifications système|Réglages des notifications
fr-CA|Ce contenu est indisponible ou vous n’y avez plus accès.|Notifications du groupe|Recevoir les notifications de ce groupe|La désactivation conserve les notifications dans l’app et les rappels d’activité existants.|Activer les notifications système|Réglages des notifications
gu|આ સામગ્રી ઉપલબ્ધ નથી અથવા તમને હવે તેને જોવાની પરવાનગી નથી.|ગ્રુપની સૂચનાઓ|આ ગ્રુપની સૂચનાઓ મેળવો|આ વિકલ્પો બંધ કરવાથી ઍપની અંદરની સૂચનાઓ અને હાલના પ્રવૃત્તિ રિમાઇન્ડર જળવાઈ રહેશે.|સિસ્ટમની સૂચનાઓ ચાલુ કરો|સૂચનાઓની સેટિંગ્સ
he|התוכן הזה אינו זמין או שאין לך עוד הרשאת גישה אליו.|התראות קבוצה|קבלת התראות מקבוצה זו|כיבוי האפשרויות שומר על ההתראות בתוך האפליקציה ועל תזכורות הפעילות הקיימות.|הפעלת התראות מערכת|הגדרות התראות
hi|यह सामग्री उपलब्ध नहीं है या अब आपके पास इसे देखने की अनुमति नहीं है।|समूह की सूचनाएँ|इस समूह की सूचनाएँ पाएँ|इन्हें बंद करने पर भी ऐप के भीतर की सूचनाएँ और गतिविधियों के मौजूदा रिमाइंडर बने रहेंगे।|सिस्टम सूचनाएँ चालू करें|सूचना सेटिंग्स
hr|Ovaj sadržaj nije dostupan ili mu više nemate pristup.|Obavijesti grupe|Primaj obavijesti ove grupe|Isključivanjem se zadržavaju obavijesti u aplikaciji i postojeći podsjetnici na aktivnosti.|Uključi obavijesti sustava|Postavke obavijesti
hu|Ez a tartalom nem érhető el, vagy már nincs hozzáférésed.|Csoportértesítések|A csoport értesítéseinek fogadása|A kikapcsolás megőrzi az alkalmazáson belüli értesítéseket és a meglévő tevékenységemlékeztetőket.|Rendszerértesítések engedélyezése|Értesítési beállítások
id|Konten ini tidak tersedia atau Anda tidak lagi memiliki akses.|Notifikasi grup|Terima notifikasi dari grup ini|Menonaktifkannya tetap menyimpan notifikasi dalam aplikasi dan pengingat aktivitas yang sudah ada.|Aktifkan notifikasi sistem|Pengaturan notifikasi
it|Questo contenuto non è disponibile o non hai più accesso.|Notifiche del gruppo|Ricevi notifiche da questo gruppo|La disattivazione mantiene le notifiche nell’app e i promemoria delle attività esistenti.|Attiva le notifiche di sistema|Impostazioni notifiche
ja|このコンテンツは利用できないか、アクセス権がなくなっています。|グループ通知|このグループの通知を受け取る|オフにしても、アプリ内通知と既存の活動リマインダーは保持されます。|システム通知を有効にする|通知設定
kn|ಈ ವಿಷಯ ಲಭ್ಯವಿಲ್ಲ ಅಥವಾ ನಿಮಗೆ ಇನ್ನು ಇದನ್ನು ವೀಕ್ಷಿಸುವ ಅನುಮತಿ ಇಲ್ಲ.|ಗುಂಪಿನ ಅಧಿಸೂಚನೆಗಳು|ಈ ಗುಂಪಿನ ಅಧಿಸೂಚನೆಗಳನ್ನು ಸ್ವೀಕರಿಸಿ|ಇವುಗಳನ್ನು ಆಫ್ ಮಾಡಿದರೂ ಆ್ಯಪ್‌ನೊಳಗಿನ ಅಧಿಸೂಚನೆಗಳು ಮತ್ತು ಅಸ್ತಿತ್ವದಲ್ಲಿರುವ ಚಟುವಟಿಕೆ ಜ್ಞಾಪನೆಗಳು ಉಳಿಯುತ್ತವೆ.|ಸಿಸ್ಟಂ ಅಧಿಸೂಚನೆಗಳನ್ನು ಸಕ್ರಿಯಗೊಳಿಸಿ|ಅಧಿಸೂಚನೆ ಸೆಟ್ಟಿಂಗ್‌ಗಳು
ko|이 콘텐츠를 사용할 수 없거나 더 이상 접근 권한이 없습니다.|그룹 알림|이 그룹의 알림 받기|꺼도 앱 내 알림과 기존 활동 미리 알림은 유지됩니다.|시스템 알림 켜기|알림 설정
ml|ഈ ഉള്ളടക്കം ലഭ്യമല്ല അല്ലെങ്കിൽ ഇത് കാണാനുള്ള അനുമതി നിങ്ങൾക്ക് ഇനിയില്ല.|ഗ്രൂപ്പ് അറിയിപ്പുകൾ|ഈ ഗ്രൂപ്പിന്റെ അറിയിപ്പുകൾ സ്വീകരിക്കുക|ഇവ ഓഫാക്കിയാലും ആപ്പിനുള്ളിലെ അറിയിപ്പുകളും നിലവിലുള്ള പ്രവർത്തന ഓർമ്മപ്പെടുത്തലുകളും നിലനിൽക്കും.|സിസ്റ്റം അറിയിപ്പുകൾ പ്രവർത്തനക്ഷമമാക്കുക|അറിയിപ്പ് ക്രമീകരണങ്ങൾ
mr|हा मजकूर उपलब्ध नाही किंवा आता तुम्हाला तो पाहण्याची परवानगी नाही.|गटाच्या सूचना|या गटाच्या सूचना मिळवा|हे बंद केल्यावरही ॲपमधील सूचना आणि उपक्रमांची विद्यमान स्मरणपत्रे कायम राहतील.|सिस्टीम सूचना सुरू करा|सूचना सेटिंग्ज
ms|Kandungan ini tidak tersedia atau anda tidak lagi mempunyai akses.|Pemberitahuan kumpulan|Terima pemberitahuan kumpulan ini|Mematikannya mengekalkan pemberitahuan dalam aplikasi dan peringatan aktiviti sedia ada.|Dayakan pemberitahuan sistem|Tetapan pemberitahuan
nb|Dette innholdet er ikke tilgjengelig, eller du har ikke lenger tilgang.|Gruppevarsler|Motta varsler fra denne gruppen|Hvis du slår disse av, beholdes varsler i appen og eksisterende aktivitetspåminnelser.|Aktiver systemvarsler|Varslingsinnstillinger
nl|Deze inhoud is niet beschikbaar of je hebt geen toegang meer.|Groepsmeldingen|Meldingen van deze groep ontvangen|Bij uitschakelen blijven meldingen in de app en bestaande activiteitsherinneringen behouden.|Systeemmeldingen inschakelen|Meldingsinstellingen
or|ଏହି ବିଷୟବସ୍ତୁ ଉପଲବ୍ଧ ନାହିଁ କିମ୍ବା ଏହା ଦେଖିବାକୁ ଆପଣଙ୍କର ଆଉ ଅନୁମତି ନାହିଁ।|ଗ୍ରୁପ୍ ସୂଚନା|ଏହି ଗ୍ରୁପ୍‌ର ସୂଚନା ପାଆନ୍ତୁ|ଏଗୁଡ଼ିକ ବନ୍ଦ କଲେ ମଧ୍ୟ ଆପ୍ ଭିତରର ସୂଚନା ଓ ପୂର୍ବରୁ ଥିବା କାର୍ଯ୍ୟକଳାପ ସ୍ମାରକ ରହିବ।|ସିଷ୍ଟମ୍ ସୂଚନା ଚାଲୁ କରନ୍ତୁ|ସୂଚନା ସେଟିଂସ୍
pa|ਇਹ ਸਮੱਗਰੀ ਉਪਲਬਧ ਨਹੀਂ ਹੈ ਜਾਂ ਤੁਹਾਡੇ ਕੋਲ ਹੁਣ ਇਸਨੂੰ ਦੇਖਣ ਦੀ ਇਜਾਜ਼ਤ ਨਹੀਂ ਹੈ।|ਗਰੁੱਪ ਦੀਆਂ ਸੂਚਨਾਵਾਂ|ਇਸ ਗਰੁੱਪ ਦੀਆਂ ਸੂਚਨਾਵਾਂ ਪ੍ਰਾਪਤ ਕਰੋ|ਇਹਨਾਂ ਨੂੰ ਬੰਦ ਕਰਨ ਨਾਲ ਵੀ ਐਪ ਅੰਦਰਲੀਆਂ ਸੂਚਨਾਵਾਂ ਅਤੇ ਮੌਜੂਦਾ ਗਤੀਵਿਧੀ ਰੀਮਾਈਂਡਰ ਬਣੇ ਰਹਿਣਗੇ।|ਸਿਸਟਮ ਸੂਚਨਾਵਾਂ ਚਾਲੂ ਕਰੋ|ਸੂਚਨਾ ਸੈਟਿੰਗਾਂ
pl|Ta treść jest niedostępna lub nie masz już do niej dostępu.|Powiadomienia grupy|Odbieraj powiadomienia tej grupy|Wyłączenie zachowuje powiadomienia w aplikacji i istniejące przypomnienia o aktywnościach.|Włącz powiadomienia systemowe|Ustawienia powiadomień
pt-BR|Este conteúdo está indisponível ou você não tem mais acesso.|Notificações do grupo|Receber notificações deste grupo|Desativar estas opções mantém as notificações no app e os lembretes de atividades existentes.|Ativar notificações do sistema|Configurações de notificações
pt-PT|Este conteúdo está indisponível ou já não tem acesso.|Notificações do grupo|Receber notificações deste grupo|Desativar estas opções mantém as notificações na app e os lembretes de atividades existentes.|Ativar notificações do sistema|Definições de notificações
ro|Acest conținut nu este disponibil sau nu mai aveți acces.|Notificări de grup|Primește notificările acestui grup|Dezactivarea păstrează notificările din aplicație și mementourile de activități existente.|Activează notificările sistemului|Setări de notificări
ru|Этот контент недоступен или у вас больше нет доступа.|Уведомления группы|Получать уведомления этой группы|При отключении уведомления в приложении и существующие напоминания о событиях сохраняются.|Включить системные уведомления|Настройки уведомлений
sk|Tento obsah nie je dostupný alebo k nemu už nemáte prístup.|Oznámenia skupiny|Prijímať oznámenia tejto skupiny|Vypnutím zostanú oznámenia v aplikácii a existujúce pripomenutia aktivít zachované.|Povoliť systémové oznámenia|Nastavenia oznámení
sl|Ta vsebina ni na voljo ali do nje nimate več dostopa.|Obvestila skupine|Prejemaj obvestila te skupine|Ob izklopu se ohranijo obvestila v aplikaciji in obstoječi opomniki za dejavnosti.|Omogoči sistemska obvestila|Nastavitve obvestil
sv|Det här innehållet är inte tillgängligt eller så har du inte längre åtkomst.|Gruppnotiser|Ta emot notiser från den här gruppen|Om du stänger av dessa behålls notiser i appen och befintliga aktivitetspåminnelser.|Aktivera systemnotiser|Notisinställningar
ta|இந்த உள்ளடக்கம் கிடைக்கவில்லை அல்லது இதைப் பார்க்க உங்களுக்கு இனி அனுமதி இல்லை.|குழு அறிவிப்புகள்|இந்தக் குழுவின் அறிவிப்புகளைப் பெறவும்|இவற்றை முடக்கினாலும் செயலியில் உள்ள அறிவிப்புகளும் ஏற்கெனவே உள்ள செயல்பாட்டு நினைவூட்டல்களும் இருக்கும்.|சிஸ்டம் அறிவிப்புகளை இயக்கவும்|அறிவிப்பு அமைப்புகள்
te|ఈ కంటెంట్ అందుబాటులో లేదు లేదా దీన్ని చూసేందుకు మీకు ఇక అనుమతి లేదు.|గ్రూప్ నోటిఫికేషన్లు|ఈ గ్రూప్ నోటిఫికేషన్లను స్వీకరించండి|వీటిని ఆఫ్ చేసినా యాప్‌లోని నోటిఫికేషన్లు మరియు ఇప్పటికే ఉన్న కార్యకలాప రిమైండర్లు అలాగే ఉంటాయి.|సిస్టమ్ నోటిఫికేషన్లను ఆన్ చేయండి|నోటిఫికేషన్ సెట్టింగ్‌లు
th|เนื้อหานี้ไม่พร้อมใช้งานหรือคุณไม่มีสิทธิ์เข้าถึงแล้ว|การแจ้งเตือนกลุ่ม|รับการแจ้งเตือนจากกลุ่มนี้|การปิดจะยังคงเก็บการแจ้งเตือนในแอปและการเตือนกิจกรรมที่มีอยู่ไว้|เปิดการแจ้งเตือนของระบบ|การตั้งค่าการแจ้งเตือน
tr|Bu içerik kullanılamıyor veya artık erişim izniniz yok.|Grup bildirimleri|Bu grubun bildirimlerini al|Kapatıldığında uygulama içi bildirimler ve mevcut etkinlik hatırlatıcıları korunur.|Sistem bildirimlerini etkinleştir|Bildirim ayarları
uk|Цей вміст недоступний або ви більше не маєте доступу.|Сповіщення групи|Отримувати сповіщення цієї групи|Після вимкнення сповіщення в застосунку та наявні нагадування про події зберігаються.|Увімкнути системні сповіщення|Налаштування сповіщень
ur|یہ مواد دستیاب نہیں یا اب آپ کو اس تک رسائی کی اجازت نہیں۔|گروپ کی اطلاعات|اس گروپ کی اطلاعات موصول کریں|انہیں بند کرنے پر بھی ایپ کے اندر کی اطلاعات اور سرگرمیوں کی موجودہ یاد دہانیاں برقرار رہیں گی۔|سسٹم کی اطلاعات فعال کریں|اطلاعات کی ترتیبات
vi|Nội dung này không khả dụng hoặc bạn không còn quyền truy cập.|Thông báo nhóm|Nhận thông báo của nhóm này|Tắt các tùy chọn này vẫn giữ thông báo trong ứng dụng và lời nhắc hoạt động hiện có.|Bật thông báo hệ thống|Cài đặt thông báo
'''


def apply():
    copies = {}
    for line in DATA.strip().splitlines():
        locale, *values = line.split('|')
        assert len(values) == len(KEYS), locale
        copies[locale] = values
    for locale in ('en', 'zh-Hans', 'zh-Hant'):
        rows = {row.key: row.value for row in localize.parse_strings(
            ROOT / f'jifen/Resources/{locale}.lproj/Localizable.strings', 'Localizable')}
        copies[locale] = [rows[key] for key in KEYS]
    assert set(copies) == set(localize.locale_map())
    backup = Path('/tmp/group-release-audit-20261019/backups/ios')
    for locale, values in copies.items():
        path = ROOT / f'jifen/Resources/{locale}.lproj/Localizable.strings'
        existing = {row.key for row in localize.parse_strings(path, 'Localizable')}
        missing = [(key, english, value) for key, english, value in zip(KEYS, copies['en'], values) if key not in existing]
        if not missing:
            continue
        relative = path.relative_to(ROOT)
        (backup / relative).parent.mkdir(parents=True, exist_ok=True)
        if not (backup / relative).exists():
            shutil.copy2(path, backup / relative)
        with path.open('a') as output:
            for key, _, value in missing:
                output.write(f'"{key}" = "{localize.encode_apple_string(value)}";\n')
        catalog = ROOT / f'scripts/localization/catalogs/{locale}.jsonl'
        relative = catalog.relative_to(ROOT)
        (backup / relative).parent.mkdir(parents=True, exist_ok=True)
        if not (backup / relative).exists():
            shutil.copy2(catalog, backup / relative)
        existing = localize.load_catalog(locale)
        with catalog.open('a') as output:
            for key, english, value in missing:
                if ('Localizable', key) in existing:
                    continue
                digest = hashlib.sha256(('Localizable\0' + key + '\0' + english).encode()).hexdigest()[:16]
                row = dict(table='Localizable', key=key, source_hash=digest, final=value, status='reviewed', flags=[], issues=[],
                           note='Notification copy authored and reviewed by Codex 2026-10-19; no external translation provider',
                           azure=None, google_web=None, google=None, machine_provider=None)
                output.write(json.dumps(row, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'PASS notification copy: {len(KEYS)} keys across {len(copies)} locales and catalogs')


if __name__ == '__main__':
    apply()
