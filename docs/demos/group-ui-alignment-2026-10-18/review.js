/* Local review artifact. No API calls or application state changes. */
(() => {
  'use strict';
  const D = window.REVIEW_DATA;
  const S = window.REVIEW_SOURCES;
  const $ = (s) => document.querySelector(s);
  const esc = (v = '') => String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const state = {view:new URLSearchParams(location.search).get('view')==='preview'?'preview':'audit', scene:'create-group', query:'', reference:'', platform:'全部', dark:false, large:false, compact:false, preview:new URLSearchParams(location.search).get('scene')||'result', picker:null, rules:false, details:false, memberQuery:'', recordTab:'比赛记录', recordLayout:'分段', sheetOrigin:null};
  const drafts = {};
  const people = ['杨扬','林启','陈一鸣','周可欣','刘思远','王明','赵婧','张晓'];
  let toastTimer;
  function toast(message) {
    $('#toast').textContent = message;
    $('#toast').classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 3000);
  }
  function page(id) { return D.pages.find(p => p.id === id); }
  function source(s) { return `<span class="source"><code>${esc(s)}</code></span>`; }
  function metrics() {
    return `<div class="metrics"><div class="metric"><strong>30</strong><span>页面 / 流程清单</span></div><div class="metric"><strong>27</strong><span>改造前 sheet 调用点</span></div><div class="metric"><strong>13</strong><span>改造前系统 Form</span></div><div class="metric"><strong>${S.sources.length}</strong><span>原 HTML 的来源副本</span></div></div>`;
  }
  function sceneNavigation() {
    const q = state.query.toLocaleLowerCase();
    return D.groups.map(g => {
      const pages = D.pages.filter(p => p.group === g && (!q || JSON.stringify(p).toLocaleLowerCase().includes(q)));
      return pages.length ? `<div class="nav-group">${esc(g)}</div>${pages.map(p => `<button data-scene="${p.id}" class="${p.id === state.scene ? 'active' : ''}"><span>${esc(p.name)}</span><small>${esc(p.priority)}</small></button>`).join('')}` : '';
    }).join('') || '<p class="empty">没有匹配的页面</p>';
  }
  function audit() {
    const p = page(state.scene);
    return `<div class="intro-note"><strong>以下保留改造前清单；v3 实施结果见页面预览与本轮原生截图。</strong><br>创建和加入成功后，还会在原 sheet 里替换为组详情；这会让之后的整组浏览继续留在 modal 容器。优先修这一条导航链，再统一表单。</div>${metrics()}
      <div class="audit-layout"><aside class="sidebar"><label class="sr-only" for="page-search">搜索页面或控件</label><input class="search" id="page-search" placeholder="搜索页面、Form、排赛…" value="${esc(state.query)}"><nav class="scene-nav" aria-label="小组页面">${sceneNavigation()}</nav></aside>
      <article class="detail"><div class="crumb">小组 / ${esc(p.group)}</div><div class="detail-head"><h2>${esc(p.name)}</h2><span class="badge ${p.action === '保留主体' ? 'tag-keep' : 'tag-change'}">${esc(p.action)}</span><span class="badge">${esc(p.priority)}</span></div><p class="detail-sub">逐项比较当前代码；“建议”尚未实施到 App。</p>
      <section class="panel"><table class="comparison"><tbody>
        <tr><th>iOS 现状</th><td>${esc(p.current)}${source(p.source)}${p.entry ? source('入口：' + p.entry) : ''}</td></tr>
        <tr><th>Android</th><td>${esc(p.android)}${source(p.androidSource)}</td></tr>
        <tr><th>鸿蒙</th><td>${esc(p.harmony)}${source(p.harmonySource)}</td></tr>
        <tr class="recommend"><th>建议</th><td>${esc(p.target)}</td></tr>
      </tbody></table></section>
      <section class="panel"><h3>迁移时要保住的行为</h3><ul class="mini-list">${p.checks.map(s => `<li>${esc(s)}</li>`).join('')}</ul><div class="actions">${p.preview ? `<button class="button green" data-open-preview="${p.preview}">查看对应页面预览 →</button>` : ''}<button class="button" data-view="references">查看原有 HTML</button></div></section>
      <div class="panel"><h3>当前清单的边界</h3><p>27 是 <code>.sheet</code> 调用点，不是 27 个不同页面：熟人组业务 15、内层规则/地点选择 4、登录/扫码 4、顺延预览 1、训练兼容 3。全部 15 个系统 Form 中，13 个可用于熟人组，2 个为训练专属。</p><p class="frame-note">四个主 tab 目前没有真正的第二层页签；单双打是榜单筛选，活动当前/历史及成员类型属于内容分段。训练不加入本轮；存量 coaching 的兼容路径仍存在。</p></div></article></div>`;
  }
  const referenceNotes = [
    ['forms-review','提取字段结构、浅底输入和选项；其“活动/编辑资料用弹窗”已落后于当前独立页。'],
    ['activity-sheet','提取更多菜单和批量报名布局；sheet 容器与“当前立即提交”的旧注释不作为现状。'],
    ['tabs-redesign','参考四 tab 信息架构；顶部三按钮已被后续底栏方案替代，训练不纳入本轮。'],
    ['overview-actions','参考 D 方案：邀请留身份卡，开始计分与补记固定底部。已包含二维码脚本和背景图。'],
    ['player-selection','提取内联名单与完整姓名；业务合法性以当前模型为准。'],
    ['score-selection','提取合法比分直选、手动及逐局展开；不从演示数据反推赛制契约。'],
    ['direct-scheduling','排赛优先参考：直接排赛归活动、顺序/预计时间、轻量场次卡。'],
    ['approval-row','参考 D 两段式完整留言和等宽审批动作；Android 当前已实现。'],
    ['member-list','参考分组名单、头像后缩进分割线；不为普通成员重复标角色。'],
    ['records-empty','提取无排行时的空态；不引入新的客户端成榜门槛。'],
    ['rules-panel','提取规则选项即点即生效；当前 Android 已去掉冗余完成按钮。'],
    ['pending-results','多种作废入口的探索；当前作废应在详情降级处理，不照搬默认候选。'],
    ['registration-layout','可复用的卡片细节：状态与人数同行、日期地点第二行，以及字号/窄屏压力预览。'],
    ['result-detail','可复用的摘要到独立详情分层；信息与操作分区，正常赛果不重复已确认。'],
    ['system-review','历史综合方案。iOS 与鸿蒙此文件内容相同；大量 sheet、训练、轮转、联赛等不作为本轮目标。鸿蒙原稿的 README 文档链接已失效，副本保留原状。'],
    ['system-complete','早期综合流程；轮转/联赛等属于历史产品探索，不代表当前实现。'],
    ['feature-','早期视觉/功能探索，优先级低于后续专项稿与当前实现。']
  ];
  function refNote(r) { return referenceNotes.find(([k]) => r.file.includes(k))?.[1] || '专项候选方案；采用情况请对照逐页分析及当前实现，不能把默认选项视为已确定要求。'; }
  function references() {
    const list = S.sources.filter(r => state.platform === '全部' || r.platform === state.platform);
    let r = list.find(r => r.id === state.reference) || list.find(r => r.file.includes('forms-review')) || list[0];
    state.reference = r.id;
    return `<div class="intro-note"><strong>把原 HTML 放在同一个评审包里，保留原文件内容和依赖。</strong><br>每份可直接操作，也可单独打开。历史综合稿与后来的专项稿分开标注；原稿的剪贴板等系统操作请单独打开体验。</div><div class="reference-layout"><aside><label class="sr-only" for="platform">原型平台</label><select id="platform" class="search">${['全部','Android','鸿蒙','iOS'].map(x => `<option ${x === state.platform ? 'selected' : ''}>${x}</option>`).join('')}</select><nav class="reference-list" aria-label="原始 HTML">${list.map(s => `<button class="reference-item ${r.id === s.id ? 'active' : ''}" data-reference="${s.id}"><strong>${esc(s.title)}</strong><span>${esc(s.platform)} · ${esc(s.status)}</span></button>`).join('')}</nav></aside><section><div class="reference-toolbar"><h2>${esc(r.title)}</h2><a class="button" href="${esc(r.file)}" target="_blank" rel="noopener">单独打开 ↗</a></div><p class="frame-note">${esc(refNote(r))}</p><iframe class="original-frame" src="${esc(r.file)}" title="${esc(r.title)}" sandbox="allow-scripts"></iframe><p class="provenance">来源：${esc(r.source)}<br>SHA-256：${esc(r.sha256)}</p></section></div>`;
  }
  function decisions() {
    return `<div class="intro-note"><strong>统一结构和交互，同时沿用 iOS 已有的主题与输入组件。</strong><br>底层 TextField、键盘、辅助功能和系统分享可以继续复用；需要替换的是系统 Form 的整页外观、默认控件排列和层层 modal 的业务路径。</div>
      <div class="rules-grid"><section class="rule-card"><h3>复杂业务进入独立页</h3><p>创建、加入、多字段编辑、报名管理、场次编排、补记和纠正上传共享导航栈。标题及底部操作固定，中间内容滚动。</p></section><section class="rule-card"><h3>短操作使用统一弹层</h3><p>确认、单项改名、日期/时间、单一成员选择可用品牌 dialog。扫码、登录和系统分享保留适当的平台承载。</p></section><section class="rule-card"><h3>先复用，再提取组件</h3><p>现有小组卡片、灰底输入、选项网格、快捷比分和确认弹窗都有基础。新增组件只统一布局与状态，延用现有业务校验。</p></section></div>
      <section class="panel decision-table"><h2>两端有分歧时怎么选</h2><table class="comparison"><tbody>${D.decisions.map(x => `<tr><th>${esc(x.topic)}<br><span class="badge">${esc(x.status)}</span></th><td><p>${esc(x.difference)}</p><p><strong>建议：</strong>${esc(x.decision)}</p></td></tr>`).join('')}</tbody></table></section>
      <section class="panel"><h2>建议的改造顺序</h2><div class="sequence">${D.stages.map(x => `<div class="stage"><div><h3>${esc(x.name)}</h3><p>${esc(x.description)}</p><p><strong>验收：</strong>${esc(x.acceptance)}</p></div></div>`).join('')}</div></section>
      <section class="panel"><h2>可以直接复用的 iOS 基础</h2><table class="comparison"><tbody>${D.reusable.map(x => `<tr><th>${esc(x.name)}</th><td>${esc(x.use)}${source(x.source)}</td></tr>`).join('')}</tbody></table></section>
      <section class="panel"><h3>宽屏、深色和大字号</h3><p>iPhone 复杂业务采用页面。iPad/宽窗口可使用居中内容或居中表单，但复用同一份表单和状态。标题栏保持窗口全宽，仅内容和底部按钮区限制宽度。保留既有主题绿色、动态灰底与全局 Token；不为本轮另建一套颜色。</p><p class="frame-note">v3 已落实 iOS 源码并完成模拟器构建与相关回归；Android / 鸿蒙只作为参考。离线 fixture 没有提交真实业务写入。</p></section>`;
  }
  function screenshots() {
    return `${currentIOSGallery()}<div class="intro-note"><strong>改造前的 iOS 截图存档。</strong><br>以下保留 2026-10-18 的离线 fixture / 主题检查，供回看改造前的状态。</div><div class="shots-grid">${S.screenshots.map(s => `<article class="shot"><h3>${esc(s.title)}</h3><a href="${esc(s.file)}" target="_blank" rel="noopener"><img src="${esc(s.file)}" alt="${esc(s.title)}，既有 iOS 截图" loading="lazy"></a><small>${esc(s.device)} · ${esc(s.capturedAtLocal||s.capturedAt)}<br>${esc(s.state)}<br>来源：${esc(s.source)}</small></article>`).join('')}</div>`;
  }
  function currentIOSGallery(scene) {
    const data=window.IOS_NATIVE_V3;
    if(!data)return '';
    const entries=scene?[data.scenes[scene]].filter(Boolean):Object.values(data.scenes);
    return `<section class="panel native-evidence"><h3>本轮 iOS 原生截图${scene?'':' · 13 页'}</h3><p class="frame-note">2026-10-19 · iPhone 17 Pro 模拟器 · 402×874 pt。真实生产视图使用离线测试数据；不是 HTML 截图，也未提交业务写入。${scene?'':' 截图保留实际键盘、滚动位置和系统 Sheet 外观。'}</p><div class="${scene?'native-shots':'shots-grid'}">${entries.map(s=>`<figure class="shot"><h3>${esc(s.title)}</h3><a href="${esc(s.file)}" target="_blank" rel="noopener"><img src="${esc(s.file)}" alt="${esc(s.title)}，本轮 iOS 原生截图" loading="lazy"></a><figcaption>${esc(s.presentation==='sheet'?'Sheet':'独立页 / 主 Tab')} · ${esc(s.capturedAtLocal)}<br>${esc(s.test)}</figcaption></figure>`).join('')}</div></section>`;
  }
  const previewScenes = [['result','补记赛果'],['start','开始计分'],['create','创建小组'],['join','加入小组'],['activity','创建活动'],['detail','活动详情'],['schedule','直接排赛'],['registration','临时成员报名'],['edit','修改小组资料'],['temporary','添加临时成员'],['members','成员与审批'],['records','战绩'],['report','举报小组']];
  const sheetScenes = new Set(['temporary','registration','report']);
  const defaultSheetOrigins = {temporary:'members', registration:'detail', report:'join'};
  const reportReasons = ['垃圾广告','骚扰辱骂','色情或违规内容','诈骗或赌博','违法或危险活动','冒充他人或官方','其他'];
  const sportAssets = {'羽毛球':'badminton','乒乓球':'pingpong','网球':'tennis','匹克球':'pickleball'};
  const notes = {
    create:['字段直接排列','删除“基本信息”等外层分组与卡片。名称、简介、项目、加入方式各保留一个字段标签。'],
    edit:['沿用创建的字段层级','名称、简介和加入方式直接排列；补全关闭加入选项。iOS 建议保留明确标签，Android 当前仍主要依赖 placeholder。'],
    activity:['只保留字段标签','删除“活动信息 / 报名设置 / 补充说明”。还原选填名称、日期/时间、截止、地点、赛制、人数、备注的实际顺序。'],
    detail:['两张有用途的内容卡','信息卡没有“活动信息”标题；报名卡只保留人数与管理入口。删除虚构的“比赛场次”卡，通过底部进入排赛。'],
    result:['规则与比分合为一张卡','删除“参赛队员 / 整场局分 / 比赛信息”外层标题。保留“比分与规则”及卡内的实际标签。'],
    start:['对阵区直接放页面','删除“参赛队员”和 A/B 队大标题，使用席位角标及常驻成员池；保留一个“比赛规则”标题。'],
    schedule:['只保留对阵安排分段','时间模式无大标题；每场标题移进卡内。预计时长改为全局设置，仅预计模式出现，每张场次都可独立选人。'],
    registration:['报名管理保留 sheet','保留名单与底部变更摘要，选择后直接批量保存。按已确认策略以 sheet 覆盖活动详情，关闭后返回原页面。'],
    join:['单张预览卡完成加入','删除“查找小组 / 小组预览 / 申请信息”。申请留言用 placeholder；加入按钮位于预览卡内。'],
    temporary:['添加临时成员保留 sheet','输入、解析数量和常用名称保留原布局。按已确认策略使用 sheet；关闭后回到成员列表或原计分设置。'],
    members:['保留实际名单分组','待审批、正式成员、临时成员是实际分组，应保留。成员行不重复“临时”，添加入口放临时分组旁。'],
    records:['筛选与实际分段','恢复榜单筛选、待确认、榜单、战绩；榜单名称在卡内。没有通用补记底栏，也不在本轮新增二级 tab。'],
    report:['举报保留共享 sheet','小组举报使用七项纵向原因和选填说明。与反馈条目详情复用 ReportSheet；反馈仍使用自己的四项原因与接口。']
  };
  function draft() {
    return drafts[state.preview] ||= {name:state.preview==='activity'?'':'周末羽毛球',intro:'周末一起打球，新手友好，以双打为主。',place:'滨江体育中心',date:state.preview==='result'?'2026-10-17':'2026-10-24',time:'14:00',deadline:'2026-10-23 20:00',format:'双打',join:'需要审批',sport:'羽毛球',capacity:12,best:3,completion:'best_of',points:21,score:'2:1',mode:'不设具体时间',duration:30,seats:['杨扬','林启','陈一鸣','周可欣'],registrations:['刘思远'],initialRegistrations:['刘思远'],sessions:2,sessionSeats:[['杨扬','林启','陈一鸣','周可欣'],['杨扬','刘思远','林启','赵婧']],activeSeats:[0,0],selectedSession:0,sessionTimes:['14:00','14:30'],sessionCourts:['1号场','2号场'],names:'刘思远\n赵婧',reason:'其他',note:'',applyNote:'',groupNo:'82603158',reminder:false};
  }
  const flow = (body,cls='') => `<div class="plain-flow ${cls}">${body}</div>`;
  const surface = (body,cls='') => `<div class="native-surface ${cls}">${body}</div>`;
  const section = (title,body,{bar=false,count='',action=''}={}) => `<section class="native-section"><div class="native-section-head ${bar?'has-bar':''}"><h3>${title}</h3>${count?`<small>${count}</small>`:''}${action}</div>${body}</section>`;
  const label = text => `<span class="native-label">${text}</span>`;
  function field(title,key,{multiline=false,value,placeholder='',hint='',height=48,cls='',maxlength}={}) {
    const v=value??draft()[key]??'';
    return `<label class="field native-field ${cls}">${title?label(title):''}${multiline?`<textarea data-field="${key}" style="height:${height}px" placeholder="${esc(placeholder)}" ${maxlength?`maxlength="${maxlength}"`:''}>${esc(v)}</textarea>`:`<input data-field="${key}" style="height:${height}px" value="${esc(v)}" placeholder="${esc(placeholder)}" ${maxlength?`maxlength="${maxlength}"`:''}>`}${hint?`<small class="business-hint">${hint}</small>`:''}</label>`;
  }
  function chips(key,values,{segmented=false,session}={}) {
    const d=draft();
    return `<div class="${segmented?'native-segment':'option-row'}" role="group" aria-label="${key==='format'?'比赛形式':key==='join'?'加入方式':key==='mode'?'时间模式':key}">${values.map(v=>`<button class="native-option ${d[key]===v?'selected':''}" data-choice="${key}" data-value="${esc(v)}" ${session!==undefined?`data-session="${session}"`:''} aria-pressed="${d[key]===v}">${esc(v)}</button>`).join('')}</div>`;
  }
  function stepper(key,min=1,max=100) {
    return `<div class="number-stepper"><button data-step="${key}" data-delta="-1" data-min="${min}" data-max="${max}" aria-label="减少报名人数" ${draft()[key]<=min?'disabled':''}>−</button><input aria-label="报名人数" data-number="${key}" inputmode="numeric" value="${draft()[key]}"><button data-step="${key}" data-delta="1" data-min="${min}" data-max="${max}" aria-label="增加报名人数" ${draft()[key]>=max?'disabled':''}>＋</button></div>`;
  }
  function calendar() {
    if(!['date','time','deadline'].includes(state.picker))return '';
    const key=state.picker,d=draft();
    return `<div class="native-picker"><div class="picker-month">2026 年 10 月<button class="text-action" data-picker-close>收起</button></div>${key!=='time'?`<div class="calendar-grid">${['一','二','三','四','五','六','日'].map(v=>`<small>${v}</small>`).join('')}${'<span></span>'.repeat(3)}${Array.from({length:31},(_,i)=>{const date=`2026-10-${String(i+1).padStart(2,'0')}`;return `<button class="native-option ${d.date===date?'selected':''}" data-date="${date}" ${state.preview==='result'&&date>'2026-10-19'?'disabled':''}>${i+1}</button>`;}).join('')}</div>`:''}<div class="option-row">${['10:00','14:00','16:00','18:00'].map(t=>`<button class="native-option ${d.time===t?'selected':''}" data-choice="time" data-value="${t}">${t}</button>`).join('')}</div></div>`;
  }
  function selectField(title,value,picker='date',cls='') {
    return `<div class="native-field ${cls}">${title?label(title):''}<button class="select-control" data-picker="${picker}" aria-label="${title||'比赛时间'}"><span>${esc(value)}</span><span aria-hidden="true">›</span></button></div>`;
  }
  function dateRow() {return `<div>${selectField('',draft().date+' '+draft().time,'date','result-date')}${calendar()}</div>`;}
  function roster(session=null) {
    const d=draft(),isSchedule=session!==null,ss=isSchedule?d.sessionSeats[session]:d.seats;
    const indices=d.format==='双打'?[[0,1],[2,3]]:[[0],[2]];
    const active=isSchedule?(d.activeSeats[session]??0):(d.activeSeat??0);
    const activeNames=indices.flat().map(i=>ss[i]);
    return `<div class="inline-roster ${isSchedule?'match-roster':''}"><div class="team-grid">${indices.map(group=>`<div class="seat-column">${group.map(i=>`<button class="seat ${active===i?'active':''}" data-seat="${i}" ${isSchedule?`data-session="${session}"`:''} aria-label="${i<2?'A':'B'}${i%2+1} ${esc(ss[i]||'点击选人')}"><span class="seat-avatar">${ss[i]?ss[i].slice(-1):'＋'}</span><span class="seat-name">${esc(ss[i]||'点击选人')}</span>${!isSchedule?`<small>${i<2?'A':'B'}${i%2+1}</small>`:''}</button>`).join('')}</div>`).join('')}</div><p class="roster-instruction">点选席位，再选择成员</p>${people.length>12?'<input id="member-search" aria-label="搜索成员" placeholder="搜索成员">':''}<div class="member-pool">${people.filter(n=>!state.memberQuery||n.includes(state.memberQuery)).map(n=>`<button class="member-token ${activeNames.includes(n)?'selected':''}" data-member="${n}" ${isSchedule?`data-session="${session}"`:''} aria-pressed="${activeNames.includes(n)}"><span class="token-avatar">${n.slice(-1)}</span><span>${n}</span></button>`).join('')}</div></div>`;
  }
  function ruleContents() {
    const d=draft(),options=[['best_of',1,'一局定胜负'],['best_of',3,'三局两胜'],['best_of',5,'五局三胜'],['play_all',3,'打满三局'],['play_all',5,'打满五局']];
    const summary=options.find(([mode,n])=>mode===d.completion&&n===d.best)?.[2]||'三局两胜';
    return `<button class="rule-summary" data-rules aria-expanded="${state.rules}"><span><strong>${summary}</strong><small>每局分数 ${d.points}</small></span><span aria-hidden="true">${state.rules?'⌄':'›'}</span></button>${state.rules?`<div class="rule-editor"><div class="option-row rule-mode-options">${options.map(([mode,n,title])=>`<button class="native-option ${d.completion===mode&&d.best===n?'selected':''}" data-rule-mode="${mode}" data-rule-count="${n}">${title}</button>`).join('')}</div>${chips('points',[11,15,21])}</div>`:''}`;
  }
  function resultControls() {
    const d=draft(),wins=Math.floor(d.best/2)+1;
    const a=Array.from({length:wins},(_,i)=>`${d.completion==='play_all'?d.best-i:wins}:${i}`),b=Array.from({length:wins},(_,i)=>`${i}:${d.completion==='play_all'?d.best-i:wins}`);
    if(![...a,...b].includes(d.score))d.score=a[0];
    return `<p class="inner-label">比赛比分</p><div class="quick-score-columns">${[a,b].map((scores,i)=>`<div class="quick-score-column ${i?'side-b':'side-a'}"><p>${i?'B':'A'} 方获胜</p>${scores.map(s=>`<button class="quick-score ${d.score===s?'selected':''}" data-choice="score" data-value="${s}" aria-pressed="${d.score===s}">${s.replace(':',' : ')}</button>`).join('')}</div>`).join('')}</div><button class="disclosure-control" data-manual aria-expanded="${!!state.manual}"><span>手动输入局分</span><span>${state.manual?'⌄':'›'}</span></button>${state.manual?`<div class="manual-score"><input aria-label="A 方局分" data-total="0" inputmode="numeric" value="${d.score.split(':')[0]}"><span>:</span><input aria-label="B 方局分" data-total="1" inputmode="numeric" value="${d.score.split(':')[1]}"></div>`:''}<button class="disclosure-control" data-details aria-expanded="${state.details}"><span>比分明细（选填）</span><span>${state.details?'⌄':'›'}</span></button>${state.details?`<div class="score-details">${Array.from({length:d.score.split(':').map(Number).reduce((a,b)=>a+b,0)},(_,i)=>`<div class="score-detail-row"><span>第 ${i+1} 局</span><input aria-label="第 ${i+1} 局 A 方分数" inputmode="numeric" data-detail-score="${i}:a" value="${esc(d['detail'+i+'a']??'')}"><span>:</span><input aria-label="第 ${i+1} 局 B 方分数" inputmode="numeric" data-detail-score="${i}:b" value="${esc(d['detail'+i+'b']??'')}"></div>`).join('')}</div>`:''}`;
  }
  function matchForm(manual) {
    return flow(chips('format',['单打','双打'],{segmented:true})+roster()+`<button class="text-action add-temporary" data-preview="temporary">＋ 添加临时成员</button>`+(manual?dateRow():'')+section(manual?'比分与规则':'比赛规则',surface((manual?'<p class="inner-label">比赛规则</p>':'')+ruleContents()+(manual?'<hr>'+resultControls():''),'score-rule-card')),'match-flow');
  }
  function createForm(edit=false) {
    return flow(field('名称','name',{height:edit?48:52,cls:edit?'':'create-name',maxlength:48})+field('简介（选填）','intro',{multiline:true,height:edit?100:88,maxlength:200,cls:edit?'':'create-description'})+(!edit?`<div class="native-field">${label('项目')}<div class="sport-tiles">${Object.entries(sportAssets).map(([n,asset])=>`<button class="sport-tile ${draft().sport===n?'selected':''}" data-choice="sport" data-value="${n}" aria-pressed="${draft().sport===n}"><img src="assets/${asset}.png" alt=""><span>${n}</span></button>`).join('')}</div></div>`:'')+`<div class="native-field">${label('加入方式')}${chips('join',edit?['直接加入','需要审批','关闭加入']:['直接加入','需要审批'],{segmented:true})}</div>`+(edit?'<p class="business-hint">关闭后，其他人无法加入，已有成员不受影响。</p>':''));
  }
  function activityForm() {
    const d=draft();
    return flow(field('活动名称（选填）','name',{placeholder:'活动名称',hint:'不填写时，将按日期自动生成，例如“10月24日活动”。'})+`<div class="date-time-fields">${selectField('日期',d.date)}${selectField('开始时间',d.time,'time')}</div>`+selectField('报名截止时间',d.deadline,'deadline')+calendar()+`<div class="native-field">${label('地点（选填）')}<div class="input-with-action"><input data-field="place" value="${esc(d.place)}" placeholder="地点（选填）"><button data-place aria-label="选择常用地点">›</button></div></div>`+chips('format',['单打','双打'],{segmented:true})+`<div class="capacity-block"><div class="capacity-row"><span>报名人数上限</span>${stepper('capacity',d.format==='双打'?4:2,100)}</div><p class="business-hint">一个活动可安排多场比赛。成员先报名活动，再在排阵时为每场单打选择 2 人、每场双打选择 4 人参赛。</p></div>`+field('备注（选填）','note',{multiline:true,height:100,maxlength:300}));
  }
  function scheduleForm() {
    const d=draft();
    return flow(field('','name',{placeholder:'活动名称（选填）',value:d.scheduleName??'',hint:'不填写时，将按日期自动生成活动名称。'})+`<div class="date-place-fields">${selectField('',d.date)}<div class="input-with-action"><input aria-label="地点" data-field="place" value="${esc(d.place)}" placeholder="地点（选填）"><button data-place aria-label="选择常用地点">›</button></div></div>`+calendar()+chips('format',['单打','双打'])+chips('mode',['不设具体时间','设置预计时间'])+(d.mode==='设置预计时间'?`<div class="native-field">${label('每场时长')}${chips('duration',[20,30,45,60])}</div>`:'')+'<hr>'+section('对阵安排',`<div class="match-cards">${Array.from({length:d.sessions},(_,i)=>surface(`<div class="match-card-head"><h4><button class="match-card-select" data-session-select="${i}" aria-expanded="${d.selectedSession===i}">第 ${i+1} 场 <small>${d.selectedSession===i?'⌄':'›'}</small></button></h4><button class="icon-action" data-remove-at="${i}" aria-label="删除第 ${i+1} 场">×</button></div>${d.selectedSession===i?`<div class="session-time-court">${d.mode==='设置预计时间'?`<button class="select-control compact" data-session-clock="${i}"><span>${d.sessionTimes[i]}</span><span>›</span></button>`:'<span class="session-sequence">按顺序进行</span>'}<input data-session-court="${i}" aria-label="第 ${i+1} 场场地" value="${esc(d.sessionCourts[i]||'')}" placeholder="场地（选填）" maxlength="16"></div>${state.sessionClock===i?`<div class="option-row">${['14:00','14:30','15:00','15:30'].map(time=>`<button class="native-option" data-session-time="${time}" data-session="${i}">${time}</button>`).join('')}</div>`:''}${roster(i)}`:`<p class="caption-text">${d.mode==='设置预计时间'?d.sessionTimes[i]:'按顺序进行'}${d.sessionCourts[i]?' · '+esc(d.sessionCourts[i]):''}</p><div class="collapsed-match-names"><span>${[d.sessionSeats[i][0],...(d.format==='双打'?[d.sessionSeats[i][1]]:[])].map(n=>esc(n||'待选成员')).join('<br>')}</span><span>:</span><span>${[d.sessionSeats[i][2],...(d.format==='双打'?[d.sessionSeats[i][3]]:[])].map(n=>esc(n||'待选成员')).join('<br>')}</span></div>`}`,'match-card')).join('')}</div><button class="add-match" data-add-session>＋ 添加一场</button>`,{bar:true,count:`${d.sessions} 场`}));
  }
  function registrationChanges() {
    const d=draft(),before=new Set(d.initialRegistrations),after=new Set(d.registrations);
    return {added:[...after].filter(n=>!before.has(n)),removed:[...before].filter(n=>!after.has(n))};
  }
  function registrationForm() {
    const d=draft();
    return flow('<p class="business-hint">为临时成员代报名，正式成员自行报名。</p>'+`<div class="registration-list">${people.slice(4).map(n=>{const changed=d.initialRegistrations.includes(n)!==d.registrations.includes(n),selected=d.registrations.includes(n);return `<label class="registration-row ${selected?'selected':''}"><input type="checkbox" data-registration="${n}" ${selected?'checked':''}><span class="avatar">${n.slice(-1)}</span><span class="registration-name">${n}<small>${changed?(selected?'待添加报名':'待取消报名'):(selected?'已报名':'未报名')}</small></span></label>`;}).join('')}</div>`);
  }
  function activityDetail() {
    return flow(`<div class="activity-heading"><h2>周六双打友谊赛</h2><button class="icon-action" data-more aria-label="活动更多操作">⋮</button></div>`+surface(`<div class="status-tags"><span>报名中</span><span>双打</span></div><p class="activity-meta">2026-10-24 14:00<br>滨江体育中心</p><p class="caption-text">报名截止时间：2026-10-23 20:00</p><label class="reminder-row"><span>活动提醒</span><input type="checkbox" class="native-switch" data-reminder ${draft().reminder?'checked':''}></label>`,'activity-info')+surface(`<div class="roster-card-head"><span>报名 · 4/12</span><button class="text-action" data-preview="registration">管理临时成员报名</button></div><div class="registered-avatars">${people.slice(0,4).map(n=>`<div><span class="avatar">${n.slice(-1)}</span><small>${n}</small></div>`).join('')}</div><div class="my-registration"><span>我的报名<small>已报名</small></span><button class="text-action" data-demo="已演示取消报名">取消报名</button></div>`,'registered-card'));
  }
  function memberList() {
    return flow(section('待审批申请',surface(`<div class="approval-row"><span class="avatar">赵</span><div class="approval-main"><div class="approval-identity"><strong>赵婧</strong><small>今天 09:30</small></div><p>周末有空，想加入一起练球。我通常周六下午方便。</p><div class="approval-actions"><button data-demo="已演示拒绝申请">拒绝</button><button class="approve" data-demo="已演示通过申请">通过</button></div></div></div>`,'approval-card'),{bar:true,count:'1'})+section('正式成员',surface(people.slice(0,4).map((n,i)=>`<div class="native-member-row"><span class="avatar">${n.slice(-1)}</span><span>${n}</span>${i===0?'<small>组长</small>':''}</div>`).join(''),'roster-list'),{bar:true,count:'4'})+section('临时成员',surface(people.slice(4,6).map(n=>`<div class="native-member-row"><span class="avatar">${n.slice(-1)}</span><span>${n}</span></div>`).join(''),'roster-list'),{bar:true,count:'2',action:'<button class="text-action" data-preview="temporary">＋ 添加</button>'})+'<button class="text-action removed-members" data-demo="已移除成员列表为保留的折叠区域">已移除成员　⌄</button>');
  }
  function resultMatchup(a,b,scoreA,scoreB) {
    return `<div class="result-matchup"><div class="result-player-columns">${[a,b].map(names=>`<div>${names.map(n=>`<div class="result-player"><span class="result-avatar">${n.slice(-1)}</span><span>${esc(n)}</span><i></i></div>`).join('')}</div>`).join('<span></span>')}</div><div class="result-total"><span>${scoreA}</span><span>−</span><span>${scoreB}</span></div></div>`;
  }
  function recordList() {
    const d=draft(),rows=[['杨扬',8,6,2,0,'14-7','75%'],['林启',6,4,2,0,'10-6','67%'],['陈一鸣',4,3,1,0,'7-4','场次不足']];
    return flow(chips('format',['单打','双打'])+section('待确认',surface(`<p class="caption-text">10 月 17 日 · 双打 · BO3</p>${resultMatchup(['杨扬','林启'],['陈一鸣','周可欣'],2,1)}<div class="result-state"><span>待确认</span><button class="text-action" data-demo="已演示确认赛果">确认</button></div>`),{bar:true,count:'1'})+surface(`<p class="inner-label">${d.format}排行榜</p><div class="ranking-scroll"><table class="native-ranking"><thead><tr>${['排名 / 成员','场次','胜','负','平','局分','胜率'].map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map((r,i)=>`<tr><td><span class="rank-identity"><b>${i+1}</b><span class="rank-avatar">${r[0].slice(-1)}</span>${r[0]}${i===0?'（我）':''}</span></td>${r.slice(1).map(v=>`<td>${v}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`,'ranking-card')+section('战绩',surface(`<p class="caption-text">10 月 16 日 · 双打 · BO3</p>${resultMatchup(['刘思远','林启'],['杨扬','赵婧'],1,2)}<p class="caption-text">补记赛果</p>`),{bar:true,action:'<button class="text-action" data-demo="历史记录筛选与排行榜筛选独立">全部 ▾</button>'}));
  }
  function joinForm() {
    const d=draft();
    return flow(`<button class="scan-entry" data-demo="扫码与相册识别继续复用系统入口"><span class="scan-symbol" aria-hidden="true">▦</span><span><strong>扫码加入</strong><small>扫描小组二维码</small></span><span>›</span></button><div class="number-separator"><span></span>或输入小组号<span></span></div>`+field('','groupNo',{height:64,cls:'group-number',placeholder:'输入小组号',maxlength:8})+'<p class="number-hint">小组号为 6–8 位 · 可向组长获取小组号</p>'+surface(`<div class="join-identity"><img src="assets/badminton.png" alt=""><div><strong>周六羽毛球</strong><small>羽毛球 · 6 名成员 · 8260 3158</small></div><small class="join-status">需审批</small></div><p class="join-description">周末一起打球，新手友好，以双打为主。</p>${field('','applyNote',{placeholder:'申请留言（选填）',height:48})}<button class="cta" data-submit>申请加入</button>`,'join-preview')+'<button class="text-action join-report" data-preview="report">举报小组</button>');
  }
  function temporaryForm() {
    const n=new Set(draft().names.split(/[\n,，;；]/).map(s=>s.trim()).filter(Boolean)).size;
    return flow('<p class="business-hint">临时成员可参与比赛与战绩统计，之后可由本人认领。每行一个姓名，也可用逗号分隔。</p>'+field('','names',{multiline:true,height:140,placeholder:'输入成员姓名',maxlength:4000})+`<div class="names-count-row"><small>${n} 个名称</small><button class="common-names" data-common-names>常用名称　›</button></div>`);
  }
  function reportForm() {
    return flow(`<div class="report-reasons">${reportReasons.map(n=>`<label class="report-reason"><input type="radio" name="report-reason" data-reason="${n}" ${draft().reason===n?'checked':''}><span>${n}</span></label>`).join('')}</div>`+field('','note',{multiline:true,height:90,placeholder:'补充说明（选填，最多 500 字）',maxlength:500})+`<small class="report-detail-count">${draft().note.length}/500</small>`);
  }
  const titles={result:'补记赛果',start:'开始计分',create:'创建小组',join:'加入小组',activity:'创建活动',detail:'活动详情',schedule:'直接排赛',registration:'临时成员报名',edit:'修改小组资料',temporary:'添加临时成员',members:'小组成员',records:'小组战绩',report:'举报小组'};
  const submitTitles={result:'提交',start:'开始计分',create:'创建',join:'申请加入',activity:'创建',detail:'活动排赛',schedule:'保存排赛',registration:'保存报名',edit:'保存',temporary:'确认',report:'提交'};
  function previewBody() {return ({result:()=>matchForm(true),start:()=>matchForm(false),create:()=>createForm(),edit:()=>createForm(true),activity:activityForm,detail:activityDetail,schedule:scheduleForm,registration:registrationForm,members:memberList,records:recordList,join:joinForm,temporary:temporaryForm,report:reportForm}[state.preview]||(()=>''))();}
  function previewPresentation() {
    if(!sheetScenes.has(state.preview))return `<header class="appbar"><button data-back aria-label="返回">‹</button><strong>${titles[state.preview]}</strong><span></span></header><div class="scroll">${previewBody()}</div>${previewFooter()}`;
    const origin=state.sheetOrigin||defaultSheetOrigins[state.preview];
    return `<div class="sheet-underlay" aria-hidden="true" inert><header class="appbar"><span>‹</span><strong>${titles[origin]}</strong><span>⋯</span></header><div class="sheet-underlay-content"><div class="sheet-underlay-card"><strong>周六羽毛球</strong><p>羽毛球 · 8260 3158</p></div><div class="sheet-underlay-card"><p>${origin==='detail'?'周六双打友谊赛':'小组成员'}</p><div class="sheet-underlay-lines"><span></span><span></span><span></span></div></div></div></div><button class="sheet-scrim" data-sheet-close aria-label="关闭弹层"></button><section class="preview-sheet" role="dialog" aria-modal="true" aria-labelledby="preview-sheet-title"><div class="sheet-drag-indicator" aria-hidden="true"></div><header class="appbar sheet-appbar"><button class="sheet-close" data-sheet-close aria-label="关闭">×</button><strong id="preview-sheet-title">${titles[state.preview]}</strong><span></span></header><div class="scroll sheet-scroll">${previewBody()}</div>${previewFooter()}</section>`;
  }
  function closePreviewSheet() {
    const origin=state.sheetOrigin||defaultSheetOrigins[state.preview];
    goPreview(origin);
  }
  function previewFooter() {
    if(['join','members','records'].includes(state.preview))return '';
    const dual=['activity','temporary','report'].includes(state.preview),c=registrationChanges();
    const count=c.added.length+c.removed.length;
    return `<footer class="bottom-action ${state.preview==='registration'?'registration-footer':''}">${state.preview==='registration'?`<div class="registration-summary"><span>${count?`新增 ${c.added.length} · 取消 ${c.removed.length}`:'没有未保存的变更'}</span><span>报名 ${(draft().registrationBaseCount??4)+c.added.length-c.removed.length}/12</span></div>`:''}<div class="footer-buttons">${dual?'<button class="cta secondary" data-back>取消</button>':''}<button class="cta" data-submit>${state.preview==='registration'?(count?`保存报名（${count} 项）`:'完成'):submitTitles[state.preview]}</button></div></footer>`;
  }
  function referencePanel() {
    const data=window.LAYOUT_REVIEW,entry=data?.scenes[state.preview],refs=window.NATIVE_REFERENCES;
    if(!entry)return '';
    return `<section class="panel layout-evidence"><h3>本页二次核对</h3><p>${esc(notes[state.preview][1])}</p><p class="frame-note">承载方式：${entry.presentation==='sheet'?'Sheet · 覆盖原页面，关闭后返回':'独立页面 · 使用主导航栈'}。</p><details><summary>页面与短任务的承载策略</summary><p>创建、加入、创建活动、排赛、开始计分和补记使用独立页面。添加临时成员、临时成员报名和举报保留 sheet。</p><p>${esc(data.presentationPolicy.additionalSheetTasks.join('、'))}等短任务继续保留 sheet。小组与反馈举报共用 ReportSheet，原因、权限和接口由各入口保留。</p></details>${currentIOSGallery(state.preview)}<p class="mini-title">采用的尺寸 · 逻辑像素</p><dl class="pixel-metrics">${Object.entries(entry.adoptedMetrics).map(([k,v])=>`<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl><details><summary>Android / 鸿蒙依据与差异</summary><p>${esc(entry.choice)}</p>${entry.androidSources.map(s=>source('Android: '+s)).join('')}${entry.harmonySources.map(s=>source('鸿蒙: '+s)).join('')}</details></section><section class="panel native-evidence"><h3>原生截图对照</h3><p class="frame-note">10 月 18 日既有截图。按当前源码核对尺寸；截图没有重新采集，不作为当前版本逐像素相同的证明。</p><div class="native-shots">${(refs.sceneMap[state.preview]||[]).map(id=>{const r=refs.references.find(x=>x.id===id);return `<figure><a href="${r.file}" target="_blank" rel="noopener"><img src="${r.file}" alt="${r.platform} ${state.preview} 原生参考" loading="lazy"></a><figcaption>${r.platform} · ${r.dimensionsPx.join('×')} px<br>${r.theme==='dark'?'深色':'浅色'} · ${r.capturedAt?r.capturedAt.slice(0,10):'2026-10-18'}${r.comparisonNote?'<br>容器或状态不同，仅比较对应内容区域。':''}</figcaption></figure>`;}).join('')}</div></section>`;
  }
  function preview() {
    return `<div class="intro-note"><strong>第三版：页面与短任务分开承载，沿用已审表单布局。</strong><br>添加临时成员、临时成员报名、举报保留 sheet；创建、加入、活动、排赛与开始 / 补记进入独立页。右侧保留逐页尺寸与原生依据。</div><div class="preview-layout"><aside class="sidebar"><nav class="scene-nav" aria-label="建议版页面">${previewScenes.map(([id,name])=>`<button data-preview="${id}" class="${id===state.preview?'active':''}">${name}</button>`).join('')}</nav></aside><section class="preview-shell ${state.compact?'compact':''}"><div class="preview-tools"><button class="button ${state.dark?'active':''}" data-toggle="dark">${state.dark?'深色':'浅色'}</button><button class="button ${state.compact?'active':''}" data-toggle="compact">${state.compact?'320 窄屏':'402 视口'}</button><button class="button ${state.large?'active':''}" data-toggle="large">${state.large?'大字号':'标准字号'}</button></div><div class="phone-shell"><div class="phone native-preview scene-${state.preview} ${state.dark?'dark':''} ${state.large?'large':''} ${sheetScenes.has(state.preview)?'has-preview-sheet':''}"><div class="status"><span>9:41</span><span>● ▰</span></div>${previewPresentation()}<div class="home-indicator" aria-hidden="true"></div></div></div><p class="caption">iOS 建议版 v3 · 演示数据 · ${state.compact?'320':'402'} 逻辑像素宽</p></section><aside class="preview-notes">${referencePanel()}</aside></div>`;
  }
  function render(keepScroll=false) {
    const scrollTop=$('.phone .scroll')?.scrollTop||0;
    $('#main').innerHTML=({audit,preview,references,decisions,screenshots}[state.view]||audit)();
    document.querySelectorAll('.view-tabs button').forEach(b=>{b.classList.toggle('active',b.dataset.view===state.view);b.setAttribute('aria-current',b.dataset.view===state.view?'page':'false');});
    if(keepScroll&&$('.phone .scroll'))$('.phone .scroll').scrollTop=scrollTop;
  }
  function goPreview(id,fromProduct=false) {state.sheetOrigin=sheetScenes.has(id)?(fromProduct&&!sheetScenes.has(state.preview)?state.preview:defaultSheetOrigins[id]):null;state.view='preview';state.preview=id;state.picker=null;state.rules=false;state.details=false;state.manual=false;state.memberQuery='';render();}
  function validate() {
    const d=draft();
    if(['create','edit'].includes(state.preview)&&!d.name.trim())return '请填写名称。';
    if(['result','start','schedule'].includes(state.preview)) {
      const seats=(d.format==='单打'?[d.seats[0],d.seats[2]]:d.seats);
      if(seats.some(s=>!s)||new Set(seats).size!==seats.length)return '请补齐对阵队员，每个席位使用不同成员。';
    }
    if(state.preview==='result'&&d.date>'2026-10-19')return '补记比赛时间不能晚于演示日期 2026-10-19。';
    if(state.preview==='temporary'&&!d.names.trim())return '请至少填写一个姓名。';
    return null;
  }
  document.addEventListener('input',e=>{
    const el=e.target;
    if(el.id==='page-search'){state.query=el.value;$('.scene-nav').innerHTML=sceneNavigation();return;}
    if(el.id==='member-search'){
      state.memberQuery=el.value;const pos=el.selectionStart;render(true);const input=$('#member-search');input?.focus();input?.setSelectionRange(pos,pos);return;
    }
    if(el.dataset.field){draft()[el.dataset.field]=el.value;if(state.preview==='report'&&el.dataset.field==='note'){const counter=document.querySelector('.report-detail-count');if(counter)counter.textContent=el.value.length+'/500';}if(state.preview==='schedule'&&el.dataset.field==='name')draft().scheduleName=el.value;if(el.dataset.field==='names'){const count=new Set(el.value.split(/[\n,，;；]/).map(v=>v.trim()).filter(Boolean)).size;const counter=document.querySelector('.names-count-row small');if(counter)counter.textContent=count+' 个名称';}}
    if(el.dataset.sessionCourt!==undefined)draft().sessionCourts[Number(el.dataset.sessionCourt)]=el.value;
    if(el.dataset.number){const n=Number(el.value);if(Number.isFinite(n))draft()[el.dataset.number]=Math.max(draft().format==='双打'?4:2,Math.min(100,n));}
    if(el.dataset.total!==undefined){const parts=draft().score.split(':');parts[Number(el.dataset.total)]=el.value.replace(/\D/g,'').slice(0,2)||'0';draft().score=parts.join(':');}
    if(el.dataset.detailScore){const [i,side]=el.dataset.detailScore.split(':');draft()['detail'+i+side]=el.value;}
  });
  document.addEventListener('change',e=>{
    const el=e.target;
    if(el.id==='platform'){state.platform=el.value;render();}
    if(el.dataset.reason){draft().reason=el.dataset.reason;}
    if(el.dataset.reminder!==undefined){draft().reminder=el.checked;}
    if(el.dataset.registration){const s=new Set(draft().registrations);el.checked?s.add(el.dataset.registration):s.delete(el.dataset.registration);draft().registrations=[...s];render(true);}
  });
  document.addEventListener('click',e=>{
    const b=e.target.closest('button');if(!b||b.disabled)return;
    const x=b.dataset;
    if(x.view){state.view=x.view;render();return;}
    if(x.scene){state.scene=x.scene;render();return;}
    if(x.openPreview){goPreview(x.openPreview);return;}
    if(x.preview){goPreview(x.preview,!!b.closest('.phone'));return;}
    if('sheetClose' in x){closePreviewSheet();return;}
    if(x.reference){state.reference=x.reference;render();return;}
    if(x.toggle){state[x.toggle]=!state[x.toggle];render(true);return;}
    if(x.choice){const d=draft();if(x.choice==='time'&&state.picker==='deadline')d.deadline=d.deadline.slice(0,10)+' '+x.value;else d[x.choice]=['best','points','duration'].includes(x.choice)?Number(x.value):x.value;render(true);return;}
    if(x.ruleMode){draft().completion=x.ruleMode;draft().best=Number(x.ruleCount);render(true);return;}
    if(x.sessionSelect!==undefined){draft().selectedSession=Number(x.sessionSelect);state.sessionClock=null;render(true);return;}
    if(x.sessionClock!==undefined){state.sessionClock=state.sessionClock===Number(x.sessionClock)?null:Number(x.sessionClock);render(true);return;}
    if(x.sessionTime){draft().sessionTimes[Number(x.session)]=x.sessionTime;state.sessionClock=null;render(true);return;}
    if('rules' in x){state.rules=!state.rules;render(true);return;}
    if('details' in x){state.details=!state.details;render(true);return;}
    if('seat' in x){if(x.session!==undefined)draft().activeSeats[Number(x.session)]=Number(x.seat);else draft().activeSeat=Number(x.seat);render(true);return;}
    if(x.member){const d=draft(),idx=x.session===undefined?null:Number(x.session),seats=idx===null?d.seats:d.sessionSeats[idx],active=idx===null?(d.activeSeat??0):(d.activeSeats[idx]??0),valid=d.format==='双打'?[0,1,2,3]:[0,2],assigned=valid.find(i=>seats[i]===x.member);if(assigned!==undefined){seats[assigned]='';if(idx===null)d.activeSeat=assigned;else d.activeSeats[idx]=assigned;}else{seats[active]=x.member;const next=valid.find(i=>!seats[i])??active;if(idx===null)d.activeSeat=next;else d.activeSeats[idx]=next;}render(true);return;}
    if('clearSeat' in x){draft().seats[state.picker]='';render(true);return;}
    if(x.picker){state.picker=state.picker===x.picker?null:x.picker;render(true);return;}
    if('pickerClose' in x){state.picker=null;render(true);return;}
    if(x.date){if(state.picker==='deadline')draft().deadline=x.date+' '+draft().time;else draft().date=x.date;render(true);return;}
    if(x.step){draft()[x.step]=Math.min(Number(x.max),Math.max(Number(x.min),draft()[x.step]+Number(x.delta)));render(true);return;}
    if('addSession' in x){const d=draft();if(d.sessions<5){d.sessions++;d.sessionSeats.push(['','','','']);d.activeSeats.push(0);d.sessionTimes.push('14:00');d.sessionCourts.push('');d.selectedSession=d.sessions-1;}else toast('演示最多显示 5 张场次卡。');render(true);return;}
    if('removeAt' in x){const d=draft();if(d.sessions>1){d.sessionSeats.splice(Number(x.removeAt),1);d.activeSeats.splice(Number(x.removeAt),1);d.sessionTimes.splice(Number(x.removeAt),1);d.sessionCourts.splice(Number(x.removeAt),1);d.sessions--;d.selectedSession=Math.min(d.selectedSession,d.sessions-1);}else toast('至少保留一场比赛。');render(true);return;}
    if('manual' in x){state.manual=!state.manual;render(true);return;}
    if('place' in x){toast('常用地点选择沿用已有组件，此处展示输入布局。');return;}
    if('removeSession' in x){draft().sessions=Math.max(1,draft().sessions-1);render(true);return;}
    if('commonNames' in x){draft().names+='\n王明';render(true);toast('已把王明加入待添加名单；尚未提交。');return;}
    if(x.recordTab){state.recordTab=x.recordTab;render(true);return;}
    if(x.layout){state.recordLayout=x.layout;render(true);return;}
    if('submit' in x){
      if(state.preview==='detail'){goPreview('schedule');return;}
      if(state.preview==='members'){goPreview('temporary');return;}
      if(state.preview==='records'){goPreview('result');return;}
      if(state.preview==='registration'){const d=draft(),c=registrationChanges();d.registrationBaseCount=(d.registrationBaseCount??4)+c.added.length-c.removed.length;d.initialRegistrations=[...d.registrations];closePreviewSheet();toast('报名变更已保存在当前演示中，未发送真实请求。');return;}
      const error=validate();if(!error&&sheetScenes.has(state.preview))closePreviewSheet();toast(error||'已完成本地演示；App 接入时复用现有预览、校验与提交流程。');return;
    }
    if('more' in x){toast('建议在此收纳编辑和取消；取消继续使用品牌确认及原因输入。');return;}
    if(x.demo){toast(x.demo+'；没有提交真实请求。');return;}
    if('back' in x){if(sheetScenes.has(state.preview)){closePreviewSheet();return;}state.view='audit';render();}
  });
  render();
})();
