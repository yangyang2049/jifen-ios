import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// A document-only build. Override MARKED_MODULE if rebuilding outside Codex.
const here = path.dirname(fileURLToPath(import.meta.url));
const markedModule = process.env.MARKED_MODULE || '/Users/yangyang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/marked/lib/marked.esm.js';
const { marked } = await import(pathToFileURL(markedModule).href);
const esc = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const specs = JSON.parse(await fs.readFile(path.join(here,'diagrams/diagrams.json'),'utf8'));
const figures = new Map();
const figureChecks=[];
function visualWidth(s,size){return [...s].reduce((n,c)=>n+(/[\u2e80-\uffff]/u.test(c)?size:size*.57),0);}
function label(text,x,y,id){ const width=visualWidth(text,14)+16; return `<g><rect x="${x-width/2}" y="${y-17}" width="${width}" height="23" rx="4" fill="#fff"/><text x="${x}" y="${y}" text-anchor="middle" class="edge-label">${esc(text)}</text></g>`; }
function wrap(text, maxWidth,size){const lines=[];let line='';for(const c of text){if(visualWidth(line+c,size)>maxWidth&&line){lines.push(line);line='';}line+=c;}if(line)lines.push(line);return lines;}
function svgStart(d){return `<svg xmlns="http://www.w3.org/2000/svg" width="${d.width}" height="${d.height}" viewBox="0 0 ${d.width} ${d.height}" role="img" aria-labelledby="${d.id}-title"><title id="${d.id}-title">${esc(d.title)}</title><defs><marker id="${d.id}-arrow" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto-start-reverse"><path d="M0 0 L9 4.5 L0 9Z" fill="#536878"/></marker><marker id="${d.id}-amber" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0 0 L9 4.5 L0 9Z" fill="#a16b23"/></marker></defs><style>text{font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif;fill:#23323e}.diagram-title{font-size:22px;font-weight:600}.node-title{font-size:17px;font-weight:600}.node-body{font-size:15px}.edge-label{font-size:14px;fill:#4b5c69}.footer{font-size:14px;fill:#5b6a75}</style><rect width="100%" height="100%" fill="#fff"/><text x="35" y="32" class="diagram-title">${esc(d.title)}</text>`;}
function renderFlow(d){
  let svg=svgStart(d);
  const labels=[];
  for(const edge of d.edges||[]){
    for(const [x,y] of edge.points)if(x<0||x>d.width||y<0||y>d.height)throw new Error(`Edge outside ${d.id}`);
    const color=edge.style==='warning'?'#a16b23':'#536878';
    svg+=`<polyline points="${edge.points.map(p=>p.join(',')).join(' ')}" fill="none" stroke="${color}" stroke-width="1.7" stroke-linejoin="round" ${edge.style==='future'?'stroke-dasharray="6 5"':''} marker-end="url(#${d.id}-${edge.style==='warning'?'amber':'arrow'})"/>`;
    if(edge.label)labels.push(label(edge.label,edge.lx,edge.ly,d.id));
  }
  for(const node of d.nodes){
    if(node.x<0||node.y<45||node.x+node.w>d.width||node.y+node.h>d.height-55)throw new Error(`Node outside ${d.id}/${node.id}`);
    const body=node.lines.flatMap(line=>wrap(line,node.w-34,15));
    const title=wrap(node.title,node.w-34,17);
    const need=29+(title.length-1)*24+(body.length?35+(body.length-1)*23:0)+16;
    if(need>node.h)throw new Error(`Text too tall ${d.id}/${node.id}: needs ${need}, has ${node.h}`);
    const fill=node.style==='accent'?'#edf7ef':node.style==='warning'?'#fcf5e9':node.style==='future'?'#f0f3f6':'#f7f9fa';
    const stroke=node.style==='accent'?'#9fc9a9':node.style==='warning'?'#d9bb8f':'#ccd6dd';
    svg+=`<g id="${d.id}-${node.id}"><rect x="${node.x}" y="${node.y}" width="${node.w}" height="${node.h}" rx="11" fill="${fill}" stroke="${stroke}" ${node.style==='future'?'stroke-dasharray="5 4"':''}/>`;
    title.forEach((line,i)=>svg+=`<text class="node-title" x="${node.x+17}" y="${node.y+29+i*24}">${esc(line)}</text>`);
    const bodyY=node.y+29+(title.length-1)*24+35;
    body.forEach((line,i)=>svg+=`<text class="node-body" x="${node.x+17}" y="${bodyY+i*23}">${esc(line)}</text>`);
    svg+='</g>';
  }
  svg+=labels.join('');
  for(const [i,line] of wrap(d.footer,d.width-70,14).entries())svg+=`<text class="footer" x="35" y="${d.height-30+i*19}">${esc(line)}</text>`;
  return svg+'</svg>';
}
function renderSequence(d){
  let svg=svgStart(d);const xs=[140,460,780,1100], top=115, step=54;
  d.actors.forEach((actor,i)=>{svg+=`<rect x="${xs[i]-105}" y="58" width="210" height="42" rx="8" fill="${i===2?'#edf7ef':'#f3f6f8'}" stroke="#c9d5dd"/><text class="node-title" x="${xs[i]}" y="85" text-anchor="middle">${esc(actor)}</text><line x1="${xs[i]}" y1="103" x2="${xs[i]}" y2="${d.height-75}" stroke="#b8c6ce" stroke-dasharray="5 5"/>`;});
  svg+=`<rect x="660" y="${top+8*step-21}" width="570" height="${step*2+39}" rx="8" fill="#edf7ef" fill-opacity=".7" stroke="#b3d3bc"/>`;
  d.messages.forEach((m,i)=>{const y=top+i*step+27;svg+=`<line x1="${xs[m.from]}" y1="${y}" x2="${xs[m.to]}" y2="${y}" stroke="#536878" stroke-width="1.6" ${m.return?'stroke-dasharray="5 4"':''} marker-end="url(#${d.id}-arrow)"/>`;svg+=label(`${i+1}. ${m.text}`,(xs[m.from]+xs[m.to])/2,y-12,d.id);});
  svg+=`<text x="35" y="${d.height-27}" class="footer">${esc(d.footer)}</text></svg>`;return svg;
}
for(const d of specs){const svg=d.type==='sequence'?renderSequence(d):renderFlow(d);await fs.writeFile(path.join(here,'diagrams',`${d.id}.svg`),svg);figures.set(`diagrams/${d.id}.svg`,{svg,title:d.title,id:d.id});figureChecks.push({id:d.id,width:d.width,height:d.height,nodes:d.nodes?.length||d.actors.length});}

const toc=[];
function documentSection(markdown,prefix){
  let html=marked.parse(markdown,{gfm:true,breaks:false});
  let headingCounter=0;
  html=html.replace(/<h([123])>([\s\S]*?)<\/h\1>/g,(_,level,body)=>{
    const text=body.replace(/<[^>]+>/g,'');const part=text.match(/^([PT]\d+)\./)?.[1]?.toLowerCase();const id=part||(level==='1'?`${prefix}-title`:`${prefix}-heading-${++headingCounter}`);
    if(level==='2')toc.push({id,text,prefix});return `<h${level} id="${id}">${body}</h${level}>`;
  });
  html=html.replace(/<p><img src="([^"]+)" alt="([^"]*)"><\/p>/g,(_,src,alt)=>{
    const f=figures.get(src);if(!f)throw new Error(`Missing figure ${src}`);
    return `<figure id="figure-${f.id}" data-figure="${f.id}"><figcaption><span>${alt}</span><button type="button" class="zoom-button" aria-label="放大${alt}">放大查看</button></figcaption><div class="diagram-body">${f.svg}</div></figure>`;
  });
  html=html.replace(/<table>/g,'<div class="table-wrap"><table>').replace(/<\/table>/g,'</table></div>');
  return `<article aria-label="${prefix==='prd'?'产品需求':'技术方案'}">${html}</article>`;
}
const prd=await fs.readFile(path.join(here,'PRD.md'),'utf8');const technical=await fs.readFile(path.join(here,'TECHNICAL-DESIGN.md'),'utf8');
const body=documentSection(prd,'prd')+documentSection(technical,'tech');
const nav=prefix=>toc.filter(t=>t.prefix===prefix).map(t=>`<a href="#${t.id}">${esc(t.text)}</a>`).join('');
const optionNav=toc.map(t=>`<option value="${t.id}">${esc(t.text)}</option>`).join('');
const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>独立队伍、队员与云协作 · PRD 与技术方案</title><meta name="description" content="全能计分器独立队伍、离线阵容、云协作、邀请认领与篮球统计的产品需求和技术方案，含十张架构与流程图。"><style>
:root{color-scheme:light;--page:#f4f6f5;--paper:#fff;--ink:#202e28;--sub:#627168;--line:#dce4de;--green:#2c7142;--soft:#eaf3ed;--code:#f2f5f3}*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:28px}body{margin:0;background:var(--page);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif;font-size:15px;line-height:1.85}a{color:var(--green);text-decoration:none}a:hover{text-decoration:underline}button,select{font:inherit}button{cursor:pointer}button:focus-visible,a:focus-visible,select:focus-visible{outline:3px solid #76aa88;outline-offset:3px}.masthead{max-width:1450px;margin:auto;padding:54px 44px 34px}.eyebrow{font-size:12px;letter-spacing:.14em;color:var(--green);font-weight:600}.masthead h1{font-size:42px;line-height:1.3;letter-spacing:-.04em;font-weight:600;margin:13px 0 14px}.masthead p{color:var(--sub);margin:0;max-width:850px}.meta{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-top:22px;color:var(--sub);font-size:12px}.badge{background:var(--soft);color:var(--green);padding:3px 10px;border-radius:5px}.top-actions{display:flex;flex-wrap:wrap;gap:20px;align-items:center;margin-top:24px}.quiet{border:1px solid var(--line);background:var(--paper);color:var(--ink);padding:6px 14px;border-radius:7px}.layout{display:grid;grid-template-columns:245px minmax(0,1fr);gap:30px;max-width:1450px;margin:auto;padding:0 34px 70px}.toc{position:sticky;top:20px;align-self:start;max-height:calc(100vh - 40px);overflow:auto;padding:6px 12px 20px 5px}.toc h2{font-size:12px;color:var(--sub);margin:18px 9px 9px;letter-spacing:.05em}.toc a{display:block;color:var(--sub);font-size:12px;line-height:1.65;padding:6px 9px;border-left:2px solid transparent}.toc a:hover,.toc a.active{color:var(--green);border-left-color:var(--green);background:var(--soft);text-decoration:none}.document{background:var(--paper);border:1px solid var(--line);border-radius:13px;padding:38px 44px;min-width:0;box-shadow:0 12px 40px #20332606}article+article{border-top:3px solid var(--line);padding-top:34px;margin-top:62px}article h1{font-size:29px;line-height:1.45;letter-spacing:-.025em;margin:0 0 20px;font-weight:600}article h2{font-size:22px;line-height:1.45;margin:46px 0 16px;padding-bottom:12px;border-bottom:1px solid var(--line);font-weight:600}article h3{font-size:17px;line-height:1.5;margin:26px 0 10px;font-weight:600}p{margin:13px 0}ul,ol{padding-left:24px;margin:13px 0}li+li{margin-top:6px}strong{font-weight:600}blockquote{border-left:3px solid #81ae8b;background:var(--soft);margin:22px 0;padding:12px 18px;color:#345541}blockquote p{margin:0}.table-wrap{overflow:auto;margin:20px 0 24px}table{width:100%;border-collapse:collapse;font-size:13px;line-height:1.75;min-width:590px}th{text-align:left;background:var(--soft);color:#314f3b;font-weight:600}th,td{padding:10px 13px;border:1px solid var(--line);vertical-align:top}tr:nth-child(even) td{background:#fafcfb}code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.87em;padding:2px 4px;border-radius:4px;background:var(--code);overflow-wrap:anywhere}pre{padding:18px 20px;background:var(--code);border-radius:8px;overflow:auto;font-size:13px;line-height:1.6}pre code{padding:0;background:none;overflow-wrap:normal}figure{margin:26px 0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:#fff}figcaption{display:flex;align-items:center;justify-content:space-between;gap:15px;background:#f7faf8;padding:11px 15px;font-size:12px;color:#56665b}.zoom-button{background:none;border:0;padding:4px;color:var(--green);font-size:12px;white-space:nowrap;min-height:30px}.diagram-body{overflow:auto;background:#fff}.diagram-body svg{display:block;width:100%;min-width:850px;height:auto}.mobile-toc{display:none}dialog{padding:0;max-width:96vw;width:1500px;max-height:94vh;border:1px solid var(--line);border-radius:12px;color:var(--ink);background:var(--paper)}dialog::backdrop{background:#15241bcc}.dialog-header{position:sticky;top:0;display:flex;justify-content:space-between;align-items:center;padding:12px 18px;background:var(--paper);border-bottom:1px solid var(--line);gap:20px;z-index:1}.dialog-body{overflow:auto;max-height:calc(94vh - 70px);background:#fff}.dialog-body svg{display:block;width:100%;min-width:1100px;height:auto}.bottom-note{font-size:12px;color:var(--sub);padding-top:30px;border-top:1px solid var(--line);margin-top:50px}.muted{color:var(--sub)}
@media(max-width:1000px){.layout{grid-template-columns:200px minmax(0,1fr);gap:16px;padding:0 18px 50px}.document{padding:28px 24px}.masthead{padding:36px 30px 26px}.masthead h1{font-size:34px}.toc a{font-size:11px}}
@media(max-width:730px){body{font-size:14px}.masthead{padding:27px 20px 22px}.masthead h1{font-size:28px;letter-spacing:-.025em}.masthead p{font-size:13px}.meta{font-size:11px}.layout{display:block;padding:0 10px 34px}.toc{display:none}.document{padding:24px 17px;border-radius:10px}article h1{font-size:23px}article h2{font-size:19px;margin-top:34px}article h3{font-size:16px}.mobile-toc{display:block;margin:0 10px 16px;padding:11px 13px;background:var(--paper);border:1px solid var(--line);border-radius:8px}.mobile-toc label{display:block;font-size:12px;color:var(--sub);margin-bottom:6px}.mobile-toc select{width:100%;padding:8px 6px;background:var(--paper);color:var(--ink);border:1px solid var(--line);border-radius:6px;font-size:14px}.top-actions{gap:16px;font-size:13px}figcaption{font-size:11px;padding:9px 10px}.zoom-button{font-size:11px}pre{padding:14px;font-size:11px}table{font-size:12px}.dialog-header{font-size:13px}}
@media print{body{background:#fff;color:#111;font-size:10.5pt}.masthead{padding:0 0 20px}.masthead h1{font-size:25pt}.layout{display:block;padding:0}.toc,.mobile-toc,.top-actions,.zoom-button,dialog{display:none!important}.document{border:0;box-shadow:none;padding:0}.diagram-body{overflow:visible}.diagram-body svg{min-width:0;width:100%;max-height:24cm}.table-wrap{overflow:visible}table{min-width:0;font-size:9pt}thead{display:table-header-group}tr,figure{break-inside:avoid}article h2{break-after:avoid}a{color:inherit}pre{white-space:pre-wrap}article+article{break-before:page}p,li{orphans:3;widows:3}.meta .badge{border:1px solid #aaa}}
</style></head><body>
<header class="masthead"><div class="eyebrow">全能计分器 · 产品与技术评审</div><h1>独立队伍、队员与云协作</h1><p>从本机阵容到云端邀请，把队伍、小组、本人身份和比赛统计的边界一次讲清。</p><div class="meta"><span class="badge">待评审 · 未实施</span><span>版本 0.1</span><span>2026.10.24</span><span>PRD + 技术方案 · 10 张图</span></div><div class="top-actions"><a href="#p01">产品需求</a><a href="#t01">技术方案</a><a href="#p12">验收用例</a><button class="quiet" type="button" id="print-document">打印／保存 PDF</button></div></header>
<div class="mobile-toc"><label for="section-picker">跳转章节</label><select id="section-picker"><option value="">选择章节</option>${optionNav}</select></div>
<div class="layout"><nav class="toc" aria-label="文档目录"><h2>产品需求</h2>${nav('prd')}<h2>技术设计</h2>${nav('tech')}</nav><main class="document">${body}<footer class="bottom-note">文档仅描述设计提案与本地源码核对结果，不代表功能已上线。两份 Markdown 与本 HTML 由相同源生成；所有图已内嵌，阅读无需联网。</footer></main></div>
<dialog id="figure-dialog" aria-labelledby="figure-dialog-title"><div class="dialog-header"><strong id="figure-dialog-title">图形详情</strong><button class="quiet" type="button" id="close-figure">关闭</button></div><div class="dialog-body" id="figure-dialog-body"></div></dialog>
<script>
(()=>{const dialog=document.getElementById('figure-dialog');document.querySelectorAll('.zoom-button').forEach(button=>button.addEventListener('click',()=>{const figure=button.closest('figure');const original=figure.querySelector('svg');document.getElementById('figure-dialog-title').textContent=original.querySelector('title').textContent;document.getElementById('figure-dialog-body').innerHTML=original.outerHTML.replaceAll(figure.dataset.figure+'-','zoom-'+figure.dataset.figure+'-');dialog.showModal();}));document.getElementById('close-figure').onclick=()=>dialog.close();dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close();});document.getElementById('print-document').onclick=()=>window.print();document.getElementById('section-picker').onchange=event=>{if(event.target.value)document.getElementById(event.target.value)?.scrollIntoView({behavior:'smooth'});};if('IntersectionObserver' in window){const observer=new IntersectionObserver(entries=>{const visible=entries.filter(entry=>entry.isIntersecting);if(!visible.length)return;const id=visible[0].target.id;document.querySelectorAll('.toc a').forEach(link=>link.classList.toggle('active',link.getAttribute('href')==='#'+id));},{rootMargin:'-10% 0px -75% 0px'});document.querySelectorAll('article h2').forEach(heading=>observer.observe(heading));}})();
</script></body></html>`;
await fs.writeFile(path.join(here,'index.html'),html);
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
const duplicates=ids.filter((id,i)=>ids.indexOf(id)!==i);if(duplicates.length)throw new Error(`Duplicate HTML ids: ${duplicates.join(',')}`);
for(const t of toc)if(!ids.includes(t.id))throw new Error(`Broken TOC ${t.id}`);
const external=[...html.matchAll(/<(?:script|link|img)\b[^>]*(?:src|href)="https?:/g)];if(external.length)throw new Error('HTML must be readable offline');
const check={generatedAt:'2026-10-24',documentStatus:'proposal_not_implemented',markdownFiles:['PRD.md','TECHNICAL-DESIGN.md'],sections:toc.length,figures:figureChecks,uniqueHtmlIds:ids.length,checks:{allFigureTextFits:true,allDiagramBoundsValid:true,tocTargetsValid:true,offlineResourcesOnly:true,duplicateIds:false},browserChecks:'pending'};
await fs.writeFile(path.join(here,'verification.json'),JSON.stringify(check,null,2)+'\n');
console.log(`Generated index.html: ${toc.length} sections, ${figures.size} embedded diagrams, ${Math.round(Buffer.byteLength(html)/1024)} KiB. Bounds, IDs and offline-resource checks passed.`);
