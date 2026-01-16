import { GameType, GameTypeIcons, GameTypeNames } from '../../../model/types';

export const GAME_GRADIENTS: Record<GameType, [ResourceColor, ResourceColor]> = {
  [GameType.BASKETBALL]: ['#EA580C', '#C2410C'], // Orange
  [GameType.FOOTBALL]: ['#10B981', '#047857'],   // Emerald
  [GameType.BADMINTON]: ['#3B82F6', '#1E40AF'],  // Blue
  [GameType.PINGPONG]: ['#EF4444', '#B91C1C'],   // Red
  [GameType.TENNIS]: ['#84CC16', '#4D7C0F'],     // Lime
  [GameType.VOLLEYBALL]: ['#EAB308', '#A16207'], // Yellow
  [GameType.GO]: ['#57534E', '#292524'],         // Stone
  [GameType.XIANGQI]: ['#B45309', '#78350F'],    // Amber
  [GameType.CHESS]: ['#525252', '#262626'],      // Neutral
  [GameType.CHECKERS]: ['#A3A3A3', '#525252'],   // Neutral Light
  [GameType.BOXING]: ['#DC2626', '#991B1B'],     // Red
  [GameType.BILLIARDS]: ['#0F766E', '#115E59'],  // Teal
  [GameType.PICKLEBALL]: ['#14B8A6', '#0F766E'], // Teal
  [GameType.GUANDAN]: ['#8B5CF6', '#6D28D9'],    // Violet
  [GameType.DOUDIZHU]: ['#F97316', '#C2410C'],   // Orange
  [GameType.SIMPLE_SCORE]: ['#6B7280', '#374151'], // Gray
  [GameType.MULTI_SCOREBOARD]: ['#6366F1', '#4338CA'], // Indigo
  [GameType.COUNTER]: ['#EC4899', '#BE185D'],    // Pink
};

export function getGameName(type: GameType): string {
  return GameTypeNames[type] || 'Unknown';
}

export function getGameIcon(type: GameType): string {
  return GameTypeIcons[type] || '🎮';
}

export function getGameGradient(type: GameType): [ResourceColor, ResourceColor] {
  return GAME_GRADIENTS[type] || ['#71717A', '#3F3F46'];
}

export function getGameStats(type: GameType): string {
  // Placeholder for now, can be connected to real stats later
  return '开始比赛';
}
