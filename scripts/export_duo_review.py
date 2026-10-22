#!/usr/bin/env python3
"""Copy the current review outside the build/worktree, retaining evidence logs."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    source, destination = args.source.resolve(), args.destination.resolve()
    if source == destination or source in destination.parents:
        parser.error('Destination must be outside the source tree')
    destination.mkdir(parents=True, exist_ok=True)
    for pose in ['folded', 'unfolded']:
        for manifest in (source / pose).glob('*/session.json'):
            target = destination / pose / manifest.parent.name
            shutil.copytree(manifest.parent, target, dirs_exist_ok=True)
            session = json.loads(manifest.read_text())
            log = Path(session.get('log', ''))
            if log.is_file():
                shutil.copy2(log, target / 'test.log')
                session['source_log'] = str(log)
                session['log'] = str(target / 'test.log')
            session['source_evidence_directory'] = str(manifest.parent)
            (target / 'session.json').write_text(json.dumps(session, ensure_ascii=False, indent=2) + '\n')
    for name in ['devices.json', 'folded-run.json', 'unfolded-run.json', 'review-plan.json']:
        if (source / name).is_file():
            shutil.copy2(source / name, destination / name)
    for folder in source.glob('ordinary-*'):
        if folder.is_dir():
            shutil.copytree(folder, destination / folder.name, dirs_exist_ok=True)
    scripts = Path(__file__).resolve().parent
    shutil.copy2(scripts / 'serve_duo_review.py', destination / 'serve_review.py')
    verification = destination / 'verification'
    verification.mkdir(exist_ok=True)
    verification_logs = list(source.parent.glob('*build.log'))
    verification_logs += [source.parent / 'walkthrough-final-unit.log']
    verification_logs += list(source.parent.glob('controls-ordinary-*.log'))
    for log in verification_logs:
        if log.is_file():
            shutil.copy2(log, verification / log.name)
    report = source / 'review-notes.md'
    if not report.is_file():
        report = scripts.parent / 'docs/qa/iphone-duo-walkthrough-2026-10-20.md'
    if report.is_file():
        shutil.copy2(report, destination / 'review-notes.md')
    (destination / 'README.txt').write_text(
        'iPhone Duo 页面巡检录像\n'
        '打开 index.html；如浏览器限制本地视频，可在本目录运行：\n'
        'python3 serve_review.py . --port 8765\n'
        '再打开 http://127.0.0.1:8765/ 。服务器仅绑定本机回环地址。\n'
        '点击截图跳转实际视频时间；可筛选内外屏、连续播放与倍速。\n'
        'PNG 为完整像素，同名 JSON 为原始界面层级；session.json 保存流程结果。\n'
        '测试数据包括模拟器本地记录及离线小组样例，不代表真实登录、支付或服务器操作。\n'
        '截图数量包含弹窗和滚动状态，不等于独立页面数量。\n', encoding='utf-8')
    subprocess.run([sys.executable, str(scripts / 'build_duo_review.py'), str(destination)], check=True)
    return subprocess.run([sys.executable, str(scripts / 'validate_duo_capture.py'), str(destination)]).returncode


if __name__ == '__main__':
    raise SystemExit(main())
