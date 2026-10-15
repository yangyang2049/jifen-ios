#!/usr/bin/env python3
"""Group notice Plan-B parity: add group_notice_mark_all, retire group_notice_open.

Reviewed, Codex-authored copy; mirrors scripts/localization/group_alignment_keys_20261015.py.
Idempotent."""
import hashlib
import json
import re
import subprocess
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KEY_ADD = 'group_notice_mark_all'
KEY_DEL = 'group_notice_open'
NOTE = 'Codex-authored group notice plan-B 2026-10-15'

T = {
'en': 'Mark all read', 'zh-Hans': '全部已读', 'zh-Hant': '全部已讀',
'ja': 'すべて既読にする', 'ko': '모두 읽음으로 표시',
'de': 'Alle als gelesen markieren', 'fr': 'Tout marquer comme lu', 'fr-CA': 'Tout marquer comme lu',
'es-ES': 'Marcar todo como leído', 'es-MX': 'Marcar todo como leído',
'it': 'Segna tutto come letto', 'pt-BR': 'Marcar tudo como lido', 'pt-PT': 'Marcar tudo como lido',
'nl': 'Alles als gelezen markeren', 'sv': 'Markera alla som lästa',
'da': 'Markér alle som læst', 'nb': 'Merk alle som lest', 'fi': 'Merkitse kaikki luetuiksi',
'pl': 'Oznacz wszystkie jako przeczytane', 'cs': 'Označit vše jako přečtené', 'sk': 'Označiť všetko ako prečítané',
'hu': 'Mindet olvasottnak jelöl', 'ro': 'Marchează tot ca citit',
'ru': 'Отметить все как прочитанные', 'uk': 'Позначити всі як прочитані',
'el': 'Σήμανση όλων ως αναγνωσμένα', 'tr': 'Tümünü okundu işaretle',
'ar': 'وضع علامة مقروء على الكل', 'he': 'סימון הכול כנקרא',
'hi': 'सभी को पढ़ा हुआ मार्क करें', 'bn': 'সব পঠিত হিসেবে চিহ্নিত করুন',
'pa': 'ਸਭ ਪੜ੍ਹਿਆ ਹੋਇਆ ਮਾਰਕ ਕਰੋ', 'gu': 'ਸਭ ਪੜ੍ਹਿਆ ਹੋਇਆ ਮਾਰਕ ਕਰੋ',
'mr': 'सर्व वाचलेले खूण करा', 'ml': 'എല്ലാം വായിച്ചതായി അടയാളപ്പെടുത്തുക',
'or': 'ସବୁ ପଢ଼ା ହୋଇଥିବା ଭଳି ଚିହ୍ନଟ କରନ୍ତୁ',
'ca': 'Marca-ho tot com a llegit', 'id': 'Tandai semua sudah dibaca', 'ms': 'Tandakan semua sebagai dibaca',
'vi': 'Đánh dấu tất cả đã đọc', 'ur': 'سب کو پڑھا ہوا نشان زد کریں',
'th': 'ทำเครื่องหมายว่าอ่านทั้งหมดแล้ว',
'hr': 'Označi sve kao pročitano', 'sl': 'Označi vse kot prebrano',
'ta': 'அனைத்தையும் படித்ததாகக் குறி', 'te': 'అన్నింటినీ చదివినట్లు గుర్తించు', 'kn': 'ಎಲ್ಲವನ್ನೂ ಓದಿದಂತೆ ಗುರ್ತಿಸಿ',
}

def main():
    resources = ROOT / 'jifen/Resources'
    locales = sorted(p.stem for p in resources.glob('*.lproj'))
    assert set(locales) == set(T), (set(locales) - set(T), set(T) - set(locales))
    for locale in locales:
        path = resources / f'{locale}.lproj/Localizable.strings'
        original = path.read_text()
        line = f'"{KEY_ADD}" = {json.dumps(T[locale], ensure_ascii=False)};'
        pattern = r'^"' + re.escape(KEY_ADD) + r'"\s*=.*;\n?'
        if re.search(pattern, original, re.M):
            original = re.sub(pattern, lambda _: line + '\n', original, flags=re.M)
        else:
            block_marker = '\n/* Group notice plan-B 2026-10-15 */\n'
            if block_marker in original:
                original = original.replace(block_marker, block_marker + line + '\n')
            else:
                original = original.rstrip('\n') + '\n' + block_marker.lstrip('\n') + line + '\n'
        # retire the removed per-row "Open group" copy
        original, n = re.subn(r'^"' + re.escape(KEY_DEL) + r'"\s*=.*;\n?', '', original, flags=re.M)
        path.write_text(original)
        print(f'{locale}: add={"ok" if KEY_ADD in original else "FAIL"} del_open={n}')
        if locale in {'en', 'zh-Hans', 'zh-Hant'}:
            continue
        catalog = ROOT / f'scripts/localization/catalogs/{locale}.jsonl'
        rows = [json.loads(line) for line in catalog.read_text().splitlines() if line.strip()]
        rows = [r for r in rows if not (r.get('key') == KEY_DEL and r.get('table') == 'Localizable')]
        rows = [r for r in rows if r.get('key') != KEY_ADD]
        source_hash = hashlib.sha256(('Localizable\0' + KEY_ADD + '\0' + T['en']).encode()).hexdigest()[:16]
        rows.append(dict(table='Localizable', key=KEY_ADD, source_hash=source_hash, azure=None, google_web=None,
                         google=None, final=T[locale], status='reviewed', flags=[], note=NOTE,
                         machine_provider=None, issues=[]))
        catalog.write_text('\n'.join(json.dumps(r, ensure_ascii=False, separators=(',', ':')) for r in rows) + '\n')
    print('done')

if __name__ == '__main__':
    main()
