#!/usr/bin/env python3
"""Capture full-window Duo UI tests through the explicit active simulator display.

Build for testing into build/duo/DerivedData first. Select the intended pose in
Device Hub, then run: python3 scripts/capture_duo_layout.py DEVICE_ID POSE
Use --live for the four host-controlled fold/unfold checkpoints.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import time


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def write_manifest(path, manifest):
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('pose')
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--chapter', choices=['home', 'scoreboards', 'timers', 'tools', 'me', 'account', 'connection', 'records', 'record-actions', 'variants', 'styles', 'schedules', 'me-forms', 'record-tail', 'chrome-safety', 'content-width'])
    parser.add_argument('--items', help='Comma-separated catalog IDs for a chapter batch')
    parser.add_argument('--test-id', help='Explicit Suite/testMethod for an additional walkthrough')
    parser.add_argument('--label', help='Output chapter name, e.g. scoreboards-01')
    parser.add_argument('--record', action='store_true', help='Record actual simulator navigation to H.264 video')
    parser.add_argument('--output-root', type=Path, default=Path('artifacts/iphone-duo-layout-20261020'))
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.pose):
        parser.error('Pose must contain lowercase letters, numbers or hyphens')
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    displays = []
    for block in re.split(r'\nPort:\n', output('xcrun', 'simctl', 'io', args.device, 'enumerate')):
        if not re.search(r'^    Display class: 0$', block, re.M):
            continue
        uuid = re.search(r'UUID: ([A-F0-9-]+)', block).group(1)
        width = int(re.search(r'Default width: (\d+)', block).group(1))
        height = int(re.search(r'Default height: (\d+)', block).group(1))
        displays.append((uuid, max(width, height) / min(width, height), width * height))
    if len(displays) != 2:
        raise RuntimeError(f'Expected two native Duo displays, got {displays}')
    container = Path(output('xcrun', 'simctl', 'get_app_container', args.device,
                            'com.douhua.jifenUITests.xctrunner', 'data'))
    marker = container / 'tmp' / 'duo-capture.json'
    for stale in container.parent.glob('*/tmp/duo-capture.json'):
        stale.unlink()
    label = args.label or args.chapter or ('live' if args.live else None)
    if label and not re.fullmatch(r'[a-z0-9-]+', label):
        parser.error('Chapter label must contain lowercase letters, numbers or hyphens')
    run_id = f'host-{args.pose}-{label + "-" if label else ""}{int(time.time())}'
    result = root / 'build' / 'duo' / f'{run_id}.xcresult'
    log = result.with_suffix('.log')
    destination = args.output_root / args.pose
    if label and (args.chapter or args.test_id):
        destination /= label
    destination.mkdir(parents=True, exist_ok=True)
    test = 'testFoldableDraftAndScoreSurviveLiveResize' if args.live else 'testCaptureFoldableWindowLayouts'
    test_id = args.test_id or f'FullAppScreenshotUITests/{"testWalkDuoReviewChapter" if args.chapter else test}'
    env = os.environ.copy()
    env.update(TEST_RUNNER_DUO_POSE=args.pose, TEST_RUNNER_DUO_HOST_CAPTURE='1')
    if args.live:
        env['TEST_RUNNER_DUO_LIVE_RESIZE'] = '1'
    if args.chapter:
        env['TEST_RUNNER_DUO_CHAPTER'] = args.chapter
    if args.items:
        env.update(TEST_RUNNER_DUO_ITEMS=args.items, TEST_RUNNER_AUDIT_GAME=args.items)
    command = ['xcodebuild', 'test-without-building', '-xctestrun',
               str(root / 'build/duo/DerivedData/Build/Products/jifen_iphonesimulator27.1-arm64.xctestrun'),
               '-destination', f'platform=iOS Simulator,id={args.device}',
               f'-only-testing:jifenUITests/{test_id}',
               '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
               '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '900',
               '-resultBundlePath', str(result)]
    print(f'Log: {log}', flush=True)
    started = time.monotonic()
    manifest = dict(pose=args.pose, chapter=label, test_id=test_id, items=args.items,
                    result=str(result), log=str(log), captures=[], status='running',
                    started_at=datetime.now(timezone.utc).isoformat())
    products = root / 'build/duo/DerivedData/Build/Products/Debug-iphonesimulator'
    manifest['binary_sha256'] = {}
    for binary in [products / 'jifen.app/jifen',
                   products / 'jifenUITests-Runner.app/PlugIns/jifenUITests.xctest/jifenUITests']:
        if binary.is_file():
            manifest['binary_sha256'][str(binary.relative_to(products))] = hashlib.sha256(binary.read_bytes()).hexdigest()
    manifest_path = destination / 'session.json'
    video = None
    video_stream = None
    try:
        if args.record:
            if args.pose not in ['folded', 'unfolded']:
                parser.error('Recording requires an explicit folded or unfolded pose')
            chosen = sorted(displays, key=lambda row: row[2])[0 if args.pose == 'folded' else -1]
            video_path = destination / 'walkthrough.mp4'
            video_stream = (destination / 'recording.log').open('w')
            video = subprocess.Popen(['xcrun', 'simctl', 'io', args.device, 'recordVideo',
                                      f'--display={chosen[0]}', '--codec=h264', '--force', str(video_path)],
                                     stdout=video_stream, stderr=subprocess.STDOUT)
            manifest.update(video='walkthrough.mp4', video_display=chosen[0])
            time.sleep(0.5)
            if video.poll() is not None:
                raise RuntimeError('Simulator recorder exited before the walkthrough')
        write_manifest(manifest_path, manifest)
        with log.open('w') as stream:
            process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
            count = 0
            while process.poll() is None:
                candidates = list(container.parent.glob('*/tmp/duo-capture.json'))
                if len(candidates) > 1:
                    raise RuntimeError('Multiple screenshot requests in this test device')
                if candidates:
                    marker = candidates[0]
                    metadata = json.loads(marker.read_text())
                    width, height = metadata['width'], metadata['height']
                    aspect = max(width, height) / min(width, height)
                    display, display_aspect, _ = min(displays, key=lambda row: abs(row[1] - aspect))
                    if abs(display_aspect - aspect) > 0.01:
                        raise RuntimeError(f'Window does not match a full display: {metadata}')
                    name = metadata['name']
                    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
                        raise RuntimeError(f'Invalid capture name: {name}')
                    target = destination / f'{name}.png'
                    subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot',
                                    f'--display={display}', str(target)], check=True, capture_output=True)
                    metadata.update(display=display, pixels=struct.unpack('>II', target.read_bytes()[16:24]))
                    metadata.update(video_seconds=round(time.monotonic() - started, 3),
                                    captured_at=datetime.now(timezone.utc).isoformat())
                    if args.record and display != manifest['video_display']:
                        raise RuntimeError('Active display changed during a fixed-surface recording')
                    target.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
                    manifest['captures'].append({key: value for key, value in metadata.items() if key != 'hierarchy'})
                    write_manifest(manifest_path, manifest)
                    print(f'Captured {name}: {width} x {height}', flush=True)
                    count += 1
                    # Keep the checkpoint visible through the recorder's next
                    # frame before allowing a navigation or app restart.
                    if video is not None:
                        time.sleep(0.8)
                    marker.unlink()
                time.sleep(0.15)
            code = process.wait()
        if code == 0 and count == 0:
            code = 3
            manifest['failure_reason'] = 'No capture checkpoints were reached; an empty test run is not coverage.'
        print(f'Captured {count}; xcodebuild exit {code}; result {result}', flush=True)
        manifest.update(status='passed' if code == 0 else 'failed', exit_code=code)
        return code
    finally:
        if 'process' in locals() and process.poll() is None:
            process.terminate()
            process.wait(timeout=15)
        marker.unlink(missing_ok=True)
        if video is not None and video.poll() is None:
            video.send_signal(signal.SIGINT)
            video.wait(timeout=30)
        if video_stream is not None:
            video_stream.close()
        manifest.update(elapsed_seconds=round(time.monotonic() - started, 3),
                        finished_at=datetime.now(timezone.utc).isoformat())
        if manifest['status'] == 'running':
            manifest['status'] = 'interrupted'
        write_manifest(manifest_path, manifest)


if __name__ == '__main__':
    raise SystemExit(main())
