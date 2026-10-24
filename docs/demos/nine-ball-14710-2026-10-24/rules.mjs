/** Pure scoring rules for the 14710 chase-score interaction demo. */
export const PLAYER_NAMES = ['甲', '乙', '丙', '丁'];

const TITLES = {
  normal: '普胜',
  big: '大金',
  small: '小金',
  golden: '黄金9',
  foul: '犯规',
  handoff: '让杆',
};
const WIN_KINDS = new Set(['normal', 'big', 'small', 'golden']);
let eventSequence = 0;

function isPlayer(value, count) {
  return Number.isInteger(value) && value >= 0 && value < count;
}

function nextSeat(player, count) {
  return (player + 1) % count;
}

function validateConfiguration({ count, smallGoldMode, goldRetainsBreak, breaker }) {
  if (!Number.isInteger(count) || count < 2 || count > 4) {
    return '人数必须为 2、3 或 4 人。';
  }
  if (!['breaker', 'all'].includes(smallGoldMode)) {
    return '小金赔付模式必须为 breaker 或 all。';
  }
  if (typeof goldRetainsBreak !== 'boolean') {
    return '大金／黄金9续开设置必须为布尔值。';
  }
  if (!isPlayer(breaker, count)) {
    return '本局开球人不在有效玩家范围内。';
  }
  return null;
}

export function createGame({
  count = 3,
  smallGoldMode = 'breaker',
  goldRetainsBreak = true,
  breaker = 0,
} = {}) {
  const error = validateConfiguration({ count, smallGoldMode, goldRetainsBreak, breaker });
  if (error) throw new RangeError(error);
  return {
    count,
    scores: Array(count).fill(0),
    round: 1,
    breaker,
    currentShooter: null,
    smallGoldMode,
    goldRetainsBreak,
    history: [],
  };
}

export function previewEvent(game, options = {}) {
  const { kind, actor } = options;
  const result = {
    kind,
    actor,
    payer: options.payer ?? null,
    continuePlayer: options.continuePlayer ?? null,
    changes: Array(Number.isInteger(game.count) && game.count >= 2 && game.count <= 4 ? game.count : 0).fill(0),
    endsRack: WIN_KINDS.has(kind),
    nextBreaker: game.breaker,
    roundBefore: game.round,
    breakerBefore: game.breaker,
    title: TITLES[kind] ?? '未知事件',
    error: null,
    summary: '',
  };
  const reject = (message) => ({ ...result, error: message, summary: message });
  const configurationError = validateConfiguration(game);
  if (configurationError) return reject(configurationError);
  if (!Array.isArray(game.scores) || game.scores.length !== game.count || !game.scores.every(Number.isFinite)) {
    return reject('当前比分数据无效。');
  }
  if (!Number.isInteger(game.round) || game.round < 1) return reject('当前局数无效。');
  if (!Object.hasOwn(TITLES, kind)) return reject('请选择有效事件。');
  if (!isPlayer(actor, game.count)) return reject('请选择有效玩家。');
  if (options.payer !== undefined && options.payer !== null && !isPlayer(options.payer, game.count)) {
    return reject('付分人不在有效玩家范围内。');
  }
  if (options.continuePlayer !== undefined && options.continuePlayer !== null && !isPlayer(options.continuePlayer, game.count)) {
    return reject('继续击球人不在有效玩家范围内。');
  }

  const transfer = (payer, receiver, points) => {
    result.changes[payer] -= points;
    result.changes[receiver] += points;
  };
  const allOthersPay = (points) => {
    for (let player = 0; player < game.count; player += 1) {
      if (player !== actor) transfer(player, actor, points);
    }
  };

  switch (kind) {
    case 'big':
      if (actor !== game.breaker) return reject('大金必须由本局开球人取得，请先更正本局开球人。');
      result.payer = null;
      result.continuePlayer = null;
      allOthersPay(10);
      break;
    case 'golden':
      result.payer = null;
      result.continuePlayer = null;
      allOthersPay(4);
      break;
    case 'small':
      result.continuePlayer = null;
      if (game.smallGoldMode === 'all') {
        result.payer = null;
        allOthersPay(7);
      } else {
        result.payer = options.payer ?? game.breaker;
        if (result.payer === actor) return reject('小金赢家不能同时是本局开球人／付分人，请核对本局开球人。');
        // A correction made in the confirmation belongs to this event's rack.
        result.breakerBefore = result.payer;
        transfer(result.payer, actor, 7);
      }
      break;
    case 'normal':
      result.payer = options.payer ?? (actor + game.count - 1) % game.count;
      result.continuePlayer = null;
      if (result.payer === actor) return reject('付分人不能是获胜者本人。');
      transfer(result.payer, actor, 4);
      break;
    case 'foul':
      result.payer = actor;
      result.continuePlayer = nextSeat(actor, game.count);
      transfer(actor, result.continuePlayer, 1);
      break;
    case 'handoff':
      result.payer = null;
      if (!isPlayer(result.continuePlayer, game.count)) return reject('请选择继续击球的玩家。');
      if (result.continuePlayer === actor) return reject('让杆需选择另一位玩家继续击球。');
      break;
  }

  if (result.endsRack) {
    result.nextBreaker = (kind === 'big' || kind === 'golden') && game.goldRetainsBreak
      ? actor
      : nextSeat(actor, game.count);
  }
  if (result.changes.reduce((sum, change) => sum + change, 0) !== 0) {
    return reject('本次转分不平衡，无法记分。');
  }
  if (kind === 'handoff') {
    result.summary = `${PLAYER_NAMES[actor]}让杆，${PLAYER_NAMES[result.continuePlayer]}继续击球；不改分，本局继续。`;
  } else {
    const changes = result.changes
      .map((change, player) => change === 0 ? null : `${PLAYER_NAMES[player]} ${change > 0 ? '+' : '−'}${Math.abs(change)}`)
      .filter(Boolean)
      .join('，');
    result.summary = `${PLAYER_NAMES[actor]}${result.title}：${changes}；${result.endsRack
      ? `下一局${PLAYER_NAMES[result.nextBreaker]}开球。`
      : `${PLAYER_NAMES[result.continuePlayer]}自由球，本局继续。`}`;
  }
  return result;
}

export function applyEvent(game, options) {
  const preview = previewEvent(game, options);
  if (preview.error) throw new Error(preview.error);
  const before = {
    scores: [...game.scores],
    round: game.round,
    breaker: game.breaker,
    currentShooter: game.currentShooter,
  };
  const entry = {
    ...preview,
    changes: [...preview.changes],
    id: `event-${Date.now().toString(36)}-${(++eventSequence).toString(36)}`,
    before,
  };
  return {
    ...game,
    scores: game.scores.map((score, player) => score + preview.changes[player]),
    round: game.round + (preview.endsRack ? 1 : 0),
    breaker: preview.nextBreaker,
    currentShooter: preview.endsRack ? preview.nextBreaker : preview.continuePlayer,
    history: [...game.history, entry],
  };
}

export function undoGame(game) {
  const lastEntry = game.history.at(-1);
  if (!lastEntry) return game;
  return {
    ...game,
    ...lastEntry.before,
    scores: [...lastEntry.before.scores],
    history: game.history.slice(0, -1),
  };
}
