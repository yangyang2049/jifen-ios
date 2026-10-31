#!/usr/bin/env python3
"""Create external test runs and expire old runs (dry-run unless --apply)."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time

ROOT = Path.home() / 'Library/Developer/jifen-ios-test-artifacts'
MARKER = '.jifen-ios-test-artifacts.json'
IDENTITY = {'project': 'jifen-ios', 'schema': 1}
RUN_NAME = re.compile(r'\d{8}T\d{12}Z-[a-z0-9][a-z0-9-]{0,63}')


def validate_root(root):
    if root.is_symlink() or (root / 'runs').is_symlink() or (root / MARKER).is_symlink():
        raise ValueError('Artifact root and runs directory must not be symlinks')
    if json.loads((root / MARKER).read_text()) != IDENTITY:
        raise ValueError('Unrecognized artifact root marker')


def initialize(root=ROOT):
    if root.is_symlink() or (root / 'runs').is_symlink():
        raise ValueError('Artifact root and runs directory must not be symlinks')
    root.mkdir(parents=True, exist_ok=True)
    marker = root / MARKER
    if not marker.exists():
        # Never adopt a populated directory as a disposable artifact root.
        if any(root.iterdir()):
            raise ValueError('Refusing to initialize a nonempty artifact root')
        marker.write_text(json.dumps(IDENTITY) + '\n')
    validate_root(root)
    (root / 'runs').mkdir(exist_ok=True)


def new_run(label, root=ROOT, active=False):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}', label):
        raise ValueError('Run label must contain only lowercase letters, digits and hyphens')
    initialize(root)
    name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + label
    run = root / 'runs' / name
    run.mkdir()
    (run / '.run.json').write_text(json.dumps({'createdAt': time.time(), 'label': label}) + '\n')
    if active:
        (run / '.active').touch()
    return run


def finish_run(run, failed=False, root=ROOT):
    """Only finish a recognized direct child of this project's managed root."""
    validate_root(root)
    run = Path(run)
    if (run.is_symlink() or run.parent != root / 'runs' or not RUN_NAME.fullmatch(run.name)
            or not (run / '.run.json').is_file() or (run / '.run.json').is_symlink()):
        raise ValueError('Not a managed test run: ' + str(run))
    if failed:
        if (run / '.keep').is_symlink():
            raise ValueError('Keep marker must not be a symlink')
        (run / '.keep').touch()
    (run / '.active').unlink(missing_ok=True)
    return cleanup(root, apply=True)


def finish_automatically(run, failed=False):
    try:
        finish_run(run, failed=failed)
    except Exception as error:
        print('Test-artifact cleanup failed: ' + str(error), file=sys.stderr)


def last_activity(run):
    latest = run.stat().st_mtime
    created = json.loads((run / '.run.json').read_text())['createdAt']
    if not isinstance(created, (int, float)) or created <= 0:
        raise ValueError('Invalid run creation time: ' + str(run))
    latest = max(latest, created)
    for parent, dirs, files in os.walk(run, followlinks=False):
        dirs[:] = [name for name in dirs if not (Path(parent) / name).is_symlink()]
        for name in dirs + files:
            child = Path(parent) / name
            if not child.is_symlink():
                latest = max(latest, child.stat().st_mtime)
    return latest


def cleanup(root=ROOT, days=14, keep=2, apply=False, now=None):
    if days < 1 or keep < 2:
        raise ValueError('Keep at least 1 day and the latest 2 runs')
    validate_root(root)
    now = time.time() if now is None else now
    runs = root / 'runs'
    candidates = []
    skipped = []
    for run in runs.iterdir():
        if (run.is_symlink() or not run.is_dir() or not RUN_NAME.fullmatch(run.name)
                or not (run / '.run.json').is_file() or (run / '.run.json').is_symlink()):
            skipped.append(str(run))
            continue
        candidates.append((last_activity(run), run))
    candidates.sort(key=lambda item: (item[0], item[1].name), reverse=True)
    expired = []
    for activity, run in candidates[keep:]:
        if activity >= now - days * 86400 or (run / '.keep').exists() or (run / '.active').exists():
            continue
        expired.append(str(run))
        if apply:
            # Recheck activity/markers before deleting; rmtree does not follow nested symlinks.
            validate_root(root)
            if run.is_symlink() or (run / '.keep').exists() or (run / '.active').exists():
                raise ValueError('Run changed during cleanup: ' + str(run))
            if last_activity(run) != activity:
                raise ValueError('Run is being updated: ' + str(run))
            shutil.rmtree(run)
    return {'apply': apply, 'retentionDays': days, 'keepLatest': keep,
            'expiredRuns': expired, 'skippedUnknownPaths': skipped}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('new-run')
    create.add_argument('label')
    create.add_argument('--active', action='store_true')
    finish = commands.add_parser('finish')
    finish.add_argument('run', type=Path)
    finish.add_argument('--failed', action='store_true')
    commands.add_parser('init')
    expire = commands.add_parser('cleanup')
    expire.add_argument('--days', type=int, default=14)
    expire.add_argument('--keep', type=int, default=2)
    expire.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.command == 'new-run':
        print(new_run(args.label, active=args.active))
    elif args.command == 'finish':
        print(json.dumps(finish_run(args.run, failed=args.failed), indent=2))
    elif args.command == 'init':
        initialize()
        print(ROOT)
    else:
        print(json.dumps(cleanup(days=args.days, keep=args.keep, apply=args.apply), indent=2))


if __name__ == '__main__':
    main()
