import { COLORS, HOME, type Color, type Token } from './types';

// Coordinates are [row, column] on a 15 × 15 board.
export const TRACK: [number, number][] = [
  [6,1],[6,2],[6,3],[6,4],[6,5],[5,6],[4,6],[3,6],[2,6],[1,6],[0,6],[0,7],[0,8],
  [1,8],[2,8],[3,8],[4,8],[5,8],[6,9],[6,10],[6,11],[6,12],[6,13],[6,14],[7,14],[8,14],
  [8,13],[8,12],[8,11],[8,10],[8,9],[9,8],[10,8],[11,8],[12,8],[13,8],[14,8],[14,7],[14,6],
  [13,6],[12,6],[11,6],[10,6],[9,6],[8,5],[8,4],[8,3],[8,2],[8,1],[8,0],[7,0],[6,0],
];
export const SAFE_CELLS = [0, 8, 13, 21, 26, 34, 39, 47];
export const START_OFFSETS: Record<Color, number> = { coral: 0, sun: 13, mint: 26, violet: 39 };
export function trackIndex(token: Token) {
  return token.position > 0 && token.position <= 51 ? (START_OFFSETS[token.color] + token.position - 1) % 52 : null;
}
export function tokenCoordinate(token: Token, index: number): [number, number] {
  const color = COLORS.indexOf(token.color);
  if (token.position === 0) {
    const bases = [[1,1],[1,10],[10,10],[10,1]];
    return [bases[color][0] + (index >= 2 ? 2 : 0) + 1, bases[color][1] + (index % 2 ? 2 : 0) + 1];
  }
  if (token.position === HOME) return [7,7];
  const track = trackIndex(token);
  if (track !== null) return TRACK[track];
  const lane = token.position - 51;
  return color === 0 ? [7,lane] : color === 1 ? [lane,7] : color === 2 ? [7,14-lane] : [14-lane,7];
}
