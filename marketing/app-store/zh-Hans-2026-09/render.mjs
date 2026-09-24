import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const width = 1320;
const height = 2868;

const sets = [
  {
    id: 'A-score-first',
    className: 'dark',
    cards: [
      { title: '每一分，\n都看得清。', sub: '乒乓球 · 羽毛球 · 篮球', image: 'pingpong_live.png', layout: 'phone' },
      { title: '常打的运动，\n一键开赛。', sub: '打开首页，选好项目就开始', image: 'home.png', layout: 'phone' },
      { title: '设好赛制，\n开球就记。', sub: '单打双打，赛前轻松设置', image: 'badminton_setup.png', layout: 'phone' },
      { title: '球场记分，\n棋局计时。', sub: '不同比赛，各有顺手的工具', image: 'basketball.png', secondary: 'go_timer.png', firstCaption: '篮球计分', secondCaption: '棋类计时', layout: 'double' },
      { title: '打完这一场，\n记录接着看。', sub: '从比分到每局过程，随时回看', image: 'record_detail.png', layout: 'phone' },
    ],
  },
  {
    id: 'B-start-first',
    className: 'light',
    cards: [
      { title: '开打吧，\n比分我来记。', sub: '常打项目，一点就开赛', image: 'home.png', layout: 'phone' },
      { title: '比分够大，\n全场都清楚。', sub: '每一次得分，都醒目呈现', image: 'pingpong_live.png', layout: 'phone' },
      { title: '想打哪场，\n都找得到。', sub: '球赛、棋局、桌游，随手切换', image: 'sports.png', layout: 'phone' },
      { title: '球赛能计分，\n棋局能计时。', sub: '计分与计时，随场景切换', image: 'basketball.png', secondary: 'go_timer.png', firstCaption: '篮球计分', secondCaption: '棋类计时', layout: 'double' },
      { title: '赛后回看，\n精彩有迹可循。', sub: '比分过程和比赛记录，随时翻看', image: 'record_detail.png', layout: 'phone' },
    ],
  },
];

function escapeHTML(s) {
  return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

function visual(card) {
  if (card.layout === 'double') {
    return '<div class="wide wide-one"><img src="../sources/' + card.image + '"></div>' +
      '<div class="wide-caption">' + escapeHTML(card.firstCaption) + '</div>' +
      '<div class="wide wide-two"><img src="../sources/' + card.secondary + '"></div>' +
      '<div class="wide-caption second">' + escapeHTML(card.secondCaption) + '</div>';
  }
  return '<div class="device"><img src="../sources/' + card.image + '"></div>';
}

function page(set, card, index) {
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=${width},initial-scale=1"><style>
    *{box-sizing:border-box}html,body{width:${width}px;height:${height}px;margin:0;overflow:hidden}
    body{font-family:"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif}
    .canvas{position:relative;width:${width}px;height:${height}px;overflow:hidden}
    .dark{background:#0c1728;color:#fff;--accent:#baf34e;--muted:#c9d5e1;--frame:#d8e3ef}
    .light{background:#f4f3ed;color:#10222a;--accent:#ff6b36;--muted:#40505b;--frame:#10222a}
    .disc{position:absolute;right:-330px;top:-370px;width:900px;height:900px;border-radius:50%;background:var(--accent);opacity:.11}
    .light .disc{opacity:.15}.rule{position:absolute;left:84px;top:118px;width:70px;height:12px;border-radius:8px;background:var(--accent)}
    .eyebrow{position:absolute;left:176px;top:98px;font-size:43px;font-weight:650;letter-spacing:2px}
    .headline{position:absolute;left:82px;top:260px;width:1160px;white-space:pre-line;font-size:145px;font-weight:800;line-height:1.18;letter-spacing:-5px}
    .sub{position:absolute;left:92px;top:670px;font-size:48px;font-weight:550;color:var(--muted)}
    .light .headline{font-weight:800}.light .sub{font-weight:600}
    .device{position:absolute;left:143px;top:875px;width:1034px;height:2250px;padding:19px;border:16px solid var(--frame);border-radius:112px;background:var(--frame);box-shadow:0 45px 85px rgba(0,0,0,.23);overflow:hidden}
    .device img{display:block;width:100%;height:100%;object-fit:cover;object-position:top;border-radius:75px}
    .light .device{box-shadow:0 42px 82px rgba(16,34,42,.17)}
    .wide{position:absolute;left:56px;width:1208px;padding:12px;border:12px solid var(--frame);border-radius:46px;background:var(--frame);box-shadow:0 32px 55px rgba(0,0,0,.18);overflow:hidden}
    .wide img{display:block;width:100%;height:auto;border-radius:22px}
    .wide-one{top:955px}.wide-two{top:1855px}
    .wide-caption{position:absolute;left:92px;top:1635px;font-size:68px;font-weight:750;color:var(--accent)}
    .wide-caption.second{top:2530px}
    .light .wide{box-shadow:0 25px 50px rgba(16,34,42,.13)}
    .index{position:absolute;right:84px;top:106px;font-size:36px;font-weight:700;letter-spacing:3px;color:var(--muted)}
  </style></head><body><main class="canvas ${set.className}"><div class="disc"></div><div class="rule"></div><div class="eyebrow">全能计分器</div><div class="index">${String(index + 1).padStart(2, '0')} / 05</div><div class="headline">${escapeHTML(card.title)}</div><div class="sub">${escapeHTML(card.sub)}</div>${visual(card)}</main></body></html>`;
}

for (const set of sets) {
  const dir = path.join(root, set.id);
  fs.mkdirSync(dir, { recursive: true });
  for (const [index, card] of set.cards.entries()) {
    const name = String(index + 1).padStart(2, '0');
    const htmlFile = path.join(dir, name + '.html');
    const pngFile = path.join(dir, name + '.png');
    fs.writeFileSync(htmlFile, page(set, card, index));
    execFileSync(chrome, [
      '--headless=new', '--no-first-run', '--disable-extensions', '--disable-background-networking',
      '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + height,
      '--screenshot=' + pngFile, 'file://' + htmlFile,
    ], { stdio: 'ignore' });
    console.log(path.relative(root, pngFile));
  }
}

const tiles = sets.map(set =>
  '<section><h2>' + set.id + '</h2><div class="row">' +
  set.cards.map((card, index) => {
    const name = String(index + 1).padStart(2, '0');
    return '<a href="' + set.id + '/' + name + '.png"><img src="' + set.id + '/' + name + '.png"><span>' + escapeHTML(card.title.replace('\n', '')) + '</span></a>';
  }).join('') + '</div></section>'
).join('');
fs.writeFileSync(path.join(root, 'preview.html'), '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>全能计分器 App Store 截图方案</title><style>body{margin:0;padding:48px;background:#e8e9e8;color:#12202c;font-family:"PingFang SC",sans-serif}h1{font-size:36px}h2{margin-top:50px}.row{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:16px}a{color:inherit;text-decoration:none}img{width:100%;border-radius:14px;box-shadow:0 8px 30px #0002}span{display:block;margin-top:12px;font-size:16px;font-weight:700}</style><h1>全能计分器 · 简体中文商店截图</h1>' + tiles + '</html>');
