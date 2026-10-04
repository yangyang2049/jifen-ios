# coding: utf-8
"""Publish local evidence and delivery archives after confirmed Play commit."""
import json, zipfile
from pathlib import Path
import play_api as api
ROOT=api.ROOT
def main():
    report=api.read(ROOT/'zh-cn-and-localized-ui-upload-verification.json')
    assert report['committed'] and report['postCommitReadbackVerified']
    package,plan=api.local_plan(None)
    assert all([im['sha256'] for im in e['images']]==report['expected'][e['language']]['hashes'] for e in plan)
    assert len(plan)==49 and sum(len(e['images']) for e in plan)==343
    for f in ('api-verification.json','verification.json','auth-status.json'):
        old=ROOT/'source'/(f.replace('.json','-before-ui-upload.json'))
        if not old.exists():old.write_bytes((ROOT/f).read_bytes())
    online={'packageName':package,'verifiedAt':report['verifiedAt'],'editId':report['editId'],'temporaryEdit':False,'validatedByGooglePlay':True,'committed':True,'publicStoreVisibilityChecked':False,'listingFieldReadbackMatches':True,'phoneScreenshotCountsOrderAndSHA256Match':True,'postCommitReadbackVerified':True,'localeCount':49,'phoneScreenshotCount':343,'languages':[e['language'] for e in plan],'currentAssetsMatchCommittedImages':True,'credentialsIncluded':False,'scope':'Store metadata and phone screenshots only; no binary or track changes.','report':'zh-cn-and-localized-ui-upload-verification.json'}
    api.dump(ROOT/'api-verification.json',online)
    api.dump(ROOT/'committed-listings.json',{'packageName':package,'verifiedAt':report['verifiedAt'],'listings':[report['expected'][e['language']]['listing'] for e in plan]})
    verification=api.read(ROOT/'verification.json');verification.update(frameCount=350,imageCount=350,uploadEligibleLanguages=49,uploadEligibleImageCount=343,onlineApiReport='api-verification.json',currentAssetsMatchCommittedImages=True,metadataCommitted=True,published=None,publicStoreVisibilityChecked=False,simplifiedChineseReport='zh-cn-verification.json',localizedNativeUIReport='localized-ui-verification.json');api.dump(ROOT/'verification.json',verification)
    auth=api.read(ROOT/'auth-status.json');auth.update(verifiedAt=report['verifiedAt'],status='49 listing locales / 343 phone screenshots committed; all listing fields, image order and SHA-256 verified in a fresh post-commit edit.');api.dump(ROOT/'auth-status.json',auth)
    text='''
## 简体中文及全部截图正式上传（2026-10-03）

新增本地 zh-CN：全能计分器／运动计分、比赛计时与赛后回顾，以及适配 Android 的完整描述；不包含 Apple 许可协议或未开放的远程分享承诺。7 张 RGB 1080×1920 图片使用 Noto Sans SC，第四／第五张来自真实简体 Android 界面；陈冠廷、林雅婷与曲线图例保持一致。第六张补齐四位玩家、主客队及第 4 节标签；第七张手机队名保持 15.8 度旋转。简体中文排在 East Asia 分区内，画布现为 50 个语言行、350 张（含不可上传的奥里亚语草稿 7 张）。可上传素材为 49 个语言、343 张。

上传前 Google Play 实际只有 11 个语言页面，zh-CN 页面尚无独立截图；此前其他语言的临时编辑没有永久保存。本次补齐缺少的 38 个语言页面，更新 zh-CN 文案和全套 7 张图，英语同步全套本地定稿；另外 9 个已有语言只替换第 4／5 张并保持第 1／2／3／6／7 张及原有商店文案。其他已有文案保持原样。

`upload_localized_ui.py` 在修改前备份全部文字和截图元数据，按 ID 删除旧图片并顺序追加；失败重试在未提交 edit 中进行。全部语言的文字、7 张图数量／顺序／SHA-256 校验通过后 validate，再显式 commit；另建只读 edit 回读全部 49 个页面和 343 张图，与本地定稿逐一匹配后删除该检查 edit。已提交商店资料更新；没有上传应用二进制、变更测试／正式轨道或发布新客户端。商店公开展示与审核状态未通过 Console 单独检查。

当前正式记录：`api-verification.json` 与 `zh-cn-and-localized-ui-upload-verification.json`；简体图检查见 `zh-cn-verification.json`，预览为 `preview-zh-CN.png`。历史 API 报告保存在 `source/*-before-ui-upload.json`，本节替代前文仍为临时编辑／未 commit 的状态。完整素材 ZIP 为 `package/google-play-49-locales-2026-10-03.zip`，不包含私钥、APK 或在线备份。

验证：48 个旧语言的 96 张更新图通过原生 UI 标签、姓名、尺寸、Pen 路径及像素区域检查，247 张其他本地导出文件 SHA-256 保持一致；简体 7 张通过文案长度、原生 UI、字形外观、文字框边界及截图规格检查。辅助 Python 脚本语法检查通过。未运行 Gradle：本次只更新营销素材、商店文案和辅助工具，无应用代码改动。模拟器已恢复原 APK、演示数据库与原应用语言，输入 helper 已卸载。
'''
    readme=ROOT/'README.md'
    if '## 简体中文及全部截图正式上传' not in readme.read_text():readme.write_text(readme.read_text()+text)
    with zipfile.ZipFile(ROOT/'package/google-play-49-locales-2026-10-03.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for e in plan:
            for im in e['images']:archive.write(im['file'],e['language']+'/'+Path(im['file']).name)
            metadata=next(x for x in api.read(ROOT/'metadata.json')['localizations'] if x['language']==e['language'])
            metadata.update(report['expected'][e['language']]['listing'])
            archive.writestr(e['language']+'/listing.json',json.dumps(metadata,ensure_ascii=False,indent=2))
        for f in ('metadata.json','committed-listings.json','copy.json','api-verification.json','localized-ui-verification.json','zh-cn-verification.json','README.md'):archive.write(ROOT/f,f)
    note=Path('/Users/yangyang/Library/Mobile Documents/iCloud~md~obsidian/Documents/yangayng/全能计分器.md')
    heading='## 2026-10-03 Google Play 49 语言商店资料与截图更新'
    if heading not in note.read_text():
        entry='\n\n'+heading+'\n\n'
        entry+=f'- Google Play 商店资料 edit 已于 {report["committedAt"]} commit；另建检查 edit 回读全部 49 个语言页面、343 张手机截图，数量／顺序／SHA-256 与本地定稿全部一致。检查 edit 已删除。原先仅保存 11 个页面，本轮补齐缺少的 38 个页面。\n'
        entry+='- 第四／第五张：48 个旧语言共 96 张应用内 UI 完成本地化，原生曲线图例、比赛详情、设置选项及示例姓名一致。简体中文新增本地页面文案和 7 张截图，采用 Noto Sans SC；第六张补齐玩家、队名及节次标签。英语同步整套本地定稿，另外 9 个已有页面保留原文案及第 1／2／3／6／7 张。\n'
        entry+='- 仅更新商店文案与截图；未上传二进制、修改发行轨道或发布新客户端。商店公开展示／审核状态未单独核查。截图资源样包仅用于模拟器，补充的 UI 译文没有移植到正式应用。未运行 Gradle；原生截图、素材规格／字形外观／文字边界、批准像素范围和辅助脚本语法检查通过。\n'
        entry+=f'- 证据：`{ROOT}/zh-cn-and-localized-ui-upload-verification.json`；本地素材与预览：`{ROOT}/exports/`、`{ROOT}/preview-zh-CN.png`；完整素材 ZIP：`{ROOT}/package/google-play-49-locales-2026-10-03.zip`。\n'
        with note.open('a') as stream:stream.write(entry)
    print('PASS: all 49 committed sets match local SHA-256; current reports, README and full delivery ZIP saved.')
if __name__=='__main__':main()
