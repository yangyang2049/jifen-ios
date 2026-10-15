#!/usr/bin/env python3
"""Reviewed, Codex-authored group parity copy; no translation services. Idempotent."""
import hashlib
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# invitation intro, download fallback, game winners, incomplete seats, duplicate seat
T = {
'en': ['Join our %@ group to play and keep score together!', 'Download iScoreboard and enter the group number to join:', 'Game winners', 'Select all players for this match', 'Each player can appear only once in this match'],
'zh-Hans': ['加入我们的%@小组，一起打球、一起计分！', '下载全能计分器，输入小组号即可加入：', '各局胜方', '请为本场比赛选齐成员', '同一成员不能在本场比赛中重复出场'],
'zh-Hant': ['加入我們的%@小組，一起打球、一起計分！', '下載全能計分器，輸入小組號即可加入：', '各局勝方', '請為本場比賽選齊成員', '同一成員不能在本場比賽中重複出場'],
'ja': ['%@グループで一緒にプレーしてスコアを記録しましょう！', 'iScoreboardをダウンロードし、グループ番号を入力して参加：', '各ゲームの勝者', 'この試合の全選手を選択してください', '同じ選手をこの試合に重複して登録できません'],
'ko': ['%@ 그룹에 가입해 함께 경기하고 점수를 기록하세요!', 'iScoreboard를 다운로드하고 그룹 번호를 입력해 가입하세요:', '게임별 승자', '이 경기의 모든 선수를 선택하세요', '같은 선수를 이 경기에 중복 배정할 수 없습니다'],
'de': ['Spiele mit uns in unserer %@-Gruppe und halte die Ergebnisse fest!', 'iScoreboard herunterladen und die Gruppennummer zum Beitreten eingeben:', 'Gewinner je Spiel', 'Wähle alle Spieler für dieses Spiel aus', 'Jeder Spieler darf in diesem Spiel nur einmal vorkommen'],
'fr': ['Rejoignez notre groupe de %@ pour jouer et compter les points ensemble !', 'Téléchargez iScoreboard et saisissez le numéro du groupe pour le rejoindre :', 'Vainqueurs des jeux', 'Sélectionnez tous les joueurs de ce match', 'Un joueur ne peut figurer qu’une fois dans ce match'],
'fr-CA': ['Joignez-vous à notre groupe de %@ pour jouer et compter les points ensemble !', 'Téléchargez iScoreboard et entrez le numéro du groupe pour le rejoindre :', 'Gagnants des jeux', 'Sélectionnez tous les joueurs de ce match', 'Un joueur ne peut figurer qu’une fois dans ce match'],
'es-ES': ['¡Únete a nuestro grupo de %@ para jugar y llevar la puntuación juntos!', 'Descarga iScoreboard e introduce el número del grupo para unirte:', 'Ganadores de los juegos', 'Selecciona a todos los jugadores de este partido', 'Cada jugador solo puede aparecer una vez en este partido'],
'es-MX': ['¡Únete a nuestro grupo de %@ para jugar y llevar la puntuación juntos!', 'Descarga iScoreboard e ingresa el número del grupo para unirte:', 'Ganadores de los juegos', 'Selecciona a todos los jugadores de este partido', 'Cada jugador solo puede aparecer una vez en este partido'],
'it': ['Unisciti al nostro gruppo di %@ per giocare e segnare i punti insieme!', 'Scarica iScoreboard e inserisci il numero del gruppo per unirti:', 'Vincitori dei giochi', 'Seleziona tutti i giocatori di questa partita', 'Ogni giocatore può comparire una sola volta in questa partita'],
'pt-BR': ['Entre no nosso grupo de %@ para jogar e marcar pontos juntos!', 'Baixe o iScoreboard e digite o número do grupo para entrar:', 'Vencedores dos jogos', 'Selecione todos os jogadores desta partida', 'Cada jogador só pode aparecer uma vez nesta partida'],
'pt-PT': ['Junta-te ao nosso grupo de %@ para jogar e marcar pontos em conjunto!', 'Descarrega o iScoreboard e introduz o número do grupo para aderir:', 'Vencedores dos jogos', 'Seleciona todos os jogadores desta partida', 'Cada jogador só pode aparecer uma vez nesta partida'],
'nl': ['Doe mee met onze %@-groep om samen te spelen en scores bij te houden!', 'Download iScoreboard en voer het groepsnummer in om lid te worden:', 'Winnaars per game', 'Selecteer alle spelers voor deze wedstrijd', 'Elke speler mag maar één keer in deze wedstrijd voorkomen'],
'sv': ['Gå med i vår %@-grupp för att spela och hålla poäng tillsammans!', 'Ladda ner iScoreboard och ange gruppnumret för att gå med:', 'Vinnare per delspel', 'Välj alla spelare för denna match', 'Varje spelare får bara förekomma en gång i denna match'],
'da': ['Deltag i vores %@-gruppe for at spille og føre point sammen!', 'Download iScoreboard, og indtast gruppenummeret for at deltage:', 'Vindere pr. delspil', 'Vælg alle spillere til denne kamp', 'Hver spiller må kun optræde én gang i denne kamp'],
'nb': ['Bli med i %@-gruppen vår for å spille og føre poeng sammen!', 'Last ned iScoreboard og skriv inn gruppenummeret for å bli med:', 'Vinnere per delspill', 'Velg alle spillere til denne kampen', 'Hver spiller kan bare forekomme én gang i denne kampen'],
'fi': ['Liity %@-ryhmäämme pelaamaan ja kirjaamaan pisteitä yhdessä!', 'Lataa iScoreboard ja liity antamalla ryhmän numero:', 'Erien voittajat', 'Valitse kaikki tämän ottelun pelaajat', 'Kukin pelaaja voi esiintyä tässä ottelussa vain kerran'],
'pl': ['Dołącz do naszej grupy %@, aby grać i liczyć punkty razem!', 'Pobierz iScoreboard i wpisz numer grupy, aby dołączyć:', 'Zwycięzcy gier', 'Wybierz wszystkich graczy do tego meczu', 'Każdy gracz może wystąpić w tym meczu tylko raz'],
'cs': ['Přidejte se k naší skupině %@, hrajte a zapisujte skóre společně!', 'Stáhněte si iScoreboard a připojte se zadáním čísla skupiny:', 'Vítězové her', 'Vyberte všechny hráče tohoto zápasu', 'Každý hráč se může v tomto zápase objevit jen jednou'],
'sk': ['Pridajte sa k našej skupine %@, hrajte a zapisujte skóre spoločne!', 'Stiahnite si iScoreboard a pripojte sa zadaním čísla skupiny:', 'Víťazi hier', 'Vyberte všetkých hráčov tohto zápasu', 'Každý hráč sa môže v tomto zápase objaviť len raz'],
'hu': ['Csatlakozz a %@-csoportunkhoz, játsszunk és számoljuk a pontokat együtt!', 'Töltsd le az iScoreboardot, és add meg a csoport számát a csatlakozáshoz:', 'Játszmák győztesei', 'Válaszd ki a mérkőzés összes játékosát', 'Egy játékos csak egyszer szerepelhet ebben a mérkőzésben'],
'ro': ['Alătură-te grupului nostru de %@ pentru a juca și a ține scorul împreună!', 'Descarcă iScoreboard și introdu numărul grupului pentru a te alătura:', 'Câștigătorii jocurilor', 'Selectează toți jucătorii acestui meci', 'Fiecare jucător poate apărea o singură dată în acest meci'],
'ru': ['Присоединяйтесь к нашей группе по %@: играйте и ведите счёт вместе!', 'Скачайте iScoreboard и введите номер группы, чтобы присоединиться:', 'Победители партий', 'Выберите всех игроков этого матча', 'Каждый игрок может участвовать в этом матче только один раз'],
'uk': ['Приєднуйтеся до нашої групи з %@: грайте й ведіть рахунок разом!', 'Завантажте iScoreboard і введіть номер групи, щоб приєднатися:', 'Переможці партій', 'Виберіть усіх гравців цього матчу', 'Кожен гравець може бути в цьому матчі лише один раз'],
'el': ['Γίνετε μέλος της ομάδας μας για %@ για να παίζουμε και να μετράμε μαζί το σκορ!', 'Κατεβάστε το iScoreboard και εισαγάγετε τον αριθμό της ομάδας για συμμετοχή:', 'Νικητές ανά παιχνίδι', 'Επιλέξτε όλους τους παίκτες αυτού του αγώνα', 'Κάθε παίκτης μπορεί να εμφανίζεται μόνο μία φορά σε αυτόν τον αγώνα'],
'tr': ['Birlikte oynamak ve skor tutmak için %@ grubumuza katılın!', 'iScoreboard uygulamasını indirin ve katılmak için grup numarasını girin:', 'Oyun kazananları', 'Bu maçın tüm oyuncularını seçin', 'Her oyuncu bu maçta yalnızca bir kez yer alabilir'],
'ar': ['انضم إلى مجموعتنا للعب %@ وتسجيل النقاط معًا!', 'نزّل iScoreboard وأدخل رقم المجموعة للانضمام:', 'الفائزون بالأشواط', 'اختر جميع لاعبي هذه المباراة', 'لا يمكن أن يظهر اللاعب نفسه أكثر من مرة في هذه المباراة'],
'he': ['הצטרפו לקבוצת ה־%@ שלנו כדי לשחק ולספור נקודות יחד!', 'הורידו את iScoreboard והזינו את מספר הקבוצה כדי להצטרף:', 'מנצחי המשחקונים', 'יש לבחור את כל השחקנים במשחק הזה', 'כל שחקן יכול להופיע פעם אחת בלבד במשחק הזה'],
'hi': ['साथ खेलने और स्कोर रखने के लिए हमारे %@ समूह से जुड़ें!', 'iScoreboard डाउनलोड करें और जुड़ने के लिए समूह नंबर दर्ज करें:', 'हर गेम के विजेता', 'इस मैच के सभी खिलाड़ी चुनें', 'इस मैच में हर खिलाड़ी केवल एक बार आ सकता है'],
'bn': ['একসঙ্গে খেলতে ও স্কোর রাখতে আমাদের %@ গ্রুপে যোগ দিন!', 'iScoreboard ডাউনলোড করে যোগ দিতে গ্রুপ নম্বর লিখুন:', 'প্রতি গেমের বিজয়ী', 'এই ম্যাচের সব খেলোয়াড় বেছে নিন', 'একই খেলোয়াড় এই ম্যাচে একাধিকবার থাকতে পারবেন না'],
'pa': ['ਇਕੱਠੇ ਖੇਡਣ ਅਤੇ ਸਕੋਰ ਰੱਖਣ ਲਈ ਸਾਡੇ %@ ਗਰੁੱਪ ਵਿੱਚ ਸ਼ਾਮਲ ਹੋਵੋ!', 'iScoreboard ਡਾਊਨਲੋਡ ਕਰੋ ਅਤੇ ਸ਼ਾਮਲ ਹੋਣ ਲਈ ਗਰੁੱਪ ਨੰਬਰ ਦਾਖ਼ਲ ਕਰੋ:', 'ਹਰ ਗੇਮ ਦੇ ਜੇਤੂ', 'ਇਸ ਮੈਚ ਦੇ ਸਾਰੇ ਖਿਡਾਰੀ ਚੁਣੋ', 'ਇੱਕ ਖਿਡਾਰੀ ਇਸ ਮੈਚ ਵਿੱਚ ਸਿਰਫ਼ ਇੱਕ ਵਾਰ ਆ ਸਕਦਾ ਹੈ'],
'gu': ['સાથે રમવા અને સ્કોર રાખવા અમારા %@ ગ્રુપમાં જોડાઓ!', 'iScoreboard ડાઉનલોડ કરો અને જોડાવા માટે ગ્રુપ નંબર દાખલ કરો:', 'દરેક ગેમના વિજેતા', 'આ મેચના બધા ખેલાડીઓ પસંદ કરો', 'દરેક ખેલાડી આ મેચમાં માત્ર એક વાર આવી શકે છે'],
'mr': ['एकत्र खेळण्यासाठी आणि गुण नोंदवण्यासाठी आमच्या %@ गटात सामील व्हा!', 'iScoreboard डाउनलोड करा आणि सामील होण्यासाठी गट क्रमांक टाका:', 'प्रत्येक गेमचे विजेते', 'या सामन्यातील सर्व खेळाडू निवडा', 'या सामन्यात प्रत्येक खेळाडू फक्त एकदाच असू शकतो'],
'ml': ['ഒരുമിച്ച് കളിക്കാനും സ്കോർ രേഖപ്പെടുത്താനും ഞങ്ങളുടെ %@ ഗ്രൂപ്പിൽ ചേരൂ!', 'iScoreboard ഡൗൺലോഡ് ചെയ്ത് ചേരാൻ ഗ്രൂപ്പ് നമ്പർ നൽകുക:', 'ഓരോ ഗെയിമിലെയും വിജയികൾ', 'ഈ മത്സരത്തിലെ എല്ലാ കളിക്കാരെയും തിരഞ്ഞെടുക്കുക', 'ഒരു കളിക്കാരൻ ഈ മത്സരത്തിൽ ഒരിക്കൽ മാത്രമേ ഉണ്ടാകാവൂ'],
'or': ['ଏକାଠି ଖେଳିବା ଏବଂ ସ୍କୋର୍ ରଖିବା ପାଇଁ ଆମର %@ ଗୋଷ୍ଠୀରେ ଯୋଗ ଦିଅନ୍ତୁ!', 'iScoreboard ଡାଉନଲୋଡ୍ କରନ୍ତୁ ଏବଂ ଯୋଗଦେବାକୁ ଗୋଷ୍ଠୀ ନମ୍ବର ଦିଅନ୍ତୁ:', 'ପ୍ରତ୍ୟେକ ଗେମ୍‌ର ବିଜେତା', 'ଏହି ମ୍ୟାଚ୍‌ର ସମସ୍ତ ଖେଳାଳିଙ୍କୁ ବାଛନ୍ତୁ', 'ଏହି ମ୍ୟାଚ୍‌ରେ ପ୍ରତ୍ୟେକ ଖେଳାଳି କେବଳ ଥରେ ରହିପାରିବେ'],
'ca': ['Uneix-te al nostre grup de %@ per jugar i comptar els punts junts!', 'Descarrega iScoreboard i introdueix el número del grup per unir-t’hi:', 'Guanyadors dels jocs', 'Selecciona tots els jugadors d’aquest partit', 'Cada jugador només pot aparèixer una vegada en aquest partit'],
'id': ['Bergabunglah dengan grup %@ kami untuk bermain dan mencatat skor bersama!', 'Unduh iScoreboard dan masukkan nomor grup untuk bergabung:', 'Pemenang tiap gim', 'Pilih semua pemain untuk pertandingan ini', 'Setiap pemain hanya boleh muncul sekali dalam pertandingan ini'],
'ms': ['Sertai kumpulan %@ kami untuk bermain dan mencatat skor bersama!', 'Muat turun iScoreboard dan masukkan nombor kumpulan untuk menyertai:', 'Pemenang setiap permainan', 'Pilih semua pemain untuk perlawanan ini', 'Setiap pemain hanya boleh muncul sekali dalam perlawanan ini'],
'vi': ['Tham gia nhóm %@ của chúng tôi để cùng chơi và ghi điểm!', 'Tải iScoreboard và nhập số nhóm để tham gia:', 'Người thắng từng ván', 'Chọn đủ người chơi cho trận này', 'Mỗi người chơi chỉ được xuất hiện một lần trong trận này'],
'ur': ['ساتھ کھیلنے اور اسکور رکھنے کے لیے ہمارے %@ گروپ میں شامل ہوں!', 'iScoreboard ڈاؤن لوڈ کریں اور شامل ہونے کے لیے گروپ نمبر درج کریں:', 'ہر گیم کے فاتح', 'اس میچ کے تمام کھلاڑی منتخب کریں', 'ہر کھلاڑی اس میچ میں صرف ایک بار شامل ہو سکتا ہے'],
'th': ['เข้าร่วมกลุ่ม%@ของเราเพื่อเล่นและบันทึกคะแนนด้วยกัน!', 'ดาวน์โหลด iScoreboard แล้วกรอกหมายเลขกลุ่มเพื่อเข้าร่วม:', 'ผู้ชนะในแต่ละเกม', 'เลือกผู้เล่นให้ครบสำหรับการแข่งขันนี้', 'ผู้เล่นแต่ละคนลงได้เพียงครั้งเดียวในการแข่งขันนี้'],
}
KEYS = ['group_invitation_intro_ball', 'group_share_message', 'group_entry_set_winners', 'group_activity_lineup_incomplete', 'group_activity_lineup_duplicate', 'group_entry_manual']

T.update({
    'hr': ['Pridružite se našoj grupi za %@ da zajedno igramo i bilježimo bodove!', 'Preuzmite iScoreboard i unesite broj grupe za pridruživanje:', 'Pobjednici gemova', 'Odaberite sve igrače za ovaj meč', 'Svaki igrač može se pojaviti samo jednom u ovom meču'],
    'sl': ['Pridružite se naši skupini za %@, da skupaj igramo in beležimo točke!', 'Prenesite iScoreboard in za pridružitev vnesite številko skupine:', 'Zmagovalci iger', 'Izberite vse igralce za to tekmo', 'Vsak igralec se lahko na tej tekmi pojavi le enkrat'],
    'ta': ['ஒன்றாக விளையாடி ஸ்கோரைப் பதிவு செய்ய எங்கள் %@ குழுவில் சேருங்கள்!', 'iScoreboard ஐப் பதிவிறக்கி, சேர்வதற்குக் குழு எண்ணை உள்ளிடுங்கள்:', 'ஒவ்வொரு ஆட்டத்தின் வெற்றியாளர்கள்', 'இந்தப் போட்டிக்கான அனைத்து வீரர்களையும் தேர்ந்தெடுக்கவும்', 'ஒவ்வொரு வீரரும் இந்தப் போட்டியில் ஒருமுறை மட்டுமே இடம்பெறலாம்'],
    'te': ['కలిసి ఆడటానికి, స్కోరు నమోదు చేయడానికి మా %@ గ్రూపులో చేరండి!', 'iScoreboard డౌన్‌లోడ్ చేసి, చేరడానికి గ్రూపు నంబర్ నమోదు చేయండి:', 'ప్రతి గేమ్ విజేతలు', 'ఈ మ్యాచ్ కోసం ఆటగాళ్లందరినీ ఎంచుకోండి', 'ప్రతి ఆటగాడు ఈ మ్యాచ్‌లో ఒక్కసారి మాత్రమే ఉండవచ్చు'],
    'kn': ['ಒಟ್ಟಿಗೆ ಆಡಲು ಮತ್ತು ಸ್ಕೋರ್ ದಾಖಲಿಸಲು ನಮ್ಮ %@ ಗುಂಪಿಗೆ ಸೇರಿ!', 'iScoreboard ಡೌನ್‌ಲೋಡ್ ಮಾಡಿ, ಸೇರಲು ಗುಂಪಿನ ಸಂಖ್ಯೆಯನ್ನು ನಮೂದಿಸಿ:', 'ಪ್ರತಿ ಆಟದ ವಿಜೇತರು', 'ಈ ಪಂದ್ಯಕ್ಕೆ ಎಲ್ಲ ಆಟಗಾರರನ್ನು ಆಯ್ಕೆಮಾಡಿ', 'ಪ್ರತಿಯೊಬ್ಬ ಆಟಗಾರ ಈ ಪಂದ್ಯದಲ್ಲಿ ಒಮ್ಮೆ ಮಾತ್ರ ಇರಬಹುದು'],
})

MANUAL = {
'en':'Manual entry', 'zh-Hans':'手动输入', 'zh-Hant':'手動輸入', 'ja':'手動入力', 'ko':'직접 입력',
'de':'Manuelle Eingabe', 'fr':'Saisie manuelle', 'fr-CA':'Saisie manuelle', 'es-ES':'Entrada manual', 'es-MX':'Entrada manual',
'it':'Inserimento manuale', 'pt-BR':'Entrada manual', 'pt-PT':'Introdução manual', 'nl':'Handmatig invoeren', 'sv':'Manuell inmatning',
'da':'Manuel indtastning', 'nb':'Manuell inntasting', 'fi':'Manuaalinen syöttö', 'pl':'Wpisz ręcznie', 'cs':'Ruční zadání',
'sk':'Ručné zadanie', 'hu':'Kézi bevitel', 'ro':'Introducere manuală', 'ru':'Ввести вручную', 'uk':'Ввести вручну',
'el':'Χειροκίνητη εισαγωγή', 'tr':'Elle giriş', 'ar':'إدخال يدوي', 'he':'הזנה ידנית', 'hi':'खुद दर्ज करें',
'bn':'নিজে লিখুন', 'pa':'ਹੱਥੀਂ ਦਾਖ਼ਲ ਕਰੋ', 'gu':'જાતે દાખલ કરો', 'mr':'स्वतः नोंदवा', 'ml':'നേരിട്ട് നൽകുക',
'or':'ନିଜେ ଲେଖନ୍ତୁ', 'ca':'Entrada manual', 'id':'Masukkan manual', 'ms':'Masukkan secara manual', 'vi':'Nhập thủ công',
'ur':'خود درج کریں', 'th':'ป้อนเอง', 'hr':'Ručni unos', 'sl':'Ročni vnos', 'ta':'கைமுறையாக உள்ளிடவும்',
'te':'మీరే నమోదు చేయండి', 'kn':'ಕೈಯಾರೆ ನಮೂದಿಸಿ',
}

def main():
    resources = ROOT / 'jifen/Resources'
    locales = sorted(p.stem for p in resources.glob('*.lproj'))
    assert set(locales) == set(T), (set(locales) - set(T), set(T) - set(locales))
    translations = {}
    for locale in locales:
        path = resources / f'{locale}.lproj/Localizable.strings'
        import subprocess
        data = plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(path)]))
        intro, download, winners, incomplete, duplicate = T[locale]
        template = '%@\n\n' + data['group_name'] + ': %@\n' + data['group_share_no'] + '\n\n' + data['group_join'] + ': %@\n\n' + download + '\n%@'
        translations[locale] = dict(zip(KEYS, [intro, template, winners, incomplete, duplicate, MANUAL[locale]]))
    # Preserve authoritative Android base/Chinese invitation text and placeholders.
    import re
    import xml.etree.ElementTree as ET
    for locale, folder in [('en', 'values'), ('zh-Hans', 'values-zh-rCN'), ('zh-Hant', 'values-zh-rTW')]:
        path = ROOT.parent / 'jifen-android/app/src/main/res' / folder / 'group_strings.xml'
        source = {s.attrib['name']: s.text or '' for s in ET.parse(path).getroot().findall('string')}
        for key in KEYS[:2]:
            translations[locale][key] = re.sub(r'%\d+\$s', '%@', source[key]).replace('\\n', '\n').replace("\\'", "'")
    for locale in locales:
        path = resources / f'{locale}.lproj/Localizable.strings'
        original = path.read_text()
        values = translations[locale]
        block = []
        for key, value in values.items():
            assert value.count('%@') == (5 if key == 'group_share_message' else 1 if key == 'group_invitation_intro_ball' else 0)
            escaped = json.dumps(value, ensure_ascii=False)
            line = f'"{key}" = {escaped};'
            pattern = r'^"' + re.escape(key) + r'"\s*=.*;\n?'
            if re.search(pattern, original, re.M):
                original = re.sub(pattern, lambda _: line + '\n', original, flags=re.M)
            else:
                block.append(line)
        if block:
            original += '\n/* Group parity alignment 2026-10-15 */\n' + '\n'.join(block) + '\n'
        path.write_text(original)
        if locale in {'en', 'zh-Hans', 'zh-Hant'}:
            continue
        catalog = ROOT / f'scripts/localization/catalogs/{locale}.jsonl'
        rows = [line for line in catalog.read_text().splitlines() if json.loads(line)['key'] not in KEYS or json.loads(line)['table'] != 'Localizable']
        for key, value in values.items():
            source_hash = hashlib.sha256(('Localizable\0' + key + '\0' + translations['en'][key]).encode()).hexdigest()[:16]
            rows.append(json.dumps(dict(table='Localizable', key=key, source_hash=source_hash, azure=None, google_web=None, google=None, final=value,
                             status='reviewed', flags=[], note='Codex-authored group parity alignment (2026-10-15)', machine_provider=None, issues=[]), ensure_ascii=False, separators=(',', ':')))
        catalog.write_text('\n'.join(rows) + '\n')
    print(f'Updated {len(KEYS)} keys in {len(locales)} locales and 44 review catalogs')

if __name__ == '__main__':
    main()
