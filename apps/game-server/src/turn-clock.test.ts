import { expect, it } from 'vitest';
import { createGame, startGame, rollDice } from '../../../packages/game-engine/src/index';
import { expireTurn } from './turn-clock';
const players = [{id:'a',name:'A',color:'coral' as const,ready:true},{id:'b',name:'B',color:'sun' as const,ready:true}];
it('expires an unrolled turn without changing tokens', () => {
  const before = startGame(createGame(players));
  const after = expireTurn(before);
  expect(after.currentPlayer).toBe('b');
  expect(after.phase).toBe('rolling');
  expect(after.version).toBe(before.version+1);
  expect(after.tokens).toEqual(before.tokens);
});
it('expires a move selection and clears the pending roll', () => {
  const before = rollDice(startGame(createGame(players)),()=>0.99);
  expect(before.phase).toBe('moving');
  const after = expireTurn(before);
  expect(after.dice).toBeNull();
  expect(after.currentPlayer).toBe('b');
  expect(expireTurn(after).currentPlayer).toBe('a');
});
it('never expires a lobby or finished match', () => {
  const lobby = createGame(players);
  expect(expireTurn(lobby)).toBe(lobby);
  const finished = {...lobby,phase:'finished' as const,winner:'a'};
  expect(expireTurn(finished)).toBe(finished);
});
