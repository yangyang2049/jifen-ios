"""Rename the "Common names/places" feature copy to "Saved names/places".

⚠️ 历史一次性脚本（勿再执行）：2026-10-17 起 zh-Hans / zh-Hant 的
common_names_* 与 common_places_* 文案已回退为「常用名称 / 常用地点」
（与安卓、鸿蒙对齐），英文及其它语言仍为 Saved Names / Saved Places。
重跑本脚本会把中文文案再改回「已保存名称 / 已保存地点」。

Applies only inside the common_names_* / common_places_* key families plus the
two clear-records/account-deletion strings that reference the feature. Languages
with a leftover old-term fragment after replacement are reverted to the original
file (reported as kept).
"""
import plistlib, re
from pathlib import Path

RES = Path('/Users/yangyang/Desktop/jifenqi/jifen-ios/jifen/Resources')

AFFECTED_KEY = re.compile(r'^(common_names_|common_places_|home_common_names|home_common_places|schedule_pick_common_place)')
EXTRA_KEYS = {'clear_records_tab_message', 'account_deletion_impact_local_data'}

PAIRS = {
    'en': [('Common Names', 'Saved Names'), ('Common names', 'Saved names'), ('common names', 'saved names'),
           ('Common Places', 'Saved Places'), ('Common places', 'Saved places'), ('common places', 'saved places'),
           ('Common Place', 'Saved Place'), ('common place', 'saved place')],
    'zh-Hans': [('常用名称', '已保存名称'), ('常用地点', '已保存地点'), ('常用名', '已保存名')],
    'zh-Hant': [('常用名稱', '已儲存名稱'), ('常用地點', '已儲存地點'), ('常用名', '已儲存名')],
    'ja': [('よく使う名前', '保存した名前'), ('よく使う場所', '保存した場所'), ('よく使う名', '保存した名')],
    'ko': [('자주 쓰는 이름', '저장한 이름'), ('자주 쓰는 장소', '저장한 장소'), ('자주 쓰는', '저장한')],
    'fr': [('Noms fréquents', 'Noms enregistrés'), ('noms fréquents', 'noms enregistrés'),
           ('Lieux fréquents', 'Lieux enregistrés'), ('lieux fréquents', 'lieux enregistrés'),
           ('fréquents', 'enregistrés'), ('fréquentes', 'enregistrées'), ('fréquent', 'enregistré'), ('fréquente', 'enregistrée')],
    'fr-CA': None,  # filled below
    'pt-BR': [('Nomes frequentes', 'Nomes salvos'), ('nomes frequentes', 'nomes salvos'),
              ('Locais frequentes', 'Locais salvos'), ('locais frequentes', 'locais salvos'),
              ('Local frequente', 'Local salvo'), ('local frequente', 'local salvo'),
              ('frequentes', 'salvos'), ('frequente', 'salvo')],
    'pt-PT': [('Nomes frequentes', 'Nomes guardados'), ('nomes frequentes', 'nomes guardados'),
              ('Locais frequentes', 'Locais guardados'), ('locais frequentes', 'locais guardados'),
              ('frequentes', 'guardados'), ('frequente', 'guardado')],
    'it': [('Nomi comuni', 'Nomi salvati'), ('nomi comuni', 'nomi salvati'),
           ('Luoghi comuni', 'Luoghi salvati'), ('luoghi comuni', 'luoghi salvati'),
           ('Nome comune', 'Nome salvato'), ('nome comune', 'nome salvato'),
           ('Luogo comune', 'Luogo salvato'), ('luogo comune', 'luogo salvato'),
           ('comuni', 'salvati'), ('comune', 'salvato')],
    'ca': [('Noms habituals', 'Noms desats'), ('noms habituals', 'noms desats'),
           ('Llocs habituals', 'Llocs desats'), ('llocs habituals', 'llocs desats'),
           ('habituals', 'desats'), ('habitual', 'desat')],
    'cs': [('Běžné názvy', 'Uložené názvy'), ('běžné názvy', 'uložené názvy'),
           ('Běžná místa', 'Uložená místa'), ('běžná místa', 'uložená místa'),
           ('Běžné', 'Uložené'), ('Běžná', 'Uložená'), ('Běžných', 'Uložených'),
           ('běžné', 'uložené'), ('běžná', 'uložená'), ('běžných', 'uložených'), ('běžným', 'uloženým'), ('běžného', 'uloženého')],
    'sk': [('Bežné názvy', 'Uložené názvy'), ('bežné názvy', 'uložené názvy'),
           ('Bežné miesta', 'Uložené miesta'), ('bežné miesta', 'uložené miesta'),
           ('Bežné', 'Uložené'), ('Bežná', 'Uložená'), ('bežné', 'uložené'), ('bežná', 'uložená'),
           ('bežných', 'uložených'), ('bežným', 'uloženým'), ('bežnej', 'uloženej'), ('bežného', 'uloženého')],
    'sl': [('Pogosta imena', 'Shranjena imena'), ('pogosta imena', 'shranjena imena'),
           ('Pogosti kraji', 'Shranjeni kraji'), ('pogosti kraji', 'shranjeni kraji'),
           ('pogosta', 'shranjena'), ('pogosti', 'shranjeni'), ('pogost', 'shranjen'), ('pogosto', 'shranjeno'),
           ('Splošnih', 'Shranjenih'), ('splošnih', 'shranjenih'), ('Splošne', 'Shranjene'),
           ('splošne', 'shranjene'), ('Splošni', 'Shranjeni'), ('splošni', 'shranjeni'),
           ('Splošno', 'Shranjeno'), ('splošno', 'shranjeno')],
    'hr': [('Uobičajen', 'Spremljen'), ('uobičajen', 'spremljen')],
    'tr': [('Yaygın Adlar', 'Kaydedilen Adlar'), ('yaygın adlar', 'kaydedilen adlar'),
           ('Yaygın Yerler', 'Kaydedilen Yerler'), ('yaygın yerler', 'kaydedilen yerler'),
           ('Yaygın', 'Kaydedilen'), ('yaygın', 'kaydedilen')],
    'id': [('Nama Umum', 'Nama Tersimpan'), ('nama umum', 'nama tersimpan'),
           ('Tempat Umum', 'Tempat Tersimpan'), ('tempat umum', 'tempat tersimpan'),
           ('Umum', 'Tersimpan'), ('umum', 'tersimpan')],
    'ms': [('Nama Biasa', 'Nama Tersimpan'), ('nama biasa', 'nama tersimpan'),
           ('Tempat Biasa', 'Tempat Tersimpan'), ('tempat biasa', 'tempat tersimpan'),
           ('Biasa', 'Tersimpan'), ('biasa', 'tersimpan')],
    'th': [('ชื่อสามัญ', 'ชื่อที่บันทึกไว้'), ('สถานที่ทั่วไป', 'สถานที่ที่บันทึกไว้'),
           ('ชื่อทั่วไป', 'ชื่อที่บันทึกไว้'), ('สามัญ', 'ที่บันทึกไว้'), ('ทั่วไป', 'ที่บันทึกไว้')],
    'vi': [('Tên thông dụng', 'Tên đã lưu'), ('tên thông dụng', 'tên đã lưu'),
           ('Địa điểm thông dụng', 'Địa điểm đã lưu'), ('địa điểm thông dụng', 'địa điểm đã lưu'),
           ('tên chung', 'tên đã lưu'), ('Tên chung', 'Tên đã lưu'),
           ('địa điểm chung', 'địa điểm đã lưu'), ('Địa điểm chung', 'Địa điểm đã lưu'),
           ('Thông dụng', 'Đã lưu'), ('thông dụng', 'đã lưu'), ('chung', 'đã lưu')],
    'ru': [('Часто используемые имена', 'Сохранённые имена'), ('часто используемые имена', 'сохранённые имена'),
           ('Часто используемые места', 'Сохранённые места'), ('часто используемые места', 'сохранённые места'),
           ('Часто используемых имён', 'Сохранённых имён'), ('часто используемых имён', 'сохранённых имён'),
           ('Часто используемых мест', 'Сохранённых мест'), ('часто используемых мест', 'сохранённых мест'),
           ('Часто используемое', 'Сохранённое'), ('часто используемое', 'сохранённое'),
           ('Часто используемые', 'Сохранённые'), ('часто используемые', 'сохранённые'),
           ('Часто используемых', 'Сохранённых'), ('часто используемых', 'сохранённых'),
           ('часто используемым', 'сохранённым'), ('часто используемыми', 'сохранёнными')],
    'ar': [('الأسماء الشائعة', 'الأسماء المحفوظة'), ('أسماء شائعة', 'أسماء محفوظة'),
           ('الأماكن المعتادة', 'الأماكن المحفوظة'), ('أماكن معتادة', 'أماكن محفوظة'),
           ('المكان المعتاد', 'المكان المحفوظ'), ('مكان معتاد', 'مكان محفوظ'),
           ('الشائعة', 'المحفوظة'), ('شائعة', 'محفوظة'), ('المعتادة', 'المحفوظة'), ('معتادة', 'محفوظة'),
           ('المعتاد', 'المحفوظ'), ('معتاد', 'محفوظ')],
    'he': [('שמות נפוצים', 'שמות שמורים'), ('מקומות קבועים', 'מקומות שמורים'),
           ('נפוצים', 'שמורים'), ('קבועים', 'שמורים'), ('נפוצות', 'שמורות'), ('קבועות', 'שמורות'),
           ('נפוץ', 'שמור'), ('קבוע', 'שמור')],
    'ur': [('عام ناموں', 'محفوظ شدہ ناموں'), ('عام نام', 'محفوظ شدہ نام'),
           ('عام مقامات', 'محفوظ شدہ مقامات'), ('عام مقام', 'محفوظ شدہ مقام'), ('عام', 'محفوظ شدہ')],
    'ta': [('பொதுவான', 'சேமித்த')],
    'te': [('సాధారణ', 'సేవ్ చేసిన')],
    'kn': [('ಸಾಮಾನ್ಯ', 'ಉಳಿಸಿದ')],
    'ml': [('പൊതുവായ', 'സംരക്ഷിച്ച'), ('സാധാരണ', 'സംരക്ഷിച്ച')],
    'or': [('ସାଧାରଣ', 'ସଂରକ୍ଷିତ')],
}
PAIRS['fr-CA'] = PAIRS['fr']

# fragments that must be gone after replacement (old-term markers per language)
LEFTOVER = {
    'en': ['ommon'], 'zh-Hans': ['常用'], 'zh-Hant': ['常用'], 'ja': ['よく使う'], 'ko': ['자주 쓰는'],
    'fr': ['fréquent'], 'fr-CA': ['fréquent'], 'pt-BR': ['frequente'], 'pt-PT': ['frequente'],
    'it': ['omun'], 'ca': ['habitual'], 'cs': ['ěžn'], 'sk': ['ežn'], 'sl': ['ogost', 'plošn'], 'hr': ['bičajen'],
    'tr': ['aygın'], 'id': ['umum', 'Umum'], 'ms': ['biasa', 'Biasa'], 'th': ['สามัญ', 'ทั่วไป'],
    'vi': ['hông dụng', 'ung'], 'ru': ['спользуем'], 'ar': ['شائع', 'عتاد'], 'he': ['נפוצ', 'קבוע'],
    'ur': [' عام'], 'ta': ['பொதுவான'], 'te': ['సాధారణ'], 'kn': ['ಸಾಮಾನ್ಯ'],
    'ml': ['പൊതുവായ', 'സാധാരണ'], 'or': ['ସାଧାରଣ'],
}
SKIP = {'bn', 'da', 'de', 'el', 'es-ES', 'es-MX', 'fi', 'gu', 'hi', 'hu', 'mr', 'nb', 'pa', 'pl', 'ro', 'sv', 'uk'}

LINE = re.compile(r'^("([a-z0-9_]+)"\s*=\s*")(.*)(";\s*)$')


def apply_pairs(text, pairs):
    for old, new in pairs:
        text = text.replace(old, new)
    return text


def patch_strings_file(path, pairs, leftover_markers):
    original = path.read_text(encoding='utf-8')
    out, changed, touched = [], 0, []
    for line in original.splitlines():
        m = LINE.match(line)
        if m and (AFFECTED_KEY.match(m.group(2)) or m.group(2) in EXTRA_KEYS):
            value = m.group(3)
            new_value = apply_pairs(value, pairs)
            if new_value != value:
                changed += 1
            touched.append(new_value)  # scan every affected value, changed or not
            out.append(m.group(1) + new_value + m.group(4))
        else:
            out.append(line)
    new_text = '\n'.join(out) + ('\n' if original.endswith('\n') else '')
    leftover = sum(v.count(frag) for frag in leftover_markers for v in touched)
    return new_text, changed, leftover, original


def patch_stringsdict_file(path, pairs, leftover_markers):
    original_bytes = path.read_bytes()
    d = plistlib.loads(original_bytes)
    changed, touched = 0, []

    def walk(node):
        nonlocal changed
        if isinstance(node, dict):
            return {k: walk(v) for k, v in node.items()}
        if isinstance(node, list):
            return [walk(v) for v in node]
        if isinstance(node, str):
            new = apply_pairs(node, pairs)
            if new != node:
                changed += 1
            touched.append(new)
            return new
        return node

    for key in list(d.keys()):
        if key.startswith('common_names') or key.startswith('common_places'):
            d[key] = walk(d[key])
    new_text = plistlib.dumps(d, fmt=plistlib.FMT_XML, sort_keys=False).decode('utf-8')
    leftover = sum(v.count(frag) for frag in leftover_markers for v in touched)
    return new_text, changed, leftover, original_bytes


def main():
    changed_langs, kept_langs = [], []
    for lang in sorted(PAIRS):
        if lang in SKIP:
            continue
        pairs, markers = PAIRS[lang], LEFTOVER[lang]
        total = 0
        results = []
        ok = True
        for path in sorted(RES.glob(f'{lang}.lproj/Localizable.strings')) + sorted(RES.glob(f'{lang}.lproj/Localizable.stringsdict')):
            is_dict = path.suffix == '.stringsdict'
            new, n, leftover, original = (patch_stringsdict_file if is_dict else patch_strings_file)(path, pairs, markers)
            if leftover:
                bad = [v for v in re.findall(r'" = "(.*)";', new) if any(frag in v for frag in markers)]
                print(f'{lang}: LEFTOVER {leftover} in {path.name}:')
                for v in bad[:4]:
                    print('   ', v[:110])
                ok = False
            results.append((path, new, original))
            total += n
        if ok:
            for path, new, original in results:
                if isinstance(original, bytes):
                    path.write_bytes(new.encode('utf-8'))
                else:
                    path.write_text(new, encoding='utf-8')
            changed_langs.append((lang, total))
        else:
            kept_langs.append(lang)
    print('changed:', ', '.join(f'{l}({n})' for l, n in changed_langs))
    print('kept:', ', '.join(kept_langs) or '(none)')

if __name__ == '__main__':
    main()
