#!/usr/bin/env python3
"""Record independent, resumable chapters on one host-selected Duo display."""
import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path
import subprocess
import sys

from test_artifacts import new_run, finish_automatically


CATALOG = ['pingpong', 'badminton', 'tennis', 'pickleball', 'football',
           'basketball', 'three_basketball', 'volleyball', 'beach_volleyball',
           'air_volleyball', 'archery', 'boxing', 'billiards', 'eight_ball',
           'nine_ball', 'snooker', 'doudizhu', 'guandan', 'shengji', 'uno',
           'foosball', 'simpleScore', 'multiScoreboard', 'shuttlecock', 'squash',
           'soft_tennis', 'padel', 'football_5v5', 'basketball_training']
CATALOG_LABELS = dict(zip(CATALOG, [
    '乒乓球', '羽毛球', '网球', '匹克球', '足球', '篮球', '三人篮球', '排球',
    '沙滩排球', '气排球', '射箭', '拳击', '台球', '黑八追局', '追分', '斯诺克',
    '斗地主', '掼蛋', '升级', 'UNO', '桌上足球', '简单计分', '多人计分', '毽球',
    '壁球', '软式网球', '板式网球', '五人制足球', '投篮训练']))


EXPECTED_CHAPTER_LABELS = (
    ['home', 'connection', 'me', 'account', 'me-forms', 'schedules', 'timers', 'tools']
    + [f'tools-{i:02d}' for i in range(1, 4)]
    + [f'timers-{i:02d}' for i in range(1, 4)]
    + [f'scoreboards-{i // 4 + 1:02d}' for i in range(0, len(CATALOG), 4)]
    + ['variants']
    + [f'records-{i // 8 + 1:02d}' for i in range(0, len(CATALOG), 8)]
    + ['record-actions', 'record-tail'] + [f'groups-{i:02d}' for i in range(1, 4)]
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('pose', choices=['folded', 'unfolded'])
    parser.add_argument('--root', type=Path, help='Existing batch to resume, or an explicit output override')
    parser.add_argument('--only', help='Comma-separated output chapter labels')
    parser.add_argument('--retry', action='store_true', help='Rerun failed chapters; passed ones stay intact')
    parser.add_argument('--video-only', action='store_true', help='Record videos and checkpoint times without screenshots')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    chapters = [('home', ['--chapter', 'home']), ('connection', ['--chapter', 'connection']), ('me', ['--chapter', 'me']),
                ('account', ['--chapter', 'account']), ('me-forms', ['--chapter', 'me-forms']), ('schedules', ['--chapter', 'schedules']),
                ('timers', ['--chapter', 'timers']), ('tools', ['--chapter', 'tools'])]
    for number, suffix in [('01', 'RandomTeamsStandingsAndAA'), ('02', 'BarrageDiceAndChallenge'),
                           ('03', 'CoinWhistleCardsAndClock')]:
        chapters.append(('tools-' + number, ['--test-id', 'DuoToolsWalkthroughUITests/testWalkDuoTools' + number + suffix]))
    for number, suffix in [('01', 'GoAndXiangqi'), ('02', 'ChessAndCheckers'),
                           ('03', 'StopwatchCountdownAndCubePreparation')]:
        chapters.append(('timers-' + number, ['--test-id', 'DuoTimerWalkthroughUITests/testWalkDuoTimers' + number + suffix]))
    for index in range(0, len(CATALOG), 4):
        label = f'scoreboards-{index // 4 + 1:02d}'
        chapters.append((label, ['--chapter', 'scoreboards', '--items', ','.join(CATALOG[index:index + 4])]))
    chapters.append(('variants', ['--chapter', 'variants']))
    for index in range(0, len(CATALOG), 8):
        label = f'records-{index // 8 + 1:02d}'
        chapters.append((label, ['--chapter', 'records', '--items', ','.join(CATALOG[index:index + 8])]))
    chapters.append(('record-actions', ['--chapter', 'record-actions']))
    chapters.append(('record-tail', ['--chapter', 'record-tail']))
    for number, suffix in [('01', 'ListManagementAndMembers'), ('02', 'MatchAndActivities'),
                           ('03', 'RecordsRankingsShareAndNotices')]:
        chapters.append(('groups-' + number, ['--test-id', 'DuoGroupWalkthroughUITests/testWalkDuoGroup' + number + suffix]))
    assert {label for label, _ in chapters} == set(EXPECTED_CHAPTER_LABELS)
    if args.only:
        requested = args.only.split(',')
        unknown = set(requested) - {label for label, _ in chapters}
        if unknown:
            parser.error('Unknown chapters: ' + ','.join(sorted(unknown)))
        chapters = [(label, options) for label, options in chapters if label in requested]
    managed_run = new_run('duo-walkthrough', active=True) if args.root is None else None
    root = (repo / args.root).resolve() if args.root is not None else managed_run
    root.mkdir(parents=True, exist_ok=True)
    print(f'Walkthrough batch: {root}', flush=True)
    failed = True
    try:
        statuses = []
        for label, options in chapters:
            manifest = root / args.pose / label / 'session.json'
            if manifest.exists():
                previous = json.loads(manifest.read_text())
                if previous.get('status') == 'passed' or not args.retry:
                    print(f'Skip existing {args.pose}/{label}: {previous.get("status")}', flush=True)
                    continue
                attempts = root / 'attempts'
                attempts.mkdir(exist_ok=True)
                archived = attempts / (args.pose + '-' + label + '-' + datetime.now().strftime('%H%M%S'))
                shutil.move(str(manifest.parent), archived)
                print(f'Archived previous attempt: {archived}', flush=True)
            command = [sys.executable, str(repo / 'scripts/capture_duo_layout.py'), args.device,
                       args.pose, '--label', label, '--record', '--output-root', str(root)] + options
            if args.video_only:
                command.append('--video-only')
            print(f'BEGIN {args.pose}/{label}', flush=True)
            result = subprocess.run(command, cwd=repo)
            statuses.append(dict(chapter=label, exit_code=result.returncode))
            print(f'END {args.pose}/{label}: {result.returncode}', flush=True)
            if not args.video_only:
                subprocess.run([sys.executable, str(repo / 'scripts/build_duo_review.py'), str(root)], cwd=repo)
        (root / f'{args.pose}-run.json').write_text(json.dumps(statuses, indent=2) + '\n')
        failed = any(status['exit_code'] for status in statuses)
        return 1 if failed else 0
    finally:
        if managed_run is not None:
            finish_automatically(managed_run, failed=failed)


if __name__ == '__main__':
    raise SystemExit(main())
