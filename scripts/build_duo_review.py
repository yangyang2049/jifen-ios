#!/usr/bin/env python3
"""Build a local video-and-screenshot index from actual Duo capture sessions."""
import argparse
import fcntl
import html
import io
import json
from pathlib import Path
import subprocess
import tempfile

from run_duo_walkthrough import CATALOG, CATALOG_LABELS, EXPECTED_CHAPTER_LABELS

from PIL import Image, ImageChops, ImageStat


VIDEO_DISPLAY_VERSION = 2


def atomic_write(path, content):
    """Readers and concurrent index processes only see complete files."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.' + path.name + '.', suffix='.tmp',
                                         delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def video_display_source(video_path, captures):
    stat = video_path.stat()
    checkpoints = []
    for capture in captures:
        image_path = video_path.parent / (capture['name'] + '.png')
        image_stat = image_path.stat()
        with Image.open(image_path) as image:
            pixels = list(image.size)
        checkpoints.append(dict(name=capture['name'], seconds=float(capture.get('video_seconds', 0)),
                                pixels=pixels, mtime_ns=image_stat.st_mtime_ns,
                                size=image_stat.st_size))
    checkpoints.sort(key=lambda item: item['seconds'])
    return dict(version=VIDEO_DISPLAY_VERSION, video=video_path.name,
                mtime_ns=stat.st_mtime_ns, size=stat.st_size, checkpoints=checkpoints)


def compare_video_rotation(video_path, checkpoint):
    """CSS angles are clockwise; Pillow's rotate() uses the opposite sign."""
    frame = subprocess.run(
        ['ffmpeg', '-v', 'error', '-ss', str(checkpoint['seconds']), '-i', str(video_path),
         '-frames:v', '1', '-vf', 'scale=240:240:force_original_aspect_ratio=decrease',
         '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True, timeout=30, check=True
    )
    with Image.open(io.BytesIO(frame.stdout)) as image:
        raw = image.convert('RGB')
    with Image.open(video_path.parent / (checkpoint['name'] + '.png')) as image:
        reference = image.convert('RGB')
        reference.thumbnail((240, 240), Image.Resampling.LANCZOS)
    errors = {}
    for angle in [-90, 90]:
        candidate = raw.rotate(-angle, expand=True).resize(reference.size, Image.Resampling.LANCZOS)
        difference = ImageChops.difference(reference, candidate)
        errors[str(angle)] = round(sum(ImageStat.Stat(difference).mean) / (3 * 255), 6)
    angle = min([-90, 90], key=lambda value: errors[str(value)])
    gap = round(abs(errors['-90'] - errors['90']), 6)
    return dict(checkpoint=checkpoint['name'], seconds=checkpoint['seconds'], pixels=checkpoint['pixels'],
                angle=angle, matched_angle=angle, mean_absolute_error=errors, confidence_gap=gap,
                reliable=gap >= 0.005 and errors[str(angle)] <= 0.12)


def video_display(video_path, captures, probe):
    """Cache display transforms, never modify or re-encode the original video."""
    streams = [stream for stream in probe.get('streams', []) if stream.get('width') and stream.get('height')]
    if not streams:
        return dict(segments=[dict(start=0, angle=0)], warnings=['无法读取录像尺寸，请使用手动旋转。'])
    stream = streams[0]
    width, height = stream['width'], stream['height']
    # ffmpeg and browsers both apply the track display matrix before rendering.
    rotation = next((item.get('rotation', 0) for item in stream.get('side_data_list', [])
                     if 'rotation' in item), float(stream.get('tags', {}).get('rotate', 0)))
    if round(rotation) % 180:
        width, height = height, width
    cache_path = video_path.parent / 'video-display.json'
    # A chapter lock avoids extracting the same frames in the two indexers.
    # Atomic replacement also protects readers that do not acquire this lock.
    with (video_path.parent / 'video-display.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        source = video_display_source(video_path, captures)
        try:
            cached = json.loads(cache_path.read_text())
            if cached.get('source') == source:
                return cached
        except (OSError, ValueError):
            pass
        segments, samples, warnings = [], [], []
        previous_orientation = None
        previous_checkpoint = None
        angle = 0
        complete = True
        for checkpoint in source['checkpoints']:
            image_width, image_height = checkpoint['pixels']
            landscape = image_width > image_height
            if landscape != previous_orientation:
                if landscape != (width > height):
                    try:
                        sample = compare_video_rotation(video_path, checkpoint)
                        samples.append(sample)
                        angle = sample['angle']
                    except (OSError, ValueError, subprocess.SubprocessError) as error:
                        complete = False
                        angle = 0
                        warnings.append(checkpoint['name'] + '：提帧失败，请手动旋转（' + type(error).__name__ + '）。')
                else:
                    angle = 0
                boundary = (previous_checkpoint['seconds'] + checkpoint['seconds']) / 2 if previous_checkpoint else 0
                segments.append(dict(start=round(boundary, 3), angle=angle,
                                     checkpoint=checkpoint['name'], pixels=checkpoint['pixels']))
                previous_orientation = landscape
            previous_checkpoint = checkpoint
        # A black transition or an application restart cannot identify a turn.
        # Reuse the nearest reliable run with the same PNG orientation instead
        # of presenting an arbitrary +/-90 tie as a successful image match.
        for sample in samples:
            if sample['reliable']:
                continue
            landscape = sample['pixels'][0] > sample['pixels'][1]
            neighbors = [other for other in samples if other['reliable']
                         and (other['pixels'][0] > other['pixels'][1]) == landscape]
            if neighbors:
                neighbor = min(neighbors, key=lambda other: abs(other['seconds'] - sample['seconds']))
                sample['angle'] = neighbor['angle']
                sample['fallback_checkpoint'] = neighbor['checkpoint']
                reason = '沿用邻近可识别片段的方向'
            else:
                sample['angle'] = 0
                reason = '保持原片方向'
            warnings.append(sample['checkpoint'] + '：对应视频帧与 PNG 无法可靠匹配，' + reason + '，请人工核对或手动旋转。')
            for segment in segments:
                if segment['checkpoint'] == sample['checkpoint']:
                    segment['angle'] = sample['angle']
        result = dict(source=source, video_pixels=[width, height], samples=samples,
                      segments=segments or [dict(start=0, angle=0)], warnings=warnings)
        # An active recorder or recapture may have replaced an input while the
        # index was running. Do not publish a stale or failed cache as complete.
        if complete and source == video_display_source(video_path, captures):
            atomic_write(cache_path, json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        return result


def video_player(identifier, relative, poster, title, session, display):
    config = dict(segments=display['segments'], pixels=display.get('video_pixels', [16, 9]),
                  duration=float(session.get('video_probe', {}).get('format', {}).get('duration', 0)))
    encoded = html.escape(json.dumps(config, separators=(',', ':')), quote=True)
    label = html.escape(title, quote=True)
    warning = ' '.join(display.get('warnings', []))
    return f'''<div class="video-player" data-display="{encoded}">
    <div class="video-viewport" role="group" aria-label="{label}录像画面">
    <video data-status="{session.get('status')}" id="{identifier}" playsinline preload="none" aria-label="{label}录像" src="{relative}"></video>
    <img class="video-poster" loading="lazy" src="{poster}" alt="{label}首张检查点预览">
    </div><div class="video-controls">
    <button data-action="toggle" aria-label="播放或暂停{label}录像">播放</button>
    <input class="video-progress" type="range" min="0" max="0" step="0.1" value="0" disabled aria-label="{label}录像播放进度">
    <output class="video-time" aria-live="off">00:00 / 00:00</output>
    <span>速度</span><button data-rate="1" aria-label="{label}录像1倍速">1×</button><button data-rate="2" aria-label="{label}录像2倍速">2×</button><button data-rate="4" aria-label="{label}录像4倍速">4×</button>
    <button data-action="rotate" aria-label="顺时针旋转{label}录像90度">旋转90°</button>
    <button data-action="auto" aria-pressed="true" aria-label="恢复{label}录像自动方向">恢复自动</button>
    <span class="video-direction"></span></div>
    <p class="note video-warning">{html.escape(warning)}</p><p><a href="{relative}" target="_blank">打开原片</a> · 方向按真实 PNG 检查点校正，切换时刻取相邻不同姿态检查点的时间中点；边界附近可手动旋转。</p></div>'''


def capture_title(name):
    for game, title in sorted(CATALOG_LABELS.items(), key=lambda pair: -len(pair[0])):
        for prefix, stages in [
            ('walk_', {'01_setup': '开赛设置', '02_board': '计分板', '03_menu': '操作菜单',
                       '04_style': '样式预览', '05_typography': '比分文字设置', '06_palette': '样式与颜色'}),
            ('record_', {'01_detail': '记录详情', '02_lower': '详情下部', '03_timeline': '比赛明细'})
        ]:
            start = prefix + game + '_'
            if name.startswith(start):
                return title + ' · ' + stages.get(name[len(start):], name[len(start):])
    return name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    plan_path = root / 'review-plan.json'
    plan = json.loads(plan_path.read_text()) if plan_path.is_file() else {}
    expected_chapters = plan.get('chapters', EXPECTED_CHAPTER_LABELS)
    sessions = []
    sections = []
    navigation = []
    pose_names = {'unfolded': '展开内屏 · regular', 'folded': '合拢外屏 · compact'}
    chapter_names = {'home': '首页、常用资料与预约', 'me': '我的、设置、登录与会员',
                     'account': '账户资料（测试登录态）', 'connection': '投屏与同步说明',
                     'timers': '七种计时器', 'tools': '十种工具', 'variants': '单打与双打',
                     'scoreboards': '计分板、菜单与样式', 'records': '真实记录入口与详情',
                     'groups': '小组（离线样例数据）', 'schedules': '本地预约详情与编辑',
                     'controls': '计分编辑与旧版样式侧栏补测'}
    chapter_titles = {
        'me-forms': '帮助说明、反馈表单与协议网页',
        'tools-01': '随机分组、积分榜与 AA 计算',
        'tools-02': '弹幕运行编辑、骰子与挑战',
        'tools-03': '硬币、哨音、红黄牌与时钟',
        'timers-01': '围棋、象棋棋钟的设置与运行',
        'timers-02': '国际象棋、跳棋棋钟的设置与运行',
        'timers-03': '秒表、倒计时与魔方准备页',
        'record-actions': '记录筛选、笔记编辑与再来一场',
        'record-tail': '乒乓球、追分的长明细页尾',
        'groups-01': '小组列表、管理与成员（离线样例）',
        'groups-02': '开赛、补录、活动与排阵（离线样例）',
        'groups-03': '排行、战绩、详情与通知（离线样例）',
    }
    chapter_titles.update(plan.get('chapter_titles', {}))
    chapter_order = ['home', 'connection', 'me', 'account', 'schedules', 'timers', 'tools', 'scoreboards', 'variants', 'records', 'groups']
    def chapter_sort(path):
        base = 'records' if path.parent.name in ['record-actions', 'record-tail'] else path.parent.name.split('-')[0]
        return (chapter_order.index(base) if base in chapter_order else 99, path.parent.name)
    for pose in ['unfolded', 'folded']:
        for path in sorted((root / pose).glob('*/session.json'), key=chapter_sort):
            session = json.loads(path.read_text())
            folder = path.parent
            chapter = session.get('chapter') or folder.name
            base = 'records' if chapter in ['record-actions', 'record-tail'] else chapter.split('-')[0]
            title = chapter_titles.get(chapter, chapter_names.get(base, chapter)) + ' / ' + chapter
            identifier = pose + '-' + chapter
            captures = []
            cards = []
            for index, capture in enumerate(session.get('captures', []), 1):
                image_path = folder / (capture['name'] + '.png')
                if not image_path.exists():
                    continue
                thumbnail = folder / 'thumbnails' / image_path.name
                thumbnail.parent.mkdir(exist_ok=True)
                if not thumbnail.exists() or thumbnail.stat().st_mtime < image_path.stat().st_mtime:
                    image = Image.open(image_path).convert('RGB')
                    image.thumbnail((360, 300), Image.Resampling.LANCZOS)
                    image.save(thumbnail)
                image_url = html.escape(str(image_path.relative_to(root)))
                thumb_url = html.escape(str(thumbnail.relative_to(root)))
                name = html.escape(capture_title(capture['name']))
                seconds = capture.get('video_seconds', 0)
                captures.append(capture)
                cards.append(f'<figure><button class="seek" data-video="{identifier}" data-time="{seconds}"><img loading="lazy" src="{thumb_url}" alt="{name}"></button><figcaption>{index}. {name}<br><button class="seek text" data-video="{identifier}" data-time="{seconds}">视频 {int(seconds)//60:02d}:{int(seconds)%60:02d}</button> · <a href="{image_url}" target="_blank">原图</a></figcaption></figure>')
            video_path = folder / session.get('video', 'walkthrough.mp4')
            video = ''
            if video_path.exists() and session.get('status') != 'running':
                probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                                        'format=duration,size:stream=codec_name,width,height:stream_tags=rotate:stream_side_data=rotation',
                                        '-of', 'json', str(video_path)], capture_output=True, text=True)
                if probe.returncode == 0:
                    session['video_probe'] = json.loads(probe.stdout)
                relative = html.escape(str(video_path.relative_to(root)))
                poster = html.escape(str((folder / 'thumbnails' / (captures[0]['name'] + '.png')).relative_to(root))) if captures else ''
                display = video_display(video_path, captures, session.get('video_probe', {}))
                session['video_display_correction'] = dict(cache='video-display.json',
                                                           segments=display['segments'],
                                                           warnings=display.get('warnings', []))
                video = video_player(identifier, relative, poster, title, session, display)
            status = {'passed': '自动化流程通过', 'failed': '流程有失败，需复查',
                      'running': '正在录制', 'interrupted': '录制中断',
                      'incomplete': '截图复核发现缺页，待补录'}.get(session.get('status'), '状态未知')
            if session.get('status') == 'failed':
                log = Path(session.get('log', ''))
                if log.is_file():
                    session['errors'] = [line for line in log.read_text(errors='replace').splitlines() if 'error:' in line][-12:]
            errors = ''.join('<li>' + html.escape(error) + '</li>' for error in (session.get('errors', []) + session.get('coverage_findings', [])))
            fixture = '<p class="note">使用本地测试记录或离线小组样例；页面导航为真实应用导航，不代表服务器操作或真实账户验证。</p>' if base in ['records', 'groups'] else ''
            sections.append(f'<section id="section-{identifier}" data-pose="{pose}"><h2>{pose_names[pose]} · {html.escape(title)}</h2><p class="status {session.get("status")}">{status} · {len(captures)} 张检查点截图</p>{fixture}{video}<ul class="errors">{errors}</ul><div class="gallery">{"".join(cards)}</div></section>')
            navigation.append(f'<a data-pose="{pose}" href="#section-{identifier}">{pose_names[pose].split(" · ")[0]} · {html.escape(title)} <small>{len(captures)}</small></a>')
            sessions.append(session)
    total = sum(len(session.get('captures', [])) for session in sessions)
    failed = sum(session.get('status') == 'failed' for session in sessions)
    incomplete = sum(session.get('status') in ['incomplete', 'interrupted', 'running'] for session in sessions)
    reached = {pose: {capture['name'] for session in sessions if session.get('pose') == pose
                       and session.get('status') == 'passed' for capture in session.get('captures', [])}
               for pose in pose_names}
    rows = []
    for game in CATALOG:
        cells = []
        for pose in ['unfolded', 'folded']:
            names = reached[pose]
            stages = [('设置', f'walk_{game}_01_setup'), ('计分', f'walk_{game}_02_board'),
                      ('菜单', f'walk_{game}_03_menu'), ('样式', f'walk_{game}_04_style'),
                      ('记录', f'record_{game}_01_detail')]
            cells.append('<td>' + ' · '.join(label + (' ✓' if checkpoint in names else ' —')
                                           for label, checkpoint in stages) + '</td>')
        rows.append('<tr><th>' + html.escape(CATALOG_LABELS[game]) + '</th>' + ''.join(cells) + '</tr>')
    matrix = '<section><details><summary><strong>29 个项目覆盖清单（点击展开）</strong></summary><p class="note">✓ 只统计流程通过且实际保存的检查点；— 表示尚未到达或该项目没有此入口，需结合章节说明，不表示通过。截图数包含弹窗和滚动状态，不等于独立页面数。</p><div style="overflow:auto"><table><thead><tr><th>项目</th><th>展开内屏</th><th>合拢外屏</th></tr></thead><tbody>' + ''.join(rows) + '</tbody></table></div></details></section>'
    if not plan.get('check_catalog', True):
        matrix = ''
    document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>iPhone Duo 页面巡检录像</title><style>
    *{box-sizing:border-box}body{margin:0;color:#21332b;background:#f4f7f5;font:15px/1.6 system-ui,-apple-system,sans-serif}aside{position:fixed;width:265px;height:100vh;overflow:auto;padding:26px 18px;background:#fff;border-right:1px solid #dce7e0}aside a{display:block;padding:7px;color:#286d47;text-decoration:none;border-bottom:1px solid #eef3ef}aside small{float:right;color:#84998c}main{margin-left:265px;padding:36px;max-width:1600px}h1{font-size:30px;margin:0 0 8px}h2{font-size:21px}header,section{background:white;padding:26px;border-radius:16px;margin-bottom:28px;border:1px solid #dce7e0}video{display:block;width:100%;max-height:72vh;background:#121a16;border-radius:10px}.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(185px,1fr));gap:14px}figure{margin:0;background:#f1f5f2;border-radius:10px;overflow:hidden}figure img{width:100%;height:190px;object-fit:contain}figcaption{padding:10px;overflow-wrap:anywhere;font-size:12px}.seek{border:0;background:none;cursor:pointer;width:100%;padding:0}.text{width:auto;color:#27764a;text-decoration:underline}button,select{font:inherit;border:1px solid #c9d9cf;border-radius:6px;background:#f7faf8;color:#244f36;padding:5px 10px}button,summary{cursor:pointer}summary{font-size:18px}.note{color:#657b6b}.status{padding:7px 12px;border-radius:6px;background:#eff6f1}.failed,.interrupted,.incomplete{color:#a23121;background:#fff0e9}.errors{font-size:12px;overflow-wrap:anywhere}.filters{display:flex;gap:8px;flex-wrap:wrap;margin:20px 0}table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:8px;border-bottom:1px solid #dce7e0;white-space:nowrap}.hidden{display:none!important}@media(max-width:800px){aside{position:static;width:auto;height:auto;max-height:240px}main{margin-left:0;padding:14px}}
    .video-viewport{position:relative;width:100%;height:min(56vw,72vh);max-height:72vh;overflow:hidden;background:#121a16;border-radius:10px}.video-viewport video{position:absolute;left:50%;top:50%;width:auto;max-height:none;border-radius:0;transform-origin:center;object-fit:contain}.video-poster{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;pointer-events:none}.video-controls{display:flex;align-items:center;flex-wrap:wrap;gap:8px;margin:12px 0}.video-progress{flex:1 1 150px;min-width:100px;accent-color:#3f9c59}.video-time{font-variant-numeric:tabular-nums;white-space:nowrap}.video-direction{font-size:12px;color:#657b6b}.video-warning:empty{display:none}.video-controls button[aria-pressed=true]{background:#e2f1e7;border:1px solid #78a889}
    </style><aside><b>视频章节与截图索引</b>NAVIGATION</aside><main><header><h1>iPhone Duo 页面巡检录像</h1><p>2026-10-20 · 原生模拟器 · 真实操作录屏，无音频</p><p>TOTAL 张检查点截图 · 已生成 SESSIONS / EXPECTED 段流程 · VIDEO_MINUTES 分钟原始录像 · FAILED 段有失败 · INCOMPLETE 段尚未完成复核。点击截图或时间点可以跳到实际视频的位置；原图保留完整像素。</p><p class="note">视频保留加载、滚动、弹窗、返回及应用重启过程。自动化通过只表示该段断言通过，仍需结合画面人工验收。登录、支付、外接显示、相机和真实服务端状态不由样例页面替代。</p><p><button id="play-all">连续播放当前筛选的完整视频</button> <select id="playlist-rate" aria-label="连续播放速度"><option value="1">1×</option><option value="2" selected>2×</option><option value="4">4×</option><option value="8">8×</option></select> <button id="stop-all">暂停播放</button> <span id="playlist-state"></span></p><div class="filters"><button data-filter="all">两种屏幕</button><button data-filter="unfolded">展开内屏</button><button data-filter="folded">合拢外屏</button></div></header>MATRIXSECTIONS</main><script>

    const players = new Map();
    const clock = seconds => {const n=Math.max(0,Math.floor(Number.isFinite(seconds)?seconds:0));return `${Math.floor(n/60).toString().padStart(2,'0')}:${(n%60).toString().padStart(2,'0')}`;};
    const autoAngle = state => {let angle=0;for(const segment of state.config.segments){if(segment.start>state.video.currentTime)break;angle=segment.angle;}return angle;};
    const layoutPlayer = state => {
        const {video,viewport,config}=state;
        if(!viewport.clientWidth)return;
        const angle=state.manualAngle===null?autoAngle(state):state.manualAngle;
        const width=video.videoWidth||config.pixels[0],height=video.videoHeight||config.pixels[1];
        const sideways=Math.abs(angle)%180===90;
        const displayWidth=sideways?height:width,displayHeight=sideways?width:height;
        const scale=Math.min(viewport.clientWidth/displayWidth,window.innerHeight*0.72/displayHeight);
        viewport.style.height=`${displayHeight*scale}px`;
        video.style.width=`${width*scale}px`;video.style.height=`${height*scale}px`;
        video.style.transform=`translate(-50%,-50%) rotate(${angle}deg)`;
        state.direction.textContent=`${state.manualAngle===null?'自动':'手动'}方向 · ${((angle%360)+360)%360}°`;
        state.auto.setAttribute('aria-pressed',String(state.manualAngle===null));
    };
    const updatePlayer = state => {
        const {video,config}=state;
        const duration=Number.isFinite(video.duration)?video.duration:config.duration;
        state.progress.max=duration||0;
        state.progress.disabled=!duration;
        state.progress.value=video.currentTime||0;
        state.time.textContent=`${clock(video.currentTime)} / ${clock(duration)}`;
        state.toggle.textContent=video.paused?'播放':'暂停';
        state.toggle.setAttribute('aria-pressed',String(!video.paused));
        layoutPlayer(state);
    };
    const setRate = (video,rate) => {const state=players.get(video.id);state.rate=rate;video.defaultPlaybackRate=rate;video.playbackRate=rate;state.element.querySelectorAll('[data-rate]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.rate)===rate)));};
    const playVideo = video => {const result=video.play();if(result&&result.catch)result.catch(()=>{players.get(video.id).warning.textContent='播放未开始，请点击播放按钮；原片链接仍可使用。';});};
    const seekVideo = (video,seconds,play=false) => {
        const jump=()=>{video.currentTime=Math.max(0,Math.min(seconds,Number.isFinite(video.duration)?video.duration:seconds));setRate(video,players.get(video.id).rate);updatePlayer(players.get(video.id));if(play)playVideo(video);};
        if(video.readyState>=1)jump();
        else{video.addEventListener('loadedmetadata',jump,{once:true});video.preload='metadata';video.load();}
    };
    document.querySelectorAll('.video-player').forEach(element=>{
        const video=element.querySelector('video');
        const state={element,video,viewport:element.querySelector('.video-viewport'),config:JSON.parse(element.dataset.display),manualAngle:null,
            toggle:element.querySelector('[data-action=toggle]'),progress:element.querySelector('.video-progress'),time:element.querySelector('.video-time'),
            auto:element.querySelector('[data-action=auto]'),direction:element.querySelector('.video-direction'),warning:element.querySelector('.video-warning')};
        players.set(video.id,state);
        setRate(video,Number(document.getElementById('playlist-rate').value));
        state.toggle.onclick=()=>{if(video.paused)playVideo(video);else video.pause();};
        state.progress.oninput=()=>seekVideo(video,Number(state.progress.value));
        element.querySelectorAll('[data-rate]').forEach(button=>button.onclick=()=>{setRate(video,Number(button.dataset.rate));});
        element.querySelector('[data-action=rotate]').onclick=()=>{state.manualAngle=((state.manualAngle===null?autoAngle(state):state.manualAngle)+90)%360;layoutPlayer(state);};
        state.auto.onclick=()=>{state.manualAngle=null;layoutPlayer(state);};
        ['loadedmetadata','durationchange','timeupdate','seeking','seeked','play','pause','ended'].forEach(event=>video.addEventListener(event,()=>updatePlayer(state)));
        video.addEventListener('loadeddata',()=>{element.querySelector('.video-poster').hidden=true;updatePlayer(state);});
        video.addEventListener('error',()=>{state.warning.textContent='视频加载失败，请检查原片链接或通过本地服务器打开索引。';});
        if(typeof ResizeObserver!=='undefined'){state.observer=new ResizeObserver(()=>layoutPlayer(state));state.observer.observe(state.viewport);}
        updatePlayer(state);
    });
    window.addEventListener('resize',()=>players.forEach(layoutPlayer));
    let playlist=[];let playlistIndex=0;
    const playNext=()=>{
        const video=playlist[playlistIndex];
        if(!video){document.getElementById('playlist-state').textContent='连续播放结束';return;}
        document.querySelectorAll('video').forEach(other=>{if(other!==video)other.pause();});
        players.get(video.id).element.scrollIntoView({behavior:'smooth',block:'center'});
        setRate(video,Number(document.getElementById('playlist-rate').value));
        seekVideo(video,0,true);
        document.getElementById('playlist-state').textContent=`${playlistIndex+1} / ${playlist.length} · ${video.id}`;
    };
    document.getElementById('play-all').onclick=()=>{playlist=[...document.querySelectorAll('section:not(.hidden) video[data-status=passed]')];playlistIndex=0;playNext();};
    document.getElementById('playlist-rate').onchange=()=>document.querySelectorAll('video').forEach(video=>{setRate(video,Number(document.getElementById('playlist-rate').value));});
    document.getElementById('stop-all').onclick=()=>document.querySelectorAll('video').forEach(video=>video.pause());
    document.querySelectorAll('video').forEach(video=>video.addEventListener('ended',()=>{if(playlist[playlistIndex]===video){playlistIndex++;playNext();}}));
    document.querySelectorAll('.seek').forEach(button=>button.onclick=()=>{
        const video=document.getElementById(button.dataset.video);if(!video)return;
        players.get(video.id).element.scrollIntoView({behavior:'smooth',block:'center'});
        seekVideo(video,Number(button.dataset.time),true);
    });
    document.querySelectorAll('[data-filter]').forEach(button=>button.onclick=()=>{
        document.querySelectorAll('[data-pose]').forEach(element=>element.classList.toggle('hidden',button.dataset.filter!=='all'&&element.dataset.pose!==button.dataset.filter));
        players.forEach(layoutPlayer);
    });
    </script></html>'''
    document = document.replace('NAVIGATION', ''.join(navigation)).replace('MATRIX', matrix).replace('SECTIONS', ''.join(sections))
    minutes = sum(float(session.get('video_probe', {}).get('format', {}).get('duration', 0)) for session in sessions) / 60
    document = document.replace('EXPECTED', str(2 * len(expected_chapters))).replace('VIDEO_MINUTES', str(round(minutes, 1)))
    document = document.replace('TOTAL', str(total)).replace('SESSIONS', str(len(sessions))).replace('FAILED', str(failed)).replace('INCOMPLETE', str(incomplete))
    document = document.replace('iPhone Duo 页面巡检录像', html.escape(plan.get('title', 'iPhone Duo 页面巡检录像')))
    if plan.get('followup_link'):
        link = html.escape(plan['followup_link'], quote=True)
        label = html.escape(plan.get('followup_label', '查看最新补测'))
        document = document.replace('<h1>', '<p class="status"><a href="' + link + '">' + label + '</a></p><h1>', 1)
    if plan.get('notice'):
        document = document.replace('<h1>', '<p class=\"status\">' + html.escape(plan['notice']) + '</p><h1>', 1)
    for name, content in [('index.html', document), ('coverage.json', json.dumps(dict(screenshot_count=total, sessions=sessions), ensure_ascii=False, indent=2) + '\n')]:
        atomic_write(root / name, content)
    print(f'{root / "index.html"}: {len(sessions)} chapters, {total} captures, {failed} failures')


if __name__ == '__main__':
    main()
