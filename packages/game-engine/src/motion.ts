import { tokenCoordinate } from './board';
import type { Token } from './index';

export const STEP_MS = 240;

// This describes visuals only; dice, turn order and move selection are unchanged.
export function moveWaypoints(token: Token, from: number, index: number): [number, number][] {
  if (from === token.position) return [];
  if (from === 0 || token.position < from) return [tokenCoordinate(token, index)];
  return Array.from({ length: token.position - from }, (_, step) =>
    tokenCoordinate({ ...token, position: from + step + 1 }, index));
}
