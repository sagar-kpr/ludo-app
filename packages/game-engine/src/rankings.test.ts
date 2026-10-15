import { describe, expect, it } from 'vitest';
import { COLORS, HOME, createGame, moveToken, restartGame, rollDice, startGame, type GameState } from './index';

const players = COLORS.map((color,index) => ({id:String(index),name:`Player ${index}`,color,ready:true}));
function finishPlayer(state: GameState, id: string) {
  const color = state.players.find(player => player.id === id)!.color;
  return moveToken({...state,currentPlayer:id,phase:'moving',dice:1,tokens:state.tokens.map(token => token.color === color ? {...token,position:token.id === `${id}-0` ? HOME - 1 : HOME} : token)},`${id}-0`);
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
  it('skips finishers on normal passes and unmovable rolls', () => {
    const ranked = finishPlayer(startGame(createGame(players)),'0');
    const state = {...ranked,currentPlayer:'3'};
    expect(rollDice(state,()=>0).currentPlayer).toBe('1');
    const moving = {...state,phase:'moving' as const,dice:1,tokens:state.tokens.map(token => token.id === '3-0' ? {...token,position:1} : token)};
    expect(moveToken(moving,'3-0').currentPlayer).toBe('1');
    expect(restartGame(state)).toBe(state);
  });
  it('recovers a missing finish entry and never rolls for an already completed player', () => {
    const started = startGame(createGame(players));
    const state = {...started, currentPlayer:'2', tokens:started.tokens.map(token => token.color === players[2].color ? {...token,position:HOME} : token)};
    const next = rollDice(state, () => { throw new Error('A finisher must not roll'); });
    expect(next.currentPlayer).toBe('3');
    expect(next.finishOrder).toEqual(['2']);
    expect(next.winner).toBe('2');
    expect(next.dice).toBeNull();
    expect(next.phase).toBe('rolling');
    expect(rollDice({...state,currentPlayer:'1'},()=>0).currentPlayer).toBe('3');
  });
  it('preserves known ranks when recovering a finisher during a normal move', () => {
    const ranked = finishPlayer(startGame(createGame(players)), '2');
    const moving = {...ranked,currentPlayer:'3',phase:'moving' as const,dice:1,tokens:ranked.tokens.map(token => token.color === players[0].color ? {...token,position:HOME} : token.id === '3-0' ? {...token,position:1} : token)};
    const next = moveToken(moving, '3-0');
    expect(next.finishOrder).toEqual(['2','0']);
    expect(next.currentPlayer).toBe('1');
    expect(next.phase).toBe('rolling');
  });
  it('ends a recovered match with only one unfinished player', () => {
    const state = startGame(createGame(players));
    const next = rollDice({...state,tokens:state.tokens.map(token => token.color !== players[3].color ? {...token,position:HOME} : token)});
    expect(next.phase).toBe('finished');
    expect(next.finishOrder).toEqual(['0','1','2','3']);
    expect(next.dice).toBeNull();
  });
  for (const dice of [1,2,3,4,5,6]) it(`handles roll ${dice} with only base and completed pawns`, () => {
    let state = finishPlayer(startGame(createGame(players)), '2');
    state = {...state,currentPlayer:'1',tokens:state.tokens.map(token => token.color === players[1].color ? {...token,position:token.id === '1-0' ? 0 : HOME} : token)};
    const next = rollDice(state, () => (dice-1)/6);
    expect(next.currentPlayer).toBe(dice === 6 ? '1' : '3');
    expect(next.phase).toBe(dice === 6 ? 'moving' : 'rolling');
    expect(next.dice).toBe(dice === 6 ? 6 : null);
    expect(next.tokens).toEqual(state.tokens);
  });
  it('keeps finishing order rather than seat order', () => {
    let state = startGame(createGame(players));
    for (const id of ['2','0','3']) state = finishPlayer(state,id);
    expect(state.finishOrder).toEqual(['2','0','3','1']);
    expect(state.winner).toBe('2');
  });
});
