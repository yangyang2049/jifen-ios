# coding: utf-8
import json, copy
from pathlib import Path
ROOT = Path(__file__).resolve().parent
def load(f): return json.loads((ROOT/f).read_text())
def save(f,d): (ROOT/f).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
d=load('copy.json')
sc=copy.deepcopy(next(e for e in d['localizations'] if e['locale']=='zh-TW'))
sc.update(locale='zh-CN',sourceLocale='zh-Hans',fontFamily='Noto Sans SC',playerNames={'score':'陈冠廷','catalog':'林雅婷'},basketballTeamNames=['主队','客队'])
texts=['每一分\n都值得\n每一场\n都精彩','比赛计分\n一眼看清','26+ 运动项目\n打开就能计分','赛后回顾\n看见每次进步','规则由你决定\n怎么打都能计分','多人游戏\n桌游都支持','投放到电视\n全场都看得清']
for c,t in zip(sc['cards'],texts): c['text']=t
if not any(e['locale']=='zh-CN' for e in d['localizations']): d['localizations'].append(sc)
save('copy.json',d)
d=load('metadata.json')
e=copy.deepcopy(next(e for e in d['localizations'] if e['language']=='zh-TW'))
e.update(sourceLocale='zh-Hans',language='zh-CN',languageName='Chinese (Simplified)',title='全能计分器',shortDescription='运动计分、比赛计时与赛后回顾',screenshotFolder='exports/zh-CN',fullDescription='每一分都值得认真记录。把 Android 手机或平板变成清晰、顺手的计分板，轻松记录比赛、训练和朋友间的对局。\n\n支持 26+ 种运动与游戏计分，包括网球、匹克球、羽毛球、乒乓球、篮球、足球、排球和台球。根据项目调整计分规则、比赛局数与双打发球顺序，让计分方式适合你的比赛。\n\n保存比赛记录，通过比分走势、时间线和语音笔记回顾精彩时刻。内置国际象棋与围棋计时、魔方计时和秒表，球类之外也能用。将计分板显示在大屏上。\n\n抛硬币、随机分队、红黄牌和费用平摊等实用工具集中在一处。少一点记分的忙乱，多一点比赛的乐趣。\n\n使用条款:\nhttps://jifenqi.com/terms\n\n隐私政策:\nhttps://jifenqi.com/privacy')
if not any(x.get('language')=='zh-CN' for x in d['localizations']): d['localizations'].append(e)
d['preparedLocaleCount'] = len(d['localizations'])
d['uploadEligibleLocaleCount'] = sum(bool(x.get('uploadEligible')) for x in d['localizations'])
save('metadata.json',d); save('locales/zh-CN.json',e)
d=load('locale-map.json')
if not any(x.get('googlePlayLocale')=='zh-CN' for x in d['locales']): d['locales'].append({'appStoreLocale':'zh-Hans','googlePlayLocale':'zh-CN','uploadEligible':True})
save('locale-map.json',d)
d=load('capture-labels.json'); d['zh-CN']={'tab_score':'计分','tab_records':'记录','tab_badminton':'羽毛球','cancel':'取消','record_detail_score_trend':'比分走势'}; save('capture-labels.json',d)
print('Added Simplified Chinese copy, listing and capture labels')
