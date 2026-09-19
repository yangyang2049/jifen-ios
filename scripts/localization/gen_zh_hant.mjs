#!/usr/bin/env node
/* zh-Hant corpus generator (one-off, kept for re-runs).
 * Pipeline: tier1 key+value direct copy from Android zh-rTW,
 * tier2 value-anchored copy, tier3 opencc cn->tw, term post-processing
 * on every tier, overrides.json wins last. See README.md. */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const args = process.argv.slice(2);
function arg(name, dflt) {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return dflt;
  if (name === 'check') return true;
  return args[i + 1];
}
const CHECK = args.includes('--check');

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const IOS_ROOT = path.resolve(SCRIPT_DIR, '../..');
const WORKSPACE_ROOT = path.dirname(IOS_ROOT);
const ANDROID_ROOT = path.join(WORKSPACE_ROOT, 'jifen-android');
const WEBSITE_ROOT = path.join(WORKSPACE_ROOT, 'jifenqi-website');
const cfg = {
  iosHans: arg('ios-hans', path.join(IOS_ROOT, 'jifen/Resources/zh-Hans.lproj/Localizable.strings')),
  androidCn: arg('android-cn', path.join(ANDROID_ROOT, 'app/src/main/res/values-zh-rCN/strings.xml')),
  androidTw: arg('android-tw', path.join(ANDROID_ROOT, 'app/src/main/res/values-zh-rTW/strings.xml')),
  terms: arg('terms', path.join(IOS_ROOT, 'scripts/localization/zh-Hant-terms.json')),
  overrides: arg('overrides', path.join(IOS_ROOT, 'scripts/localization/zh-Hant-overrides.json')),
  out: arg('out', path.join(IOS_ROOT, 'build/zh-Hant.draft.lproj/Localizable.strings')),
  report: arg('report', path.join(IOS_ROOT, 'build/zh-Hant-report.md')),
  websiteRoot: arg('website-root', WEBSITE_ROOT),
};

/* ---------- converter ---------- */
let convert = (s) => s;
let converterName = 'identity';
if (arg('converter', 'opencc') === 'opencc') {
  try {
    const req = createRequire(path.join(cfg.websiteRoot, 'x.js'));
    const OpenCC = req('opencc-js/cn2t');
    convert = OpenCC.Converter({ from: 'cn', to: 'tw' });
    converterName = 'opencc-js cn2t(cn->tw)';
  } catch (e) {
    console.error(`opencc unavailable (${e.message}); falling back to identity — tier3 output WILL contain simplified glyphs`);
  }
}

/* ---------- parsers ---------- */
const ENTRY_RE = /^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$/;
function unescapeStrings(s) {
  return s.replace(/\\(n|t|\\|"|'|u[0-9a-fA-F]{4})/g, (_, g) => {
    if (g === 'n') return '\n';
    if (g === 't') return '\t';
    if (g === '\\' || g === '"' || g === "'") return g;
    return String.fromCharCode(parseInt(g.slice(1), 16));
  });
}
const escapeStrings = (s) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\t/g, '\\t');

function stringCodecFailures() {
  const cases = [
    [String.raw`\"`, '"'],
    [String.raw`\\`, '\\'],
    [String.raw`\'`, "'"],
    [String.raw`\n`, '\n'],
    [String.raw`\t`, '\t'],
    [String.raw`\u7e41`, '繁'],
  ];
  const failures = cases
    .filter(([encoded, expected]) => unescapeStrings(encoded) !== expected)
    .map(([encoded]) => encoded);
  const roundTrip = '引號"、反斜線\\、換行\n、定位\t';
  if (unescapeStrings(escapeStrings(roundTrip)) !== roundTrip) failures.push('round-trip');
  return failures;
}

function parseTemplate(file) {
  const lines = readFileSync(file, 'utf8').split('\n');
  const out = [];
  lines.forEach((raw, idx) => {
    const m = raw.match(ENTRY_RE);
    if (m) out.push({ kind: 'entry', key: unescapeStrings(m[1]), value: unescapeStrings(m[2]), lineNo: idx });
    else out.push({ kind: 'other', raw, lineNo: idx });
  });
  return out;
}

function unescapeXml(s) {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&')
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/\\(.)/g, (m, c) => (c === 'n' ? '\n' : c)); // \' \" \\ \% → c
}
function parseAndroid(file) {
  const map = new Map();
  const re = /<string name="([^"]+)"(?:[^>]*)>([\s\S]*?)<\/string>/g;
  const text = readFileSync(file, 'utf8');
  let m;
  while ((m = re.exec(text))) {
    const key = m[1];
    const raw = m[2].trim();
    if (map.has(key)) console.error(`dup <string> in ${file}: ${key} (keeping first)`);
    else map.set(key, unescapeXml(raw));
  }
  return map;
}

/* ---------- tokens / terms ---------- */
const TOKEN_RE = /%(?:\d+\$)?(?:ll|l)?(?:[@dqsfxF%])/g;
const tokens = (s) => (s.match(TOKEN_RE) || []).map((t) => t.replace(/^\d+\$/, '%').replace(/^%(?:ll|l)/, '%')).sort();
const sameTokens = (a, b) => tokens(a).join(',') === tokens(b).join(',');

const terms = JSON.parse(readFileSync(cfg.terms, 'utf8'));
function applyTerms(value, hits) {
  let out = value;
  for (const t of terms.replacements) {
    if (!out.includes(t.from)) continue;
    out = out.split(t.from).join(t.to);
    hits.push(t.from);
  }
  const openL = (out.match(/[\u201c\u300c]/g) || []).length;
  const closeR = (out.match(/[\u201d\u300d]/g) || []).length;
  if (openL === closeR && openL > 0) out = out.replace(/\u201c([^\u201d]*)\u201d/g, '\u300c$1\u300d');
  else if (openL !== closeR) hits.push('__quote_unbalanced__');
  return out;
}

/* ---------- main ---------- */
const template = parseTemplate(cfg.iosHans);
const cn = parseAndroid(cfg.androidCn);
const tw = parseAndroid(cfg.androidTw);
const overrides = JSON.parse(readFileSync(cfg.overrides, 'utf8'));

const cnValueIndex = new Map(); // cn value -> [tw keys]
for (const [k, v] of cn) if (tw.has(k)) cnValueIndex.set(v, (cnValueIndex.get(v) || []).concat(k));

const PLATFORM_RE = new RegExp(terms.platformKeyPrefixes.join('|'), 'i');
const convolvableRe = /[\u4e00-\u9fff]/;

const keys = template.filter((l) => l.kind === 'entry');
const tiers = { override: [], tier1: [], tier2: [], tier3: [] };
const termHits = [];
const platformKeys = [];
const suspects = [];
const hardErrors = [];
const produced = new Map();

for (const { key, value: hans } of keys) {
  let candidate = null;
  let tier = 'tier3';
  const platform = PLATFORM_RE.test(key);
  if (Object.prototype.hasOwnProperty.call(overrides, key)) {
    candidate = overrides[key].value;
    tier = 'override';
  } else if (!platform && tw.has(key) && cn.get(key) === hans) {
    candidate = tw.get(key);
    tier = 'tier1';
  } else if (!platform) {
    const anchors = cnValueIndex.get(hans);
    if (anchors && anchors.length === 1) {
      const c = tw.get(anchors[0]);
      if (c && sameTokens(c, hans)) { candidate = c; tier = 'tier2'; }
    }
  }
  if (candidate == null) { candidate = convert(hans); tier = 'tier3'; }
  if (platform) platformKeys.push(key);

  const hits = [];
  candidate = applyTerms(candidate, hits);
  if (hits.length) termHits.push({ key, hits: hits.filter((h) => h !== '__quote_unbalanced__'), quoteUnbalanced: hits.includes('__quote_unbalanced__') });

  if (!sameTokens(candidate, hans)) hardErrors.push({ key, why: `token mismatch: "${hans}" -> "${candidate}"` });
  if (tier !== 'override') {
    const suspicious = [];
    if (candidate === hans && convolvableRe.test(hans) && convert(hans) !== hans) suspicious.push('unchanged-simplified');
    if (hans.length >= 4 && candidate.length / hans.length > 1.3) suspicious.push('length-inflation');
    if (/您/.test(candidate) && /你[^們们]/.test(candidate)) suspicious.push('mix-nin-ni');
    for (const t of terms.simplifiedResidue) if (candidate.includes(t)) suspicious.push(`residue:${t}`);
    if (suspicious.length) suspects.push({ key, tier, suspicious, value: candidate });
  }
  tiers[tier].push(key);
  produced.set(key, candidate);
}

/* ---------- emit ---------- */
const outLines = template.map((l) => {
  if (l.kind !== 'entry') return l.raw;
  return `"${escapeStrings(l.key)}" = "${escapeStrings(produced.get(l.key))}";`;
});
outLines[0] = '/* Localizable.strings\n   Chinese Traditional localization for jifen app\n*/';
if (template[1]?.kind === 'other' && template[2]?.raw === '*/') outLines.splice(1, 2);
mkdirSync(path.dirname(cfg.out), { recursive: true });
writeFileSync(cfg.out, outLines.join('\n'), 'utf8');

const sha = (f) => createHash('sha256').update(readFileSync(f)).digest('hex').slice(0, 12);
const baseline = (() => { try { return execSync('git rev-parse --short HEAD', { cwd: IOS_ROOT }).toString().trim(); } catch { return 'unknown'; } })();
const rp = [];
rp.push(`# zh-Hant generation report`, ``,
  `- baseline: ${baseline} | converter: ${converterName}`,
  `- inputs: ios-hans@${sha(cfg.iosHans)} android-cn@${sha(cfg.androidCn)} android-tw@${sha(cfg.androidTw)} terms@${sha(cfg.terms)} overrides@${sha(cfg.overrides)}`,
  `- keys total: ${keys.length}`,``,
  `## ① tier 分布`,
  `- override(人工): ${tiers.override.length}`,
  `- tier1 直抄(key+值等): ${tiers.tier1.length}`,
  `- tier2 值锚定: ${tiers.tier2.length}`,
  `- tier3 简转繁: ${tiers.tier3.length}`,``,
  `## ② 术语命中（复核参考，不入门禁）`, ...termHits.map((h) => `- \`${h.key}\`: ${h.hits.join(', ')}${h.quoteUnbalanced?' | 引号不成对，未转':''}`), ``,
  `## ③ 平台专属 key（必须人工 override）`, ...platformKeys.map((k) => `- \`${k}\` → 当前值「${produced.get(k)}」${overrides[k]?'（已 override）':' ⚠ 待复核'}`), ``,
  `## ④ 可疑条目（入门禁）`, ...suspects.map((s) => `- \`${s.key}\` [${s.tier}] ${s.suspicious.join(',')}: 「${s.value}」${overrides[s.key]?'（已 override）':' ⚠ 待复核'}`), ``,
  hardErrors.length ? `## ✗ 硬错误（占位符）\n${hardErrors.map((e) => `- \`${e.key}\`: ${e.why}`).join('\n')}` : `## ✓ 占位符校验全部通过`);
writeFileSync(cfg.report, rp.join('\n'), 'utf8');

console.log(`total=${keys.length} override=${tiers.override.length} tier1=${tiers.tier1.length} tier2=${tiers.tier2.length} tier3=${tiers.tier3.length} termHits=${termHits.length} platform=${platformKeys.length} suspects=${suspects.length} hardErrors=${hardErrors.length}`);
console.log(`draft -> ${cfg.out}\nreport -> ${cfg.report}`);

if (CHECK) {
  const needReview = new Set([...platformKeys, ...suspects.map((s) => s.key)]);
  const uncovered = [...needReview].filter((k) => !overrides[k]);
  const codecFailures = stringCodecFailures();
  const problems = [];
  if (hardErrors.length) problems.push(`${hardErrors.length} 条占位符硬错误`);
  if (uncovered.length) problems.push(`${uncovered.length} 条 ③/④ 未复核项（缺 override）`);
  if (tiers.tier1.length + tiers.tier2.length < keys.length * 0.3) problems.push(`tier1+2 覆盖率异常偏低（<30%），检查安卓语料输入`);
  if (codecFailures.length) problems.push(`Strings 转义回归失败：${codecFailures.join(', ')}`);
  if (problems.length) { console.error(`CHECK FAILED: ${problems.join('；')}`); process.exit(1); }
  console.log('CHECK PASSED (including Strings escape codec)');
}
