import { describe, expect, it } from 'vitest';
import { COLORS, createGame, moveToken, restartGame, rollDice, startGame, type GameState } from './index';
import { expireTurn } from '../../../apps/game-server/src/turn-clock';

const players = COLORS.map((color,index) => ({id:String(index),name:`Player ${index}`,color,ready:true}));
function finishPlayer(state: GameState, id: string) {
  const color = state.players.find(player => player.id === id)!.color;
  return moveToken({...state,currentPlayer:id,phase:'moving',dice:1,tokens:state.tokens.map(token => token.color === color ? {...token,position:token.id === `${id}-0` ? 57 : 58} : token)},`${id}-0`);
}
describe('ranked multiplayer matches', () => {
  for (const count of [2,3,4]) it(`ends a ${count}-player match after ${count-1} finishers`, () => {
    let state = startGame(createGame(players.slice(0,count)));
    for (let i=0;i<count-1;i++) {
      state = finishPlayer(state,String(i));
      expect(state.winner).toBe('0');
      expect(state.phase).toBe(i === count-2 ? 'finished' : 'rolling');
      if (i < count-2) expect(state.currentPlayer).toBe(String(i+1));
    }
    expect(state.finishOrder).toEqual(players.slice(0,count).map(player => player.id));
    expect(moveToken(state,'0-0')).toBe(state);
    expect(rollDice(state)).toBe(state);
    const restarted = restartGame(state);
    expect(restarted.version).toBe(state.version+1);
    expect(restarted.players).toEqual(state.players);
    expect(restarted.phase).toBe('rolling');
    expect(restarted.currentPlayer).toBe('0');
    expect(restarted.finishOrder).toEqual([]);
    expect(restarted.winner).toBeUndefined();
    expect(restarted.tokens.every(token => token.position === 0)).toBe(true);
  });
  it('skips finishers on normal passes, unmovable rolls and timeouts', () => {
    const ranked = finishPlayer(startGame(createGame(players)),'0');
    const state = {...ranked,currentPlayer:'3'};
    expect(rollDice(state,()=>0).currentPlayer).toBe('1');
    expect(expireTurn(state).currentPlayer).toBe('1');
    const moving = {...state,phase:'moving' as const,dice:1,tokens:state.tokens.map(token => token.id === '3-0' ? {...token,position:1} : token)};
    expect(moveToken(moving,'3-0').currentPlayer).toBe('1');
    expect(restartGame(state)).toBe(state);
  });
  it('keeps finishing order rather than seat order', () => {
    let state = startGame(createGame(players));
    for (const id of ['2','0','3']) state = finishPlayer(state,id);
    expect(state.finishOrder).toEqual(['2','0','3','1']);
    expect(state.winner).toBe('2');
  });
});
