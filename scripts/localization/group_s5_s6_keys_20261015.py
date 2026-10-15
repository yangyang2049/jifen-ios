#!/usr/bin/env python3
"""Group port s5/s6 delta keys (2026-10-15).

Adds 9 keys missing on iOS vs Android GroupDetailRecordsTab / GroupShareScreen:
  ranking: group_filter_singles / group_filter_doubles / group_ranking_me_suffix /
           group_ranking_insufficient_matches
  share:   group_audit_ui_share_invitation / group_audit_ui_share_qr /
           group_audit_ui_share_number / group_audit_ui_share_failed /
           group_audit_ui_group_number_message

en / zh-Hans take the authoritative Android `values` / `values-zh-rCN` wording;
zh-Hant follows `values-zh-rTW`; the other 44 locales are Codex-authored and
written to both the .lproj files and the review catalogs (status "reviewed"),
mirroring the group-port-20261013 batch.

Android %1$s/%2$s are normalized to %@ (project rule: %N$s segfaults in Swift).
"""

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "jifen" / "Resources"
CATALOGS = ROOT / "scripts" / "localization" / "catalogs"

RANKING_KEYS = [
    "group_filter_singles",
    "group_filter_doubles",
    "group_ranking_me_suffix",
    "group_ranking_insufficient_matches",
]
SHARE_KEYS = [
    "group_audit_ui_share_invitation",
    "group_audit_ui_share_qr",
    "group_audit_ui_share_number",
    "group_audit_ui_share_failed",
    "group_audit_ui_group_number_message",
]
ALL_KEYS = RANKING_KEYS + SHARE_KEYS
RANKING_ANCHOR = "group_ranking_empty"
SHARE_ANCHOR = "group_share_no"

# Values hold real newlines; encode_apple_string escapes them for .strings.
T = {
    "en": {
        "group_filter_singles": "Singles",
        "group_filter_doubles": "Doubles",
        "group_ranking_me_suffix": " (me)",
        "group_ranking_insufficient_matches": "Too few matches",
        "group_audit_ui_share_invitation": "Share invitation",
        "group_audit_ui_share_qr": "Share QR code",
        "group_audit_ui_share_number": "Share group number",
        "group_audit_ui_share_failed": "Sharing failed. Try again.",
        "group_audit_ui_group_number_message": "Group: %@\nGroup number: %@ (not accepting members)",
    },
    "zh-Hans": {
        "group_filter_singles": "单打",
        "group_filter_doubles": "双打",
        "group_ranking_me_suffix": "（我）",
        "group_ranking_insufficient_matches": "场次不足",
        "group_audit_ui_share_invitation": "分享邀请",
        "group_audit_ui_share_qr": "分享二维码",
        "group_audit_ui_share_number": "分享小组号",
        "group_audit_ui_share_failed": "分享失败，请重试",
        "group_audit_ui_group_number_message": "小组：%@\n小组号：%@（当前不可加入）",
    },
    "zh-Hant": {
        "group_filter_singles": "單打",
        "group_filter_doubles": "雙打",
        "group_ranking_me_suffix": "（我）",
        "group_ranking_insufficient_matches": "場次不足",
        "group_audit_ui_share_invitation": "分享邀請",
        "group_audit_ui_share_qr": "分享 QR Code",
        "group_audit_ui_share_number": "分享小組號",
        "group_audit_ui_share_failed": "分享失敗，請重試",
        "group_audit_ui_group_number_message": "小組：%@\n小組號：%@（目前不可加入）",
    },
    "ja": {
        "group_filter_singles": "シングルス",
        "group_filter_doubles": "ダブルス",
        "group_ranking_me_suffix": "（自分）",
        "group_ranking_insufficient_matches": "試合数が不足",
        "group_audit_ui_share_invitation": "招待をシェア",
        "group_audit_ui_share_qr": "QRコードをシェア",
        "group_audit_ui_share_number": "グループ番号をシェア",
        "group_audit_ui_share_failed": "シェアに失敗しました。もう一度お試しください。",
        "group_audit_ui_group_number_message": "グループ：%@\nグループ番号：%@（現在は参加できません）",
    },
    "ko": {
        "group_filter_singles": "단식",
        "group_filter_doubles": "복식",
        "group_ranking_me_suffix": "(나)",
        "group_ranking_insufficient_matches": "경기 수 부족",
        "group_audit_ui_share_invitation": "초대 공유",
        "group_audit_ui_share_qr": "QR 코드 공유",
        "group_audit_ui_share_number": "그룹 번호 공유",
        "group_audit_ui_share_failed": "공유하지 못했습니다. 다시 시도해 주세요.",
        "group_audit_ui_group_number_message": "그룹: %@\n그룹 번호: %@ (현재 신규 회원을 받고 있지 않습니다)",
    },
    "de": {
        "group_filter_singles": "Einzel",
        "group_filter_doubles": "Doppel",
        "group_ranking_me_suffix": " (ich)",
        "group_ranking_insufficient_matches": "Zu wenige Spiele",
        "group_audit_ui_share_invitation": "Einladung teilen",
        "group_audit_ui_share_qr": "QR-Code teilen",
        "group_audit_ui_share_number": "Gruppennummer teilen",
        "group_audit_ui_share_failed": "Teilen fehlgeschlagen. Bitte erneut versuchen.",
        "group_audit_ui_group_number_message": "Gruppe: %@\nGruppennummer: %@ (derzeit keine neuen Mitglieder)",
    },
    "fr": {
        "group_filter_singles": "Simple",
        "group_filter_doubles": "Double",
        "group_ranking_me_suffix": " (moi)",
        "group_ranking_insufficient_matches": "Trop peu de matchs",
        "group_audit_ui_share_invitation": "Partager l'invitation",
        "group_audit_ui_share_qr": "Partager le code QR",
        "group_audit_ui_share_number": "Partager le numéro de groupe",
        "group_audit_ui_share_failed": "Le partage a échoué. Réessayez.",
        "group_audit_ui_group_number_message": "Groupe : %@\nNuméro de groupe : %@ (n'accepte pas de nouveaux membres pour le moment)",
    },
    "fr-CA": {
        "group_filter_singles": "Simple",
        "group_filter_doubles": "Double",
        "group_ranking_me_suffix": " (moi)",
        "group_ranking_insufficient_matches": "Trop peu de matchs",
        "group_audit_ui_share_invitation": "Partager l'invitation",
        "group_audit_ui_share_qr": "Partager le code QR",
        "group_audit_ui_share_number": "Partager le numéro de groupe",
        "group_audit_ui_share_failed": "Le partage a échoué. Réessayez.",
        "group_audit_ui_group_number_message": "Groupe : %@\nNuméro de groupe : %@ (n'accepte pas de nouveaux membres pour le moment)",
    },
    "es-ES": {
        "group_filter_singles": "Individual",
        "group_filter_doubles": "Dobles",
        "group_ranking_me_suffix": " (yo)",
        "group_ranking_insufficient_matches": "Muy pocos partidos",
        "group_audit_ui_share_invitation": "Compartir invitación",
        "group_audit_ui_share_qr": "Compartir código QR",
        "group_audit_ui_share_number": "Compartir número de grupo",
        "group_audit_ui_share_failed": "No se pudo compartir. Inténtalo de nuevo.",
        "group_audit_ui_group_number_message": "Grupo: %@\nNúmero de grupo: %@ (actualmente no acepta nuevos miembros)",
    },
    "es-MX": {
        "group_filter_singles": "Individual",
        "group_filter_doubles": "Dobles",
        "group_ranking_me_suffix": " (yo)",
        "group_ranking_insufficient_matches": "Muy pocos partidos",
        "group_audit_ui_share_invitation": "Compartir invitación",
        "group_audit_ui_share_qr": "Compartir código QR",
        "group_audit_ui_share_number": "Compartir número de grupo",
        "group_audit_ui_share_failed": "No se pudo compartir. Inténtalo de nuevo.",
        "group_audit_ui_group_number_message": "Grupo: %@\nNúmero de grupo: %@ (actualmente no acepta nuevos miembros)",
    },
    "pt-BR": {
        "group_filter_singles": "Simples",
        "group_filter_doubles": "Duplas",
        "group_ranking_me_suffix": " (eu)",
        "group_ranking_insufficient_matches": "Poucas partidas",
        "group_audit_ui_share_invitation": "Compartilhar convite",
        "group_audit_ui_share_qr": "Compartilhar código QR",
        "group_audit_ui_share_number": "Compartilhar número do grupo",
        "group_audit_ui_share_failed": "Falha ao compartilhar. Tente novamente.",
        "group_audit_ui_group_number_message": "Grupo: %@\nNúmero do grupo: %@ (não aceita novos membros no momento)",
    },
    "pt-PT": {
        "group_filter_singles": "Simples",
        "group_filter_doubles": "Duplas",
        "group_ranking_me_suffix": " (eu)",
        "group_ranking_insufficient_matches": "Poucas partidas",
        "group_audit_ui_share_invitation": "Partilhar convite",
        "group_audit_ui_share_qr": "Partilhar código QR",
        "group_audit_ui_share_number": "Partilhar número do grupo",
        "group_audit_ui_share_failed": "Falha ao partilhar. Tente novamente.",
        "group_audit_ui_group_number_message": "Grupo: %@\nNúmero do grupo: %@ (de momento não aceita novos membros)",
    },
    "it": {
        "group_filter_singles": "Singolare",
        "group_filter_doubles": "Doppio",
        "group_ranking_me_suffix": " (io)",
        "group_ranking_insufficient_matches": "Poche partite",
        "group_audit_ui_share_invitation": "Condividi invito",
        "group_audit_ui_share_qr": "Condividi codice QR",
        "group_audit_ui_share_number": "Condividi numero del gruppo",
        "group_audit_ui_share_failed": "Condivisione non riuscita. Riprova.",
        "group_audit_ui_group_number_message": "Gruppo: %@\nNumero del gruppo: %@ (al momento non accetta nuovi membri)",
    },
    "nl": {
        "group_filter_singles": "Enkel",
        "group_filter_doubles": "Dubbel",
        "group_ranking_me_suffix": " (ik)",
        "group_ranking_insufficient_matches": "Te weinig wedstrijden",
        "group_audit_ui_share_invitation": "Uitnodiging delen",
        "group_audit_ui_share_qr": "QR-code delen",
        "group_audit_ui_share_number": "Groepsnummer delen",
        "group_audit_ui_share_failed": "Delen mislukt. Probeer het opnieuw.",
        "group_audit_ui_group_number_message": "Groep: %@\nGroepsnummer: %@ (accepteert momenteel geen nieuwe leden)",
    },
    "sv": {
        "group_filter_singles": "Singel",
        "group_filter_doubles": "Dubbel",
        "group_ranking_me_suffix": " (jag)",
        "group_ranking_insufficient_matches": "För få matcher",
        "group_audit_ui_share_invitation": "Dela inbjudan",
        "group_audit_ui_share_qr": "Dela QR-kod",
        "group_audit_ui_share_number": "Dela gruppenummer",
        "group_audit_ui_share_failed": "Delningen misslyckades. Försök igen.",
        "group_audit_ui_group_number_message": "Grupp: %@\nGruppnummer: %@ (tar inte emot nya medlemmar just nu)",
    },
    "da": {
        "group_filter_singles": "Single",
        "group_filter_doubles": "Double",
        "group_ranking_me_suffix": " (mig)",
        "group_ranking_insufficient_matches": "For få kampe",
        "group_audit_ui_share_invitation": "Del invitation",
        "group_audit_ui_share_qr": "Del QR-kode",
        "group_audit_ui_share_number": "Del gruppenummer",
        "group_audit_ui_share_failed": "Deling mislykkedes. Prøv igen.",
        "group_audit_ui_group_number_message": "Gruppe: %@\nGruppenummer: %@ (modtager i øjeblikket ikke nye medlemmer)",
    },
    "nb": {
        "group_filter_singles": "Single",
        "group_filter_doubles": "Double",
        "group_ranking_me_suffix": " (meg)",
        "group_ranking_insufficient_matches": "For få kamper",
        "group_audit_ui_share_invitation": "Del invitasjonen",
        "group_audit_ui_share_qr": "Del QR-koden",
        "group_audit_ui_share_number": "Del gruppenummeret",
        "group_audit_ui_share_failed": "Deling mislyktes. Prøv igjen.",
        "group_audit_ui_group_number_message": "Gruppe: %@\nGruppenummer: %@ (tar foreløpig ikke imot nye medlemmer)",
    },
    "fi": {
        "group_filter_singles": "Kaksinpeli",
        "group_filter_doubles": "Nelinpeli",
        "group_ranking_me_suffix": " (minä)",
        "group_ranking_insufficient_matches": "Liian vähän pelejä",
        "group_audit_ui_share_invitation": "Jaa kutsu",
        "group_audit_ui_share_qr": "Jaa QR-koodi",
        "group_audit_ui_share_number": "Jaa ryhmän numero",
        "group_audit_ui_share_failed": "Jakaminen epäonnistui. Yritä uudelleen.",
        "group_audit_ui_group_number_message": "Ryhmä: %@\nRyhmän numero: %@ (ei ota tällä hetkellä uusia jäseniä)",
    },
    "pl": {
        "group_filter_singles": "Pojedyncze",
        "group_filter_doubles": "Podwójne",
        "group_ranking_me_suffix": " (ja)",
        "group_ranking_insufficient_matches": "Zbyt mało meczów",
        "group_audit_ui_share_invitation": "Udostępnij zaproszenie",
        "group_audit_ui_share_qr": "Udostępnij kod QR",
        "group_audit_ui_share_number": "Udostępnij numer grupy",
        "group_audit_ui_share_failed": "Udostępnianie nie powiodło się. Spróbuj ponownie.",
        "group_audit_ui_group_number_message": "Grupa: %@\nNumer grupy: %@ (obecnie nie przyjmuje nowych członków)",
    },
    "ca": {
        "group_filter_singles": "Individuals",
        "group_filter_doubles": "Dobles",
        "group_ranking_me_suffix": " (jo)",
        "group_ranking_insufficient_matches": "Massa pocs partits",
        "group_audit_ui_share_invitation": "Comparteix la invitació",
        "group_audit_ui_share_qr": "Comparteix el codi QR",
        "group_audit_ui_share_number": "Comparteix el número del grup",
        "group_audit_ui_share_failed": "No s'ha pogut compartir. Torna-ho a provar.",
        "group_audit_ui_group_number_message": "Grup: %@\nNúmero del grup: %@ (actualment no admet nous membres)",
    },
    "cs": {
        "group_filter_singles": "Dvouhry",
        "group_filter_doubles": "Čtyřhry",
        "group_ranking_me_suffix": " (já)",
        "group_ranking_insufficient_matches": "Příliš málo zápasů",
        "group_audit_ui_share_invitation": "Sdílet pozvánku",
        "group_audit_ui_share_qr": "Sdílet QR kód",
        "group_audit_ui_share_number": "Sdílet číslo skupiny",
        "group_audit_ui_share_failed": "Sdílení se nezdařilo. Zkuste to znovu.",
        "group_audit_ui_group_number_message": "Skupina: %@\nČíslo skupiny: %@ (momentálně nepřijímá nové členy)",
    },
    "sk": {
        "group_filter_singles": "Dvojhry",
        "group_filter_doubles": "Štvorhry",
        "group_ranking_me_suffix": " (ja)",
        "group_ranking_insufficient_matches": "Príliš málo zápasov",
        "group_audit_ui_share_invitation": "Zdieľať pozvánku",
        "group_audit_ui_share_qr": "Zdieľať QR kód",
        "group_audit_ui_share_number": "Zdieľať číslo skupiny",
        "group_audit_ui_share_failed": "Zdieľanie sa nepodarilo. Skúste to znova.",
        "group_audit_ui_group_number_message": "Skupina: %@\nČíslo skupiny: %@ (aktuálne neprijíma nových členov)",
    },
    "hu": {
        "group_filter_singles": "Egyes",
        "group_filter_doubles": "Páros",
        "group_ranking_me_suffix": " (én)",
        "group_ranking_insufficient_matches": "Túl kevés mérkőzés",
        "group_audit_ui_share_invitation": "Meghívó megosztása",
        "group_audit_ui_share_qr": "QR-kód megosztása",
        "group_audit_ui_share_number": "Csoportszám megosztása",
        "group_audit_ui_share_failed": "A megosztás nem sikerült. Próbáld újra.",
        "group_audit_ui_group_number_message": "Csoport: %@\nCsoportszám: %@ (jelenleg nem fogad új tagokat)",
    },
    "ro": {
        "group_filter_singles": "Simplu",
        "group_filter_doubles": "Dublu",
        "group_ranking_me_suffix": " (eu)",
        "group_ranking_insufficient_matches": "Prea puține meciuri",
        "group_audit_ui_share_invitation": "Partajează invitația",
        "group_audit_ui_share_qr": "Partajează codul QR",
        "group_audit_ui_share_number": "Partajează numărul grupului",
        "group_audit_ui_share_failed": "Partajarea a eșuat. Încearcă din nou.",
        "group_audit_ui_group_number_message": "Grup: %@\nNumărul grupului: %@ (nu acceptă membri noi momentan)",
    },
    "hr": {
        "group_filter_singles": "Pojedinačno",
        "group_filter_doubles": "Parovi",
        "group_ranking_me_suffix": " (ja)",
        "group_ranking_insufficient_matches": "Premalo utakmica",
        "group_audit_ui_share_invitation": "Podijeli pozivnicu",
        "group_audit_ui_share_qr": "Podijeli QR kod",
        "group_audit_ui_share_number": "Podijeli broj grupe",
        "group_audit_ui_share_failed": "Dijeljenje nije uspjelo. Pokušajte ponovo.",
        "group_audit_ui_group_number_message": "Grupa: %@\nBroj grupe: %@ (trenutno ne prima nove članove)",
    },
    "sl": {
        "group_filter_singles": "Posamično",
        "group_filter_doubles": "Dvojice",
        "group_ranking_me_suffix": " (jaz)",
        "group_ranking_insufficient_matches": "Premalo tekem",
        "group_audit_ui_share_invitation": "Deli vabilo",
        "group_audit_ui_share_qr": "Deli kodo QR",
        "group_audit_ui_share_number": "Deli številko skupine",
        "group_audit_ui_share_failed": "Dajanje v skupno rabo ni uspelo. Poskusite znova.",
        "group_audit_ui_group_number_message": "Skupina: %@\nŠtevilka skupine: %@ (trenutno ne sprejema novih članov)",
    },
    "el": {
        "group_filter_singles": "Μονοί",
        "group_filter_doubles": "Διπλοί",
        "group_ranking_me_suffix": " (εγώ)",
        "group_ranking_insufficient_matches": "Υπερβολικά λίγοι αγώνες",
        "group_audit_ui_share_invitation": "Κοινοποίηση πρόσκλησης",
        "group_audit_ui_share_qr": "Κοινοποίηση κωδικού QR",
        "group_audit_ui_share_number": "Κοινοποίηση αριθμού ομάδας",
        "group_audit_ui_share_failed": "Η κοινοποίηση απέτυχε. Δοκιμάστε ξανά.",
        "group_audit_ui_group_number_message": "Ομάδα: %@\nΑριθμός ομάδας: %@ (δεν δέχεται νέα μέλη αυτή τη στιγμή)",
    },
    "ru": {
        "group_filter_singles": "Одиночный",
        "group_filter_doubles": "Парный",
        "group_ranking_me_suffix": " (я)",
        "group_ranking_insufficient_matches": "Слишком мало матчей",
        "group_audit_ui_share_invitation": "Поделиться приглашением",
        "group_audit_ui_share_qr": "Поделиться QR-кодом",
        "group_audit_ui_share_number": "Поделиться номером группы",
        "group_audit_ui_share_failed": "Не удалось поделиться. Попробуйте снова.",
        "group_audit_ui_group_number_message": "Группа: %@\nНомер группы: %@ (сейчас не принимает новых участников)",
    },
    "uk": {
        "group_filter_singles": "Одиночний",
        "group_filter_doubles": "Парний",
        "group_ranking_me_suffix": " (я)",
        "group_ranking_insufficient_matches": "Занадто мало матчів",
        "group_audit_ui_share_invitation": "Поділитися запрошенням",
        "group_audit_ui_share_qr": "Поділитися QR-кодом",
        "group_audit_ui_share_number": "Поділитися номером групи",
        "group_audit_ui_share_failed": "Не вдалося поділитися. Спробуйте ще раз.",
        "group_audit_ui_group_number_message": "Група: %@\nНомер групи: %@ (наразі не приймає нових учасників)",
    },
    "tr": {
        "group_filter_singles": "Tekler",
        "group_filter_doubles": "Çiftler",
        "group_ranking_me_suffix": " (ben)",
        "group_ranking_insufficient_matches": "Çok az maç",
        "group_audit_ui_share_invitation": "Davetiyeyi paylaş",
        "group_audit_ui_share_qr": "QR kodu paylaş",
        "group_audit_ui_share_number": "Grup numarasını paylaş",
        "group_audit_ui_share_failed": "Paylaşma başarısız oldu. Tekrar deneyin.",
        "group_audit_ui_group_number_message": "Grup: %@\nGrup numarası: %@ (şu anda yeni üye kabul etmiyor)",
    },
    "ar": {
        "group_filter_singles": "فردي",
        "group_filter_doubles": "زوجي",
        "group_ranking_me_suffix": " (أنا)",
        "group_ranking_insufficient_matches": "مباريات قليلة جداً",
        "group_audit_ui_share_invitation": "مشاركة الدعوة",
        "group_audit_ui_share_qr": "مشاركة رمز QR",
        "group_audit_ui_share_number": "مشاركة رقم المجموعة",
        "group_audit_ui_share_failed": "فشلت المشاركة. حاول مرة أخرى.",
        "group_audit_ui_group_number_message": "المجموعة: %@\nرقم المجموعة: %@ (لا يقبل أعضاء جدد حالياً)",
    },
    "he": {
        "group_filter_singles": "יחידים",
        "group_filter_doubles": "זוגות",
        "group_ranking_me_suffix": " (אני)",
        "group_ranking_insufficient_matches": "מעט מדי משחקים",
        "group_audit_ui_share_invitation": "שיתוף הזמנה",
        "group_audit_ui_share_qr": "שיתוף קוד QR",
        "group_audit_ui_share_number": "שיתוף מספר הקבוצה",
        "group_audit_ui_share_failed": "השיתוף נכשל. נסו שוב.",
        "group_audit_ui_group_number_message": "קבוצה: %@\nמספר קבוצה: %@ (אינה מקבלת חברים חדשים כרגע)",
    },
    "ur": {
        "group_filter_singles": "سنگلز",
        "group_filter_doubles": "ڈبلز",
        "group_ranking_me_suffix": " (میں)",
        "group_ranking_insufficient_matches": "بہت کم میچ",
        "group_audit_ui_share_invitation": "دعوت شیئر کریں",
        "group_audit_ui_share_qr": "QR کوڈ شیئر کریں",
        "group_audit_ui_share_number": "گروپ نمبر شیئر کریں",
        "group_audit_ui_share_failed": "شیئر کرنے میں ناکامی۔ دوبارہ کوشش کریں۔",
        "group_audit_ui_group_number_message": "گروپ: %@\nگروپ نمبر: %@ (فی الحال نئے ارکان قبول نہیں کر رہا)",
    },
    "hi": {
        "group_filter_singles": "एकल",
        "group_filter_doubles": "युगल",
        "group_ranking_me_suffix": " (मैं)",
        "group_ranking_insufficient_matches": "बहुत कम मैच",
        "group_audit_ui_share_invitation": "आमंत्रण साझा करें",
        "group_audit_ui_share_qr": "QR कोड साझा करें",
        "group_audit_ui_share_number": "ग्रुप नंबर साझा करें",
        "group_audit_ui_share_failed": "साझा करना विफल रहा। फिर से प्रयास करें।",
        "group_audit_ui_group_number_message": "ग्रुप: %@\nग्रुप नंबर: %@ (इस समय नए सदस्य स्वीकार नहीं कर रहा)",
    },
    "bn": {
        "group_filter_singles": "একক",
        "group_filter_doubles": "দ্বৈত",
        "group_ranking_me_suffix": " (আমি)",
        "group_ranking_insufficient_matches": "খেলা খুব কম",
        "group_audit_ui_share_invitation": "আমন্ত্রণ শেয়ার করুন",
        "group_audit_ui_share_qr": "QR কোড শেয়ার করুন",
        "group_audit_ui_share_number": "গ্রুপ নম্বর শেয়ার করুন",
        "group_audit_ui_share_failed": "শেয়ার করা ব্যর্থ হয়েছে। আবার চেষ্টা করুন।",
        "group_audit_ui_group_number_message": "গ্রুপ: %@\nগ্রুপ নম্বর: %@ (এখন সদস্য নেওয়া হচ্ছে না)",
    },
    "gu": {
        "group_filter_singles": "એકલ",
        "group_filter_doubles": "યુગલ",
        "group_ranking_me_suffix": " (હું)",
        "group_ranking_insufficient_matches": "બહુ ઓછી રમતો",
        "group_audit_ui_share_invitation": "આમંત્રણ શેર કરો",
        "group_audit_ui_share_qr": "QR કોડ શેર કરો",
        "group_audit_ui_share_number": "ગ્રુપ નંબર શેર કરો",
        "group_audit_ui_share_failed": "શેર કરવામાં નિષ્ફળતા. ફરી પ્રયાસ કરો.",
        "group_audit_ui_group_number_message": "ગ્રુપ: %@\nગ્રુપ નંબર: %@ (હાલમાં નવા સભ્યો સ્વીકારતું નથી)",
    },
    "mr": {
        "group_filter_singles": "एकेरी",
        "group_filter_doubles": "दुहेरी",
        "group_ranking_me_suffix": " (मी)",
        "group_ranking_insufficient_matches": "खूप कमी सामने",
        "group_audit_ui_share_invitation": "आमंत्रण शेअर करा",
        "group_audit_ui_share_qr": "QR कोड शेअर करा",
        "group_audit_ui_share_number": "ग्रुप क्रमांक शेअर करा",
        "group_audit_ui_share_failed": "शेअर अयशस्वी. पुन्हा प्रयत्न करा.",
        "group_audit_ui_group_number_message": "ग्रुप: %@\nग्रुप क्रमांक: %@ (सध्या नवीन सदस्य स्वीकारत नाही)",
    },
    "pa": {
        "group_filter_singles": "ਇਕਹਿਰਾ",
        "group_filter_doubles": "ਜੋੜੀਦਾਰ",
        "group_ranking_me_suffix": " (ਮੈਂ)",
        "group_ranking_insufficient_matches": "ਬਹੁਤ ਘੱਟ ਮੈਚ",
        "group_audit_ui_share_invitation": "ਸੱਦਾ ਸਾਂਝਾ ਕਰੋ",
        "group_audit_ui_share_qr": "QR ਕੋਡ ਸਾਂਝਾ ਕਰੋ",
        "group_audit_ui_share_number": "ਗਰੁੱਪ ਨੰਬਰ ਸਾਂਝਾ ਕਰੋ",
        "group_audit_ui_share_failed": "ਸਾਂਝਾ ਕਰਨਾ ਅਸਫਲ ਰਿਹਾ। ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
        "group_audit_ui_group_number_message": "ਗਰੁੱਪ: %@\nਗਰੁੱਪ ਨੰਬਰ: %@ (ਇਸ ਸਮੇਂ ਨਵੇਂ ਮੈਂਬਰ ਸਵੀਕਾਰ ਨਹੀਂ ਕਰ ਰਿਹਾ)",
    },
    "ta": {
        "group_filter_singles": "ஒற்றை",
        "group_filter_doubles": "இரட்டை",
        "group_ranking_me_suffix": " (நான்)",
        "group_ranking_insufficient_matches": "மிகக் குறைவான போட்டிகள்",
        "group_audit_ui_share_invitation": "அழைப்பைப் பகிர்",
        "group_audit_ui_share_qr": "QR குறியீட்டைப் பகிர்",
        "group_audit_ui_share_number": "குழு எண்ணைப் பகிர்",
        "group_audit_ui_share_failed": "பகிர்தல் தோல்வி. மீண்டும் முயற்சிக்கவும்.",
        "group_audit_ui_group_number_message": "குழு: %@\nகுழு எண்: %@ (தற்போது புதிய உறுப்பினர்களை ஏற்கவில்லை)",
    },
    "te": {
        "group_filter_singles": "సింగిల్స్",
        "group_filter_doubles": "డబుల్స్",
        "group_ranking_me_suffix": " (నేను)",
        "group_ranking_insufficient_matches": "చాలా తక్కువ మ్యాచ్‌లు",
        "group_audit_ui_share_invitation": "ఆహ్వానాన్ని షేర్ చేయండి",
        "group_audit_ui_share_qr": "QR కోడ్‌ను షేర్ చేయండి",
        "group_audit_ui_share_number": "గ్రూప్ నంబర్‌ను షేర్ చేయండి",
        "group_audit_ui_share_failed": "షేర్ చేయడం విఫలమైంది. మళ్లీ ప్రయత్నించండి.",
        "group_audit_ui_group_number_message": "గ్రూప్: %@\nగ్రూప్ నంబర్: %@ (ప్రస్తుతం కొత్త సభ్యులను అంగీకరించడం లేదు)",
    },
    "kn": {
        "group_filter_singles": "ಏಕ",
        "group_filter_doubles": "ಜೋಡಿ",
        "group_ranking_me_suffix": " (ನಾನು)",
        "group_ranking_insufficient_matches": "ಬಹಳ ಕಡಿಮೆ ಪಂದ್ಯಗಳು",
        "group_audit_ui_share_invitation": "ಆಮಂತ್ರಣ ಹಂಚಿಕೊಳ್ಳಿ",
        "group_audit_ui_share_qr": "QR ಕೋಡ್ ಹಂಚಿಕೊಳ್ಳಿ",
        "group_audit_ui_share_number": "ಗುಂಪಿನ ಸಂಖ್ಯೆ ಹಂಚಿಕೊಳ್ಳಿ",
        "group_audit_ui_share_failed": "ಹಂಚಿಕೆ ವಿಫಲವಾಗಿದೆ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
        "group_audit_ui_group_number_message": "ಗುಂಪು: %@\nಗುಂಪಿನ ಸಂಖ್ಯೆ: %@ (ಪ್ರಸ್ತುತ ಹೊಸ ಸದಸ್ಯರನ್ನು ಸ್ವೀಕರಿಸುತ್ತಿಲ್ಲ)",
    },
    "ml": {
        "group_filter_singles": "സിംഗിൾസ്",
        "group_filter_doubles": "ഡബിൾസ്",
        "group_ranking_me_suffix": " (ഞാൻ)",
        "group_ranking_insufficient_matches": "വളരെ കുറച്ച് മത്സരങ്ങൾ",
        "group_audit_ui_share_invitation": "ക്ഷണം പങ്കിടുക",
        "group_audit_ui_share_qr": "QR കോഡ് പങ്കിടുക",
        "group_audit_ui_share_number": "ഗ്രൂപ്പ് നമ്പർ പങ്കിടുക",
        "group_audit_ui_share_failed": "പങ്കിടൽ പരാജയപ്പെട്ടു. വീണ്ടും ശ്രമിക്കുക.",
        "group_audit_ui_group_number_message": "ഗ്രൂപ്പ്: %@\nഗ്രൂപ്പ് നമ്പർ: %@ (ഇപ്പോൾ പുതിയ അംഗങ്ങളെ സ്വീകരിക്കുന്നില്ല)",
    },
    "or": {
        "group_filter_singles": "ଏକକ",
        "group_filter_doubles": "ଯୁଗଳ",
        "group_ranking_me_suffix": " (ମୁଁ)",
        "group_ranking_insufficient_matches": "ବହୁତ କମ୍ ମ୍ୟାଚ",
        "group_audit_ui_share_invitation": "ଆମନ୍ତ୍ରଣ ସେୟାର କରନ୍ତୁ",
        "group_audit_ui_share_qr": "QR କୋଡ୍ ସେୟାର କରନ୍ତୁ",
        "group_audit_ui_share_number": "ଗୋଷ୍ଠୀ ନମ୍ବର ସେୟାର କରନ୍ତୁ",
        "group_audit_ui_share_failed": "ସେୟାର ବିଫଳ ହେଲା। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।",
        "group_audit_ui_group_number_message": "ଗୋଷ୍ଠୀ: %@\nଗୋଷ୍ଠୀ ନମ୍ବର: %@ (ବର୍ତ୍ତମାନ ନୂଆ ସଦସ୍ୟ ଗ୍ରହଣ କରୁନାହିଁ)",
    },
    "id": {
        "group_filter_singles": "Tunggal",
        "group_filter_doubles": "Ganda",
        "group_ranking_me_suffix": " (saya)",
        "group_ranking_insufficient_matches": "Terlalu sedikit pertandingan",
        "group_audit_ui_share_invitation": "Bagikan undangan",
        "group_audit_ui_share_qr": "Bagikan kode QR",
        "group_audit_ui_share_number": "Bagikan nomor grup",
        "group_audit_ui_share_failed": "Gagal membagikan. Coba lagi.",
        "group_audit_ui_group_number_message": "Grup: %@\nNomor grup: %@ (saat ini tidak menerima anggota baru)",
    },
    "ms": {
        "group_filter_singles": "Perseorangan",
        "group_filter_doubles": "Beregu",
        "group_ranking_me_suffix": " (saya)",
        "group_ranking_insufficient_matches": "Terlalu sedikit perlawanan",
        "group_audit_ui_share_invitation": "Kongsi jemputan",
        "group_audit_ui_share_qr": "Kongsi kod QR",
        "group_audit_ui_share_number": "Kongsi nombor kumpulan",
        "group_audit_ui_share_failed": "Gagal berkongsi. Cuba lagi.",
        "group_audit_ui_group_number_message": "Kumpulan: %@\nNombor kumpulan: %@ (buat masa ini tidak menerima ahli baharu)",
    },
    "th": {
        "group_filter_singles": "เดี่ยว",
        "group_filter_doubles": "คู่",
        "group_ranking_me_suffix": " (ฉัน)",
        "group_ranking_insufficient_matches": "มีการแข่งขันน้อยเกินไป",
        "group_audit_ui_share_invitation": "แชร์คำเชิญ",
        "group_audit_ui_share_qr": "แชร์คิวอาร์โค้ด",
        "group_audit_ui_share_number": "แชร์หมายเลขกลุ่ม",
        "group_audit_ui_share_failed": "แชร์ไม่สำเร็จ โปรดลองอีกครั้ง",
        "group_audit_ui_group_number_message": "กลุ่ม: %@\nหมายเลขกลุ่ม: %@ (ขณะนี้ยังไม่รับสมาชิกใหม่)",
    },
    "vi": {
        "group_filter_singles": "Đơn",
        "group_filter_doubles": "Đôi",
        "group_ranking_me_suffix": " (tôi)",
        "group_ranking_insufficient_matches": "Quá ít trận đấu",
        "group_audit_ui_share_invitation": "Chia sẻ lời mời",
        "group_audit_ui_share_qr": "Chia sẻ mã QR",
        "group_audit_ui_share_number": "Chia sẻ số nhóm",
        "group_audit_ui_share_failed": "Chia sẻ không thành công. Hãy thử lại.",
        "group_audit_ui_group_number_message": "Nhóm: %@\nSố nhóm: %@ (hiện không nhận thành viên mới)",
    },
}


def encode_apple_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def source_hash(key: str, value: str) -> str:
    payload = "Localizable\0%s\0%s" % (key, value)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def insert_after_anchor(lines, anchor_key, new_lines):
    prefix = '"%s" =' % anchor_key
    for index, line in enumerate(lines):
        if line.strip().startswith(prefix):
            return lines[: index + 1] + new_lines + lines[index + 1:], True
    return lines + new_lines, False


def main() -> int:
    en_values = T["en"]
    hashes = {key: source_hash(key, en_values[key]) for key in ALL_KEYS}
    locales = sorted(T.keys())
    missing = [path.name for path in RES.glob("*.lproj") if path.name[: -len(".lproj")] not in T]
    if missing:
        print("!! lproj without translations: %s" % ", ".join(missing))
        return 1
    for locale in locales:
        values = T[locale]
        missing_keys = [key for key in ALL_KEYS if key not in values]
        if missing_keys:
            print("!! %s missing keys: %s" % (locale, missing_keys))
            return 1
        path = RES / (locale + ".lproj") / "Localizable.strings"
        if not path.exists():
            print("!! strings file missing: %s" % path)
            return 1
        text = path.read_text(encoding="utf-8")
        for key in ALL_KEYS:
            marker = '"%s" =' % key
            if marker in text:
                print("skip %s (already has %s)" % (locale, key))
        lines = text.splitlines()
        ranking_block = ['"%s" = "%s";' % (key, encode_apple_string(values[key]))
                         for key in RANKING_KEYS if ('"%s" =' % key) not in text]
        share_block = ['"%s" = "%s";' % (key, encode_apple_string(values[key]))
                       for key in SHARE_KEYS if ('"%s" =' % key) not in text]
        lines, ok1 = insert_after_anchor(lines, RANKING_ANCHOR, ranking_block)
        lines, ok2 = insert_after_anchor(lines, SHARE_ANCHOR, share_block)
        if not (ok1 and ok2):
            print("!! %s anchor missing (ranking=%s share=%s), appended at EOF" % (locale, ok1, ok2))
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        if locale in {"en", "zh-Hans", "zh-Hant"}:
            continue  # existing locales have no review catalog
        catalog = CATALOGS / (locale + ".jsonl")
        if not catalog.exists():
            print("!! catalog missing: %s" % catalog)
            return 1
        existing = catalog.read_text(encoding="utf-8")
        with catalog.open("a", encoding="utf-8") as handle:
            for key in ALL_KEYS:
                entry = {
                    "table": "Localizable",
                    "key": key,
                    "source_hash": hashes[key],
                    "azure": None,
                    "google_web": None,
                    "google": None,
                    "final": values[key],
                    "status": "reviewed",
                    "flags": [],
                    "note": "Codex-authored group-port s5/s6 delta (2026-10-15)",
                    "machine_provider": None,
                    "issues": [],
                }
                if '"%s"' % key in existing:
                    continue
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print("ok: %d locales updated, %d keys each" % (len(locales), len(ALL_KEYS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
