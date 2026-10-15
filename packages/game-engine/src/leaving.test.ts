import { expect, it } from 'vitest';
import { COLORS, createGame, removePlayer, rollDice, startGame } from './index';

const players = COLORS.map((color, i) => ({ id: String(i), name: `Player ${i}`, color, ready: true }));
it('removes the current player and their pawns, preserving the departed seat for display', () => {
  const game = { ...startGame(createGame(players)), phase: 'moving' as const, dice: 6 };
  const next = removePlayer(game, '0');
  expect(next.currentPlayer).toBe('1');
  expect(next.phase).toBe('rolling');
  expect(next.dice).toBeNull();
  expect(next.departedPlayers).toEqual([players[0]]);
  expect(next.tokens.some(token => token.color === players[0].color)).toBe(false);
  expect(removePlayer(next, '0')).toBe(next);
  expect(rollDice({ ...next, currentPlayer: '3' }, () => 0).currentPlayer).toBe('1');
});
it('keeps the current roll when another player leaves and declares the sole survivor', () => {
  const game = { ...startGame(createGame(players.slice(0, 3))), phase: 'moving' as const, dice: 6 };
  const next = removePlayer(game, '1');
  expect(next.currentPlayer).toBe('0');
  expect(next.dice).toBe(6);
  expect(next.phase).toBe('moving');
  const finished = removePlayer(next, '0');
  expect(finished.phase).toBe('finished');
  expect(finished.winner).toBe('2');
  expect(finished.finishOrder).toEqual(['2']);
  expect(finished.dice).toBeNull();
  expect(finished.departedPlayers).toEqual([players[1], players[0]]);
});
it('retains an earned winner when a later player leaves', () => {
  const game = { ...startGame(createGame(players)), finishOrder: ['2'], winner: '2' };
  expect(removePlayer(game, '1').winner).toBe('2');
});
