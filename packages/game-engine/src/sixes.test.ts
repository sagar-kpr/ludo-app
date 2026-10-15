import { describe, expect, it } from 'vitest';
import { createGame, diceSidesForRoll, moveToken, removePlayer, restartGame, rollDice, startGame } from './index';

const players = [
  { id: 'a', name: 'A', color: 'coral' as const, ready: true },
  { id: 'b', name: 'B', color: 'mint' as const, ready: true },
];
const fresh = () => startGame(createGame(players));

describe('at most two consecutive sixes per player', () => {
  it('allows two sixes and forces the third roll to 1–5 without forfeiting the move', () => {
    let state = fresh();
    for (let count = 1; count <= 2; count++) {
      state = rollDice(state, () => 0.99999);
      expect(state.dice).toBe(6);
      expect(state.consecutiveSixes?.a).toBe(count);
      state = moveToken(state, 'a-0');
      expect(state.currentPlayer).toBe('a');
    }
    const third = rollDice(state, () => 0.99999);
    expect(third.dice).toBe(5);
    expect(third.consecutiveSixes?.a).toBe(0);
    expect(moveToken(third, 'a-0').tokens[0].position).toBe(12);
  });
  it('uses all five result buckets after two sixes, then permits another six', () => {
    const state = { ...fresh(), consecutiveSixes: { a: 2 } };
    for (let value = 1; value <= 5; value++) {
      const rolled = rollDice(state, () => (value - 0.5) / 5);
      // Base pawns cannot move on 1–5, but the roll still breaks the streak.
      expect(rolled.dice).toBeNull();
      expect(rolled.consecutiveSixes?.a).toBe(0);
      expect(rollDice({ ...rolled, currentPlayer: 'a' }, () => 0.99999).dice).toBe(6);
    }
  });
  it('keeps each player’s own streak across other players’ turns', () => {
    const state = { ...fresh(), consecutiveSixes: { a: 2, b: 1 } };
    const other = rollDice({ ...state, currentPlayer: 'b' }, () => 0.99999);
    expect(other.dice).toBe(6);
    expect(other.consecutiveSixes).toEqual({ a: 2, b: 2 });
    const returned = rollDice({ ...other, phase: 'rolling', currentPlayer: 'a' }, () => 0.99999);
    expect(returned.consecutiveSixes).toEqual({ a: 0, b: 2 });
  });
  it('resets only the rolling player’s streak on a non-six', () => {
    const rolled = rollDice({ ...fresh(), consecutiveSixes: { a: 1, b: 2 } }, () => 0);
    expect(rolled.consecutiveSixes).toEqual({ a: 0, b: 2 });
  });
  it('supports older snapshots and clears streaks on departure and restart', () => {
    const old = { ...fresh(), consecutiveSixes: undefined };
    expect(diceSidesForRoll(old)).toBe(6);
    expect(rollDice(old, () => 0.99999).consecutiveSixes).toEqual({ a: 1 });
    const state = { ...fresh(), consecutiveSixes: { a: 2, b: 1 } };
    expect(removePlayer(state, 'a').consecutiveSixes).toEqual({ b: 1 });
    expect(restartGame({ ...state, phase: 'finished' }).consecutiveSixes).toEqual({});
    expect(rollDice({ ...state, phase: 'moving' })).toEqual({ ...state, phase: 'moving' });
  });
});
