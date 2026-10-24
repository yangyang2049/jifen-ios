import test from 'node:test';
import assert from 'node:assert/strict';
import { PLAYER_NAMES, createGame, previewEvent, applyEvent, undoGame } from './rules.mjs';

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

test('game defaults and names match the three-player demo', () => {
  assert.deepEqual(PLAYER_NAMES, ['甲', '乙', '丙', '丁']);
  assert.deepEqual(createGame(), {
    count: 3,
    scores: [0, 0, 0],
    round: 1,
    breaker: 0,
    currentShooter: null,
    smallGoldMode: 'breaker',
    goldRetainsBreak: true,
    history: [],
  });
});

for (const count of [2, 3, 4]) {
  test(`${count} players: big/golden collect one share per other player`, () => {
    const game = createGame({ count });
    for (const [kind, points] of [['big', 10], ['golden', 4]]) {
      const preview = previewEvent(game, { kind, actor: 0 });
      assert.equal(preview.error, null);
      assert.deepEqual(preview.changes, [(count - 1) * points, ...Array(count - 1).fill(-points)]);
      assert.equal(sum(preview.changes), 0);
      const next = applyEvent(game, { kind, actor: 0 });
      assert.deepEqual(next.scores, preview.changes);
      assert.equal(sum(next.scores), 0);
      assert.equal(next.round, 2);
      assert.equal(next.breaker, 0);
    }
  });

  test(`${count} players: normal and default small transfer a single share`, () => {
    const game = createGame({ count });
    const normal = previewEvent(game, { kind: 'normal', actor: 1 });
    const small = previewEvent(game, { kind: 'small', actor: 1 });
    assert.deepEqual(normal.changes, [-4, 4, ...Array(count - 2).fill(0)]);
    assert.deepEqual(small.changes, [-7, 7, ...Array(count - 2).fill(0)]);
    assert.equal(normal.payer, 0);
    assert.equal(small.payer, 0);
    assert.equal(small.breakerBefore, 0);
    assert.equal(sum(normal.changes), 0);
    assert.equal(sum(small.changes), 0);
    assert.equal(normal.nextBreaker, 2 % count);
    assert.equal(small.nextBreaker, 2 % count);
  });

  test(`${count} players: all-player small mode collects all seven-point shares`, () => {
    const game = createGame({ count, smallGoldMode: 'all' });
    const preview = previewEvent(game, { kind: 'small', actor: 0 });
    assert.equal(preview.error, null);
    assert.equal(preview.payer, null);
    assert.deepEqual(preview.changes, [(count - 1) * 7, ...Array(count - 1).fill(-7)]);
    assert.equal(sum(preview.changes), 0);
  });

  test(`${count} players: foul pays the next seat and keeps rack/breaker`, () => {
    const game = createGame({ count, breaker: 1 });
    const actor = count - 1;
    const next = applyEvent(game, { kind: 'foul', actor });
    assert.equal(next.scores[actor], -1);
    assert.equal(next.scores[0], 1);
    assert.equal(sum(next.scores), 0);
    assert.equal(next.round, 1);
    assert.equal(next.breaker, 1);
    assert.equal(next.currentShooter, 0);
    assert.equal(next.history[0].endsRack, false);
  });
}

test('normal payer can be confirmed as the actual previous shooter', () => {
  const game = createGame({ count: 4, breaker: 0 });
  const preview = previewEvent(game, { kind: 'normal', actor: 2, payer: 0 });
  assert.deepEqual(preview.changes, [-4, 0, 4, 0]);
  assert.equal(preview.payer, 0);
  assert.equal(preview.breakerBefore, 0);
  assert.equal(preview.nextBreaker, 3);
  assert.match(preview.summary, /甲 −4/);
  assert.match(preview.summary, /丙 \+4/);
});

test('small payer correction is recorded as the effective rack breaker', () => {
  const game = createGame({ count: 4, breaker: 0 });
  const preview = previewEvent(game, { kind: 'small', actor: 1, payer: 3 });
  assert.equal(preview.error, null);
  assert.equal(preview.breakerBefore, 3);
  assert.deepEqual(preview.changes, [0, 7, 0, -7]);
  const next = applyEvent(game, { kind: 'small', actor: 1, payer: 3 });
  assert.equal(next.history[0].breakerBefore, 3);
  assert.equal(next.history[0].before.breaker, 0);
  assert.deepEqual(undoGame(next), game);
});

test('golden/big retain the winner when enabled; otherwise next seat of winner', () => {
  for (const goldRetainsBreak of [true, false]) {
    const game = createGame({ count: 3, breaker: 1, goldRetainsBreak });
    assert.equal(previewEvent(game, { kind: 'big', actor: 1 }).nextBreaker, goldRetainsBreak ? 1 : 2);
    // Winner differs from current breaker, to distinguish winner-next from breaker-next.
    assert.equal(previewEvent(game, { kind: 'golden', actor: 2 }).nextBreaker, goldRetainsBreak ? 2 : 0);
    assert.equal(previewEvent(game, { kind: 'normal', actor: 2 }).nextBreaker, 0);
    assert.equal(previewEvent(game, { kind: 'small', actor: 2 }).nextBreaker, 0);
  }
});

test('the user four-rack example: A big, B golden, C normal, B small', () => {
  let game = createGame();
  const options = [
    { kind: 'big', actor: 0 },
    { kind: 'golden', actor: 1 },
    { kind: 'normal', actor: 2 },
    { kind: 'small', actor: 1 },
  ];
  const expectedBreakers = [0, 1, 0, 2];
  for (const [index, event] of options.entries()) {
    game = applyEvent(game, event);
    assert.equal(game.breaker, expectedBreakers[index]);
    assert.equal(game.currentShooter, expectedBreakers[index]);
    assert.equal(game.round, index + 2);
    assert.equal(sum(game.scores), 0);
  }
  assert.deepEqual(game.scores, [9, 1, -10]);
  assert.deepEqual(game.history.map((entry) => entry.breakerBefore), [0, 0, 1, 0]);
});

test('handoff changes only shooter and history; it never scores or ends rack', () => {
  const game = createGame({ count: 4, breaker: 2 });
  const preview = previewEvent(game, { kind: 'handoff', actor: 0, continuePlayer: 3 });
  assert.deepEqual(preview.changes, [0, 0, 0, 0]);
  assert.equal(preview.endsRack, false);
  assert.equal(preview.nextBreaker, 2);
  assert.match(preview.summary, /丁继续击球/);
  const next = applyEvent(game, { kind: 'handoff', actor: 0, continuePlayer: 3 });
  assert.equal(next.round, 1);
  assert.equal(next.breaker, 2);
  assert.equal(next.currentShooter, 3);
  assert.deepEqual(next.scores, [0, 0, 0, 0]);
});

test('full undo restores scores, round, breaker and shooter after a mixed event stream', () => {
  const initial = createGame();
  const states = [initial];
  for (const event of [
    { kind: 'foul', actor: 1 },
    { kind: 'handoff', actor: 2, continuePlayer: 1 },
    { kind: 'normal', actor: 2, payer: 0 },
    { kind: 'small', actor: 1 },
    { kind: 'golden', actor: 0 },
  ]) {
    states.push(applyEvent(states.at(-1), event));
  }
  let game = states.at(-1);
  for (let index = states.length - 2; index >= 0; index -= 1) {
    game = undoGame(game);
    assert.deepEqual(game, states[index]);
  }
  assert.deepEqual(undoGame(game), initial);
});

test('preview and apply reject self payment, invalid big winner and invalid handoff', () => {
  const game = createGame();
  for (const event of [
    { kind: 'normal', actor: 1, payer: 1 },
    { kind: 'small', actor: 0 },
    { kind: 'small', actor: 1, payer: 1 },
    { kind: 'big', actor: 1 },
    { kind: 'handoff', actor: 0 },
    { kind: 'handoff', actor: 0, continuePlayer: 0 },
  ]) {
    assert.equal(typeof previewEvent(game, event).error, 'string');
    assert.throws(() => applyEvent(game, event));
  }
});

test('all invalid player indices are rejected without clamping', () => {
  const game = createGame();
  for (const index of [-1, 3, 8, 1.5, '1', NaN, Infinity]) {
    for (const event of [
      { kind: 'normal', actor: index },
      { kind: 'normal', actor: 1, payer: index },
      { kind: 'small', actor: 1, payer: index },
      { kind: 'handoff', actor: 0, continuePlayer: index },
    ]) {
      assert.equal(typeof previewEvent(game, event).error, 'string');
      assert.throws(() => applyEvent(game, event));
    }
  }
  assert.ok(previewEvent(game, { kind: 'normal' }).error);
  assert.ok(previewEvent(game, { kind: 'typo', actor: 0 }).error);
});

test('configuration is validated strictly', () => {
  for (const config of [
    { count: 1 }, { count: 5 }, { count: 2.5 }, { count: '3' },
    { breaker: -1 }, { breaker: 3 }, { breaker: '0' },
    { smallGoldMode: 'other' }, { goldRetainsBreak: 1 },
  ]) assert.throws(() => createGame(config), RangeError);
});

test('preview, apply and undo leave old state and options unchanged', () => {
  const game = createGame();
  Object.freeze(game.scores);
  Object.freeze(game.history);
  Object.freeze(game);
  const options = Object.freeze({ kind: 'normal', actor: 1 });
  const original = structuredClone(game);
  const preview = previewEvent(game, options);
  assert.equal(preview.error, null);
  assert.deepEqual(game, original);
  const next = applyEvent(game, options);
  assert.deepEqual(game, original);
  const snapshot = structuredClone(next);
  assert.deepEqual(undoGame(next), game);
  assert.deepEqual(next, snapshot);
  assert.notStrictEqual(next.scores, game.scores);
  assert.notStrictEqual(next.history, game.history);
  assert.notStrictEqual(next.history[0].before.scores, game.scores);
  assert.equal('history' in next.history[0].before, false);
  const second = applyEvent(next, { kind: 'foul', actor: 0 });
  assert.notEqual(second.history[0].id, second.history[1].id);
  assert.equal('history' in second.history[1].before, false);
});
