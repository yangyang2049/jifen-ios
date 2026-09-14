export function cloneOfficialBreakState(state: OfficialBreakWireState): OfficialBreakWireState {
  return {
    version: 1,
    sport: state.sport,
    kind: state.kind,
    phase: state.phase,
    startedAt: state.startedAt,
    endsAt: state.endsAt,
    remainingMs: state.remainingMs,
    prepareRemaining: state.prepareRemaining,
    revision: state.revision,
    afterAction: state.afterAction,
    title: state.title
  };
}

function sanitizeDisplayRestState(state: OfficialBreakWireState | undefined): OfficialBreakWireState | undefined {
  if (state === undefined || state.version !== 1 || !Number.isInteger(state.revision) || state.revision < 0 ||
    !Number.isFinite(state.startedAt) || state.startedAt < 0 ||
    !Number.isFinite(state.endsAt) || state.endsAt < state.startedAt ||
    !Number.isFinite(state.remainingMs) || state.remainingMs < 0 ||
    !Number.isInteger(state.prepareRemaining) || state.prepareRemaining < 0 ||
    ['badminton', 'pingpong', 'tennis', 'pickleball'].indexOf(state.sport) < 0 ||
    ['mid_game', 'game_break', 'set_break', 'changeover', 'timeout', 'medical'].indexOf(state.kind) < 0 ||
    ['countdown', 'prepare'].indexOf(state.phase) < 0 ||
    ['none', 'advance_period', 'exchange_sides', 'advance_and_exchange'].indexOf(state.afterAction) < 0) {
    return undefined;
  }
  const phaseValuesValid = state.phase === 'countdown'
    ? state.prepareRemaining === 0 && state.remainingMs <= state.endsAt - state.startedAt
    : state.remainingMs === 0 && state.prepareRemaining > 0;
  if (!phaseValuesValid) {
    return undefined;
  }
  return cloneOfficialBreakState(state);
}

function isDisplayStyleColor(value: Object | string | number | boolean | null | undefined): value is string {
  return typeof value === 'string' && /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(value);
}

export function sanitizeDisplayStyleSnapshotV2(
  value: DisplayStyleSnapshotV2 | Object | undefined
): DisplayStyleSnapshotV2 | undefined {
  if (!value || typeof value !== 'object') {
    return undefined;
  }
  const record = value as Record<string, Object | string | number | boolean | null | undefined>;
  if (record.version !== 2 || typeof record.themeCode !== 'string' ||
    typeof record.fontCode !== 'string' || !Array.isArray(record.panels) ||
    !Array.isArray(record.elements) || !isDisplayStyleColor(record.serverIndicatorColor) ||
    typeof record.styleRevision !== 'number' || !Number.isFinite(record.styleRevision) ||
    record.styleRevision < 0) {
    return undefined;
  }
  const fontSizeMultipliers: Record<string, number> = {};
  if (record.fontSizeMultipliers && typeof record.fontSizeMultipliers === 'object') {
    const source = record.fontSizeMultipliers as Record<string, Object | string | number | boolean | null | undefined>;
    Object.keys(source).forEach((key: string): void => {
      const multiplier = source[key];
      if (!key.startsWith('_') && typeof multiplier === 'number' && Number.isFinite(multiplier) && multiplier > 0) {
        fontSizeMultipliers[key] = multiplier;
      }
    });
  }
  const panelSlots: Set<string> = new Set();
  const panels: DisplayStylePanelV2[] = [];
  record.panels.forEach((rawPanel: Object): void => {
    if (!rawPanel || typeof rawPanel !== 'object') {
      return;
    }
    const panel = rawPanel as Record<string, Object | string | number | boolean | null | undefined>;
    if (typeof panel.slotKey !== 'string' || panel.slotKey.length === 0 ||
      panelSlots.has(panel.slotKey) || !isDisplayStyleColor(panel.backgroundColor)) {
      return;
    }
    panelSlots.add(panel.slotKey);
    panels.push({
      slotKey: panel.slotKey,
      participantId: typeof panel.participantId === 'string' ? panel.participantId : undefined,
      backgroundColor: panel.backgroundColor.toUpperCase()
    });
  });
  const elementKeys: Set<string> = new Set();
  const elements: DisplayStyleElementV2[] = [];
  record.elements.forEach((rawElement: Object): void => {
    if (!rawElement || typeof rawElement !== 'object') {
      return;
    }
    const element = rawElement as Record<string, Object | string | number | boolean | null | undefined>;
    if (typeof element.elementKey !== 'string' || element.elementKey.length === 0 ||
      elementKeys.has(element.elementKey) || !Array.isArray(element.textColors)) {
      return;
    }
    const colorSlots: Set<string> = new Set();
    const textColors: DisplayStyleTextColorV2[] = [];
    element.textColors.forEach((rawColor: Object): void => {
      if (!rawColor || typeof rawColor !== 'object') {
        return;
      }
      const color = rawColor as Record<string, Object | string | number | boolean | null | undefined>;
      if (typeof color.slotKey !== 'string' || color.slotKey.length === 0 ||
        colorSlots.has(color.slotKey) || !isDisplayStyleColor(color.color)) {
        return;
      }
      colorSlots.add(color.slotKey);
      textColors.push({ slotKey: color.slotKey, color: color.color.toUpperCase() });
    });
    if (textColors.length > 0) {
      elementKeys.add(element.elementKey);
      elements.push({ elementKey: element.elementKey, textColors });
    }
  });
  if (panels.length === 0) {
    return undefined;
  }
  return {
    version: 2,
    themeCode: record.themeCode,
    fontCode: record.fontCode,
    fontSizeMultipliers,
    panels,
    elements,
    serverIndicatorColor: record.serverIndicatorColor.toUpperCase(),
    styleRevision: Math.floor(record.styleRevision)
  };
}
import fs from 'node:fs';
import assert from 'node:assert/strict';
const state=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const style=sanitizeDisplayStyleSnapshotV2(state.appearance.style);
const rest=sanitizeDisplayRestState(state.rest);
assert.ok(style, 'Current iOS style rejected by HarmonyOS');
assert.ok(rest, 'Current iOS official break rejected by HarmonyOS');
assert.deepEqual(style.fontSizeMultipliers,state.appearance.style.fontSizeMultipliers);
assert.deepEqual(style.elements,state.appearance.style.elements);
assert.equal(sanitizeDisplayStyleSnapshotV2({fontSizeMultipliers:{mainScore:1.5}}),undefined);
console.log(JSON.stringify({iosAccepted:true,officialBreakAccepted:true,oldIncompleteStyleRejected:true,style,rest},null,2));
