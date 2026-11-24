#!/usr/bin/env node
/* Generate the Apple Watch zh-Hant catalog from zh-Hans.
 *
 * Mirrors scripts/localization/gen_zh_hant.mjs: phone zh-Hant values win for
 * shared keys (tier 1), everything else goes through opencc cn->tw plus the
 * reviewed term replacements (tier 2). The watch has no Android corpus, so
 * there is no value-anchored tier.
 *
 * Usage: node scripts/localization/gen_watch_zh_hant.mjs [--check]
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const CHECK = process.argv.includes('--check');
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const IOS_ROOT = path.resolve(SCRIPT_DIR, '../..');
const WORKSPACE_ROOT = path.dirname(IOS_ROOT);
const WEBSITE_ROOT = path.join(WORKSPACE_ROOT, 'jifenqi-website');

const HANS = path.join(IOS_ROOT, 'jifenWatch Watch App/Resources/zh-Hans.lproj/Localizable.strings');
const PHONE_HANT = path.join(IOS_ROOT, 'jifen/Resources/zh-Hant.lproj/Localizable.strings');
const TERMS = path.join(IOS_ROOT, 'scripts/localization/zh-Hant-terms.json');
const OUT = path.join(IOS_ROOT, 'jifenWatch Watch App/Resources/zh-Hant.lproj/Localizable.strings');

const requireFromWebsite = createRequire(path.join(WEBSITE_ROOT, 'package.json'));
const OpenCC = requireFromWebsite('opencc-js/cn2t');
const convert = OpenCC.Converter({ from: 'cn', to: 'tw' });
const replacements = JSON.parse(readFileSync(TERMS, 'utf8')).replacements ?? [];

const ENTRY_RE = /^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$/;

function parse(file) {
  const map = new Map();
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const match = ENTRY_RE.exec(line.trim());
    if (match) map.set(match[1], match[2]);
  }
  return map;
}

function postProcess(value) {
  let out = value;
  for (const { from, to } of replacements) out = out.split(from).join(to);
  return out;
}

const hans = parse(HANS);
const phoneHant = existsSync(PHONE_HANT) ? parse(PHONE_HANT) : new Map();

const lines = [
  '/* Watch App - 繁體中文（由 zh-Hans 轉換，共用鍵沿用手機 zh-Hant） */',
  '',
];
let reused = 0;
let converted = 0;
for (const [key, value] of hans) {
  let output;
  if (phoneHant.has(key)) {
    output = phoneHant.get(key);
    reused += 1;
  } else {
    output = postProcess(convert(value));
    converted += 1;
  }
  lines.push(`"${key}" = "${output}";`);
}
lines.push('');

const content = lines.join('\n');
if (CHECK) {
  const current = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  if (current !== content) {
    console.error('watch zh-Hant is out of date; re-run without --check');
    process.exit(1);
  }
  console.log('watch zh-Hant is up to date');
  process.exit(0);
}

writeFileSync(OUT, content);
console.log(`wrote ${OUT} (reused ${reused}, converted ${converted})`);
