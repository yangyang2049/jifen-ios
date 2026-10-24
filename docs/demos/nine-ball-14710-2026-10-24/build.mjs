import { readFile, writeFile } from 'node:fs/promises';

const source = await readFile(new URL('./source.html', import.meta.url), 'utf8');
const rules = await readFile(new URL('./rules.mjs', import.meta.url), 'utf8');
const importLine = "import { PLAYER_NAMES, createGame, previewEvent, applyEvent, undoGame } from './rules.mjs';";
if (!source.includes(importLine)) throw new Error('Rules import marker missing.');
const inlineRules = `const { PLAYER_NAMES, createGame, previewEvent, applyEvent, undoGame } = (() => {\n${rules.replace(/^export /gm, '')}\nreturn { PLAYER_NAMES, createGame, previewEvent, applyEvent, undoGame };\n})();`;
await writeFile(new URL('./index.html', import.meta.url), source.replace(importLine, inlineRules));
console.log('Built standalone index.html; no server or external assets required.');
