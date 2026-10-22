#!/usr/bin/env python3
"""Validate captured files; this does not replace visual or functional review."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageStat
from run_duo_walkthrough import CATALOG, EXPECTED_CHAPTER_LABELS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    plan_path = root / 'review-plan.json'
    plan = json.loads(plan_path.read_text()) if plan_path.is_file() else {}
    expected_chapters = plan.get('chapters', EXPECTED_CHAPTER_LABELS)
    catalog = CATALOG if plan.get('check_catalog', True) else []
    sessions = []
    issues = []
    seen = {pose: set() for pose in ['unfolded', 'folded']}
    total_duration = 0
    for pose in seen:
        for path in sorted((root / pose).glob('*/session.json')):
            session = json.loads(path.read_text())
            captures = session.get('captures', [])
            folder = path.parent
            identifier = f'{pose}/{folder.name}'
            if session.get('status') != 'passed':
                issues.append(f'{identifier}: status={session.get("status")}')
            video = folder / session.get('video', 'walkthrough.mp4')
            probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                                    'format=duration,size:stream=codec_name,width,height',
                                    '-of', 'json', str(video)], capture_output=True, text=True)
            if probe.returncode:
                issues.append(f'{identifier}: invalid video')
                continue
            data = json.loads(probe.stdout)
            duration = float(data['format']['duration'])
            total_duration += duration
            if not captures:
                issues.append(f'{identifier}: no screenshots')
            previous = -1
            for capture in captures:
                name = capture['name']
                image_path = folder / (name + '.png')
                metadata_path = folder / (name + '.json')
                if not image_path.exists() or not metadata_path.exists():
                    issues.append(f'{identifier}/{name}: missing PNG or JSON')
                    continue
                metadata = json.loads(metadata_path.read_text())
                with Image.open(image_path) as image:
                    pixels = list(image.size)
                    image = image.convert('RGB')
                    if any(key in name for key in ['yellow_card', 'red_card']):
                        width, height = image.size
                        center = image.getpixel((width // 2, height // 2))
                        for point in [(width - 12, height // 2), (width // 2, height - 12)]:
                            edge = image.getpixel(point)
                            if max(abs(a - b) for a, b in zip(center, edge)) > 8:
                                issues.append(f'{identifier}/{name}: card background leaves an edge band at {point}')
                    image.thumbnail((180, 180))
                    if max(high for low, high in image.getextrema()) < 12:
                        issues.append(f'{identifier}/{name}: black screenshot')
                    if max(ImageStat.Stat(image).stddev) < 1:
                        issues.append(f'{identifier}/{name}: flat screenshot; review required')
                if pixels != metadata.get('pixels'):
                    issues.append(f'{identifier}/{name}: pixel metadata mismatch')
                seconds = capture.get('video_seconds', -1)
                if seconds < previous or seconds > duration + 2:
                    issues.append(f'{identifier}/{name}: invalid video timestamp')
                previous = seconds
                if metadata.get('display') != session.get('video_display'):
                    issues.append(f'{identifier}/{name}: screenshot and video displays differ')
                if session.get('status') == 'passed':
                    seen[pose].add(name)
            sessions.append(dict(chapter=identifier, status=session.get('status'),
                                 screenshots=len(captures), video_seconds=duration,
                                 bytes=int(data['format']['size'])))
    for pose, names in seen.items():
        present = {path.parent.name for path in (root / pose).glob('*/session.json')}
        for chapter in sorted(set(expected_chapters) - present):
            issues.append(f'{pose}/{chapter}: missing planned chapter')
        for game in catalog:
            required = [f'walk_{game}_01_setup', f'walk_{game}_02_board',
                        f'walk_{game}_03_menu', f'record_{game}_01_detail']
            if game != 'basketball_training':
                required.append(f'walk_{game}_04_style')
            for checkpoint in required:
                if checkpoint not in names:
                    issues.append(f'{pose}/{checkpoint}: missing passed catalog checkpoint')
    with (root / 'catalog-coverage.csv').open('w') as stream:
        writer = csv.writer(stream)
        writer.writerow(['game', 'pose', 'setup', 'scoreboard', 'menu', 'style', 'record_detail'])
        for game in catalog:
            for pose, names in seen.items():
                checkpoints = [f'walk_{game}_01_setup', f'walk_{game}_02_board',
                               f'walk_{game}_03_menu', f'walk_{game}_04_style', f'record_{game}_01_detail']
                writer.writerow([game, pose] + [int(name in names) for name in checkpoints])
    report = dict(sessions=sessions, screenshot_count=sum(s['screenshots'] for s in sessions),
                  video_minutes=round(total_duration / 60, 2), issues=issues,
                  note='File validation only; page identity and layout require screenshot review.')
    (root / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'sessions'}, ensure_ascii=False, indent=2))
    return 1 if issues else 0


if __name__ == '__main__':
    raise SystemExit(main())
