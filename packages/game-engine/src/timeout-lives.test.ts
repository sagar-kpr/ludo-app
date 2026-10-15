import { expect, it } from 'vitest';
import { createGame, moveToken, restartGame, rollDice, startGame } from './index';

const players = [
  { id: 'a', name: 'A', color: 'coral' as const, ready: true },
  { id: 'b', name: 'B', color: 'mint' as const, ready: true },
];
it('starts each player with five timeout chances and resets for a fresh match', () => {
  const state = createGame(players);
  expect(state.timeoutLives).toEqual({ a: 5, b: 5 });
  expect(restartGame({ ...state, phase: 'finished', timeoutLives: { a: 1, b: 2 } }).timeoutLives).toEqual({ a: 5, b: 5 });
});
it('manual rolls and moves preserve spent lives without charging or refilling', () => {
  const state = { ...startGame(createGame(players)), timeoutLives: { a: 2, b: 4 } };
  const rolled = rollDice(state, () => 0.99);
  expect(rolled.timeoutLives).toEqual({ a: 2, b: 4 });
  expect(moveToken(rolled, 'a-0').timeoutLives).toEqual({ a: 2, b: 4 });
});
