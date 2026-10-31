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
import plistlib
import re
import signal
import struct
import subprocess
import time

from test_artifacts import new_run, finish_automatically


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def write_manifest(path, manifest):
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(path)


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def binary_provenance(xctestrun):
    """Resolve UI products from the selected v1/v2 XCTest configuration."""
    xctestrun = xctestrun.resolve(strict=True)
    configuration_bytes = xctestrun.read_bytes()
    configuration = plistlib.loads(configuration_bytes)
    if 'TestConfigurations' in configuration:
        targets = [target for item in configuration['TestConfigurations']
                   if item.get('IsEnabled', True) for target in item.get('TestTargets', [])
                   if target.get('BlueprintName') == 'jifenUITests']
    else:
        targets = [target for name, target in configuration.items()
                   if isinstance(target, dict)
                   and target.get('BlueprintName', name) == 'jifenUITests']
    if not targets:
        raise ValueError(f'No enabled jifenUITests target in {xctestrun}')

    def product_path(raw, host=None):
        expanded = raw.replace('__TESTROOT__', str(xctestrun.parent))
        if host is not None:
            expanded = expanded.replace('__TESTHOST__', str(host))
        if re.search(r'__[A-Z_]+__', expanded):
            raise ValueError(f'Unresolved XCTest product path: {raw}')
        path = Path(expanded)
        return (path if path.is_absolute() else xctestrun.parent / path).resolve(strict=True)

    def executable(bundle):
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        name = info.get('CFBundleExecutable')
        if not isinstance(name, str) or not name or Path(name).name != name:
            raise ValueError(f'Missing or invalid CFBundleExecutable in {bundle}')
        binary = (bundle / name).resolve(strict=True)
        if not binary.is_file():
            raise FileNotFoundError(f'Missing XCTest product executable: {binary}')
        return binary

    binaries = {}
    products = []
    for target in targets:
        host = product_path(target['TestHostPath'])
        app = product_path(target['UITargetAppPath'])
        bundle = product_path(target['TestBundlePath'], host=host)
        products.append(dict(app=str(app), host=str(host), test_bundle=str(bundle)))
        for product in [app, host, bundle]:
            binary = executable(product)
            binaries[str(binary)] = file_sha256(binary)
            debug_library = product / (binary.name + '.debug.dylib')
            if debug_library.is_file():
                binaries[str(debug_library.resolve())] = file_sha256(debug_library)
    return dict(xctestrun=str(xctestrun),
                xctestrun_sha256=hashlib.sha256(configuration_bytes).hexdigest(),
                test_products=products, binary_sha256=binaries)


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
    parser.add_argument('--video-only', action='store_true', help='Keep video and checkpoint times without PNG screenshots')
    parser.add_argument('--xctestrun', type=Path, help='Use an explicitly built XCTest configuration')
    parser.add_argument('--output-root', type=Path, help='Override the managed external test batch')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.pose):
        parser.error('Pose must contain lowercase letters, numbers or hyphens')
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    xctestrun = args.xctestrun or root / 'build/duo/DerivedData/Build/Products/jifen_iphonesimulator27.1-arm64.xctestrun'
    provenance = binary_provenance(xctestrun)
    displays = []
    for block in re.split(r'\nPort:\n', output('xcrun', 'simctl', 'io', args.device, 'enumerate')):
        if not re.search(r'^    Display class: 0$', block, re.M):
            continue
        uuid = re.search(r'UUID: ([A-F0-9-]+)', block).group(1)
        width = int(re.search(r'Default width: (\d+)', block).group(1))
        height = int(re.search(r'Default height: (\d+)', block).group(1))
        displays.append((uuid, max(width, height) / min(width, height), width * height))
    if not displays:
        raise RuntimeError('No simulator display is available')
    if args.video_only and not args.record:
        parser.error('--video-only requires --record')
    container = Path(output('xcrun', 'simctl', 'get_app_container', args.device,
                            'com.douhua.jifenUITests.xctrunner', 'data'))
    marker = container / 'tmp' / 'duo-capture.json'
    for stale in container.parent.glob('*/tmp/duo-capture.json'):
        stale.unlink()
    label = args.label or args.chapter or ('live' if args.live else None)
    if label and not re.fullmatch(r'[a-z0-9-]+', label):
        parser.error('Chapter label must contain lowercase letters, numbers or hyphens')
    run_id = f'host-{args.pose}-{label + "-" if label else ""}{int(time.time())}'
    managed_run = new_run('duo-capture', active=True) if args.output_root is None else None
    args.output_root = args.output_root or managed_run
    results = args.output_root / 'results'
    results.mkdir(parents=True, exist_ok=True)
    result = results / f'{run_id}.xcresult'
    log = result.with_suffix('.log')
    destination = args.output_root / args.pose
    if label and (args.chapter or args.test_id):
        destination /= label
    destination.mkdir(parents=True, exist_ok=True)
    test = 'testFoldableDraftAndScoreSurviveLiveResize' if args.live else 'testCaptureFoldableWindowLayouts'
    test_id = args.test_id or f'FullAppScreenshotUITests/{"testWalkDuoReviewChapter" if args.chapter else test}'
    env = os.environ.copy()
    layout_expectation = args.pose if len(displays) == 2 else 'ordinary'
    env.update(TEST_RUNNER_DUO_POSE=layout_expectation, TEST_RUNNER_DUO_HOST_CAPTURE='1')
    if args.live:
        env['TEST_RUNNER_DUO_LIVE_RESIZE'] = '1'
    if args.chapter:
        env['TEST_RUNNER_DUO_CHAPTER'] = args.chapter
    if args.items:
        env.update(TEST_RUNNER_DUO_ITEMS=args.items, TEST_RUNNER_AUDIT_GAME=args.items)
    command = ['xcodebuild', 'test-without-building', '-xctestrun',
               provenance['xctestrun'],
               '-destination', f'platform=iOS Simulator,id={args.device}',
               f'-only-testing:jifenUITests/{test_id}',
               '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
               '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '900',
               '-resultBundlePath', str(result)]
    print(f'Log: {log}', flush=True)
    started = time.monotonic()
    manifest = dict(pose=args.pose, chapter=label, test_id=test_id, items=args.items,
                    result=str(result), log=str(log), captures=[], status='running',
                    device=args.device, layout_expectation=layout_expectation,
                    started_at=datetime.now(timezone.utc).isoformat())
    manifest.update(provenance)
    manifest_path = destination / 'session.json'
    video = None
    video_stream = None
    video_started = None
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
            ready_deadline = time.monotonic() + 20
            while True:
                if video.poll() is not None:
                    raise RuntimeError('Simulator recorder exited before the walkthrough')
                if 'Recording started' in (destination / 'recording.log').read_text():
                    video_started = time.monotonic()
                    manifest['video_time_basis'] = 'recordVideo-ready'
                    break
                if time.monotonic() >= ready_deadline:
                    raise RuntimeError('Simulator recorder did not become ready')
                time.sleep(0.05)
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
                    name = metadata['name']
                    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
                        raise RuntimeError(f'Invalid capture name: {name}')
                    pose_match = re.search(r'(?:^|_)(open|closed)(?:_|$)', name) if args.live else None
                    explicit_pose = pose_match.group(1) if pose_match else None
                    if explicit_pose:
                        if len(displays) != 2:
                            raise RuntimeError('Explicit live pose capture requires two built-in displays')
                        # Duo AX can retain the old app.frame after a live resize.
                        # The host-controlled checkpoint names the intended surface.
                        chooser = max if explicit_pose == 'open' else min
                        display, display_aspect, _ = chooser(displays, key=lambda row: row[2])
                    else:
                        display, display_aspect, _ = min(displays, key=lambda row: abs(row[1] - aspect))
                    aspect_mismatch = abs(display_aspect - aspect) > 0.01
                    if not explicit_pose and aspect_mismatch:
                        raise RuntimeError(f'Window does not match a full display: {metadata}')
                    metadata.update(explicit_pose=explicit_pose,
                                    display_selection='explicit-live-pose' if explicit_pose else 'window-aspect',
                                    ax_window_aspect=aspect, display_aspect=display_aspect,
                                    ax_display_aspect_mismatch=aspect_mismatch)
                    target = destination / f'{name}.png'
                    if not args.video_only:
                        subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot',
                                        f'--display={display}', str(target)], check=True, capture_output=True)
                        metadata['pixels'] = struct.unpack('>II', target.read_bytes()[16:24])
                    metadata['display'] = display
                    metadata.update(video_seconds=round(time.monotonic() - (video_started or started), 3),
                                    captured_at=datetime.now(timezone.utc).isoformat())
                    if args.record and display != manifest['video_display']:
                        raise RuntimeError('Active display changed during a fixed-surface recording')
                    if not args.video_only:
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
        if managed_run is not None:
            finish_automatically(managed_run, failed=manifest['status'] != 'passed')


if __name__ == '__main__':
    raise SystemExit(main())
