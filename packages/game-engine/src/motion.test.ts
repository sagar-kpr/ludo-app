import { describe, expect, it } from 'vitest';
import { moveWaypoints } from './motion';
import { tokenCoordinate } from './board';
import { HOME } from './types';

describe('visual movement path', () => {
  it('visits every intervening square, including corners and home entry', () => {
    for (const color of ['coral', 'sun', 'mint', 'violet'] as const) {
      for (const from of [4, 11, 49, 53]) {
        const token = { id: color+'-0', color, position: Math.min(HOME, from+5) };
        expect(moveWaypoints(token, from, 0)).toEqual(Array.from({length: token.position-from}, (_, n) => tokenCoordinate({ ...token, position: from+n+1 }, 0)));
      }
    }
  });
  it('uses one final hop from the last lane cell into the finished triangle', () => {
    for (const color of ['coral', 'sun', 'mint', 'violet'] as const) {
      const token = { id: color+'-0', color, position: HOME };
      expect(moveWaypoints(token, HOME-1, 0)).toEqual([tokenCoordinate(token, 0)]);
    }
  });
  it('handles base entry and captures without traversing the track backwards', () => {
    expect(moveWaypoints({ id: 'a', color: 'coral', position: 1 }, 0, 0)).toHaveLength(1);
    const captured = { id: 'a', color: 'coral' as const, position: 0 };
    expect(moveWaypoints(captured, 15, 0)).toEqual([tokenCoordinate(captured, 0)]);
    expect(moveWaypoints(captured, 0, 0)).toEqual([]);
  });
});
