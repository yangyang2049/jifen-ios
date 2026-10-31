const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const coreScript = html.match(/<script id="cornhole-core">([\s\S]*?)<\/script>/)[1];
const context = { window: {} };
vm.runInNewContext(coreScript, context);
const core = context.window.CornholeCore;

test('valid raw scores agree with every possible outcome of four 0/1/3-point bags', () => {
  const possible = new Set();
  for (const a of [0,1,3]) for (const b of [0,1,3]) {
    for (const c of [0,1,3]) for (const d of [0,1,3]) possible.add(a+b+c+d);
  }
  for (let raw = 0; raw <= 12; raw++) {
    assert.equal(core.validate([raw,0]) === '', possible.has(raw), `raw score ${raw}`);
    assert.equal(core.validate([0,raw]) === '', possible.has(raw));
  }
  assert.equal(possible.has(11), false);
});

test('7:5 credits only red 2 and clears the next round', () => {
  const before = { ...core.makeState(), draft:[7,5] };
  const after = core.settle(before);
  assert.equal(after.totals.join(','), '2,0');
  assert.equal(after.draft.join(','), '0,0');
  assert.equal(after.rounds[0].raw.join(','), '7,5');
  assert.equal(before.draft.join(','), '7,5');
  assert.equal(before.rounds.length, 0);
});

test('net 11 and maximum net 12 are both legitimate', () => {
  for (const [raw,expected] of [[[12,1],11],[[12,0],12]]) {
    const state = core.settle({ ...core.makeState(), draft:raw });
    assert.equal(state.totals[0], expected);
    assert.equal(state.totals[1], 0);
  }
});

test('blue can score, and a tied round preserves the next first throw', () => {
  const blue = core.settle({ ...core.makeState(), draft:[1,9] });
  assert.equal(blue.totals.join(','), '0,8');
  assert.equal(blue.first, 1);
  const tie = core.settle({ ...blue, draft:[6,6] });
  assert.equal(tie.totals.join(','), '0,8');
  assert.equal(tie.first, 1);
  assert.equal(tie.rounds.length, 2);
});

test('all-miss 0:0 is a valid recorded round', () => {
  const state = core.settle(core.makeState());
  assert.equal(state.totals.join(','), '0,0');
  assert.equal(state.rounds.length, 1);
});

test('winner is decided after cancellation, including going over 21', () => {
  const state = core.settle({ ...core.makeState(), totals:[20,18], draft:[3,1] });
  assert.equal(state.totals.join(','), '22,18');
  assert.equal(state.winner, 0);
  const blue = core.settle({ ...core.makeState(), totals:[20,18], draft:[10,12] });
  assert.equal(blue.totals.join(','), '20,20');
  assert.equal(blue.winner, null);
  assert.equal(core.change(state,0,1), state);
  assert.equal(core.settle(state), state);
});

test('raw 11, fractional and out-of-range scores cannot be settled', () => {
  for (const draft of [[11,0],[0,11],[-1,0],[13,0],[1.5,0]]) {
    assert.throws(() => core.settle({ ...core.makeState(), draft }));
  }
});

test('tap input stays within 0–12, including editable 11 on the way to 12', () => {
  let state = core.makeState();
  for (let i = 0; i < 11; i++) state = core.change(state,0,1);
  assert.equal(state.draft[0], 11);
  assert.notEqual(core.validate(state.draft), '');
  state = core.change(state,0,1);
  assert.equal(state.draft[0], 12);
  assert.equal(core.validate(state.draft), '');
  assert.equal(core.change(state,0,1), state);
  assert.equal(core.change(state,1,-1), state);
  assert.equal(state.totals.join(','), '0,0');
});
