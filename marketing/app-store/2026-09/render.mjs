import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// 多语言 App Store 截图渲染（蓝色方案 + 可视化编辑器）
//  - settings.json 保存可调参数（描边宽度/颜色/透明度、圆角等），出图时读取。
//  - node render.mjs 同时生成 editor.html：右侧面板实时调节，"下载 settings.json"
//    后放到本目录再跑 render.mjs 即可让 PNG 与预览一致。
//  - hero 卡（第 1、2 张）与投屏卡（第 6 张）为手绘场景（分级描边、出血、Lucide 图标），
//    其余卡为真实截图；状态栏由源图自行处理，管线不盖条。
// 用法：node render.mjs              渲染全部语言 + editor.html
//       node render.mjs --locale en  只渲染一个语言

const root = path.dirname(fileURLToPath(import.meta.url));
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const width = 1320;
const height = 2868;

// 主方案背景：蓝色（曾经的 black 双版本已弃用）
const PAGE_BG = '#0B61FB';

// ---------- 可调参数 ----------

const DEFAULT_SETTINGS = {
  strokeWidth: 16,
  strokeColor: '#FFFFFF',
  strokeOpacity: 0.75,
  cardRadius: 72,
  panelRadius: 56,
  // 手绘记分板卡更大 → 描边按倍数加粗；横版双图卡更小 → 描边变细、圆角单独一档
  heroStrokeScale: 1.2,
  wideStrokeScale: 0.85,
  wideRadius: 46,
};

// 三类卡片各自的描边像素值（由基准宽度 × 倍数推导）
const heroStrokeWidth = () => Math.round(S.strokeWidth * S.heroStrokeScale);
const wideStrokeWidth = () => Math.round(S.strokeWidth * S.wideStrokeScale);

function loadSettings() {
  try {
    const raw = JSON.parse(fs.readFileSync(path.join(root, 'settings.json'), 'utf8'));
    return { ...DEFAULT_SETTINGS, ...raw };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

const S = loadSettings();

function hexToRgb(hex) {
  let h = hex.replace('#', '');
  if (h.length === 3) h = h.split('').map(c => c + c).join('');
  const n = parseInt(h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

const strokeRGBA = () => {
  const [r, g, b] = hexToRgb(S.strokeColor);
  return `rgba(${r},${g},${b},${S.strokeOpacity})`;
};

// ---------- 基础 ----------

const argv = process.argv.slice(2);
const only = argv.includes('--locale') ? argv[argv.indexOf('--locale') + 1] : null;

const locales = fs.readdirSync(path.join(root, 'locales'))
  .filter(f => f.endsWith('.json'))
  .map(f => JSON.parse(fs.readFileSync(path.join(root, 'locales', f), 'utf8')))
  .filter(l => !only || l.code === only)
  .sort((a, b) => a.code.localeCompare(b.code));

if (locales.length === 0) {
  console.error('没有匹配的语言文件');
  process.exit(1);
}

function escapeHTML(s) {
  return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

// 源图按文件粒度解析：sources-<code>/ 优先，缺失时回退共享 sources/（共享目录是简体中文 UI，
// 回退即意味着该语言截图里混了中文画面），渲染末尾统一告警。
function makeSources(code) {
  const own = 'sources-' + code;
  const has = (dir, file) => fs.existsSync(path.join(root, dir, file));
  const fallback = new Set();
  return {
    dir(file) {
      if (has(own, file)) return own;
      if (code === 'sources' || has('sources', file)) fallback.add(file);
      return 'sources';
    },
    has(file) { return has(own, file) || has('sources', file); },
    abs(file) { return path.join(root, this.dir(file), file); },
    url(prefix, file) { return `${prefix}${this.dir(file)}/${file}`; },
    fallback,
  };
}

function pngSize(file) {
  const b = fs.readFileSync(file);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

// fontsPrefix：页面 HTML 在子目录用 '../fonts/'，editor.html 在根目录用 'fonts/'
function fontFaces(fontsPrefix = '../fonts/') {
  let css = '';
  const has = f => fs.existsSync(path.join(root, 'fonts', f));
  if (has('YouSheBiaoTiHei.ttf')) css += `@font-face{font-family:'YouSheBiaoTiHei';src:url('${fontsPrefix}YouSheBiaoTiHei.ttf');}`;
  if (has('Poppins-ExtraBoldItalic.ttf')) css += `@font-face{font-family:'Poppins';src:url('${fontsPrefix}Poppins-ExtraBoldItalic.ttf');font-style:italic;font-weight:800;}`;
  if (has('Poppins-BoldItalic.ttf')) css += `@font-face{font-family:'Poppins';src:url('${fontsPrefix}Poppins-BoldItalic.ttf');font-style:italic;font-weight:700;}`;
  if (has('Poppins-ExtraBold.ttf')) css += `@font-face{font-family:'Poppins';src:url('${fontsPrefix}Poppins-ExtraBold.ttf');font-style:normal;font-weight:800;}`;
  if (has('Poppins-Bold.ttf')) css += `@font-face{font-family:'Poppins';src:url('${fontsPrefix}Poppins-Bold.ttf');font-style:normal;font-weight:700;}`;
  if (has('NotoSansSC-VF.ttf')) css += `@font-face{font-family:'Noto Sans SC';src:url('${fontsPrefix}NotoSansSC-VF.ttf');font-weight:100 900;}`;
  return css;
}

const STROKE = 'var(--stroke-width)';
const STROKE_COLOR = 'var(--stroke-color)';

// Lucide 线性图标（ISC 协议），白色描边
const LUCIDE = {
  volume: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>',
  arrowLeft: '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
  pencil: '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/>',
  more: '<circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/>',
};
const lucideIcon = (name, size = 66) =>
  `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${LUCIDE[name]}</svg>`;

// 拼贴卡倾角备选（评审用，输出 <语言>/card5-B.png / card5-C.png）
const COLLAGE_VARIANTS = { B: { tilt: -3 }, C: { tilt: -11 } };

// hero 卡片：大标题 + 手绘记分板面板（实际比例、出血、16px 描边、Lucide 图标、iOS 系统字体）
// 面板内容按"可见区域"水平居中（面板出血后若按面板居中，内容会偏向画布外侧）
function heroBody(card, srcPrefix) {
  const L = card.panelLeft, T = card.panelTop, W = card.panelWidth, H = card.panelHeight;
  const visibleLeft = Math.max(L, 0), visibleRight = Math.min(L + W, width);
  const contentShift = Math.round((visibleLeft + visibleRight) / 2 - (L + W / 2));
  const panel = `<div class="panel" style="left:${L}px;top:${T}px;width:${W}px;height:${H}px;background:${card.panel}">
    <div class="pname" style="top:13%;left:${contentShift}px;width:${W}px">${escapeHTML(card.name)}</div>
    <div class="pscore" style="top:26%;left:${contentShift}px;width:${W}px">${escapeHTML(card.score)}</div>
    <div class="psub" style="top:70%;left:${contentShift}px;width:${W}px">${escapeHTML(card.sub)}</div>
    ${card.icons === 'left'
      ? `<div class="pbtn" style="left:88px;top:88px">${lucideIcon('volume')}</div>
         <div class="pbtn" style="left:88px;bottom:88px">${lucideIcon('arrowLeft')}</div>`
      : `<div class="pbtn" style="right:88px;top:88px">${lucideIcon('pencil')}</div>
         <div class="pbtn" style="right:88px;bottom:88px">${lucideIcon('more')}</div>`}
  </div>`;
  // 发球三角画在面板上层
  const serve = card.serve
    ? `<div style="position:absolute;left:0;top:${Math.round(T + H * 0.47)}px;width:96px;height:136px;background:#30D158;clip-path:polygon(0 0,100% 50%,0 100%);z-index:2"></div>`
    : '';
  return panel + serve;
}

// 投屏卡:同一场篮球赛投上电视。电视画面按 App 显示端 two_side 版式手绘
// （50/50 双面板 + 顶部节次/犯规条 + 底部时钟条，显示端无操控按钮），
// 手机用真截图放进横置手机壳，两边比分/队名/时钟完全一致。
function castBody(card, src, srcPrefix, opts = {}) {
  const font = "-apple-system,system-ui,'Helvetica Neue',sans-serif";
  const pill = (inner, bg, extra = '') =>
    `<div style="display:flex;align-items:center;justify-content:center;gap:14px;background:${bg};${extra}font-family:${font}">${inner}</div>`;
  const tvPanel = (name, score, bg) => `
    <div style="flex:1;background:${bg};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:26px">
      <div style="font-family:${font};font-weight:700;font-size:52px;line-height:1;color:#fff">${escapeHTML(name)}</div>
      <div style="font-family:${font};font-weight:700;font-size:184px;line-height:1;color:#fff">${escapeHTML(score)}</div>
    </div>`;
  const clockPill = pill(`
      <span style="font-weight:700;font-size:34px;color:rgba(255,255,255,.86)">${escapeHTML(card.period)}<span style="font-size:21px">${escapeHTML(card.periodSuffix)}</span></span>
      <span style="font-weight:400;font-size:26px;color:rgba(255,255,255,.32)">|</span>
      <span style="font-weight:700;font-size:44px;color:#fff;font-variant-numeric:tabular-nums">${escapeHTML(card.time)}</span>
      <span style="font-weight:400;font-size:26px;color:rgba(255,255,255,.32)">|</span>
      <span style="font-weight:700;font-size:44px;color:#FDE047;font-variant-numeric:tabular-nums">${escapeHTML(card.shotClock)}</span>`,
    'rgba(10,12,18,.82)',
    'border:1px solid rgba(255,255,255,.14);border-radius:24px;padding:14px 30px');
  const pauseBar = pill(`
      <span style="display:flex;gap:4px"><i style="width:5px;height:18px;border-radius:2px;background:rgba(255,255,255,.95)"></i><i style="width:5px;height:18px;border-radius:2px;background:rgba(255,255,255,.95)"></i></span>
      <span style="font-weight:600;font-size:26px;color:#fff">${escapeHTML(card.clockPauseLabel)}</span>`,
    'rgba(218,45,32,.92)', 'border-radius:22px;height:46px;padding:0 22px');
  const tvScreen = `
    <div style="position:absolute;inset:0;display:flex">
      ${tvPanel(card.name, card.score, '#C62828')}
      ${tvPanel(card.name2, card.score2, '#007AFF')}
    </div>
    <div style="position:absolute;left:0;right:0;top:5%;display:flex;flex-direction:column;align-items:center;gap:16px">
      ${pill(`<span style="font-weight:600;font-size:29px;color:#fff">${escapeHTML(card.periodBadge)}</span>`, 'rgba(0,0,0,.32)', 'border-radius:14px;padding:9px 24px')}
      ${pill(`<span style="font-weight:700;font-size:38px;color:#fff">0</span><span style="font-weight:400;font-size:26px;color:rgba(255,255,255,.72)">${escapeHTML(card.foulLabel)}</span><span style="font-weight:700;font-size:38px;color:#fff">0</span>`, 'rgba(0,0,0,.28)', 'border-radius:14px;padding:9px 24px')}
    </div>
    <div style="position:absolute;left:0;right:0;bottom:5%;display:flex;flex-direction:column;align-items:center;gap:14px">
      ${pauseBar}
      ${clockPill}
    </div>`;

  const dim = pngSize(src.abs(card.image));
  const tvW = 1240, bezel = 14, tvLeft = (width - tvW) / 2, tvTop = 700;
  const tvScreenW = tvW - bezel * 2, tvScreenH = Math.round(tvScreenW * 9 / 16);
  const caseW = 1240, caseBorder = 22, caseRadius = 66;
  const screenW = caseW - caseBorder * 2;
  const screenH = Math.round(screenW * dim.h / dim.w);
  const caseH = screenH + caseBorder * 2;
  const caseLeft = (width - caseW) / 2, caseTop = 1720;
  const signal = `
    <svg width="190" height="100" viewBox="0 0 190 100" style="position:absolute;left:${(width - 190) / 2}px;top:${tvTop + bezel * 2 + tvScreenH + 118}px">
      <circle cx="95" cy="90" r="9" fill="#fff" opacity=".9"/>
      <path d="M65 68 a42 42 0 0 1 60 0" stroke="#fff" stroke-opacity=".52" stroke-width="9" fill="none" stroke-linecap="round"/>
      <path d="M40 42 a78 78 0 0 1 110 0" stroke="#fff" stroke-opacity=".3" stroke-width="9" fill="none" stroke-linecap="round"/>
    </svg>`;
  return `
    <div class="tv" style="left:${tvLeft}px;top:${tvTop}px;width:${tvW}px">
      <div class="tv-frame" style="height:${tvScreenH + bezel * 2}px">
        <div class="tv-screen">${tvScreen}</div>
      </div>
      <div class="tv-neck"></div>
      <div class="tv-foot"></div>
    </div>
    ${signal}
    <div class="phone-case" style="left:${caseLeft}px;top:${caseTop}px;width:${caseW}px;height:${caseH}px;border-radius:${caseRadius}px;transform:rotate(-5deg)">
      <div class="phone-screen" style="left:${caseBorder}px;top:${caseBorder}px;width:${screenW}px;height:${screenH}px;border-radius:${caseRadius - caseBorder - 8}px"><img src="${src.url(srcPrefix, card.image)}"></div>
      <div class="phone-island" style="left:${caseBorder + 22}px;top:${caseBorder + (screenH - 70) / 2}px"></div>
      <div class="phone-key" style="left:${Math.round(caseW * .30)}px;bottom:-5px;width:74px;height:10px"></div>
      <div class="phone-key" style="left:${Math.round(caseW * .40)}px;bottom:-5px;width:74px;height:10px"></div>
      <div class="phone-key" style="left:${Math.round(caseW * .66)}px;bottom:-5px;width:120px;height:10px"></div>
    </div>
    ${opts.hand ? castHand(caseLeft, caseTop, caseW, caseH) : ''}`;
}

// 双手握持:两只拇指从下缘压住手机壳下角,掌根延伸到画布外
function castHand(caseLeft, caseTop, caseW, caseH) {
  const skin = 'linear-gradient(160deg,#F3C9A6,#DFA97F)';
  const thumb = (side) => {
    const x = side === 'left' ? caseLeft + 66 : caseLeft + caseW - 66 - 108;
    const rot = side === 'left' ? 16 : -16;
    return `
      <div style="position:absolute;left:${side === 'left' ? caseLeft - 150 : caseLeft + caseW - 60}px;top:${caseTop + caseH - 150}px;width:210px;height:520px;background:${skin};border-radius:96px;transform:rotate(${rot}deg);box-shadow:0 -10px 30px rgba(0,0,0,.22)"></div>
      <div style="position:absolute;left:${x}px;top:${caseTop + caseH - 250}px;width:108px;height:300px;background:${skin};border-radius:54px;transform:rotate(${rot}deg);box-shadow:0 -8px 26px rgba(0,0,0,.26)"></div>
      <div style="position:absolute;left:${x + 21}px;top:${caseTop + caseH - 236}px;width:66px;height:84px;background:rgba(255,255,255,.26);border-radius:33px;transform:rotate(${rot}deg)"></div>`;
  };
  return `<div style="position:absolute;inset:0;z-index:5">${thumb('left')}${thumb('right')}</div>`;
}

// 拼贴卡:等高行 + 统一倾角的整齐网格,左右出血由画布裁切。
// 语言可在 card.tiles 指定素材(用横屏截图排起来才整齐),card.collage 覆盖 { tilt, perRow, bleed, gap }。
const DEFAULT_TILES = ['basketball.png', 'xiangqi.png', 'volleyball.png', 'snooker.png', 'go_timer.png'];
const COLLAGE_LAYOUT = { tilt: -7, perRow: 2, bleed: 210, gap: 36, top: 620, bottom: 2790 };

function collageBody(card, src, srcPrefix) {
  const L = { ...COLLAGE_LAYOUT, ...(card.collage || {}) };
  const files = (card.tiles || DEFAULT_TILES).filter(f => src.has(f));
  const contentW = width + L.bleed * 2;
  const rows = [];
  for (let i = 0; i < files.length; i += L.perRow) rows.push(files.slice(i, i + L.perRow));
  const aspect = f => { const d = pngSize(src.abs(f)); return d.w / d.h; };
  const byWidth = Math.min(...rows.map(row => (contentW - (row.length - 1) * L.gap) / row.reduce((s, f) => s + aspect(f), 0)));
  const byHeight = (L.bottom - L.top - (rows.length - 1) * L.gap) / rows.length;
  const h = Math.floor(Math.min(byWidth, byHeight));
  const blockH = rows.length * h + (rows.length - 1) * L.gap;
  const top = Math.round(L.top + (L.bottom - L.top - blockH) / 2);
  const rowsHTML = rows.map(row =>
    `<div style="display:flex;justify-content:center;gap:${L.gap}px;height:${h}px">` +
    row.map(f => `<div class="shot wide collage" style="position:relative;width:${Math.round(h * aspect(f))}px;height:${h}px"><img src="${src.url(srcPrefix, f)}"></div>`).join('') +
    `</div>`
  ).join('');
  return `<div style="position:absolute;left:${-L.bleed}px;top:${top}px;width:${contentW}px;display:flex;flex-direction:column;gap:${L.gap}px;transform:rotate(${L.tilt}deg)">${rowsHTML}</div>`;
}

// 普通卡片：真实截图（状态栏由源图自行处理，这里不盖条）
function shotBody(card, src, srcPrefix) {
  if (card.layout === 'double') {
    const imgs = [card.image, card.secondary].map(f => ({ f, ...pngSize(src.abs(f)) }));
    const regionTop = 560, regionBottom = height - 120, gap = 48;
    let w1 = 1160, w2 = 1160;
    let h1 = w1 * imgs[0].h / imgs[0].w, h2 = w2 * imgs[1].h / imgs[1].w;
    const avail = regionBottom - regionTop - gap;
    if (h1 + h2 > avail) {
      const k = avail / (h1 + h2);
      w1 *= k; w2 *= k; h1 *= k; h2 *= k;
    }
    const top = regionTop + (avail - (h1 + h2)) / 2;
    return `<div class="shot wide" style="left:${(width - w1) / 2}px;top:${top}px;width:${w1}px;height:${h1}px"><img src="${src.url(srcPrefix, imgs[0].f)}"></div>` +
      `<div class="shot wide" style="left:${(width - w2) / 2}px;top:${top + h1 + gap}px;width:${w2}px;height:${h2}px"><img src="${src.url(srcPrefix, imgs[1].f)}"></div>`;
  }
  const w = 1000, h = Math.round(w * height / width), top = 560;
  return `<div class="shot" style="left:${(width - w) / 2}px;top:${top}px;width:${w}px;height:${h}px"><img src="${src.url(srcPrefix, card.image)}"></div>`;
}

// slogan 卡：超大标语 + 底部品牌名（Sofascore 式首图）。
// 无 image 时为纯色背景 + 巨型比分水印；有 image 时照片铺满画布压成品牌蓝 duotone
// （灰度 → 乘品牌蓝提亮部 → 再以深蓝 lighten 提暗部），标语移到画面中央留白处。
// 字体栈含双引号，放进 inline style 属性必须转成单引号，否则属性被截断、font-size 全部失效
const styleAttrFont = f => f.replaceAll('"', "'");

function sloganBody(card, loc, src, srcPrefix) {
  const up = loc.headlineUppercase ? 'text-transform:uppercase;' : '';
  const font = styleAttrFont(loc.headlineFont);
  const brand = card.brand || loc.eyebrow;
  const photo = card.image && src.has(card.image)
    ? `<div class="slogan-photo"><img src="${src.url(srcPrefix, card.image)}"></div>
       <div class="slogan-tint"></div>
       <div class="slogan-tint2"></div>
       <div class="slogan-scrim"></div>`
    : card.watermark
      ? `<div class="slogan-mark" style="font-family:${font}">${escapeHTML(card.watermark)}</div>`
      : '';
  const textClass = card.image && src.has(card.image) ? 'slogan-text slogan-text-mid' : 'slogan-text';
  return `${photo}
    <div class="${textClass}" data-max="${card.sloganMaxHeight || 480}" style="font-family:${font};font-style:${loc.headlineStyle};font-weight:${loc.headlineWeight};${up}font-size:${card.headlineSize || 200}px;line-height:${loc.headlineLineHeight || 1.06};letter-spacing:${loc.headlineTracking || '0px'}">${escapeHTML(card.title)}</div>
    <div class="slogan-brand" style="font-family:${font}">${escapeHTML(brand)}</div>`;
}

function canvasInner(loc, card, src, bg, srcPrefix) {
  const isHero = card.layout === 'hero';
  const headlineCss = `position:absolute;left:80px;top:190px;width:1160px;height:330px;overflow:hidden;` +
    `text-align:center;white-space:pre-line;font-family:${loc.headlineFont};font-style:${loc.headlineStyle};` +
    `font-weight:${loc.headlineWeight};font-size:${card.headlineSize || loc.headlineSize}px;` +
    `line-height:${loc.headlineLineHeight};` +
    `letter-spacing:${loc.headlineTracking};color:#fff;${loc.headlineUppercase ? 'text-transform:uppercase;' : ''}`;
  const body = card.layout === 'slogan' ? sloganBody(card, loc, src, srcPrefix)
    : isHero ? heroBody(card, srcPrefix)
    : card.layout === 'cast' ? castBody(card, src, srcPrefix, { hand: card.hand === true })
    : card.layout === 'collage' ? collageBody(card, src, srcPrefix)
    : shotBody(card, src, srcPrefix);
  const headline = card.layout === 'slogan' ? '' : `<div class="headline" data-max="330"><span class="skew">${escapeHTML(card.title)}</span></div>`;
  return { isHero, html: `${headline}${body}`, headlineCss };
}

function baseCSS(loc, isHeroSkew) {
  return `
    *{box-sizing:border-box}
    .canvas{position:relative;width:${width}px;height:${height}px;overflow:hidden;color:#fff}
    .headline .skew{display:inline-block;transform:skewX(${isHeroSkew ? (loc.heroSkew || '0deg') : '0deg'})}
    .shot{position:absolute;border-radius:var(--card-radius);box-shadow:0 0 0 ${STROKE} ${STROKE_COLOR};overflow:hidden;background:#111}
    .shot.wide{border-radius:var(--wide-radius);box-shadow:0 0 0 var(--wide-stroke-width) ${STROKE_COLOR}}
    .shot.collage{box-shadow:0 0 0 var(--wide-stroke-width) ${STROKE_COLOR}, 0 34px 70px rgba(0,0,0,.38)}
    .shot img{display:block;width:100%;height:100%;object-fit:cover}
    .panel{position:absolute;border-radius:var(--panel-radius);box-shadow:0 0 0 var(--hero-stroke-width) ${STROKE_COLOR};overflow:hidden}
    .pname{position:absolute;right:auto;text-align:center;font-family:var(--panel-font);font-style:normal;font-weight:700;font-size:96px;color:#fff}
    .pscore{position:absolute;right:auto;text-align:center;font-family:var(--panel-font);font-style:normal;font-weight:var(--score-weight,700);font-size:460px;line-height:1;color:#fff}
    .psub{position:absolute;right:auto;text-align:center;font-family:var(--panel-font);font-style:normal;font-weight:600;font-size:150px;line-height:1;color:rgba(255,255,255,.45)}
    .pbtn{position:absolute;width:128px;height:128px;border-radius:50%;background:var(--pbtn-bg);display:flex;align-items:center;justify-content:center}
    .tv{position:absolute}
    .tv-frame{background:#0B0D12;border-radius:22px;padding:${14}px;box-sizing:border-box;box-shadow:0 30px 70px rgba(0,0,0,.38)}
    .tv-screen{position:relative;display:flex;width:100%;height:100%;border-radius:10px;overflow:hidden}
    .tv-neck{width:96px;height:54px;background:#0B0D12;margin:0 auto}
    .tv-foot{width:340px;height:16px;border-radius:8px;background:#0B0D12;margin:0 auto}
    .phone-case{position:absolute;background:#1A1B20;box-shadow:0 34px 80px rgba(0,0,0,.45),inset 0 0 0 2px rgba(255,255,255,.10)}
    .phone-screen{position:absolute;overflow:hidden;background:#000}
    .phone-screen img{display:block;width:100%;height:100%;object-fit:cover}
    .phone-island{position:absolute;width:16px;height:70px;border-radius:8px;background:#07070A}
    .phone-key{position:absolute;border-radius:5px;background:#2A2B30}
    .slogan-mark{position:absolute;left:50%;top:58%;transform:translate(-50%,-50%) rotate(-6deg);font-style:italic;font-weight:800;font-size:1150px;line-height:1;color:#fff;opacity:.08;white-space:nowrap;pointer-events:none}
    .slogan-text{position:absolute;left:80px;right:80px;top:250px;text-align:center;white-space:pre-line;color:#fff}
    .slogan-text-mid{top:50%;transform:translateY(-54%)}
    .slogan-photo{position:absolute;inset:0;overflow:hidden}
    .slogan-photo img{display:block;width:100%;height:100%;object-fit:cover;filter:grayscale(1) contrast(1.08) brightness(.95)}
    .slogan-tint{position:absolute;inset:0;background:${PAGE_BG};mix-blend-mode:multiply}
    .slogan-tint2{position:absolute;inset:0;background:#0A2F7A;mix-blend-mode:lighten}
    .slogan-scrim{position:absolute;left:0;right:0;bottom:0;height:700px;background:linear-gradient(180deg,rgba(4,24,64,0),rgba(4,24,64,.6))}
    .slogan-brand{position:absolute;left:0;right:0;bottom:280px;text-align:center;font-style:normal;font-weight:700;font-size:72px;letter-spacing:2px;color:#fff}
  `;
}

function page(loc, card, index, total, src, bg) {
  const { isHero, html, headlineCss } = canvasInner(loc, card, src, bg, '../');
  return `<!doctype html><html lang="${loc.htmlLang}" dir="${loc.dir || 'ltr'}"><head><meta charset="utf-8"><style>
    ${fontFaces()}
    :root{--stroke-width:${S.strokeWidth}px;--stroke-color:${strokeRGBA()};--card-radius:${S.cardRadius}px;--panel-radius:${S.panelRadius}px;--hero-stroke-width:${heroStrokeWidth()}px;--wide-stroke-width:${wideStrokeWidth()}px;--wide-radius:${S.wideRadius}px;--pbtn-bg:${card.circle || 'rgba(0,0,0,.22)'};--panel-font:${loc.headlineFont};--score-weight:${loc.scoreWeight || 700}}
    ${baseCSS(loc, isHero)}
    html,body{width:${width}px;height:${height}px;margin:0;overflow:hidden;background:${bg}}
    .canvas{background:${bg}}
    .headline{${headlineCss}}
  </style></head><body><main class="canvas">${html}</main><script>
    window.addEventListener('load', () => {
      document.querySelectorAll('.headline, .slogan-text').forEach(el => {
        let size = parseFloat(getComputedStyle(el).fontSize);
        const max = parseFloat(el.dataset.max);
        while ((el.scrollHeight > max || el.scrollWidth > el.clientWidth) && size > 56) { size -= 4; el.style.fontSize = size + 'px'; }
      });
    });
  </script></body></html>`;
}

// ---------- 可视化编辑器 ----------

function buildEditor(sets) {
  const sections = sets.map(({ key, loc, cards, src, bg }) => {
    const frames = cards.map((card) => {
      const { isHero, html, headlineCss } = canvasInner(loc, card, src, bg, '');
      return `<div class="frame-wrap" style="--panel-font:${loc.headlineFont};--score-weight:${loc.scoreWeight || 700}"><div class="canvas" style="background:${bg}"><style>.frame-wrap .headline{${headlineCss}}.frame-wrap .pbtn{--pbtn-bg:${card.circle || 'rgba(0,0,0,.22)'}}</style>${html}</div></div>`;
    }).join('\n');
    return `<div class="set"><h2>${escapeHTML(key)}</h2><div class="frames">${frames}</div></div>`;
  }).join('\n');

  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>商店截图编辑器</title><style>
    ${fontFaces('fonts/')}
    :root{--stroke-width:${S.strokeWidth}px;--stroke-color:${strokeRGBA()};--card-radius:${S.cardRadius}px;--panel-radius:${S.panelRadius}px;--hero-stroke-width:${heroStrokeWidth()}px;--wide-stroke-width:${wideStrokeWidth()}px;--wide-radius:${S.wideRadius}px}
    ${baseCSS(locales[0], true)}
    body{background:#161616;color:#eee;font-family:-apple-system,"PingFang SC",sans-serif;margin:0}
    .main{padding:0 28px 60px}
    .topbar{position:sticky;top:0;z-index:6;background:#161616;margin:0 -28px 20px;padding:22px 28px 16px;border-bottom:1px solid #2c2c2c}
    h1{font-size:22px;margin:0 0 4px}
    .hint{color:#999;font-size:13px;margin:0}
    .set h2{font-size:18px;margin:26px 0 12px;color:#fff}
    .frames{display:flex;gap:26px;flex-wrap:wrap}
    .frame-wrap{width:340px;height:740px;overflow:hidden;border-radius:10px;flex:none;box-shadow:0 6px 24px #0006}
    .frame-wrap .canvas{transform:scale(0.2576);transform-origin:top left}
    .fab{position:fixed;right:18px;top:18px;z-index:11;background:#0B61FB;color:#fff;border:none;border-radius:24px;padding:10px 18px;font-size:14px;cursor:pointer;box-shadow:0 6px 20px #0008}
    .sidebar{position:fixed;right:18px;top:64px;bottom:18px;width:300px;z-index:10;background:rgba(30,30,32,.97);border-radius:14px;box-shadow:0 14px 44px #000b;padding:20px;box-sizing:border-box;overflow:auto}
    body.collapsed .sidebar{display:none}
    .sidebar h2{font-size:16px;margin:0 0 14px}
    .group{margin-bottom:24px}
    .group h3{font-size:13px;color:#aaa;margin:0 0 10px;text-transform:uppercase;letter-spacing:1px}
    .row{display:flex;align-items:center;gap:10px;margin-bottom:12px}
    .row label{width:88px;font-size:13px;color:#ccc;flex:none}
    .row input[type=range]{flex:1;accent-color:#0B61FB}
    .row input[type=color]{width:44px;height:30px;border:none;background:none;padding:0}
    .row .val{width:56px;font-size:12px;color:#888;text-align:right}
    button.action{background:#0B61FB;color:#fff;border:none;border-radius:8px;padding:10px 14px;font-size:14px;cursor:pointer;width:100%}
    button.action:hover{filter:brightness(1.1)}
    .note{font-size:12px;color:#888;margin-top:12px;line-height:1.6}
    code{background:#333;border-radius:4px;padding:1px 5px}
  </style></head><body>
  <button class="fab" id="toggle">⚙ 调节面板</button>
  <div class="main">
    <div class="topbar">
      <h1>全能计分器 · 商店截图编辑器</h1>
      <div class="hint">右侧浮动面板调节，全部方案实时生效；点「下载 settings.json」保存到本目录，再运行 <code>node render.mjs</code> 出正式 PNG。</div>
    </div>
    ${sections}
  </div>
  <div class="sidebar">
    <h2>样式调节</h2>
    <div class="group"><h3>描边</h3>
      <div class="row"><label>宽度</label><input type="range" id="strokeWidth" min="0" max="40" step="1" value="${S.strokeWidth}"><span class="val" id="strokeWidth-val">${S.strokeWidth}px</span></div>
      <div class="row"><label>颜色</label><input type="color" id="strokeColor" value="${S.strokeColor}"><span class="val" id="strokeColor-hex">${S.strokeColor}</span></div>
      <div class="row"><label>不透明度</label><input type="range" id="strokeOpacity" min="0" max="100" step="1" value="${Math.round(S.strokeOpacity * 100)}"><span class="val" id="strokeOpacity-val">${Math.round(S.strokeOpacity * 100)}%</span></div>
    </div>
    <div class="group"><h3>圆角</h3>
      <div class="row"><label>截图卡</label><input type="range" id="cardRadius" min="0" max="120" step="2" value="${S.cardRadius}"><span class="val" id="cardRadius-val">${S.cardRadius}px</span></div>
      <div class="row"><label>记分板</label><input type="range" id="panelRadius" min="0" max="120" step="2" value="${S.panelRadius}"><span class="val" id="panelRadius-val">${S.panelRadius}px</span></div>
      <div class="row"><label>横版双图</label><input type="range" id="wideRadius" min="0" max="120" step="2" value="${S.wideRadius}"><span class="val" id="wideRadius-val">${S.wideRadius}px</span></div>
    </div>
    <div class="group"><h3>分级描边倍数</h3>
      <div class="row"><label>记分板卡</label><input type="range" id="heroStrokeScale" min="1" max="1.5" step="0.05" value="${S.heroStrokeScale}"><span class="val" id="heroStrokeScale-val">${heroStrokeWidth()}px</span></div>
      <div class="row"><label>横版双图</label><input type="range" id="wideStrokeScale" min="0.5" max="1" step="0.05" value="${S.wideStrokeScale}"><span class="val" id="wideStrokeScale-val">${wideStrokeWidth()}px</span></div>
    </div>
    <button class="action" id="download">下载 settings.json</button>
    <div class="note">把下载的 settings.json 放到本目录（与 render.mjs 同级），然后在终端运行 <code>node render.mjs</code>，正式 PNG 就会应用这些参数。后续要加字体等新调节项，在这里和 DEFAULT_SETTINGS 里各加一行即可。</div>
  </div>
  <script>
    const $ = id => document.getElementById(id);
    $('toggle').onclick = () => document.body.classList.toggle('collapsed');

    function current() {
      const c = $('strokeColor').value;
      const r = parseInt(c.slice(1, 3), 16), g = parseInt(c.slice(3, 5), 16), b = parseInt(c.slice(5, 7), 16);
      return {
        strokeWidth: +$('strokeWidth').value,
        strokeColor: c,
        strokeOpacity: +$('strokeOpacity').value / 100,
        cardRadius: +$('cardRadius').value,
        panelRadius: +$('panelRadius').value,
        wideRadius: +$('wideRadius').value,
        heroStrokeScale: +$('heroStrokeScale').value,
        wideStrokeScale: +$('wideStrokeScale').value,
        _rgba: 'rgba(' + r + ',' + g + ',' + b + ',' + ($('strokeOpacity').value / 100) + ')',
      };
    }
    function refresh() {
      const v = current();
      const r = document.documentElement.style;
      r.setProperty('--stroke-width', v.strokeWidth + 'px');
      r.setProperty('--stroke-color', v._rgba);
      r.setProperty('--card-radius', v.cardRadius + 'px');
      r.setProperty('--panel-radius', v.panelRadius + 'px');
      r.setProperty('--wide-radius', v.wideRadius + 'px');
      r.setProperty('--hero-stroke-width', Math.round(v.strokeWidth * v.heroStrokeScale) + 'px');
      r.setProperty('--wide-stroke-width', Math.round(v.strokeWidth * v.wideStrokeScale) + 'px');
      $('strokeWidth-val').textContent = v.strokeWidth + 'px';
      $('strokeColor-hex').textContent = v.strokeColor;
      $('strokeOpacity-val').textContent = Math.round(v.strokeOpacity * 100) + '%';
      $('cardRadius-val').textContent = v.cardRadius + 'px';
      $('panelRadius-val').textContent = v.panelRadius + 'px';
      $('wideRadius-val').textContent = v.wideRadius + 'px';
      $('heroStrokeScale-val').textContent = Math.round(v.strokeWidth * v.heroStrokeScale) + 'px';
      $('wideStrokeScale-val').textContent = Math.round(v.strokeWidth * v.wideStrokeScale) + 'px';
    }
    ['strokeWidth','strokeColor','strokeOpacity','cardRadius','panelRadius','wideRadius','heroStrokeScale','wideStrokeScale'].forEach(id => $(id).addEventListener('input', refresh));
    $('download').onclick = () => {
      const v = current(); delete v._rgba;
      const blob = new Blob([JSON.stringify(v, null, 2)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'settings.json'; a.click();
    };
  </script></body></html>`;
}

// ---------- 渲染 ----------

const rendered = [];

for (const loc of locales) {
  const src = makeSources(loc.code);
  const missing = [];
  const cards = [];
  for (const card of loc.cards) {
    let imgs = [card.image];
    if (card.layout === 'double') imgs = [card.image, card.secondary];
    else if (card.layout === 'hero' || card.layout === 'slogan') imgs = [];
    else if (card.layout === 'collage') imgs = card.tiles || DEFAULT_TILES;
    if (imgs.every(i => src.has(i))) cards.push(card);
    else missing.push(card.id + '(' + imgs.filter(i => !src.has(i)).join(', ') + ')');
  }
  if (missing.length) console.log(`[${loc.code}] 跳过缺源图: ${missing.join(', ')}`);
  const dir = path.join(root, loc.code);
  fs.mkdirSync(dir, { recursive: true });
  for (const [index, card] of cards.entries()) {
    const name = String(index + 1).padStart(2, '0');
    const htmlFile = path.join(dir, name + '.html');
    const pngFile = path.join(dir, name + '.png');
    fs.writeFileSync(htmlFile, page(loc, card, index, cards.length, src, PAGE_BG));
    execFileSync(chrome, [
      '--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking',
      '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + height,
      '--virtual-time-budget=6000',
      '--screenshot=' + pngFile, 'file://' + htmlFile,
    ], { stdio: 'ignore' });
    console.log(path.relative(root, pngFile));
  }
  rendered.push({ key: loc.code, loc, cards, src, bg: PAGE_BG });
  // 用了共享目录（简体中文 UI）的源图 = 该语言包里混了中文画面
  if (loc.code !== 'zh-Hans' && src.fallback.size) {
    console.log(`[${loc.code}] 仍来自共享 sources/（中文画面）: ${[...src.fallback].join(', ')}`);
  }
}

// 第 5 张拼贴的备选排版 + 投屏卡握持备选(评审用,文件名 -B/-C 后缀,不进商店编号)
for (const r of rendered) {
  const collageCard = r.cards.find(c => c.layout === 'collage');
  if (collageCard) for (const [name, override] of Object.entries(COLLAGE_VARIANTS)) {
    const variantCard = { ...collageCard, collage: { ...(collageCard.collage || {}), ...override } };
    const htmlFile = path.join(root, r.key, 'card5-' + name + '.html');
    const pngFile = path.join(root, r.key, 'card5-' + name + '.png');
    fs.writeFileSync(htmlFile, page(r.loc, variantCard, 4, r.cards.length, r.src, r.bg));
    execFileSync(chrome, [
      '--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking',
      '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + height,
      '--virtual-time-budget=6000',
      '--screenshot=' + pngFile, 'file://' + htmlFile,
    ], { stdio: 'ignore' });
    console.log(path.relative(root, pngFile));
  }
  const castCard = r.cards.find(c => c.layout === 'cast');
  if (castCard) {
    const variantCard = { ...castCard, hand: true };
    const htmlFile = path.join(root, r.key, 'cast-B.html');
    const pngFile = path.join(root, r.key, 'cast-B.png');
    fs.writeFileSync(htmlFile, page(r.loc, variantCard, r.cards.indexOf(castCard), r.cards.length, r.src, r.bg));
    execFileSync(chrome, [
      '--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking',
      '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + height,
      '--virtual-time-budget=6000',
      '--screenshot=' + pngFile, 'file://' + htmlFile,
    ], { stdio: 'ignore' });
    console.log(path.relative(root, pngFile));
  }
}

fs.writeFileSync(path.join(root, 'editor.html'), buildEditor(rendered));

const tiles = rendered.map(({ key, cards }) =>
  '<section><h2>' + escapeHTML(key) + '</h2><div class="row">' +
  cards.map((card, index) => {
    const name = String(index + 1).padStart(2, '0');
    return '<a href="' + key + '/' + name + '.png"><img loading="lazy" src="' + key + '/' + name + '.png"><span>' + escapeHTML(card.title.replace('\n', ' ')) + '</span></a>';
  }).join('') + '</div></section>'
).join('');
fs.writeFileSync(path.join(root, 'preview.html'), '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>App Store 截图 · 多语言双版本</title><style>body{margin:0;padding:48px;background:#1a1a1a;color:#eee;font-family:"PingFang SC",sans-serif}h1{font-size:36px}h2{margin-top:50px;font-size:24px}.row{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}a{color:inherit;text-decoration:none}img{width:100%;border-radius:14px;box-shadow:0 8px 30px #0008}span{display:block;margin-top:12px;font-size:15px;font-weight:700}</style><h1>全能计分器 · 多语言商店截图（蓝 / 黑双版本）</h1>' + tiles + '</html>');
console.log('editor.html + preview.html 已更新');
