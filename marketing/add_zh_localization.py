"""Add zh-Hant (ASC) / zh-TW (Google Play) entries to every copy table.

The ASC metadata.json already contains a prepared zh-Hant listing (name/subtitle/
description/screenshotTitles) that was excluded from earlier uploads; that copy is
adopted verbatim. Only the card-6 "multiplayer" headline is new, written in the
same voice. The Google Play zh-TW listing adapts the prepared ASC text to Android
wording (no share-code promise, no Apple EULA).
"""
import json
from pathlib import Path

ROOT = Path('/Users/yangyang/Desktop/jifenqi/jifen-ios')
IOS = ROOT / 'marketing/app-store/ios-screenshots-pen-2026-10-02'
GP = ROOT / 'marketing/google-play/localization-2026-10-02'
ASC = ROOT / 'marketing/app-store/localization-2026-10-02'

def read(p): return json.loads(Path(p).read_text())
def write(p, v): Path(p).write_text(json.dumps(v, ensure_ascii=False, indent=2) + '\n')

FONT = 'Noto Sans TC'
TEAMS = ['主隊', '客隊']
NAMES4 = ['陳冠廷', '林雅婷', '王宗翰', '黃淑芬']
TITLE = 'iScoreboard: 全能計分器'
SHORT = '運動計分、比賽計時與賽後回顧'

def prepared_titles():
    m = read(ASC / 'metadata.json')
    zh = next(x for x in m['localizations'] if x['locale'] == 'zh-Hant')
    return {t['id']: t['title'] for t in zh['screenshotTitles'] if t.get('enabled', True)}

ZH = prepared_titles()
MULTIPLAYER = '多人遊戲\n桌遊都支援'

def cards(platform):
    order = ['slogan', 'score', 'catalog', 'recap', 'setup', 'multiplayer', 'cast']
    out = []
    for cid in order:
        text = MULTIPLAYER if cid == 'multiplayer' else ZH[cid]
        if platform == 'ios' and cid == 'slogan':
            text = ZH[cid]  # keep prepared break
        out.append({'id': cid, 'text': text})
    return out

GP_FULL = (
    '每一分都值得認真記錄。把 Android 手機或平板變成清楚、好用的計分板，輕鬆記錄比賽、訓練和朋友間的對局。\n\n'
    '支援 26+ 種運動與遊戲計分，包括網球、匹克球、羽毛球、桌球、籃球、足球、排球和撞球。'
    '依照項目調整計分規則、比賽局數與雙打發球順序，讓計分方式符合你的比賽。\n\n'
    '儲存比賽紀錄，透過比分趨勢、時間軸和語音筆記回顧精彩時刻。內建西洋棋與圍棋計時、魔術方塊計時和碼錶，'
    '球類之外也能用。將計分板顯示在大螢幕上。\n\n'
    '擲硬幣、隨機分隊、紅黃牌和費用分攤等實用工具集中在一處。少一點記分的忙亂，多一點比賽的樂趣。\n\n'
    '使用條款:\nhttps://jifenqi.com/terms\n\n隱私權政策:\nhttps://jifenqi.com/privacy'
)

def main():
    # 1. GP copy.json
    p = GP / 'copy.json'; c = read(p)
    c['localizations'] = [x for x in c['localizations'] if x['locale'] != 'zh-TW']
    c['localizations'].append({'locale': 'zh-TW', 'fontFamily': FONT, 'cards': cards('gp'),
                               'playerNames': {'score': NAMES4[0], 'catalog': NAMES4[1]},
                               'sourceLocale': 'zh-Hant', 'basketballTeamNames': TEAMS})
    write(p, c)

    # 2. GP metadata.json
    p = GP / 'metadata.json'; m = read(p)
    m['localizations'] = [x for x in m['localizations'] if x['language'] != 'zh-TW']
    m['localizations'].append({'sourceLocale': 'zh-Hant', 'language': 'zh-TW',
                               'languageName': 'Chinese (Traditional)', 'direction': 'ltr',
                               'reviewStatus': 'adapted-draft', 'title': TITLE,
                               'shortDescription': SHORT, 'fullDescription': GP_FULL,
                               'screenshotFolder': 'exports/zh-TW', 'uploadEligible': True})
    m['excludedAppStoreLocales'] = ['zh-Hans']
    m['preparedLocaleCount'] = len(m['localizations'])
    m['uploadEligibleLocaleCount'] = sum(1 for x in m['localizations'] if x['uploadEligible'])
    write(p, m)

    # 3. GP locale-map.json
    p = GP / 'locale-map.json'; lm = read(p)
    lm['locales'] = [x for x in lm['locales'] if x['appStoreLocale'] != 'zh-Hant']
    lm['locales'].append({'appStoreLocale': 'zh-Hant', 'googlePlayLocale': 'zh-TW', 'uploadEligible': True})
    write(p, lm)

    # 4. iOS copy.json
    p = IOS / 'copy.json'; c = read(p)
    c['localizations'] = [x for x in c['localizations'] if x['locale'] != 'zh-Hant']
    c['localizations'].append({'locale': 'zh-Hant', 'fontFamily': FONT, 'cards': cards('ios'),
                               'playerNames': {'score': NAMES4[0], 'catalog': NAMES4[1]},
                               'sourceLocale': 'zh-Hant'})
    write(p, c)

    # 5. iOS player-names.json + basketball-teams.json
    p = IOS / 'player-names.json'; pn = read(p)
    pn['localizations'] = [x for x in pn['localizations'] if x['locale'] != 'zh-Hant']
    pn['localizations'].append({'locale': 'zh-Hant', 'names': NAMES4[:2], 'fontFamily': FONT})
    write(p, pn)
    p = IOS / 'basketball-teams.json'; bt = read(p)
    bt['localizations'] = [x for x in bt['localizations'] if x['locale'] != 'zh-Hant']
    bt['localizations'].append({'locale': 'zh-Hant', 'names': TEAMS, 'fontFamily': FONT})
    write(p, bt)

    # 6. ASC metadata.json already has the prepared zh-Hant entry — verify and leave it.
    m = read(ASC / 'metadata.json')
    zh = next(x for x in m['localizations'] if x['locale'] == 'zh-Hant')
    assert zh['name'] == TITLE and zh['screenshotTitles'], 'prepared zh-Hant entry unexpected'

    # 7. ASC-side locale-map.json (prepared with zh entries all along — ensure ours)
    p = ASC / 'locale-map.json'; lm = read(p)
    if not any(x['locale'] == 'zh-Hant' for x in lm['locales']):
        lm['locales'].append({'locale': 'zh-Hant', 'iosLocale': 'zh-Hant'})
        write(p, lm)

    # 8. iPad capture-config.json (iPhone capture-config.json is regenerated by the driver)
    p = ROOT / 'marketing/app-store/ipad-screenshots-2026-10-03/capture-config.json'; c = read(p)
    if not any(x['locale'] == 'zh-Hant' for x in c['localizations']):
        c['localizations'].append({'locale': 'zh-Hant', 'appleLanguage': 'zh-Hant', 'appleLocale': 'zh_TW',
                                   'names': NAMES4, 'fontFamily': FONT, 'basketballTeams': TEAMS})
        write(p, c)
    print('Copy tables updated. GP cards:', [x['text'].replace(chr(10), '/') for x in cards('gp')])

if __name__ == '__main__':
    main()
